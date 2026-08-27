//
//  MainAppLauncher.swift
//  QechoIME
//
//  输入法进程负责保证主 App（轻语）在跑：FN 热键监听、录音与转写全部住在主 App，
//  只选中输入法而主 App 没进程时，按 FN 不会有任何反应。因此焦点每次进入输入框
//  （`activateServer`）都检查一次，必要时静默拉起，不抢焦点、不显示窗口。
//
//  所有调用都在主 RunLoop（IMKit 回调线程），无需加锁。
//

import Cocoa

final class MainAppLauncher {
    static let shared = MainAppLauncher()

    /// 本进程上次尝试拉起主 App 的时间，用于节流（见 MainAppLaunchPolicy.launchRetryInterval）
    private var lastAttemptAt: Date?

    private init() {}

    /// 主 App 进程是否已存在
    var isMainAppRunning: Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: InputMethodBridgeContract.mainAppBundleID)
            .isEmpty
    }

    /// 焦点进入输入框时调用：主 App 不在跑就静默拉起。
    /// 用户主动退出过主 App 时（同一次开机会话内）不再自动拉起。
    func ensureMainAppRunning() {
        let shouldLaunch = MainAppLaunchPolicy.shouldAttemptLaunch(
            isMainAppRunning: isMainAppRunning,
            lastAttemptAt: lastAttemptAt,
            suppressedAt: AutoLaunchSuppression.load()?.quitAt,
            systemBootAt: MainAppLaunchPolicy.systemBootDate(),
            now: Date()
        )
        guard shouldLaunch else { return }
        lastAttemptAt = Date()
        launch(activating: false)
    }

    /// 输入法菜单「打开轻语设置」：前台拉起主 App 并请求它打开设置窗口
    func openMainAppSettings() {
        launch(activating: true)
        let post = {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(InputMethodBridgeContract.openSettingsDistributedNotification),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
        post()
        // 主 App 冷启动时首个通知可能赶不上观察者注册，延迟补发一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: post)
    }

    // MARK: - Private

    /// - Parameter activating: true 为用户显式操作（前台拉起）；false 为静默保活启动
    private func launch(activating: Bool) {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: InputMethodBridgeContract.mainAppBundleID
        ) else {
            NSLog("QechoIME: 找不到主 App（\(InputMethodBridgeContract.mainAppBundleID)），语音输入不可用")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activating
        configuration.addsToRecentItems = false
        if !activating {
            // 静默启动：主 App 据此只起托盘与热键监听，不显示主窗口、不抢焦点
            configuration.arguments = [MainAppLaunchPolicy.backgroundLaunchArgument]
        }

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("QechoIME: 拉起主 App 失败：\(error.localizedDescription)")
            }
        }
    }
}
