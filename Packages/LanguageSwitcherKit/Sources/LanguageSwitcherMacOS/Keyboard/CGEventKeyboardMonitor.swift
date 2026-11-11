// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import CoreGraphics
import LanguageSwitcherDomain

public final class CGEventKeyboardMonitor {
    private let modifierShortcuts: [ModifierShortcut]
    private let maximumModifierTapDuration: TimeInterval
    private let maximumTextShortcutMultiPressInterval: TimeInterval
    private let textShortcuts: [TextAction: TextActionShortcut]
    private let trackedTextBuffer: TrackedTextBuffer
    private let contextTracker: InputContextTracker
    private let applicationProvider: any FrontmostApplicationProviding
    private let onModifierTrigger: () -> Void
    private let onTextAction: (TextAction) -> Void
    private let onUnavailable: () -> Void
    private let diagnostics: ((String) -> Void)?
    private var modifierTrackers: [StandaloneModifierTapTracker]
    private var textGestureRecognizer: TextShortcutGestureRecognizer
    private let textInputContextPolicy: TextShortcutInputContextPolicy
    private var textSequenceWorkItems: [TextShortcutChord: DispatchWorkItem] = [:]
    private var textSequenceTokens: [TextShortcutChord: UUID] = [:]
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?

    public convenience init(
        modifierShortcuts: [ModifierShortcut],
        maximumModifierTapDuration: TimeInterval,
        maximumTextShortcutMultiPressInterval: TimeInterval,
        textShortcuts: [TextAction: TextActionShortcut],
        trackedTextBuffer: TrackedTextBuffer,
        contextTracker: InputContextTracker,
        onModifierTrigger: @escaping () -> Void,
        onTextAction: @escaping (TextAction) -> Void,
        onUnavailable: @escaping () -> Void,
        diagnostics: ((String) -> Void)? = nil
    ) {
        self.init(
            modifierShortcuts: modifierShortcuts,
            maximumModifierTapDuration: maximumModifierTapDuration,
            maximumTextShortcutMultiPressInterval: maximumTextShortcutMultiPressInterval,
            textShortcuts: textShortcuts,
            trackedTextBuffer: trackedTextBuffer,
            contextTracker: contextTracker,
            applicationProvider: FrontmostApplicationProvider(),
            onModifierTrigger: onModifierTrigger,
            onTextAction: onTextAction,
            onUnavailable: onUnavailable,
            diagnostics: diagnostics
        )
    }

    init(
        modifierShortcuts: [ModifierShortcut],
        maximumModifierTapDuration: TimeInterval,
        maximumTextShortcutMultiPressInterval: TimeInterval,
        textShortcuts: [TextAction: TextActionShortcut],
        trackedTextBuffer: TrackedTextBuffer,
        contextTracker: InputContextTracker,
        applicationProvider: any FrontmostApplicationProviding,
        onModifierTrigger: @escaping () -> Void,
        onTextAction: @escaping (TextAction) -> Void,
        onUnavailable: @escaping () -> Void,
        diagnostics: ((String) -> Void)? = nil
    ) {
        self.modifierShortcuts = modifierShortcuts
        self.maximumModifierTapDuration = maximumModifierTapDuration
        self.maximumTextShortcutMultiPressInterval = maximumTextShortcutMultiPressInterval
        self.textShortcuts = textShortcuts
        self.trackedTextBuffer = trackedTextBuffer
        self.contextTracker = contextTracker
        self.applicationProvider = applicationProvider
        self.onModifierTrigger = onModifierTrigger
        self.onTextAction = onTextAction
        self.onUnavailable = onUnavailable
        self.diagnostics = diagnostics
        modifierTrackers = Self.makeTrackers(
            shortcuts: modifierShortcuts,
            maximumTapDuration: maximumModifierTapDuration
        )
        textGestureRecognizer = TextShortcutGestureRecognizer(
            shortcuts: textShortcuts,
            maximumInterval: maximumTextShortcutMultiPressInterval
        )
        textInputContextPolicy = TextShortcutInputContextPolicy(shortcuts: textShortcuts)
    }

    public var isRunning: Bool {
        guard let eventTap, CFMachPortIsValid(eventTap) else {
            return false
        }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    @discardableResult
    public func start() -> Bool {
        stop()
        guard CGPreflightListenEventAccess() else {
            log("start.denied")
            return false
        }

        let eventTypes: [CGEventType] = [
            .flagsChanged,
            .keyDown,
            .keyUp,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]
        let mask = eventTypes.reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<CGEventKeyboardMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            log("start.tapCreateFailed")
            return false
        }

        self.eventTap = eventTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        observeApplicationChanges()

        guard CGEvent.tapIsEnabled(tap: eventTap) else {
            log("start.tapDisabled")
            stop()
            return false
        }
        log("start.succeeded")
        return true
    }

