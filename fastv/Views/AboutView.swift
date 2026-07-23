//
//  AboutView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import AppKit
import Combine
import SwiftUI

/// 关于窗口
struct AboutView: View {
    static let defaultWindowSize = CGSize(width: 700, height: 500)

    private let appGridColumns = [
        GridItem(.adaptive(minimum: 156), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Divider()

                recommendedAppsSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.defaultWindowSize.width, height: Self.defaultWindowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.accentColor)
        .focusable(false)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            AboutPenguinAnimationView()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(NSLocalizedString("app.name", comment: ""))
                        .font(.title2.weight(.semibold))

                    Text("v\(AppVersionManager.shortVersion)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(NSLocalizedString("about.summary", comment: ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: URL(string: "https://83d.me")!) {
                    Label(NSLocalizedString("about.author_homepage", comment: ""), systemImage: "link")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.link)
            }
        }
    }

    private var recommendedAppsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("about.other_apps", comment: ""))
                    .font(.headline)

                Text(NSLocalizedString("about.other_apps.summary", comment: ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: appGridColumns, alignment: .leading, spacing: 10) {
                ForEach(AboutRecommendedApp.allCases) { app in
                    AboutRecommendedAppCard(app: app)
                }
            }
        }
    }
}

enum AboutWindowOpener {
    private static var windowController: NSWindowController?

    static func open() {
        if let window = windowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = AboutView()
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: AboutView.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        let appName = NSLocalizedString("app.name", comment: "")
        let titleFormat = NSLocalizedString("about.title", comment: "")
        window.title = String(format: titleFormat, appName)
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.setContentSize(AboutView.defaultWindowSize)
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }
}

private struct AboutPenguinAnimationView: View {
    @State private var frameIndex = 0

    private let frameCount = 16
    private let timer = Timer.publish(every: 0.065, on: .main, in: .common).autoconnect()

    var body: some View {
        Image(currentFrameName)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .onReceive(timer) { _ in
                frameIndex = (frameIndex + 1) % frameCount
            }
    }

    private var currentFrameName: String {
        String(format: "PenguinWalkAbout%02d", frameIndex)
    }
}

private enum AboutRecommendedApp: String, CaseIterable, Identifiable {
    case willDeep
    case timeBill
    case museUploader
    case markReader
    case gitWise
    case veilPic
    case museMail
    case museMate

    var id: String { rawValue }

    var nameKey: String {
        "about.app.\(rawValue).name"
    }

    var summaryKey: String {
        "about.app.\(rawValue).summary"
    }

    var iconAssetName: String {
        switch self {
        case .willDeep:
            return "AboutAppWillDeepIcon"
        case .timeBill:
            return "AboutAppTimeBillIcon"
        case .museUploader:
            return "AboutAppMuseUploaderIcon"
        case .markReader:
            return "AboutAppMarkReaderIcon"
        case .gitWise:
            return "AboutAppGitWiseIcon"
        case .veilPic:
            return "AboutAppVeilPicIcon"
        case .museMail:
            return "AboutAppMuseMailIcon"
        case .museMate:
            return "AboutAppMuseMateIcon"
        }
    }

    var productURL: URL {
        switch self {
        case .willDeep:
            return URL(string: "https://83d.me/products/veilwriter")!
        case .timeBill:
            return URL(string: "https://83d.me/products/timebill")!
        case .museUploader:
            return URL(string: "https://83d.me/products/qpic")!
        case .markReader:
            return URL(string: "https://83d.me/products/qmarkview")!
        case .gitWise:
            return URL(string: "https://83d.me/products/gitwise")!
        case .veilPic:
            return URL(string: "https://83d.me/products/qpic")!
        case .museMail:
            return URL(string: "https://83d.me/products/qmailmate")!
        case .museMate:
            return URL(string: "https://83d.me/products/qnote")!
        }
    }
}

private struct AboutRecommendedAppCard: View {
    let app: AboutRecommendedApp

    var body: some View {
        Link(destination: app.productURL) {
            HStack(alignment: .center, spacing: 10) {
                Image(app.iconAssetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString(app.nameKey, comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(NSLocalizedString(app.summaryKey, comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.44), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AboutView()
}
