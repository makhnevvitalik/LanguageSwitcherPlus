// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

//
//  AboutWindowController.swift
//  LanguageSwitcher
//
//  Created by Vitalik Makhnev on 11.06.2026.
//

import AppKit
import Foundation
import LanguageSwitcherEdition
import LanguageSwitcherMacOS

@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private let identity: AppIdentity
    private var aboutWindow: NSWindow?
    private var licensesWindowController: LicensesAcknowledgementsWindowController?
    private var updateButton: NSButton?
    private var updateProgressIndicator: NSProgressIndicator?
    private var updateStatusLabel: NSTextField?
    private lazy var updateChecker = GitHubReleaseChecker(
        apiURL: identity.latestReleaseAPIURL, releaseURL: identity.latestReleaseURL
    )
    private var downloadURL: URL?

    init(identity: AppIdentity) {
        self.identity = identity
        super.init()
    }

    func showWindow() {
        if aboutWindow == nil {
            aboutWindow = makeAboutWindow()
        }

        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        resetUpdateState()
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? localized("Unknown version")
        return localizedFormat("Version %@", version)
    }

    private var copyrightText: String {
        (Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
            .replacingOccurrences(of: "Copyright ", with: "")
    }

    private func makeAboutWindow() -> NSWindow {
        let windowWidth = AppStyle.AboutLayout.width
        let windowHeight = AppStyle.AboutLayout.height
        let windowContent = NSView()

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: AppStyle.AboutLayout.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: AppStyle.AboutLayout.iconSize)
        ])

        let nameLabel = NSTextField(labelWithString: identity.brandName)
        nameLabel.font = AppStyle.Font.appName

        let editionLabel = NSTextField(labelWithString: identity.editionName)
        editionLabel.font = AppStyle.Font.appEdition
        editionLabel.textColor = .secondaryLabelColor

        let versionLabel = NSTextField(labelWithString: versionText)
        versionLabel.font = AppStyle.Font.body
        versionLabel.textColor = .secondaryLabelColor

        let copyrightLabel = NSTextField(labelWithString: copyrightText)
        copyrightLabel.font = AppStyle.Font.body
        copyrightLabel.textColor = .secondaryLabelColor

        let taglineLabel = NSTextField(
            wrappingLabelWithString: localized("Switch keyboard layouts and fix text typed in the wrong layout or case.")
        )
        taglineLabel.isSelectable = false
        taglineLabel.font = AppStyle.Font.body
        taglineLabel.textColor = .secondaryLabelColor
        taglineLabel.maximumNumberOfLines = 2
        taglineLabel.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let updateButton = NSButton(
            title: localized("Check for Updates"),
            target: self,
            action: #selector(updateButtonPressed)
        )
        updateButton.bezelStyle = .rounded
        updateButton.font = AppStyle.Font.controlLabel
        updateButton.keyEquivalent = "\r"
        updateButton.widthAnchor.constraint(equalToConstant: AppStyle.AboutLayout.updateButtonWidth).isActive = true
        self.updateButton = updateButton

        let gitHubButton = NSButton(title: "GitHub ↗", target: self, action: #selector(openGitHub))
        gitHubButton.isBordered = false
        gitHubButton.contentTintColor = .linkColor
        gitHubButton.font = AppStyle.Font.controlLabel
        gitHubButton.focusRingType = .none

        let licensesButton = NSButton(
            title: localized("Licenses…"),
            target: self,
            action: #selector(showLicenses)
        )
        licensesButton.isBordered = false
        licensesButton.contentTintColor = .linkColor
        licensesButton.font = AppStyle.Font.controlLabel
        licensesButton.focusRingType = .none

        let progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.isHidden = true
        self.updateProgressIndicator = progressIndicator

        let actionStack = NSStackView(views: [updateButton, progressIndicator, gitHubButton])
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = AppStyle.AboutLayout.actionSpacing
        actionStack.detachesHiddenViews = true

        let statusLabel = NSTextField(wrappingLabelWithString: "")
        statusLabel.isSelectable = false
        statusLabel.identifier = NSUserInterfaceItemIdentifier("AboutUpdateStatus")
        statusLabel.font = AppStyle.Font.statusText
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.heightAnchor.constraint(equalToConstant: AppStyle.AboutLayout.statusHeight).isActive = true
        statusLabel.widthAnchor.constraint(equalToConstant: windowWidth - AppStyle.Layout.windowInset * 2).isActive = true
        self.updateStatusLabel = statusLabel

        let separator = NSTextField(labelWithString: "·")
        separator.font = AppStyle.Font.body
        separator.textColor = .secondaryLabelColor
        let versionRow = NSStackView(views: [editionLabel, separator, versionLabel])
        versionRow.orientation = .horizontal
        versionRow.alignment = .centerY
        versionRow.spacing = 6
        let identityStack = NSStackView(views: [nameLabel, versionRow])
        identityStack.orientation = .vertical
        identityStack.alignment = .leading
        identityStack.spacing = 2
        let header = NSStackView(views: [iconView, identityStack])
        header.orientation = .horizontal
        header.alignment = .centerY
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

        let contentStack = NSStackView(views: [header, taglineLabel, actionStack, statusLabel, footer])
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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = localizedFormat("About %@", identity.productName)
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = windowContent
        window.center()

        return window
    }

    @objc private func openGitHub() {
        aboutWindow?.close()
        NSWorkspace.shared.open(identity.repositoryURL)
    }

    @objc private func showLicenses() {
        if licensesWindowController == nil {
            licensesWindowController = LicensesAcknowledgementsWindowController(identity: identity)
        }
        licensesWindowController?.showWindow()
    }

    @objc private func updateButtonPressed() {
        if let downloadURL {
            NSWorkspace.shared.open(downloadURL)
            return
        }
        checkForUpdates()
    }

    private func checkForUpdates() {
        guard !updateChecker.isChecking else { return }
        downloadURL = nil
        updateButton?.title = localized("Checking…")
        updateButton?.isEnabled = false
        setUpdateStatusText("")
        updateProgressIndicator?.isHidden = false
        updateProgressIndicator?.startAnimation(nil)
        updateChecker.check { [weak self] result in
            self?.showUpdateResult(result)
        }
    }

    private func showUpdateResult(_ result: ReleaseUpdateResult) {
        updateProgressIndicator?.stopAnimation(nil)
        updateProgressIndicator?.isHidden = true
        updateButton?.isEnabled = true

        switch result {
        case .upToDate:
            downloadURL = nil
            updateButton?.title = localized("Check for Updates")
            updateStatusLabel?.textColor = AppStyle.Color.success
            setUpdateStatusText(localized("You’re up to date."))

        case let .updateAvailable(tag, url):
            downloadURL = url
            updateButton?.title = localized("View Release")
            updateStatusLabel?.textColor = .labelColor
            setUpdateStatusText(localizedFormat("%@ is available.", tag))

        case let .failure(failure):
            downloadURL = nil
            updateButton?.title = localized("Try Again")
            updateStatusLabel?.textColor = .systemRed
            setUpdateStatusText(updateFailureText(failure))
        }
    }

    private func updateFailureText(_ failure: ReleaseUpdateFailure) -> String {
        switch failure {
        case .network:
            return localized("Could not contact GitHub. Please try again.")
        case .invalidResponse:
            return localized("GitHub returned an invalid response.")
        case .invalidRelease:
            return localized("GitHub returned invalid update information.")
        case .currentVersion:
            return localized("Could not determine the installed app version.")
        case let .http(status):
            return localizedFormat("GitHub returned HTTP %d.", status)
        }
    }

    private func setUpdateStatusText(_ text: String) {
        updateStatusLabel?.stringValue = text
        updateStatusLabel?.toolTip = text.isEmpty ? nil : text
    }

    private func resetUpdateState() {
        updateChecker.cancel()
        downloadURL = nil
        updateProgressIndicator?.stopAnimation(nil)
        updateProgressIndicator?.isHidden = true
        updateButton?.isEnabled = true
        updateButton?.title = localized("Check for Updates")
        updateStatusLabel?.textColor = .secondaryLabelColor
        setUpdateStatusText("")
    }
}

