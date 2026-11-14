// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import Foundation
import LanguageSwitcherApplication
import LanguageSwitcherDomain

@MainActor
final class ActiveInputsMenuController: NSObject {
    private enum Layout {
        static let maximumControlWidth: CGFloat = 260
        static let navigationButtonWidth: CGFloat = 14
    }

    private let inputSources: () -> [InputSource]
    private let isSelected: (InputSource) -> Bool
    private let setSelected: (InputSource, Bool) -> InputSourceSelectionUpdateResult
    private let summary = NSStackView()
    private let buttonStrip = NSStackView()
    private let scrollView = NSScrollView()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private var buttonStripWidthConstraint: NSLayoutConstraint!
    private var displayedSources: [InputSource]?
    private var inputButtons: [CompactSelectionButton] = []

    var view: NSView { summary }

    init(
        inputSources: @escaping () -> [InputSource],
        isSelected: @escaping (InputSource) -> Bool,
        setSelected: @escaping (InputSource, Bool) -> InputSourceSelectionUpdateResult
    ) {
        self.inputSources = inputSources
        self.isSelected = isSelected
        self.setSelected = setSelected

        super.init()

        configureSummary()
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func refresh() {
        let sources = inputSources()
        if sources == displayedSources {
            for (source, button) in zip(sources, inputButtons) {
                updateInputButton(button, for: source)
            }
            return
        }
        clearArrangedSubviews(from: summary)
        clearArrangedSubviews(from: buttonStrip)

        displayedSources = sources
        let buttons = sources.enumerated().map { index, source in
            inputButton(for: source, index: index)
        }
        inputButtons = buttons
        let contentWidth = CGFloat(buttons.count) * MenuCardLayout.compactControlWidth
            + CGFloat(max(0, buttons.count - 1)) * MenuCardLayout.compactControlSpacing

        if contentWidth <= Layout.maximumControlWidth {
            buttons.forEach(summary.addArrangedSubview)
            return
        }

        buttons.forEach(buttonStrip.addArrangedSubview)
        buttonStripWidthConstraint.constant = contentWidth

        summary.addArrangedSubview(previousButton)
        summary.addArrangedSubview(scrollView)
        summary.addArrangedSubview(nextButton)

        scrollView.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateNavigationButtons()
    }

    private func configureSummary() {
        summary.orientation = .horizontal
        summary.alignment = .centerY
        summary.spacing = 4
        summary.setContentHuggingPriority(.required, for: .horizontal)
        summary.setContentCompressionResistancePriority(.required, for: .horizontal)

        buttonStrip.orientation = .horizontal
        buttonStrip.alignment = .centerY
        buttonStrip.spacing = MenuCardLayout.compactControlSpacing
        buttonStrip.translatesAutoresizingMaskIntoConstraints = false

        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = buttonStrip
        buttonStripWidthConstraint = buttonStrip.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            buttonStripWidthConstraint,
            buttonStrip.heightAnchor.constraint(
                equalToConstant: MenuCardLayout.compactControlHeight
            )
        ])
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let viewportWidth = Layout.maximumControlWidth
            - Layout.navigationButtonWidth * 2
            - summary.spacing * 2
        scrollView.widthAnchor.constraint(equalToConstant: viewportWidth).isActive = true
        scrollView.heightAnchor.constraint(
            equalToConstant: MenuCardLayout.compactControlHeight
        ).isActive = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollPositionDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        configureNavigationButton(
            previousButton,
            symbolName: "chevron.left",
            toolTip: localized("Scroll input sources left"),
            action: #selector(scrollLeft)
        )
        configureNavigationButton(
            nextButton,
            symbolName: "chevron.right",
            toolTip: localized("Scroll input sources right"),
            action: #selector(scrollRight)
        )
    }

    private func configureNavigationButton(
        _ button: NSButton,
        symbolName: String,
        toolTip: String,
        action: Selector
    ) {
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.toolTip = toolTip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Layout.navigationButtonWidth),
            button.heightAnchor.constraint(equalToConstant: MenuCardLayout.compactControlHeight)
        ])
    }

    private func inputButton(for source: InputSource, index: Int) -> CompactSelectionButton {
        let button = CompactSelectionButton(
            title: inputCode(for: source),
            target: self,
            action: #selector(toggleInputSource(_:))
        )
        button.tag = index
        button.toolTip = source.displayName
        MenuCardLayout.configureCompactControl(button)
        button.setAccessibilityRole(.checkBox)
        updateInputButton(button, for: source)
        return button
    }

    private func updateInputButton(_ button: CompactSelectionButton, for source: InputSource) {
        let selected = isSelected(source)
        button.updateSelection(title: inputCode(for: source), isSelected: selected)
        button.setAccessibilityValue(selected)
    }

    @objc private func toggleInputSource(_ sender: NSButton) {
        guard let displayedSources, displayedSources.indices.contains(sender.tag) else { return }
        let source = displayedSources[sender.tag]
        _ = setSelected(source, !isSelected(source))
        refresh()
    }

    @objc private func scrollLeft() {
        scroll(by: -scrollStep)
    }

    @objc private func scrollRight() {
        scroll(by: scrollStep)
    }

    private func scroll(by distance: CGFloat) {
        let clipView = scrollView.contentView
        let targetOffset = min(
            maximumScrollOffset,
            max(0, clipView.bounds.origin.x + distance)
        )
        clipView.scroll(to: NSPoint(x: targetOffset, y: 0))
        scrollView.reflectScrolledClipView(clipView)
        updateNavigationButtons()
    }

    @objc private func scrollPositionDidChange() {
        updateNavigationButtons()
    }

    private func updateNavigationButtons() {
        let offset = scrollView.contentView.bounds.origin.x
        previousButton.isEnabled = offset > 0.5
        nextButton.isEnabled = offset < maximumScrollOffset - 0.5
    }

    private var maximumScrollOffset: CGFloat {
        max(0, buttonStrip.frame.width - scrollView.contentView.bounds.width)
    }

    private var scrollStep: CGFloat {
        MenuCardLayout.compactControlWidth + MenuCardLayout.compactControlSpacing
    }

    private func clearArrangedSubviews(from stack: NSStackView) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    private func inputCode(for source: InputSource) -> String {
        if let localeIdentifier = source.localeIdentifier,
           let languageCode = Locale(identifier: localeIdentifier).language.languageCode?.identifier {
            return languageCode.uppercased()
        }
        return String(source.displayName.prefix(2)).uppercased()
    }
}
