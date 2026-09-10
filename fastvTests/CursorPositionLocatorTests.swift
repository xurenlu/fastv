//
//  CursorPositionLocatorTests.swift
//  fastvTests
//
//  覆盖 followCursor 模式下的纯函数定位逻辑：clampedRect 数学正确性。
//  AX caret 解析依赖系统 AX 权限与真实焦点元素，不在单测覆盖范围内。
//

import Testing
import Foundation
import AppKit
@testable import musetype

@Suite("CursorPositionLocator")
struct CursorPositionLocatorTests {

    private let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 200, height: 60)

    @Test("clampedRect: 锚点在屏幕内 → 原样返回")
    func anchorInsideKeepsOrigin() {
        let r = CursorPositionLocator.clampedRect(
            origin: NSPoint(x: 500, y: 400),
            size: size,
            into: bounds,
            margin: 8
        )
        #expect(r.origin.x == 500)
        #expect(r.origin.y == 400)
    }

    @Test("clampedRect: 右边溢出 → clamp 到 maxX - width - margin")
    func clampsToRight() {
        let r = CursorPositionLocator.clampedRect(
            origin: NSPoint(x: 1400, y: 100),
            size: size,
            into: bounds,
            margin: 8
        )
        #expect(r.origin.x == bounds.maxX - 8 - size.width)
    }

    @Test("clampedRect: 左边/下边都溢出 → clamp 到 margin")
    func clampsToBottomLeft() {
        let r = CursorPositionLocator.clampedRect(
            origin: NSPoint(x: -200, y: -100),
            size: size,
            into: bounds,
            margin: 8
        )
        #expect(r.origin.x == 8)
        #expect(r.origin.y == 8)
    }

    @Test("clampedRect: 屏幕比窗口窄 → 居中放，不再 clamp")
    func tinyScreenCentersWindow() {
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 50) // 比 size 还小
        let r = CursorPositionLocator.clampedRect(
            origin: NSPoint(x: 30, y: 20),
            size: size,
            into: tiny,
            margin: 8
        )
        // x 应为 (0+100)/2 - 200/2 = -50（midX - width/2，居中后允许出界）
        #expect(r.origin.x == tiny.midX - size.width / 2)
        #expect(r.origin.y == tiny.midY - size.height / 2)
    }

    @Test("clampedRect: 副屏负坐标空间也工作（主屏左侧的外接屏）")
    func negativeOriginScreen() {
        let secondary = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        let anchor = NSPoint(x: -1000, y: 800)
        let r = CursorPositionLocator.clampedRect(
            origin: anchor,
            size: size,
            into: secondary,
            margin: 8
        )
        #expect(r.origin.x == -1000)
        #expect(r.origin.y == 800)
        // 现在锚点跑出 secondary 左边界
        let leftOf = CursorPositionLocator.clampedRect(
            origin: NSPoint(x: -3000, y: 800),
            size: size,
            into: secondary,
            margin: 8
        )
        #expect(leftOf.origin.x == secondary.minX + 8)
    }

    @Test("WaveformWindowPosition.followCursor 在 allCases 中且 isFollowingCursor=true")
    func enumExposesFollowCursor() {
        #expect(WaveformWindowPosition.allCases.contains(.followCursor))
        #expect(WaveformWindowPosition.followCursor.isFollowingCursor)
        #expect(!WaveformWindowPosition.bottomCenter.isFollowingCursor)
    }

    // MARK: - 多显示器下的屏幕选取
    //
    // 用户反馈「悬浮条有时候完全不显示」。真相是它显示在了另一块屏上：固定位置
    // （正中下方等）原先用 NSScreen.main 定位，而该 API 返回「包含键盘焦点窗口的
    // 屏幕」，轻语常驻后台没有键窗口，于是基本固定落回主显示器。用户在副屏打字，
    // 指示器却画到主屏。这几条锁住「按点选屏」的语义。

    /// 主屏 2560×1600 在原点，外接 4K（缩放 1920×1080）挂在右侧——与报告该问题的机器一致。
    private var dualScreenFrames: [CGRect] {
        [
            CGRect(x: 0, y: 0, width: 2560, height: 1600),
            CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        ]
    }

    @Test("鼠标在主屏 → 选中主屏")
    func picksPrimaryWhenPointerOnPrimary() {
        let index = CursorPositionLocator.indexOfScreen(
            containing: NSPoint(x: 1280, y: 800),
            in: dualScreenFrames
        )
        #expect(index == 0)
    }

    @Test("鼠标在副屏 → 选中副屏，不落回主屏")
    func picksSecondaryWhenPointerOnSecondary() {
        let index = CursorPositionLocator.indexOfScreen(
            containing: NSPoint(x: 3520, y: 540),
            in: dualScreenFrames
        )
        #expect(index == 1, "鼠标在副屏时必须选副屏，否则指示器会画到用户看不见的屏上")
    }

    @Test("主屏左侧的副屏（负坐标空间）同样能命中")
    func picksScreenInNegativeCoordinateSpace() {
        let frames = [
            CGRect(x: 0, y: 0, width: 2560, height: 1600),
            CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        ]
        #expect(CursorPositionLocator.indexOfScreen(containing: NSPoint(x: -960, y: 540), in: frames) == 1)
        #expect(CursorPositionLocator.indexOfScreen(containing: NSPoint(x: 100, y: 100), in: frames) == 0)
    }

    @Test("点不在任何屏幕内 → 返回 nil，由调用方兜底")
    func returnsNilWhenPointOutsideAllScreens() {
        #expect(CursorPositionLocator.indexOfScreen(containing: NSPoint(x: 9999, y: 9999), in: dualScreenFrames) == nil)
        #expect(CursorPositionLocator.indexOfScreen(containing: .zero, in: []) == nil)
    }

    @Test("跟随光标模式把窗口 clamp 在锚点所在的副屏内")
    func followCursorStaysOnAnchorScreen() {
        // 锚点在右侧副屏靠右边缘，窗口不能溢出到主屏或屏幕外
        let secondary = CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        let size = CGSize(width: 200, height: 60)
        let rect = CursorPositionLocator.clampedRect(
            origin: NSPoint(x: secondary.maxX - 20, y: 500),
            size: size,
            into: secondary,
            margin: 8
        )
        #expect(rect.maxX <= secondary.maxX - 8)
        #expect(rect.minX >= secondary.minX + 8)
    }
}
