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

            RecommendedAppsGrid()
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

#Preview {
    AboutView()
}
