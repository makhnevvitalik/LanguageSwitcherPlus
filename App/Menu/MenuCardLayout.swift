// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit

@MainActor
enum MenuCardLayout {
    static let cardCornerRadius: CGFloat = 11
    static let sectionHeight: CGFloat = 30
    static let simpleRowHeight: CGFloat = 40
    static let detailedRowHeight: CGFloat = 46
    static let horizontalInset: CGFloat = 14
    static let compactControlWidth: CGFloat = 28
    static let compactControlHeight: CGFloat = 20
    static let compactControlSpacing: CGFloat = 6
    static let compactControlCornerRadius: CGFloat = 6
    static let popUpControlMinWidth: CGFloat = 106

    static func resolvedCGColor(_ color: NSColor, for view: NSView) -> CGColor {
        var resolved = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }

    static func sectionHeading(title: String, symbolName: String) -> NSView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: AppStyle.Font.sectionTitle.pointSize, weight: .medium)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.imageScaling = .scaleProportionallyDown
        imageView.alignment = .center
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16)
        ])

        let label = NSTextField(labelWithString: title)
        label.font = AppStyle.Font.sectionTitle
        label.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
        stack.heightAnchor.constraint(equalToConstant: sectionHeight).isActive = true
        return stack
    }

    static func row(title: String, detail: String?, trailing: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = AppStyle.Font.body

        let labels = NSStackView(views: [titleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        if let detail {
            let detailLabel = NSTextField(wrappingLabelWithString: detail)
            detailLabel.font = AppStyle.Font.supportingText
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.maximumNumberOfLines = 2
            labels.addArrangedSubview(detailLabel)
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [labels, spacer, trailing])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(
            top: detail == nil ? 5 : 3,
            left: horizontalInset,
            bottom: detail == nil ? 5 : 3,
            right: horizontalInset
        )
        stack.heightAnchor.constraint(
            equalToConstant: detail == nil ? simpleRowHeight : detailedRowHeight
        ).isActive = true
        return stack
    }

    static func addSeparator(to stack: NSStackView) {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(separator)
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

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
        button.layer?.backgroundColor = resolvedCGColor(
            isActive ? AppStyle.Color.activeControl : AppStyle.Color.inactiveControl,
            for: button
        )
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: AppStyle.Font.compactControlLabel,
                .foregroundColor: isActive ? NSColor.white : NSColor.labelColor
            ]
        )
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
