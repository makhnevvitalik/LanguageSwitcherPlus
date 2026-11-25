// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import AppKit
import SwiftUI

@MainActor
final class PanelPresentation: ObservableObject {
    @Published var isPanel = true
    @Published var monitoringWarning: KeyboardMonitoringWarning?
}

@MainActor
struct PanelContent: View {
    @ObservedObject var presentation: PanelPresentation
    @ObservedObject var updateAvailability: UpdateAvailability
    let name: String
    let width: CGFloat
    let settingsButton: NSPopUpButton
    let textTools: TextToolsMenuController
    let keyboardSwitching: KeyboardSwitchingMenuController
    let resume: () -> Void
    let openRelease: () -> Void

    private static let brandIcon = AppStyle.Icon.brandImage(NSApp.applicationIconImage, size: AppStyle.Icon.brandSize)

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Layout.cardSpacing) {
            header
            if let warning = presentation.monitoringWarning {
                monitoringNotice(warning)
            }
            textTools.content(isPanel: presentation.isPanel)
            keyboardSwitching.content
        }
        .padding(AppStyle.Layout.panelInset)
        .frame(width: width)
        .controlSize(.small)
        .font(Font(AppStyle.Font.body))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func monitoringNotice(_ warning: KeyboardMonitoringWarning) -> some View {
        HStack {
            Image(systemName: "exclamationmark.shield").foregroundStyle(.orange).accessibilityHidden(true)
            Text(warning.title)
                .font(Font(AppStyle.Font.fieldLabel))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(warning.buttonTitle, action: resume).fixedSize()
        }
        .padding(8).padding(.horizontal, 4)
        .background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: AppStyle.Layout.cardCornerRadius))
    }

    private var header: some View {
        HStack(spacing: AppStyle.Layout.headerItemSpacing) {
            Image(nsImage: Self.brandIcon).resizable().scaledToFit()
                .frame(width: AppStyle.Icon.brandSize.width, height: AppStyle.Icon.brandSize.height)
                .frame(width: AppStyle.Layout.headerIconFrame, height: AppStyle.Layout.headerIconFrame)
            VStack(alignment: .leading, spacing: AppStyle.Layout.headerStatusSpacing) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: AppStyle.Layout.headerVersionSpacing) {
                        title
                        version
                    }.fixedSize()
                    VStack(alignment: .leading, spacing: AppStyle.Layout.headerStatusSpacing) {
                        title
                        version
                    }.fixedSize(horizontal: false, vertical: true)
                }
                if updateAvailability.release != nil {
                    Button(localized("Update available"), action: openRelease)
                        .buttonStyle(.link)
                        .font(Font(AppStyle.Font.statusText))
                        .frame(minHeight: AppStyle.Layout.headerStatusHeight)
                } else {
                    Color.clear.frame(width: 0, height: AppStyle.Layout.headerStatusHeight)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PanelNativeControl(view: settingsButton)
                .frame(width: AppStyle.Layout.settingsButtonSize.width, height: AppStyle.Layout.settingsButtonSize.height)
        }
        .padding(.horizontal, AppStyle.Layout.headerHorizontalInset)
        .frame(minHeight: AppStyle.Layout.headerHeight)
    }

    private var title: some View { Text(name).font(Font(AppStyle.Font.appName)) }

    @ViewBuilder private var version: some View {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            Text(version).font(Font(AppStyle.Font.metadata)).foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct PanelNativeControl<Control: NSView>: NSViewRepresentable {
    let view: Control

    func makeNSView(context: Context) -> Control { view }
    func updateNSView(_ nsView: Control, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Control, context: Context) -> CGSize? {
        nsView.fittingSize
    }
}

@MainActor
struct PanelCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: symbol)
                .font(Font(AppStyle.Font.sectionTitle))
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppStyle.Layout.cardInset)
                .frame(minHeight: AppStyle.Layout.sectionHeaderHeight)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: AppStyle.Color.cardBackground), in: RoundedRectangle(cornerRadius: AppStyle.Layout.cardCornerRadius))
    }
}

@MainActor
struct PanelRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: AppStyle.Layout.rowItemSpacing) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(detail).font(Font(AppStyle.Font.supportingText)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            control.fixedSize()
        }
        .padding(.horizontal, AppStyle.Layout.cardInset)
        .padding(.vertical, 3)
        .frame(minHeight: detail == nil ? AppStyle.Layout.rowHeight : AppStyle.Layout.detailedRowHeight)
    }
}
