//
//  ContentView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

/// 测试 runner（xcodebuild test）会让主 app 跟测试 bundle 共宿一个进程；
/// macOS 26 的 SwiftUI 在 test bootstrap 阶段求值真实主界面时会在 AttributeGraph
/// 里 SIGSEGV（`InitialAllocationPool` → `ContentView.body.getter`），让 runner
/// 还没连上就先挂掉。单测根本不需要 UI，统一短路即可。
let isRunningUnderXCTest: Bool = {
    let env = ProcessInfo.processInfo.environment
    return env["XCTestConfigurationFilePath"] != nil
        || env["XCInjectBundleInto"] != nil
        || NSClassFromString("XCTestCase") != nil
}()

struct ContentView: View {
    @State private var showSettings = false
    @ObservedObject private var preferences = UserPreferences.shared

    var body: some View {
        if isRunningUnderXCTest {
            // 测试态：渲染一个最小占位 view，避免真实主界面 + 一堆 @ObservedObject
            // 单例在 XCTest host 里求值导致的 SwiftUI runtime crash。
            Color.clear.frame(width: 1, height: 1)
        } else {
            mainBody
                // 装 sentinel：给主窗口打 identifier、拦截关闭按钮改为 orderOut，
                // 这样系统托盘的「显示妙打」/ Dock 点击 / applicationShouldHandleReopen
                // 能可靠找回主窗口，不再误打到 NSStatusBarWindow。
                .background(MainWindowSentinel())
        }
    }

    @ViewBuilder
    private var mainBody: some View {
        Group {
            if !preferences.hasCompletedOnboarding {
                OnboardingView()
            } else {
                VoiceInputView()
                    .frame(minWidth: 560, minHeight: 520)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button(action: { showSettings = true }) {
                                Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                            }
                            .help(NSLocalizedString("settings", comment: ""))
                            .focusable(false)
                        }
                    }
                    .sheet(isPresented: $showSettings) {
                        SettingsView()
                            .frame(minWidth: 800, idealWidth: 900, maxWidth: 1000, minHeight: 600, idealHeight: 700, maxHeight: 800)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                        showSettings = true
                    }
            }
        }
        .onChange(of: preferences.hasCompletedOnboarding) { _, completed in
            if completed {
                SpeechModelPreloadManager.shared.startPreloadIfNeeded()
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

#Preview {
    ContentView()
}
