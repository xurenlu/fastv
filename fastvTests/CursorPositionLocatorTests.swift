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
}