    public func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        textSequenceWorkItems.values.forEach { $0.cancel() }
        textSequenceWorkItems.removeAll()
        textSequenceTokens.removeAll()
        runLoopSource = nil
        eventTap = nil
        modifierTrackers = Self.makeTrackers(
            shortcuts: modifierShortcuts,
            maximumTapDuration: maximumModifierTapDuration
        )
        textGestureRecognizer = TextShortcutGestureRecognizer(
            shortcuts: textShortcuts,
            maximumInterval: maximumTextShortcutMultiPressInterval
        )
        trackedTextBuffer.invalidate()
    }

    deinit {
        stop()
    }

    func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log("tap.disabled type=\(type.rawValue)")
            recoverDisabledTap()
            return
        }
        guard event.getIntegerValueField(.eventSourceUserData) != KeyboardCommandEventMarker.value,
              let input = NSEvent(cgEvent: event) else {
            return
        }

        let modifierEvent = makeModifierEvent(type: type, event: input)
        let shouldSwitch = modifierEvent.map { event in
            var result = false
            for index in modifierTrackers.indices where modifierTrackers[index].handle(event) {
                result = true
            }
            return result
        } ?? false

        let textInput = makeTextShortcutInput(type: type, event: input)
        let shouldPreserveTextContext = textInput.map(
            textInputContextPolicy.shouldPreserveContext
        ) ?? false
        if let textInput {
            let recognition = textGestureRecognizer.handle(
                textInput,
                contextGeneration: contextTracker.generation
            )
            handleTextShortcutRecognition(recognition)
        } else if type == .keyDown || type == .leftMouseDown
                    || type == .rightMouseDown || type == .otherMouseDown {
            _ = textGestureRecognizer.handle(
                .unrelatedInput,
                contextGeneration: contextTracker.generation
            )
            cancelTextShortcutTimeouts()
        }

        if !shouldPreserveTextContext {
            if type == .keyDown || type == .leftMouseDown
                || type == .rightMouseDown || type == .otherMouseDown {
                contextTracker.recordInteraction()
            }
            if type != .keyUp {
                updateTypingSession(type: type, event: input)
            }
        }
        if shouldSwitch {
            contextTracker.recordInteraction()
            dispatch { [weak self] in self?.onModifierTrigger() }
        }
    }

    private func makeModifierEvent(type: CGEventType, event: NSEvent) -> ModifierTapEvent? {
        switch type {
        case .flagsChanged:
            .flagsChanged(keyCode: event.keyCode, flags: event.modifierFlags, timestamp: event.timestamp)
        case .keyDown:
            .keyDown(flags: event.modifierFlags)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            .mouseDown(flags: event.modifierFlags)
        default:
            nil
        }
    }

    private func makeTextShortcutInput(
        type: CGEventType,
        event: NSEvent
    ) -> TextShortcutInputEvent? {
        let modifiers = KeyModifiers(eventModifierFlags: event.modifierFlags)
            .intersection(.textShortcutModifiers)
        if type == .flagsChanged,
           let modifier = ShortcutModifier(keyCode: event.keyCode) {
            let key = TextShortcutKey.modifier(modifier)
            if modifiers.contains(modifier.mask) {
                return .keyDown(
                    key,
                    activeModifiers: modifiers,
                    timestamp: event.timestamp,
                    isRepeat: false
                )
            }
            return .keyUp(
                key,
                activeModifiers: modifiers,
                timestamp: event.timestamp
            )
        }
        guard type == .keyDown || type == .keyUp,
              let functionKey = ShortcutFunctionKey(keyCode: event.keyCode) else {
            return nil
        }
        let key = TextShortcutKey.function(functionKey)
        if type == .keyDown {
            return .keyDown(
                key,
                activeModifiers: modifiers,
                timestamp: event.timestamp,
                isRepeat: event.isARepeat
            )
        }
        return .keyUp(
            key,
            activeModifiers: modifiers,
            timestamp: event.timestamp
        )
    }

    private func handleTextShortcutRecognition(
        _ recognition: TextShortcutRecognition
    ) {
        switch recognition {
        case let .trigger(action):
            cancelTextShortcutTimeouts()
            logShortcutActivation(action)
            dispatchTextAction(action, contextGeneration: contextTracker.generation)
        case let .wait(chord):
            scheduleTextShortcutTimeout(for: chord)
        case .none:
            break
        }
    }

    private func scheduleTextShortcutTimeout(for chord: TextShortcutChord) {
        textSequenceWorkItems[chord]?.cancel()
        let token = UUID()
        let workItem = DispatchWorkItem { [weak self] in
            self?.completeTextShortcutSequence(for: chord, token: token)
        }
        textSequenceWorkItems[chord] = workItem
        textSequenceTokens[chord] = token
        DispatchQueue.main.asyncAfter(
            deadline: .now() + maximumTextShortcutMultiPressInterval,
            execute: workItem
        )
    }

    private func completeTextShortcutSequence(
        for chord: TextShortcutChord,
        token: UUID
    ) {
        guard textSequenceTokens[chord] == token else { return }
        textSequenceWorkItems[chord] = nil
        textSequenceTokens[chord] = nil
        let action = textGestureRecognizer.handleTimeout(
            chord: chord,
            at: ProcessInfo.processInfo.systemUptime,
            contextGeneration: contextTracker.generation
        )
        if let action {
            logShortcutActivation(action)
            dispatchTextAction(action, contextGeneration: contextTracker.generation)
        }
    }

    private func cancelTextShortcutTimeouts() {
        textSequenceWorkItems.values.forEach { $0.cancel() }
        textSequenceWorkItems.removeAll()
        textSequenceTokens.removeAll()
    }

    private func dispatchTextAction(
        _ action: TextAction,
        contextGeneration: UInt64
    ) {
        dispatch { [weak self] in
            guard let self,
                  self.contextTracker.isCurrent(contextGeneration) else {
                return
            }
            self.onTextAction(action)
        }
    }

    private func updateTypingSession(type: CGEventType, event: NSEvent) {
        guard type == .keyDown else {
            if type != .flagsChanged {
                trackedTextBuffer.invalidate()
            }
            return
        }
        guard let applicationID = applicationProvider.applicationID else {
            trackedTextBuffer.invalidate()
            return
        }

        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if Self.newLineKeyCodes.contains(keyCode) {
            trackedTextBuffer.invalidate()
        } else if keyCode == 51 {
            if flags.intersection([.option, .command, .control, .function]).isEmpty {
                trackedTextBuffer.recordBackspace(applicationID: applicationID)
            } else {
                // The application decides how much text modified Backspace deletes.
                trackedTextBuffer.invalidate()
            }
        } else if Self.resetKeyCodes.contains(keyCode)
                    || !flags.intersection([.command, .control, .function]).isEmpty {
            trackedTextBuffer.invalidate()
        } else if let characters = event.characters,
                  !characters.isEmpty,
                  !characters.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            trackedTextBuffer.recordPrintableText(
                characters,
                keyCode: keyCode,
                eventFlags: event.cgEvent?.flags.rawValue ?? 0,
                applicationID: applicationID
            )
        } else {
            trackedTextBuffer.invalidate()
        }
    }

    private func recoverDisabledTap() {
        modifierTrackers = Self.makeTrackers(
            shortcuts: modifierShortcuts,
            maximumTapDuration: maximumModifierTapDuration
        )
        textGestureRecognizer = TextShortcutGestureRecognizer(
            shortcuts: textShortcuts,
            maximumInterval: maximumTextShortcutMultiPressInterval
        )
        cancelTextShortcutTimeouts()
        trackedTextBuffer.invalidate()
        log("buffer.invalidated reason=tapRecovery")
        if let eventTap, CGPreflightListenEventAccess() {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            if CGEvent.tapIsEnabled(tap: eventTap) {
                return
            }
        }
        stop()
        DispatchQueue.main.async { [weak self] in
            self?.onUnavailable()
        }
    }

    private func observeApplicationChanges() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak trackedTextBuffer, weak contextTracker] _ in
            contextTracker?.recordInteraction()
            trackedTextBuffer?.invalidate()
        }
    }

    private func dispatch(_ operation: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard self?.eventTap != nil else { return }
            operation()
        }
    }

    private func logShortcutActivation(_ action: TextAction) {
        guard let diagnostics else { return }
        let applicationID = applicationProvider.applicationID ?? "unknown"
        let trackedText = trackedTextBuffer.snapshot(for: applicationID)?.text
        diagnostics(
            "shortcut.activated app=\(applicationID) action=\(String(describing: action)) "
                + "tracked=\(trackedText.map(Self.quoted) ?? "missing")"
        )
    }

    private func log(_ message: @autoclosure () -> String) {
        guard let diagnostics else { return }
        diagnostics(message())
    }

    private static func quoted(_ text: String) -> String {
        String(reflecting: text)
    }

    private static func makeTrackers(
        shortcuts: [ModifierShortcut],
        maximumTapDuration: TimeInterval
    ) -> [StandaloneModifierTapTracker] {
        shortcuts.map {
            StandaloneModifierTapTracker(shortcut: $0, maximumTapDuration: maximumTapDuration)
        }
    }

    private static let newLineKeyCodes: Set<UInt16> = [36, 76]
    private static let resetKeyCodes: Set<UInt16> = [
        48, 53, 115, 116, 117, 119, 121, 123, 124, 125, 126
    ]
}
