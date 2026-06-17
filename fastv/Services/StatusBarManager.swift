//
//  StatusBarManager.swift
//  fastv
//

import AppKit
import SwiftUI
import Combine

/// 菜单栏状态徽章管理器。
///
/// 设计目标：让用户**瞥一眼菜单栏就知道当前在做什么**。状态四态可视化：
/// - `.idle`         闲置 → 闪电图标（模板色，跟随系统）
/// - `.recording`    录音中 → 麦克风（红）
/// - `.transcribing` 转写中 → 波形（蓝）
/// - `.polishing`    AI 优化中 → 星花（紫）
///
/// 状态来源不在这里自己拍脑袋，而是订阅 [`WaveformWindowManager`](../Views/WaveformView.swift)
/// 的现有状态机：那边已经维护了 recording / transcribing / aiCorrecting 等枚举，
/// 把它映射到这里的 4 态即可，避免「两份真相」漂移。
class StatusBarManager: NSObject, ObservableObject {
    static let shared = StatusBarManager()

    /// 当前活动状态。
    enum Activity {
        case idle
        case recording
        case transcribing
        case polishing

        fileprivate var symbolName: String {
            switch self {
            case .idle:         return "bolt.fill"
            case .recording:    return "mic.fill"
            case .transcribing: return "waveform"
            case .polishing:    return "sparkles"
            }
        }

        /// 非 nil 时上色（`isTemplate = false`）；nil 时走模板色（跟随菜单栏深/浅色）。
        fileprivate var tintColor: NSColor? {
            switch self {
            case .idle:         return nil
            case .recording:    return .systemRed
            case .transcribing: return .systemBlue
            case .polishing:    return .systemPurple
            }
        }

        fileprivate var tooltipKey: String {
            switch self {
            case .idle:         return "app.name"
            case .recording:    return "statusbar.activity.recording"
            case .transcribing: return "statusbar.activity.transcribing"
            case .polishing:    return "statusbar.activity.polishing"
            }
        }
    }

    private var statusItem: NSStatusItem?
    private var statusBarButton: NSStatusBarButton?

    /// 当前状态，可供外部观察（如未来的悬浮提示等）。
    @Published private(set) var activity: Activity = .idle

    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        setupStatusBar()
        subscribeToWaveformState()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let statusItem = statusItem else { return }

        if let button = statusItem.button {
            statusBarButton = button
            applyActivity(.idle, to: button)
        }

        updateMenu()
    }

    /// 订阅波形窗口的状态机 + 可见性，自动同步状态徽章。
    ///
    /// 映射规则：
    /// - `isVisible == false`            → `.idle`
    /// - `state == .recording`           → `.recording`
    /// - `state == .transcribing`        → `.transcribing`
    /// - `state == .aiCorrecting`        → `.polishing`
    /// - 其余 aiCorrected/Failed/Disabled 都是「结束态」，会很快触发 hide() 让窗口消失，
    ///   这里短暂保持上一帧即可，无需特殊处理（isVisible 一旦置 false 自动回 idle）。
    private func subscribeToWaveformState() {
        let manager = WaveformWindowManager.shared
        Publishers.CombineLatest(manager.$isVisible, manager.$state)
            .receive(on: RunLoop.main)
            .sink { [weak self] visible, state in
                self?.setActivity(Self.mapActivity(visible: visible, state: state))
            }
            .store(in: &cancellables)
    }

    private static func mapActivity(visible: Bool, state: WaveformWindowState) -> Activity {
        guard visible else { return .idle }
        switch state {
        case .recording:                                      return .recording
        case .transcribing:                                   return .transcribing
        case .aiCorrecting:                                   return .polishing
        case .aiCorrected, .aiCorrectionFailed, .aiCorrectionDisabled:
            // 结束态：保持当前显示，等 isVisible 翻 false 自然回 idle。
            // 这里返回当前活动以避免抖动。
            return StatusBarManager.shared.activity
        }
    }

    /// 手动设置状态（供未来扩展使用，比如不依赖波形窗口的「仅 AI 改写」流程）。
    func setActivity(_ activity: Activity) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.activity != activity else { return }
            self.activity = activity
            if let button = self.statusBarButton {
                self.applyActivity(activity, to: button)
            }
        }
    }

    private func applyActivity(_ activity: Activity, to button: NSStatusBarButton) {
        let tooltip = NSLocalizedString(activity.tooltipKey, comment: "")
        let image = NSImage(systemSymbolName: activity.symbolName, accessibilityDescription: tooltip)
        if let tint = activity.tintColor {
            // 上色：必须关掉 template，否则 contentTintColor 会被忽略。
            image?.isTemplate = false
            button.contentTintColor = tint
        } else {
            // 闲置：恢复模板色，跟随菜单栏深浅模式。
            image?.isTemplate = true
            button.contentTintColor = nil
        }
        button.image = image
        button.toolTip = tooltip
    }

    private func updateMenu() {
        guard let statusItem = statusItem else { return }

        let menu = NSMenu()

        let appName = NSLocalizedString("app.name", comment: "")
        let showMenuItem = NSMenuItem(
            title: String(format: NSLocalizedString("show.app", value: "显示 %@", comment: ""), appName),
            action: #selector(showMainWindow(_:)),
            keyEquivalent: ""
        )
        showMenuItem.target = self
        menu.addItem(showMenuItem)

        menu.addItem(NSMenuItem.separator())

        let quitMenuItem = NSMenuItem(
            title: NSLocalizedString("quit", value: "退出", comment: ""),
            action: #selector(quitApplication(_:)),
            keyEquivalent: "q"
        )
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        statusItem.menu = menu
    }

    @objc private func showMainWindow(_ sender: NSMenuItem) {
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            NSApplication.shared.windows.forEach { window in
                window.makeKeyAndOrderFront(nil)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    @objc private func quitApplication(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }

    func show() {
        statusItem?.isVisible = true
    }

    func hide() {
        statusItem?.isVisible = false
    }

    func cleanup() {
        cancellables.removeAll()
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        statusBarButton = nil
    }
}
