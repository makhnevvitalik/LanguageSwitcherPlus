// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit

@MainActor
final class AboutContent {
    let view = NSView()
    let contentStack = NSStackView()
    let taglineLabel = NSTextField(wrappingLabelWithString: "")
    let progressIndicator = NSProgressIndicator()
    let statusLabel = NSTextField(wrappingLabelWithString: "")

    init(name: String, icon: NSImage, tagline: String, copyright: String,
         updateButton: NSButton, gitHubButton: NSButton, licensesButton: NSButton, statusIdentifier: String) {
        let windowWidth = AppStyle.AboutLayout.width
        let contentWidth = windowWidth - 2 * AppStyle.Layout.windowInset
        let windowContent = self.view

        let iconSize = AppStyle.AboutLayout.iconSize
        let iconView = NSImageView(image: AppStyle.Icon.brandImage(icon,
            size: NSSize(width: iconSize, height: iconSize)))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: AppStyle.AboutLayout.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: AppStyle.AboutLayout.iconSize)
        ])

        let copyrightLabel = NSTextField(labelWithString: copyright)
        copyrightLabel.font = AppStyle.Font.metadata
        copyrightLabel.textColor = .secondaryLabelColor

        taglineLabel.stringValue = tagline
        taglineLabel.isSelectable = false
        taglineLabel.font = AppStyle.Font.body
        taglineLabel.textColor = .secondaryLabelColor
        taglineLabel.preferredMaxLayoutWidth = contentWidth
        taglineLabel.lineBreakMode = .byWordWrapping

        updateButton.bezelStyle = .rounded
        updateButton.font = AppStyle.Font.controlLabel
        updateButton.keyEquivalent = "\r"
        updateButton.widthAnchor.constraint(equalToConstant: AppStyle.AboutLayout.updateButtonWidth).isActive = true

        gitHubButton.isBordered = false
        gitHubButton.contentTintColor = .linkColor
        gitHubButton.font = AppStyle.Font.secondaryAction

        licensesButton.isBordered = false
        licensesButton.contentTintColor = .linkColor
        licensesButton.font = AppStyle.Font.secondaryAction

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.isHidden = true

        let actionStack = NSStackView(views: [updateButton, progressIndicator, gitHubButton])
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = AppStyle.AboutLayout.actionSpacing
        actionStack.detachesHiddenViews = true

        statusLabel.isSelectable = false
        statusLabel.identifier = NSUserInterfaceItemIdentifier(statusIdentifier)
        statusLabel.font = AppStyle.Font.statusText
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.preferredMaxLayoutWidth = contentWidth
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: AppStyle.AboutLayout.statusHeight).isActive = true
        statusLabel.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        let name = AppStyle.makeAboutIdentityView(name: name,
                                             availableWidth: contentWidth - AppStyle.AboutLayout.iconSize
                                                 - AppStyle.AboutLayout.headerSpacing)
        let header = NSStackView(views: [iconView, name])
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = AppStyle.AboutLayout.headerSpacing

        // Align the borderless button's title with the text labels above it.
        let licensesRow = NSView()
        licensesButton.translatesAutoresizingMaskIntoConstraints = false
        licensesRow.addSubview(licensesButton)
        NSLayoutConstraint.activate([
            licensesButton.leadingAnchor.constraint(equalTo: licensesRow.leadingAnchor, constant: -2),
            licensesButton.trailingAnchor.constraint(equalTo: licensesRow.trailingAnchor),
            licensesButton.topAnchor.constraint(equalTo: licensesRow.topAnchor),
            licensesButton.bottomAnchor.constraint(equalTo: licensesRow.bottomAnchor)
        ])
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [licensesRow, footerSpacer, copyrightLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        [header, taglineLabel, actionStack, statusLabel, footer].forEach(contentStack.addArrangedSubview)
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = AppStyle.AboutLayout.contentSpacing
        contentStack.setCustomSpacing(12, after: taglineLabel)
        contentStack.setCustomSpacing(4, after: actionStack)
        contentStack.setCustomSpacing(AppStyle.AboutLayout.statusFooterSpacing, after: statusLabel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        windowContent.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: windowContent.leadingAnchor, constant: AppStyle.Layout.windowInset),
            contentStack.trailingAnchor.constraint(equalTo: windowContent.trailingAnchor, constant: -AppStyle.Layout.windowInset),
            contentStack.topAnchor.constraint(equalTo: windowContent.topAnchor, constant: AppStyle.Layout.windowTopInset),
            taglineLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: windowContent.bottomAnchor, constant: -AppStyle.AboutLayout.bottomInset)
        ])
    }
}
