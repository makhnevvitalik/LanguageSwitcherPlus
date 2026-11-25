// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

//
//  AboutWindowController.swift
//  LanguageSwitcher
//
//  Created by Vitalik Makhnev on 11.06.2026.
//

import AppKit
import Combine
import Foundation
import LanguageSwitcherEdition
import LanguageSwitcherMacOS

@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private let identity: AppIdentity
    private let updates: GitHubReleaseChecker
    private var updateObservation: AnyCancellable?
    private var aboutWindow: NSWindow?
    private var returnToSource: (() -> Void)?
    private var licensesWindowController: LicensesAcknowledgementsWindowController?
    private var updateButton: NSButton?
    private var releaseButton: NSButton?
    private var updateProgressIndicator: NSProgressIndicator?
    private var updateStatusLabel: NSTextField?
    private weak var contentStack: NSStackView?
    init(identity: AppIdentity, updates: GitHubReleaseChecker) {
        self.identity = identity
        self.updates = updates
        super.init()
        updateObservation = updates.$state.dropFirst().sink { [weak self] state in
            guard let self, self.aboutWindow != nil else { return }
            self.refreshUpdateControls(state: state)
        }
    }

    func showWindow(returningTo source: (() -> Void)? = nil) {
        if aboutWindow == nil {
            aboutWindow = makeAboutWindow()
        }
        if let source { returnToSource = source }
        refreshUpdateControls(state: updates.state)

        NSApp.activate(ignoringOtherApps: true)
        if let aboutWindow {
            AppStyle.showWithoutInitialControlFocus(aboutWindow)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let returnToSource else { return }
        self.returnToSource = nil
        DispatchQueue.main.async { [weak self] in
            guard self?.aboutWindow?.isVisible == false else { return }
            returnToSource()
        }
    }

    private var copyrightText: String {
        (Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
            .replacingOccurrences(of: "Copyright ", with: "")
    }

    private func makeAboutWindow() -> NSWindow {
        let updateButton = NSButton(title: localized("Check for Updates"), target: self,
                                    action: #selector(updateButtonPressed))
        let releaseButton = NSButton(title: "", target: self, action: #selector(openRelease))
        let licensesButton = NSButton(title: localized("Licenses…"), target: self, action: #selector(showLicenses))
        let content = AboutContent(name: identity.productName, icon: NSApp.applicationIconImage,
            tagline: localized("Switch keyboard layouts and fix text typed in the wrong layout or case."),
            copyright: copyrightText, updateButton: updateButton, releaseButton: releaseButton,
            gitHubButton: NSButton(title: "GitHub ↗", target: self, action: #selector(openGitHub)),
            licensesButton: licensesButton, statusIdentifier: "AboutUpdateStatus")
        self.updateButton = updateButton
        self.releaseButton = releaseButton
        updateProgressIndicator = content.progressIndicator
        updateStatusLabel = content.statusLabel
        contentStack = content.contentStack

        let window = AppStyle.InformationWindow(
            contentRect: NSRect(x: 0, y: 0, width: AppStyle.AboutLayout.width, height: 1),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = localizedFormat("About %@", identity.productName)
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = content.view
        AppStyle.sizeAboutWindow(window, to: content.contentStack)
        window.center()

        return window
    }

    @objc private func openGitHub() {
        returnToSource = nil
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
        updates.check()
    }

    @objc private func openRelease() {
        guard let release = updates.availableRelease else { return }
        NSWorkspace.shared.open(release.url)
    }

    private func refreshUpdateControls(state: GitHubReleaseChecker.State) {
        let checking: Bool
        if case .checking = state { checking = true } else { checking = false }
        let release = updates.availableRelease
        updateButton?.title = localized(checking ? "Checking…" : "Check for Updates")
        updateButton?.isEnabled = !checking
        let releaseTitle = release.map { localizedFormat("%@ is available", $0.tag) }
        releaseButton?.title = releaseTitle.map { $0 + " ↗" } ?? ""
        releaseButton?.toolTip = releaseTitle
        releaseButton?.setAccessibilityLabel(releaseTitle)
        releaseButton?.setAccessibilityHelp(localized("View Release"))
        releaseButton?.isHidden = release == nil

        let status: String
        switch state {
        case .finished(.upToDate):
            updateStatusLabel?.textColor = AppStyle.Color.success
            status = localized("You’re up to date.")
        case .finished(.notPublished):
            updateStatusLabel?.textColor = .secondaryLabelColor
            status = localized("The repository or a public release has not been published yet.")
        case let .finished(.failure(failure)):
            updateStatusLabel?.textColor = .systemRed
            status = updateFailureText(failure)
        case .idle, .checking, .finished(.updateAvailable):
            updateStatusLabel?.textColor = .secondaryLabelColor
            status = checking && release == nil ? localized("Checking GitHub for updates…") : ""
        }
        updateStatusLabel?.isHidden = release != nil && status.isEmpty
        updateProgressIndicator?.isHidden = !checking
        if checking { updateProgressIndicator?.startAnimation(nil) }
        else { updateProgressIndicator?.stopAnimation(nil) }
        setUpdateStatusText(status)
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
        case .rateLimited:
            return localized("GitHub’s request limit was reached. Please try again later.")
        case let .http(status):
            return localizedFormat("GitHub returned HTTP %d.", status)
        }
    }

    private func setUpdateStatusText(_ text: String) {
        updateStatusLabel?.stringValue = text
        updateStatusLabel?.toolTip = text.isEmpty ? nil : text
        if let aboutWindow, let contentStack {
            AppStyle.sizeAboutWindow(aboutWindow, to: contentStack)
        }
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
