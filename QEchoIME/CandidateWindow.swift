//
//  CandidateWindow.swift
//  QechoIME
//
//  自绘候选窗：无边框浮动 NSPanel + 自绘 NSView，替代系统 IMKCandidates。
//  支持横排/竖排、字体/字号、明暗两套配色、圆角/间距/内边距、序号与编码提示显隐。
//  跟随组字光标定位；点击候选回调 controller 选字。所有调用在主线程。
//

import Cocoa

/// 一个候选项的渲染数据
struct CandidateItem {
    let text: String
    let comment: String   // 编码 / 拼音反查提示，可空
}

final class CandidateWindow {
    private let panel: NSPanel
    private let contentView: CandidateContentView

    /// 点击第 index 个候选（当前页内序号）的回调
    var onSelect: ((Int) -> Void)? {
        get { contentView.onSelect }
        set { contentView.onSelect = newValue }
    }

    init() {
        contentView = CandidateContentView(frame: .zero)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = contentView
    }

    /// 更新候选内容与外观并显示；candidateCursorRect 为组字光标屏幕坐标（AppKit 坐标系）
    func update(
        items: [CandidateItem],
        highlightedIndex: Int,
        appearance: CandidateAppearance,
        near candidateCursorRect: NSRect
    ) {
        guard !items.isEmpty else { hide(); return }
        contentView.configure(
            items: items,
            highlightedIndex: highlightedIndex,
            appearance: appearance,
            isDark: Self.resolveDark(appearance)
        )
        let size = contentView.intrinsicPanelSize()
        let origin = Self.placeOrigin(for: size, near: candidateCursorRect)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        contentView.needsDisplay = true
        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    // MARK: - 明暗解析

    private static func resolveDark(_ appearance: CandidateAppearance) -> Bool {
        guard appearance.followSystemDarkMode else { return false }
        let name = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return name == .darkAqua
    }

    // MARK: - 定位：优先放在光标下方，屏幕边缘自动翻转/夹取

    private static func placeOrigin(for size: NSSize, near caret: NSRect) -> NSPoint {
        let gap: CGFloat = 4
        let screen = NSScreen.screens.first {
            $0.frame.contains(NSPoint(x: caret.midX, y: caret.midY))
        } ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = caret.minX
        // 默认放光标下方（AppKit 原点在左下，"下方"是 y 更小）
        var y = caret.minY - gap - size.height
        // 下方放不下则翻到上方
        if y < visible.minY {
            y = caret.maxY + gap
        }
        // 水平夹取到屏内
        if x + size.width > visible.maxX { x = visible.maxX - size.width }
        if x < visible.minX { x = visible.minX }
        // 垂直再兜底夹取
        if y + size.height > visible.maxY { y = visible.maxY - size.height }
        if y < visible.minY { y = visible.minY }
        return NSPoint(x: x, y: y)
    }
}
