//
//  MainAppLaunchPolicyTests.swift
//  fastvTests
//
//  覆盖输入法「静默拉起主 App」的决策逻辑：节流、用户退出抑制、开机会话失效，
//  以及主 App 侧的静默启动标记识别。这条链路一旦判错，用户不是按 FN 没反应，
//  就是主 App 杀不死，两种都是事故。
//

import Testing
import Foundation
@testable import musetype

@Suite("主 App 自动拉起策略")
struct MainAppLaunchPolicyTests {

    private let boot = Date(timeIntervalSince1970: 1_000_000)

    @Test("主 App 已在运行时不重复拉起")
    func skipsWhenRunning() {
        #expect(MainAppLaunchPolicy.shouldAttemptLaunch(
            isMainAppRunning: true,
            lastAttemptAt: nil,
            suppressedAt: nil,
            systemBootAt: boot,
            now: boot.addingTimeInterval(60)
        ) == false)
    }

    @Test("主 App 未运行且从未尝试过：立即拉起")
    func launchesWhenMissing() {
        #expect(MainAppLaunchPolicy.shouldAttemptLaunch(
            isMainAppRunning: false,
            lastAttemptAt: nil,
            suppressedAt: nil,
            systemBootAt: boot,
            now: boot.addingTimeInterval(60)
        ))
    }

    @Test("节流窗口内不重复尝试：焦点频繁切换不该反复 open")
    func throttlesRapidRetries() {
        let now = boot.addingTimeInterval(600)
        let justTried = now.addingTimeInterval(-(MainAppLaunchPolicy.launchRetryInterval - 1))
        #expect(MainAppLaunchPolicy.shouldAttemptLaunch(
            isMainAppRunning: false,
            lastAttemptAt: justTried,
            suppressedAt: nil,
            systemBootAt: boot,
            now: now
        ) == false)
    }

    @Test("超过节流窗口后允许再次尝试")
    func retriesAfterInterval() {
        let now = boot.addingTimeInterval(600)
        let longAgo = now.addingTimeInterval(-(MainAppLaunchPolicy.launchRetryInterval + 1))
        #expect(MainAppLaunchPolicy.shouldAttemptLaunch(
            isMainAppRunning: false,
            lastAttemptAt: longAgo,
            suppressedAt: nil,
            systemBootAt: boot,
            now: now
        ))
    }

    @Test("本次开机内用户主动退出过：不再自动拉起")
    func respectsUserQuitInSameBootSession() {
        #expect(MainAppLaunchPolicy.shouldAttemptLaunch(
            isMainAppRunning: false,
            lastAttemptAt: nil,
            suppressedAt: boot.addingTimeInterval(120),
            systemBootAt: boot,
            now: boot.addingTimeInterval(300)
        ) == false)
    }

    @Test("上次开机的退出标记不应压制本次开机的自动拉起")
    func suppressionExpiresAfterReboot() {
        let previousBootQuit = boot.addingTimeInterval(-3600)
        #expect(MainAppLaunchPolicy.shouldAttemptLaunch(
            isMainAppRunning: false,
            lastAttemptAt: nil,
            suppressedAt: previousBootQuit,
            systemBootAt: boot,
            now: boot.addingTimeInterval(60)
        ))
    }

    @Test("静默启动标记：启动参数与环境变量都认，缺省为前台启动")
    func recognizesBackgroundLaunchMarkers() {
        #expect(MainAppLaunchPolicy.isBackgroundLaunch(
            arguments: ["/path/QEcho", MainAppLaunchPolicy.backgroundLaunchArgument],
            environment: [:]
        ))
        #expect(MainAppLaunchPolicy.isBackgroundLaunch(
            arguments: ["/path/QEcho"],
            environment: [MainAppLaunchPolicy.backgroundLaunchEnvironmentKey: "1"]
        ))
        #expect(MainAppLaunchPolicy.isBackgroundLaunch(
            arguments: ["/path/QEcho"],
            environment: [MainAppLaunchPolicy.backgroundLaunchEnvironmentKey: "0"]
        ) == false)
        #expect(MainAppLaunchPolicy.isBackgroundLaunch(
            arguments: ["/path/QEcho"],
            environment: [:]
        ) == false)
    }

    @Test("退出抑制标记：写入后可读回，清除后消失")
    func suppressionRoundTripsOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qecho-launch-policy-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(AutoLaunchSuppression.load(from: directory) == nil)

        let quitAt = Date(timeIntervalSince1970: 1_700_000_000)
        try AutoLaunchSuppression.write(quitAt: quitAt, to: directory)
        let loaded = AutoLaunchSuppression.load(from: directory)
        #expect(loaded?.quitAt.timeIntervalSince1970 == quitAt.timeIntervalSince1970)

        AutoLaunchSuppression.clear(in: directory)
        #expect(AutoLaunchSuppression.load(from: directory) == nil)
    }

    @Test("开机时间可取到，且早于当前时间")
    func systemBootDateIsSane() {
        let bootDate = MainAppLaunchPolicy.systemBootDate()
        #expect(bootDate < Date())
        #expect(bootDate > Date(timeIntervalSince1970: 1_000_000_000))
    }
}
