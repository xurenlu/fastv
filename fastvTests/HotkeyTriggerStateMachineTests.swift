//
//  HotkeyTriggerStateMachineTests.swift
//  fastvTests
//
//  覆盖 pushToTalk / toggle / hybrid 三种触发模式的状态机行为。
//

import Testing
import Foundation
@testable import musetype

@Suite("HotkeyTriggerStateMachine")
struct HotkeyTriggerStateMachineTests {

    // 帮手：把回调录到数组里，便于断言"按下/松开"顺序
    final class Recorder {
        enum Event: Equatable { case press(ShortcutType, Bool); case release(ShortcutType, Bool) }
        var events: [Event] = []
    }

    private func makeMachine(_ mode: HotkeyTriggerMode) -> (HotkeyTriggerStateMachine, Recorder) {
        let m = HotkeyTriggerStateMachine()
        m.mode = mode
        let r = Recorder()
        m.onPress = { type, ctrl in r.events.append(.press(type, ctrl)) }
        m.onRelease = { type, ctrl in r.events.append(.release(type, ctrl)) }
        return (m, r)
    }

    // MARK: - pushToTalk

    @Test("pushToTalk: 按下 fire press、松开 fire release，1:1 透传")
    func pushToTalkPassesThrough() {
        let (m, r) = makeMachine(.pushToTalk)
        m.handleRawPress(type: .voiceInput, hasCtrl: false)
        m.handleRawRelease(type: .voiceInput, hasCtrl: false)
        m.handleRawPress(type: .voiceInputWithAI, hasCtrl: true)
        m.handleRawRelease(type: .voiceInputWithAI, hasCtrl: true)

        #expect(r.events == [
            .press(.voiceInput, false),
            .release(.voiceInput, false),
            .press(.voiceInputWithAI, true),
            .release(.voiceInputWithAI, true),
        ])
    }

    // MARK: - toggle

    @Test("toggle: 第一次按下 fire press、松开忽略；再按下 fire release")
    func toggleFirstPressStartsSecondPressStops() {
        let (m, r) = makeMachine(.toggle)
        m.handleRawPress(type: .voiceInput, hasCtrl: false)
        m.handleRawRelease(type: .voiceInput, hasCtrl: false)
        #expect(r.events == [.press(.voiceInput, false)])

        m.handleRawPress(type: .voiceInput, hasCtrl: false)
        #expect(r.events == [.press(.voiceInput, false), .release(.voiceInput, false)])
    }

    @Test("toggle: 松开永不 fire release，无论按多少次松开")
    func toggleIgnoresRawRelease() {
        let (m, r) = makeMachine(.toggle)
        m.handleRawRelease(type: .voiceInput, hasCtrl: false)
        m.handleRawRelease(type: .voiceInput, hasCtrl: false)
        #expect(r.events.isEmpty)

        m.handleRawPress(type: .voiceInput, hasCtrl: false)  // 开
        m.handleRawRelease(type: .voiceInput, hasCtrl: false) // 忽略
        m.handleRawRelease(type: .voiceInput, hasCtrl: false) // 仍忽略
        #expect(r.events == [.press(.voiceInput, false)])
    }

    @Test("toggle: 第二次按下使用最新的 type/hasCtrl 触发 release")
    func toggleReleaseUsesLatestType() {
        let (m, r) = makeMachine(.toggle)
        m.handleRawPress(type: .voiceInput, hasCtrl: false)
        m.handleRawPress(type: .voiceInputWithAI, hasCtrl: true)
        #expect(r.events == [
            .press(.voiceInput, false),
            .release(.voiceInputWithAI, true),
        ])
    }

    // MARK: - hybrid

    @Test("hybrid: 短按（未决期内松开）只 fire press、不 fire release，latch 住录音")
    func hybridShortTapLatchesAsToggle() {
        let (m, r) = makeMachine(.hybrid)
        m.handleRawPress(type: .voiceInput, hasCtrl: false)
        // 立刻松开（远早于阈值）→ 短按 → latch
        m.handleRawRelease(type: .voiceInput, hasCtrl: false)
        #expect(r.events == [.press(.voiceInput, false)])
        #expect(m._testSnapshot.hybridLatched == true)
    }

    @Test("hybrid: 短按 latch 后再按一次 fire release，状态归零")
    func hybridSecondTapEndsLatched() {
        let (m, r) = makeMachine(.hybrid)
        m.handleRawPress(type: .voiceInput, hasCtrl: false)
        m.handleRawRelease(type: .voiceInput, hasCtrl: false)
        // latched
        m.handleRawPress(type: .voiceInput, hasCtrl: false)
        #expect(r.events == [
            .press(.voiceInput, false),
            .release(.voiceInput, false),
        ])
        #expect(m._testSnapshot.hybridLatched == false)
    }

    @Test("hybrid: 长按（决策 timer 触发后才松开）退化为 push-to-talk")
    func hybridLongHoldBehavesAsPTT() {
        let (m, r) = makeMachine(.hybrid)
        m.handleRawPress(type: .voiceInput, hasCtrl: false)
        // 模拟过了 0.25s
        m._testForceHybridDecisionFire()
        m.handleRawRelease(type: .voiceInput, hasCtrl: false)
        #expect(r.events == [
            .press(.voiceInput, false),
            .release(.voiceInput, false),
        ])
        #expect(m._testSnapshot.hybridLatched == false)
    }

    @Test("hybrid: latch 后切换模式调用 reset 清空状态")
    func resetClearsLatched() {
        let (m, _) = makeMachine(.hybrid)
        m.handleRawPress(type: .voiceInput, hasCtrl: false)
        m.handleRawRelease(type: .voiceInput, hasCtrl: false)
        #expect(m._testSnapshot.hybridLatched == true)
        m.reset()
        #expect(m._testSnapshot.hybridLatched == false)
        #expect(m._testSnapshot.hybridAwaiting == false)
        #expect(m._testSnapshot.toggleActive == false)
    }

    @Test("toggle: reset 后再按一次仍是 fire press（而非 release）")
    func toggleResetReinitializes() {
        let (m, r) = makeMachine(.toggle)
        m.handleRawPress(type: .voiceInput, hasCtrl: false)  // 开
        m.reset()
        r.events.removeAll()
        m.handleRawPress(type: .voiceInput, hasCtrl: false)  // 再按 → 应再 fire press
        #expect(r.events == [.press(.voiceInput, false)])
    }
}
