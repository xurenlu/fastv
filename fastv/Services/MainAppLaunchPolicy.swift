//
//  MainAppLaunchPolicy.swift
//  fastv
//
//  主 App（轻语）自动拉起策略。本文件同时编译进 musetype 与 QechoIME 两个 target：
//  输入法进程按此决定「要不要把主 App 静默拉起来」，主 App 按此识别自己是否为静默启动。
//
//  背景：FN 热键监听与录音管线都住在主 App。用户只选中输入法时，系统只会拉起 IME 进程，
//  主 App 不在跑 → 没人监听 FN → 语音输入按不出来。所以由 IME 在焦点进入输入框时兜底拉起。
//
//  纯决策逻辑（无 AppKit / 文件 IO）集中在此，便于单测覆盖。
//

import Foundation

enum MainAppLaunchPolicy {
    /// 静默启动标记：IME 拉起主 App 时通过启动参数传入，主 App 据此不显示窗口、不抢焦点。
    static let backgroundLaunchArgument = "--background-launch"

    /// 同义的环境变量开关（调试与脚本用；值为 "1" 生效）
    static let backgroundLaunchEnvironmentKey = "QECHO_BACKGROUND_LAUNCH"

    /// 自动拉起的最小重试间隔（秒）。
    /// `activateServer` 在每次焦点进入输入框时都会触发检查，没有节流会在主 App 起不来
    /// （被删除 / 签名失效 / 用户拒绝）时反复 open，制造持续的系统噪音。
    static let launchRetryInterval: TimeInterval = 15

    /// 「用户主动退出主 App」抑制标记文件名，与 IME 设置同目录。
    static let suppressionFileName = "auto-launch-suppressed.json"

    /// 判断当前进程是否为静默启动
    static func isBackgroundLaunch(arguments: [String], environment: [String: String]) -> Bool {
        if arguments.contains(backgroundLaunchArgument) { return true }
        return environment[backgroundLaunchEnvironmentKey] == "1"
    }

    /// 是否应当尝试拉起主 App。
    ///
    /// - Parameters:
    ///   - isMainAppRunning: 主 App 进程是否已存在
    ///   - lastAttemptAt: 本 IME 进程上次尝试拉起的时间，nil 表示从未尝试
    ///   - suppressedAt: 用户主动退出主 App 的时间，nil 表示无抑制标记
    ///   - systemBootAt: 本次开机时间；抑制标记只在同一次开机会话内有效，重启即失效
    ///   - now: 当前时间
    static func shouldAttemptLaunch(
        isMainAppRunning: Bool,
        lastAttemptAt: Date?,
        suppressedAt: Date?,
        systemBootAt: Date,
        now: Date
    ) -> Bool {
        guard !isMainAppRunning else { return false }
        // 用户这次开机后主动退过主 App：尊重意图，不再自动拉起（否则这玩意儿杀不死）
        if let suppressedAt, suppressedAt >= systemBootAt { return false }
        if let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < launchRetryInterval { return false }
        return true
    }

    /// 本次开机时间。sysctl 取不到时返回 `.distantPast`，
    /// 此时抑制标记恒被视为「本次开机内」，宁可不自动拉起，也不违背用户的退出意图。
    static func systemBootDate() -> Date {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else { return .distantPast }
        return Date(timeIntervalSince1970: Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000)
    }
}

/// 「用户主动退出主 App」抑制标记。主 App 在 `applicationShouldTerminate` 写入，
/// 前台启动时清除；IME 读取后在同一次开机会话内不再自动拉起。
struct AutoLaunchSuppression: Codable, Equatable {
    let quitAt: Date

    static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(MainAppLaunchPolicy.suppressionFileName, isDirectory: false)
    }

    static func load(from directory: URL = InputMethodBridgeContract.imeUserDataDirectory()) -> AutoLaunchSuppression? {
        guard let data = try? Data(contentsOf: fileURL(in: directory)) else { return nil }
        return try? JSONDecoder().decode(AutoLaunchSuppression.self, from: data)
    }

    static func write(
        quitAt: Date = Date(),
        to directory: URL = InputMethodBridgeContract.imeUserDataDirectory()
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(AutoLaunchSuppression(quitAt: quitAt))
        try data.write(to: fileURL(in: directory), options: .atomic)
    }

    /// 清除抑制标记（主 App 前台启动即视为用户又要用了）
    static func clear(in directory: URL = InputMethodBridgeContract.imeUserDataDirectory()) {
        try? FileManager.default.removeItem(at: fileURL(in: directory))
    }
}
