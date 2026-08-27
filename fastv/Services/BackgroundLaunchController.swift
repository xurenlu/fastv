//
//  BackgroundLaunchController.swift
//  fastv
//
//  静默启动（由输入法进程拉起）状态。
//
//  静默启动时主 App 只承担「托盘 + FN 热键 + 录音」，不显示主窗口、不抢焦点：
//  用户只是切到了轻语输入法，并没有要求打开设置界面。
//  一旦用户主动要窗口（托盘「显示轻语」/ Dock 点击 / 输入法菜单「打开轻语设置」），
//  本次进程就退出静默态，窗口按常规显示。
//

import AppKit

@MainActor
final class BackgroundLaunchController {
    static let shared = BackgroundLaunchController()

    /// 本次进程是否由输入法静默拉起
    let isBackgroundLaunch: Bool

    /// 静默启动后用户是否已主动要过窗口
    private(set) var windowRevealed = false

    private init() {
        isBackgroundLaunch = MainAppLaunchPolicy.isBackgroundLaunch(
            arguments: CommandLine.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    /// 主窗口是否应保持隐藏
    var shouldKeepWindowHidden: Bool {
        isBackgroundLaunch && !windowRevealed
    }

    /// 用户主动要窗口了：退出静默态（幂等）
    func markWindowRevealed() {
        guard !windowRevealed else { return }
        windowRevealed = true
        print("🪟 [BackgroundLaunch] 用户主动请求窗口，退出静默启动态")
    }
}
