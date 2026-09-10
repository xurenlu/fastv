//
//  WaveformHideSchedulingTests.swift
//  fastvTests
//
//  悬浮指示器的延迟隐藏必须可取消。
//
//  用户反馈两个连在一起的现象：说完一句之后悬浮条还顶着一个 AI 图标多停 1~2 秒；
//  而且这段时间内再按快捷键，悬浮条「容易出不来」。
//
//  根因是同一处：`setAICorrection*` 用裸的 `DispatchQueue.main.asyncAfter { hide() }`
//  排延迟隐藏，没有任何人能取消它。于是上一轮遗留的 hide 会在下一轮 show() 之后到点触发，
//  把刚显示出来的新窗口关掉。
//

import Testing
import Foundation
import AppKit
@testable import musetype

@Suite("悬浮指示器隐藏调度", .serialized)
@MainActor
struct WaveformHideSchedulingTests {

    /// 等待到给定时刻，其间让主线程 runloop 继续跑（延迟隐藏是投递到主队列的）。
    private func spin(seconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            await Task.yield()
        }
    }

    @Test("上一轮排下的延迟隐藏，不能关掉下一轮刚显示的窗口")
    func pendingHideDoesNotCloseNextSession() async {
        let manager = WaveformWindowManager.shared

        // 第一轮：结束时排了一个 0.8 秒后的隐藏
        manager.show()
        manager.setAICorrectionDisabled()

        // 用户在这 0.8 秒内又按了一次快捷键
        await spin(seconds: 0.2)
        manager.show()
        #expect(manager.isVisible, "刚 show() 完必须是可见的")

        // 越过上一轮那个 0.8 秒的时间点
        await spin(seconds: 0.9)
        #expect(manager.isVisible, "上一轮遗留的延迟隐藏不该把这一轮的窗口关掉")

        manager.cleanup()
    }

    @Test("处理中的状态切换会撤掉待执行的隐藏")
    func workingStatesCancelPendingHide() async {
        let manager = WaveformWindowManager.shared

        manager.show()
        manager.setAICorrectionDisabled()   // 排下 0.8 秒隐藏
        await spin(seconds: 0.2)
        manager.setTranscribing()           // 又开始干活了，隐藏必须撤掉

        await spin(seconds: 0.9)
        #expect(manager.isVisible, "切回处理中状态后，窗口不该被之前排的隐藏关掉")

        manager.cleanup()
    }

    @Test("纯语音输入结束立即收起，不经过 AI 状态")
    func pureVoiceInputFinishesImmediately() async {
        let manager = WaveformWindowManager.shared

        manager.show()
        #expect(manager.isVisible)

        manager.finishWithoutAICorrection()
        // hide() 会立刻把 isVisible 置 false，窗口引用延迟 0.3 秒再释放
        #expect(!manager.isVisible, "纯语音输入结束应立即收起，而不是顶着 AI 图标停 0.8 秒")

        await spin(seconds: 0.4)
        manager.cleanup()
    }
}
