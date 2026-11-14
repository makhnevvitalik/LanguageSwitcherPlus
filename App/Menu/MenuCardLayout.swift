// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit

final class CompactSelectionButton: NSButton {
    private var selectionTitle = ""
    private var isSelected = false

    func updateSelection(title: String, isSelected: Bool) {
        selectionTitle = title
        self.isSelected = isSelected
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        MenuCardLayout.styleCompactControl(self, title: selectionTitle, isActive: isSelected)
    }
}

@MainActor
enum MenuCardLayout {
    static let compactControlWidth: CGFloat = 28
    static let compactControlHeight: CGFloat = 20
    static let compactControlSpacing: CGFloat = 6
    static let compactControlCornerRadius: CGFloat = 6
    static let popUpControlMinWidth: CGFloat = 106

    static func configureCompactControl(_ button: NSButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = compactControlCornerRadius
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: compactControlWidth),
            button.heightAnchor.constraint(equalToConstant: compactControlHeight)
        ])
    }

    static func styleCompactControl(
        _ button: NSButton,
        title: String,
        isActive: Bool
    ) {
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            let fill = isActive ? AppStyle.Color.compactSelectionBackground() : AppStyle.Color.inactiveControl
            button.layer?.backgroundColor = fill.cgColor
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: AppStyle.Font.compactControlLabel,
                    .foregroundColor: isActive ? NSColor.white : NSColor.labelColor
                ]
            )
        }
    }

    static func configureTimeIntervalOptions(
        for button: NSPopUpButton,
        options: [TimeInterval],
        selectedValue: TimeInterval,
        defaultValue: TimeInterval
    ) {
        button.removeAllItems()
        for option in options {
            let suffix = option == defaultValue ? localized(" (Default)") : ""
            button.addItem(withTitle: localizedFormat("%.1f s", option) + suffix)
            button.lastItem?.representedObject = option
        }
        if let index = options.firstIndex(of: selectedValue) {
            button.selectItem(at: index)
        }
    }

    static func configurePopUpControl(_ button: NSPopUpButton) {
        button.controlSize = .small
        button.font = AppStyle.Font.controlLabel
        button.widthAnchor.constraint(
            greaterThanOrEqualToConstant: popUpControlMinWidth
        ).isActive = true
    }
}
