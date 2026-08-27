//
//  AccessibilityTrustWatcher.swift
//  fastv
//
//  辅助功能权限守望者。
//
//  `NSEvent.addGlobalMonitorForEvents` 在未授权时不报错、只是永远收不到事件——
//  表现就是「按 FN 毫无反应」。而用户在系统设置里勾选授权后，已注册的监听器不会
//  自动复活，必须重新注册。这里在未授权期间轮询（5 秒一次，授权后立即停），
//  权限一到手就回调宿主重新注册热键并刷新菜单栏提示。
//

import AppKit
import ApplicationServices

@MainActor
final class AccessibilityTrustWatcher {
    static let shared = AccessibilityTrustWatcher()

    /// 轮询间隔：仅在未授权期间运行，授权后立即停止
    private static let pollInterval: TimeInterval = 5

    private var timer: Timer?

    /// 权限从「未授权」变为「已授权」时回调（主线程）
    var onTrustGranted: (() -> Void)?

    private init() {}

    /// 当前是否已获辅助功能权限（不弹系统授权框）。
    /// 菜单栏渲染等非主 actor 上下文也要读，故声明为 nonisolated。
    nonisolated static var isTrusted: Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        )
    }

    /// 未授权时开始轮询；已授权则直接返回，不占用任何定时器
    func startIfNeeded() {
        guard timer == nil else { return }
        guard !Self.isTrusted else { return }

        print("👀 [AccessibilityTrust] 未获辅助功能权限，开始轮询等待授权")
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkNow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 立即检查一次（菜单栏菜单展开、App 激活时可主动调用）
    func checkNow() {
        guard Self.isTrusted else { return }
        stop()
        print("✅ [AccessibilityTrust] 辅助功能权限已授权，重新注册全局热键")
        onTrustGranted?()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 打开系统设置的「辅助功能」页
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
