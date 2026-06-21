//
//  AppContextResolver.swift
//  fastv
//
//  从 NSWorkspace + AX API 解析当前前台 App 的上下文（bundleId / appName / 浏览器 URL），
//  供 Power Mode (ContextProfileManager) 按 App 匹配 prompt 模板。
//
//  缓存策略：1 秒 TTL，避免每次录音都重复 AX 调用。
//

import Foundation
import AppKit
import ApplicationServices

/// 当前前台 App 的上下文快照
struct AppContext: Equatable {
    /// Bundle ID，如 "com.apple.mail" / "com.google.Chrome" / "com.apple.dt.Xcode"
    let bundleId: String?
    /// localizedName，如 "邮件" / "Visual Studio Code"
    let appName: String?
    /// 浏览器当前 tab 的 URL（仅 Safari / Chrome / Arc / Edge，其它返回 nil）
    let browserURL: String?
    /// 解析时间戳（缓存判定用）
    let resolvedAt: Date

    static let unknown = AppContext(bundleId: nil, appName: nil, browserURL: nil, resolvedAt: Date(timeIntervalSince1970: 0))
}

/// 解析前台 App 上下文。线程：所有方法均在主线程或经由 NSWorkspace 同步调用，主线程安全。
final class AppContextResolver {
    static let shared = AppContextResolver()

    private var cache: AppContext = .unknown
    private let cacheTTL: TimeInterval = 1.0

    private init() {}

    /// 解析当前前台 App 上下文。1s 内重复调用返回缓存。
    /// 注意：AX API 在沙盒受限或未授权时会安静失败（返回 nil URL），不会崩。
    func resolve() -> AppContext {
        let now = Date()
        if now.timeIntervalSince(cache.resolvedAt) < cacheTTL && cache != .unknown {
            return cache
        }

        let workspace = NSWorkspace.shared
        guard let app = workspace.frontmostApplication else {
            cache = AppContext(bundleId: nil, appName: nil, browserURL: nil, resolvedAt: now)
            return cache
        }

        let bundleId = app.bundleIdentifier
        let appName = app.localizedName
        let url = Self.extractBrowserURL(for: app)

        let ctx = AppContext(bundleId: bundleId, appName: appName, browserURL: url, resolvedAt: now)
        cache = ctx
        return ctx
    }

    /// 让缓存立即失效，下次 resolve 强制重抓。
    func invalidate() {
        cache = .unknown
    }

    // MARK: - 内部：浏览器 URL 抽取

    /// 支持抽取 URL 的浏览器 bundleId 列表。
    /// 这些浏览器走 AX 树时都把当前 tab 的 webarea 暴露在 AXWebArea 节点上，URL 在 kAXURL 属性。
    private static let browserBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "company.thebrowser.Browser", // Arc
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
    ]

    /// 尝试通过 AX API 抽出前台浏览器当前 tab 的 URL。
    /// 失败（非浏览器 / 无 AX 权限 / 未加载页面）返回 nil。
    private static func extractBrowserURL(for app: NSRunningApplication) -> String? {
        guard let bundleId = app.bundleIdentifier,
              browserBundleIds.contains(bundleId) else {
            return nil
        }
        guard AXIsProcessTrusted() else {
            return nil
        }

        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        // 优先：focused window → AXWebArea → kAXURL
        if let url = findBrowserURL(from: axApp, depth: 0) {
            return url
        }
        return nil
    }

    /// 在 AX 树里 DFS 找第一个有 kAXURL 属性的节点的 URL；限深度避免遍历过深。
    private static func findBrowserURL(from element: AXUIElement, depth: Int) -> String? {
        if depth > 6 { return nil }

        // 直接尝试读 kAXURL
        var urlValue: CFTypeRef?
        let urlResult = AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &urlValue)
        if urlResult == .success {
            if let nsurl = urlValue as? URL {
                return nsurl.absoluteString
            }
            if let str = urlValue as? String {
                return str
            }
        }

        // role: 是 AXWebArea 但没 URL 也不要继续往下钻（叶子）
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if roleResult == .success, let role = roleValue as? String, role == "AXWebArea" {
            return nil
        }

        // 递归子节点
        var childrenValue: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        if childResult == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                if let found = findBrowserURL(from: child, depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
    }
}
