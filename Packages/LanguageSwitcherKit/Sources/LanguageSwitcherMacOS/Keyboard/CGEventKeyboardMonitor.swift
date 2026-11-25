// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import CoreGraphics
import LanguageSwitcherDomain

public enum TextShortcutInterception: Equatable {
    case inactive
    case active
    case needsAccessibility
    case unavailable
}

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
    private let inputMonitoringPermission: any InputMonitoringPermissionChecking
    private let accessibilityPermission: any AccessibilityPermissionChecking
    private let onInterceptionChanged: () -> Void
    private var modifierTrackers: [StandaloneModifierTapTracker]
    private var textGestureRecognizer: TextShortcutGestureRecognizer
    private let textInputContextPolicy: TextShortcutInputContextPolicy
    private var interceptedKeys: Set<TextShortcutKey> = []
    private var isFiltering = false
    private var accessibilityAtStart: Bool?
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
        diagnostics: ((String) -> Void)? = nil,
        inputMonitoringPermission: InputMonitoringPermissionController = InputMonitoringPermissionController(),
        accessibilityPermission: AccessibilityPermissionController = AccessibilityPermissionController(),
        onInterceptionChanged: @escaping () -> Void = {}
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
            diagnostics: diagnostics,
            inputMonitoringPermission: inputMonitoringPermission,
            accessibilityPermission: accessibilityPermission,
            onInterceptionChanged: onInterceptionChanged
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
        diagnostics: ((String) -> Void)? = nil,
        inputMonitoringPermission: any InputMonitoringPermissionChecking = InputMonitoringPermissionController(),
        accessibilityPermission: any AccessibilityPermissionChecking = AccessibilityPermissionController(),
        onInterceptionChanged: @escaping () -> Void = {}
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
        self.inputMonitoringPermission = inputMonitoringPermission
        self.accessibilityPermission = accessibilityPermission
        self.onInterceptionChanged = onInterceptionChanged
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

    public var textShortcutInterception: TextShortcutInterception {
        guard textInputContextPolicy.hasAlphanumericShortcuts, isRunning else { return .inactive }
        guard accessibilityPermission.isAllowed else { return .needsAccessibility }
        return isFiltering ? .active : .unavailable
    }

    @discardableResult
    public func start() -> Bool {
        stop()
        guard inputMonitoringPermission.isAllowed else {
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
        let canFilter = textInputContextPolicy.hasAlphanumericShortcuts && accessibilityPermission.isAllowed
        accessibilityAtStart = textInputContextPolicy.hasAlphanumericShortcuts ? canFilter : nil
        if canFilter && installTap(mask: mask, options: .defaultTap) {
            isFiltering = true
        } else {
            if canFilter { log("start.filteringTapUnavailable") }
            guard installTap(mask: mask, options: .listenOnly) else {
                log("start.listenTapUnavailable")
                return false
            }
        }
        observeApplicationChanges()
        log("start.succeeded filtering=\(isFiltering)")
        return true
    }

    private func installTap(mask: CGEventMask, options: CGEventTapOptions) -> Bool {
        guard let eventTap = makeEventTap(mask: mask, options: options) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        guard CGEvent.tapIsEnabled(tap: eventTap) else {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(eventTap)
            return false
        }
        self.eventTap = eventTap
        runLoopSource = source
        return true
    }

    private func makeEventTap(mask: CGEventMask, options: CGEventTapOptions) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<CGEventKeyboardMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                let didIntercept = monitor.handle(
                    type: type,
                    event: event,
                    interceptionAllowed: monitor.isFiltering && monitor.accessibilityPermission.isAllowed
                )
                return didIntercept ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
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
        isFiltering = false
        accessibilityAtStart = nil
        interceptedKeys.removeAll()
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

    @discardableResult
    func handle(
        type: CGEventType,
        event: CGEvent,
        interceptionAllowed: @autoclosure () -> Bool = false
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log("tap.disabled type=\(type.rawValue)")
            recoverDisabledTap()
            return false
        }
        guard event.getIntegerValueField(.eventSourceUserData) != KeyboardCommandEventMarker.value,
              let input = NSEvent(cgEvent: event) else {
            return false
        }

        let modifierEvent = makeModifierEvent(type: type, event: input)
        let shouldSwitch = modifierEvent.map { event in
            var result = false
            for index in modifierTrackers.indices where modifierTrackers[index].handle(event) {
                result = true
            }
            return result
        } ?? false

        let keyInput = TextShortcutKeyInput(event: input)
        var textInput = makeTextShortcutInput(type: type, event: input, keyInput: keyInput)
        var didIntercept = false
        if let inputEvent = textInput {
            switch inputEvent {
            case let .keyDown(key, _, _, _) where key.isAlphanumeric:
                // Repeats and key-up belong to whoever received the initial key-down.
                if interceptedKeys.contains(key) { return true }
                if !keyInput.rejectsFn,
                   textInputContextPolicy.shouldPreserveContext(for: inputEvent), interceptionAllowed() {
                    interceptedKeys.insert(key)
                    didIntercept = true
                } else {
                    textInput = nil
                }
            case let .keyUp(key, _, _) where key.isAlphanumeric:
                didIntercept = interceptedKeys.remove(key) != nil
                if !didIntercept { textInput = nil }
            default:
                break
            }
        }
        let shouldPreserveTextContext = didIntercept || textInput.map(
            textInputContextPolicy.shouldPreserveContext
        ) == true
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
        return didIntercept
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
        event: NSEvent,
        keyInput: TextShortcutKeyInput
    ) -> TextShortcutInputEvent? {
        guard let key = keyInput.key else { return nil }
        let isDown: Bool
        switch type {
        case .flagsChanged:
            guard let mask = key.modifierMask else { return nil }
            isDown = keyInput.modifiers.contains(mask)
        case .keyDown: isDown = true
        case .keyUp: isDown = false
        default: return nil
        }
        if isDown {
            return .keyDown(
                key,
                activeModifiers: keyInput.modifiers,
                timestamp: event.timestamp,
                isRepeat: type == .keyDown && event.isARepeat
            )
        }
        return .keyUp(
            key,
            activeModifiers: keyInput.modifiers,
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
                  !characters.unicodeScalars.contains(where: Self.isControlInput) {
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

    private static func isControlInput(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200C, 0x200D, 0xE0020...0xE007F:
            // Joiners and emoji tags are part of the text payload.
            return false
        default:
            return CharacterSet.controlCharacters.contains(scalar)
        }
    }

    private func recoverDisabledTap() {
        interceptedKeys.removeAll()
        modifierTrackers = Self.makeTrackers(
            shortcuts: modifierShortcuts,
            maximumTapDuration: maximumModifierTapDuration
        )
        textGestureRecognizer = TextShortcutGestureRecognizer(
            shortcuts: textShortcuts,
            maximumInterval: maximumTextShortcutMultiPressInterval
        )
        cancelTextShortcutTimeouts()
        contextTracker.recordInteraction()
        trackedTextBuffer.invalidate()
        log("buffer.invalidated reason=tapRecovery")
        let accessibilityChanged = accessibilityAtStart.map { $0 != accessibilityPermission.isAllowed } ?? false
        if !accessibilityChanged, let eventTap, inputMonitoringPermission.isAllowed {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            if CGEvent.tapIsEnabled(tap: eventTap) {
                return
            }
        }
        if start() {
            onInterceptionChanged()
            return
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
        ) { [weak self] _ in
            guard let self else { return }
            self.contextTracker.recordInteraction()
            self.trackedTextBuffer.invalidate()
            if let accessibilityAtStart = self.accessibilityAtStart,
               accessibilityAtStart != self.accessibilityPermission.isAllowed {
                if self.start() {
                    self.onInterceptionChanged()
                } else {
                    self.onUnavailable()
                }
            }
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
