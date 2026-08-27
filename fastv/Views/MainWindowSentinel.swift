//
//  MainWindowSentinel.swift
//  fastv
//
//  挂在 ContentView 的 `.background` 里。两个职责：
//
//  1. 给主窗口打 identifier `mainContentWindowId`，让 StatusBarManager /
//     AppDelegate 能可靠地在 `NSApp.windows` 里找回它，不再误打到
//     `NSStatusBarWindow`（即「显示妙打」点了无反应那条 bug）。
//
//  2. 拦截红色关闭按钮：点关闭时只 `orderOut(nil)` 把窗口隐藏，不真正
//     close。这样窗口对象常驻 `NSApp.windows`，托盘菜单 / Dock 点击都能
//     直接 makeKeyAndOrderFront 找回来。
//
//  注：不替换 SwiftUI 内部设置的 NSWindowDelegate，避免破坏框架内部观察；
//  Cmd+W 仍会走 SwiftUI 默认 close 路径，由 StatusBarManager 的 fallback
//  兜底（filter + 重激活）处理。
//

import SwiftUI
import AppKit

/// 主窗口标识符。供 StatusBarManager / AppDelegate 在 `NSApp.windows` 里定位。
let mainContentWindowId = "museTypeMainContentWindow"

struct MainWindowSentinel: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityHidden(true)
        DispatchQueue.main.async {
            installIfReady(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 视图重用到新窗口的兜底
        DispatchQueue.main.async {
            installIfReady(nsView.window)
        }
    }

    private func installIfReady(_ window: NSWindow?) {
        guard let window = window else { return }

        // 1. 打 identifier
        if window.identifier?.rawValue != mainContentWindowId {
            window.identifier = NSUserInterfaceItemIdentifier(mainContentWindowId)
        }

        // 1.5 静默启动（输入法拉起）：SwiftUI 的 WindowGroup 一定会建窗，这里建完即隐。
        //     用户只是切了输入法，不该被弹一个设置窗口。
        if MainActor.assumeIsolated({ BackgroundLaunchController.shared.shouldKeepWindowHidden }) {
            window.orderOut(nil)
        }

        // 2. 红色关闭按钮 → 隐藏（不 close）
        if let closeButton = window.standardWindowButton(.closeButton),
           closeButton.target !== MainWindowCloseInterceptor.shared {
            closeButton.target = MainWindowCloseInterceptor.shared
            closeButton.action = #selector(MainWindowCloseInterceptor.hideMainWindow(_:))
        }
    }
}

/// 共享的「把主窗口拉到前面」逻辑：identifier 优先 → 排除 NSStatusBarWindow
/// 的内容窗口兜底 → 都找不到时 activate 触发系统重激活。
///
/// 给 StatusBarManager 的「显示妙打」菜单与 AppDelegate 的
/// `applicationShouldHandleReopen` 共用。
enum MainWindowPresenter {
    /// 用于 NSWindow.identifier 比较，需与 MainWindowSentinel 装的一致。
    static let windowIdentifier = mainContentWindowId

    /// 尝试找回并显示主内容窗口。命中返回 true；未命中（窗口已被销毁）返回 false。
    @MainActor
    static func bringToFront() -> Bool {
        // 用户主动要窗口了：退出静默启动态，恢复常规 Dock / 激活策略
        BackgroundLaunchController.shared.markWindowRevealed()
        AppDelegate.applyDockIconPolicy()

        // 不管哪条路径，都先激活 App
        NSApp.activate(ignoringOtherApps: true)

        // 1. identifier 命中 → 直接显示（最快、最准）
        if let main = NSApp.windows.first(where: { $0.identifier?.rawValue == windowIdentifier }) {
            main.makeKeyAndOrderFront(nil)
            return true
        }

        // 2. 退一步：找第一个 canBecomeKey 且非 NSStatusBarWindow / 非 borderless
        //    的窗口（borderless 是 WaveformWindowManager 的小工具条，不是主窗口）
        if let content = NSApp.windows.first(where: { window in
            let cls = String(describing: type(of: window))
            if cls == "NSStatusBarWindow" { return false }
            if window.styleMask.contains(.borderless) { return false }
            return window.canBecomeKey
        }) {
            content.makeKeyAndOrderFront(nil)
            return true
        }

        // 3. 兜底：窗口对象已被 SwiftUI 销毁（用户用 Cmd+W 真正关掉过）。
        //    切到 .regular 激活策略让 SwiftUI 有机会重建 WindowGroup 场景；
        //    若用户偏好仍是「隐藏 Dock 图标」，等窗口出现后再切回 .accessory。
        print("⚠️ [MainWindowPresenter] 找不到主内容窗口，尝试触发激活重建")
        let preferredHidden = UserPreferences.shared.hideDockIcon
        if preferredHidden {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if UserPreferences.shared.hideDockIcon {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        return false
    }
}

/// 关闭按钮 target，把红 × 改为 orderOut。
final class MainWindowCloseInterceptor: NSObject {
    static let shared = MainWindowCloseInterceptor()
    private override init() { super.init() }

    @objc func hideMainWindow(_ sender: Any?) {
        // sender 可能是 NSButton；取其 window；否则按 identifier 找
        let window: NSWindow?
        if let btn = sender as? NSButton {
            window = btn.window
        } else {
            window = NSApp.windows.first { $0.identifier?.rawValue == mainContentWindowId }
        }
        guard let win = window else { return }
        print("🪟 [MainWindowCloseInterceptor] 拦截关闭按钮，仅 orderOut 隐藏主窗口")
        win.orderOut(nil)
    }
}
