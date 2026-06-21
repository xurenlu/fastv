//
//  HotkeyTriggerStateMachine.swift
//  fastv
//
//  把"原始物理按键 press/release"转换为"有效录音 start/stop"的状态机。
//  独立于 NSEvent，便于单测覆盖三种触发模式。
//

import Foundation

/// 热键触发模式
enum HotkeyTriggerMode: String, Codable, CaseIterable {
    /// 按住录音：按下开始、松开结束（v1 行为）
    case pushToTalk = "pushToTalk"
    /// 按一下切换：第一次按下开始录、再按一下停止；松开不处理
    case toggle = "toggle"
    /// 混合：短按 = toggle 切换；长按 ≥ 决策阈值 = push-to-talk
    case hybrid = "hybrid"
}

/// 状态机：吃下原始 press / release 物理事件，吐出有效的录音 onPress / onRelease 回调。
///
/// 用法：
/// 1. 配置 `mode` 与回调 `onPress` / `onRelease`
/// 2. 在 GlobalShortcutMonitor 检测到原始按键时，调用 `handleRawPress` / `handleRawRelease`
/// 3. 监听器停止时调用 `reset()`
///
/// 线程：所有方法均在主线程调用（与 GlobalShortcutMonitor 一致）。
final class HotkeyTriggerStateMachine {

    /// 当前触发模式
    var mode: HotkeyTriggerMode = .pushToTalk

    /// 有效 press 回调（驱动开始录音）
    var onPress: ((ShortcutType, Bool) -> Void)?

    /// 有效 release 回调（驱动结束录音）
    var onRelease: ((ShortcutType, Bool) -> Void)?

    /// hybrid 模式下"短按 vs 长按"的判定阈值（秒）。默认 0.25s。
    var hybridDecisionInterval: TimeInterval = 0.25

    // MARK: - 内部状态

    /// toggle 模式：当前录音是否激活
    private var toggleActive: Bool = false

    /// hybrid 模式：处于"短按 latched 录音中"
    private var hybridLatched: Bool = false

    /// hybrid 模式：处于"未决期（按下后 < 阈值，还没决定 toggle 还是 PTT）"
    private var hybridAwaitingDecision: Bool = false

    private var hybridDecisionTimer: Timer?

    /// 测试可注入的 timer 工厂；nil 时用真实 Timer。
    var timerFactory: ((TimeInterval, @escaping () -> Void) -> Timer?)?

    init() {}

    deinit {
        hybridDecisionTimer?.invalidate()
    }

    // MARK: - 公开 API

    /// 原始按键按下
    func handleRawPress(type: ShortcutType, hasCtrl: Bool) {
        switch mode {
        case .pushToTalk:
            onPress?(type, hasCtrl)

        case .toggle:
            if toggleActive {
                toggleActive = false
                onRelease?(type, hasCtrl)
            } else {
                toggleActive = true
                onPress?(type, hasCtrl)
            }

        case .hybrid:
            if hybridLatched {
                // 已 latch（前一次短按之后），本次按下视为"第二次 tap"，结束录音
                hybridLatched = false
                onRelease?(type, hasCtrl)
                return
            }
            // 新一轮录音：立刻 fire press（避免首字丢失），并进入未决期
            onPress?(type, hasCtrl)
            hybridAwaitingDecision = true
            startHybridDecisionTimer()
        }
    }

    /// 原始按键松开
    func handleRawRelease(type: ShortcutType, hasCtrl: Bool) {
        switch mode {
        case .pushToTalk:
            onRelease?(type, hasCtrl)

        case .toggle:
            // toggle 模式完全忽略松开
            return

        case .hybrid:
            cancelHybridDecisionTimer()
            if hybridAwaitingDecision {
                // 未决期内松开 → 短按 → latch 为 toggle 状态，不结束录音
                hybridAwaitingDecision = false
                hybridLatched = true
            } else {
                // 决策已过阈值 → 长按 PTT → 松开即结束
                onRelease?(type, hasCtrl)
            }
        }
    }

    /// 监听器停止 / 重置（清空 latched / awaiting / toggle 状态，避免下一轮误触）
    func reset() {
        toggleActive = false
        hybridLatched = false
        hybridAwaitingDecision = false
        cancelHybridDecisionTimer()
    }

    // MARK: - 内部辅助

    private func startHybridDecisionTimer() {
        cancelHybridDecisionTimer()
        if let factory = timerFactory {
            hybridDecisionTimer = factory(hybridDecisionInterval) { [weak self] in
                self?.hybridDecisionFired()
            }
        } else {
            hybridDecisionTimer = Timer.scheduledTimer(
                withTimeInterval: hybridDecisionInterval,
                repeats: false
            ) { [weak self] _ in
                self?.hybridDecisionFired()
            }
        }
    }

    private func cancelHybridDecisionTimer() {
        hybridDecisionTimer?.invalidate()
        hybridDecisionTimer = nil
    }

    private func hybridDecisionFired() {
        if hybridAwaitingDecision {
            // 用户还没松开就到了阈值 → 这次按下确定为 PTT；松开时再 fire release
            hybridAwaitingDecision = false
        }
    }

    // MARK: - 测试钩子（仅供单测使用）

    /// 手动让 hybrid 的决策 timer 立即触发，避免单测等真实 0.25s。
    func _testForceHybridDecisionFire() {
        cancelHybridDecisionTimer()
        hybridDecisionFired()
    }

    /// 暴露当前内部状态用于单测断言。
    var _testSnapshot: (toggleActive: Bool, hybridLatched: Bool, hybridAwaiting: Bool) {
        (toggleActive, hybridLatched, hybridAwaitingDecision)
    }
}