@MainActor
private final class LicensesAcknowledgementsWindowController: NSObject, NSWindowDelegate {
    private struct Document {
        let title: String
        let text: String
        let format: LicenseDocumentRenderer.Format
    }

    private let identity: AppIdentity
    private var window: NSWindow?
    private let textView = NSTextView()
    private var documents: [Document] = []

    init(identity: AppIdentity) {
        self.identity = identity
        super.init()
    }

    func showWindow() {
        if window == nil {
            window = makeWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        documents = loadDocuments()

        let contentView = NSView()
        let documentPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        documentPicker.addItems(withTitles: documents.map(\.title))
        documentPicker.font = AppStyle.Font.controlLabel
        documentPicker.target = self
        documentPicker.action = #selector(selectDocument(_:))

        let heading = NSTextField(labelWithString: localized("Licenses & Acknowledgements"))
        heading.font = AppStyle.Font.windowTitle

        let intro = NSTextField(
            wrappingLabelWithString: localized("Language Switcher materials and bundled language data are covered by separate license terms.")
        )
        intro.font = AppStyle.Font.body
        intro.textColor = .secondaryLabelColor

        let header = NSStackView(views: [heading, intro, documentPicker])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 7
        header.setCustomSpacing(14, after: intro)
        header.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = AppStyle.Font.body
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(header)
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppStyle.Layout.windowInset),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppStyle.Layout.windowInset),
            header.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppStyle.Layout.windowTopInset),
            documentPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppStyle.Layout.windowInset),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppStyle.Layout.windowInset),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppStyle.Layout.windowTopInset)
        ])

        showDocument(at: 0)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = localized("Licenses & Acknowledgements")
        window.minSize = NSSize(width: 520, height: 380)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = contentView
        window.center()
        return window
    }

    @objc private func selectDocument(_ sender: NSPopUpButton) {
        showDocument(at: sender.indexOfSelectedItem)
    }

    private func showDocument(at index: Int) {
        guard documents.indices.contains(index) else { return }
        let document = documents[index]
        textView.textStorage?.setAttributedString(
            LicenseDocumentRenderer.render(document.text, format: document.format)
        )
        textView.scrollToBeginningOfDocument(nil)
    }

    private func loadDocuments() -> [Document] {
        var result = [
            Document(
                title: localizedFormat("License for %@", identity.productName),
                text: resourceText(named: "LICENSE")
                    ?? localizedFormat("The %@ license is unavailable.", identity.productName),
                format: .plainText
            ),
            Document(
                title: localized("Third-Party Materials & Notices"),
                text: resourceText(named: "THIRD_PARTY_NOTICES", extension: "md")
                    ?? localized("Third-party notices are unavailable."),
                format: .markdown
            )
        ]

        if let resourceBundle = lexiconResourceBundle() {
            if let attribution = resourceText(
                named: "ATTRIBUTION",
                extension: "md",
                bundle: resourceBundle
            ) {
                result.append(Document(title: localized("Frequency Data Attribution"), text: attribution, format: .markdown))
            }
            if let license = resourceText(
                named: "LICENSE-CC-BY-SA-4.0",
                extension: "txt",
                bundle: resourceBundle
            ) {
                result.append(Document(title: localized("CC BY-SA 4.0 Legal Code"), text: license, format: .plainText))
            }
        }
        return result
    }

    private func resourceText(
        named name: String,
        extension fileExtension: String? = nil,
        bundle: Bundle = .main
    ) -> String? {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func lexiconResourceBundle() -> Bundle? {
        guard let url = Bundle.main.url(
            forResource: "LanguageSwitcherKit_LanguageSwitcherLexicon",
            withExtension: "bundle"
        ) else {
            return nil
        }
        return Bundle(url: url)
    }
}
