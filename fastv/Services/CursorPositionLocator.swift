//
//  CursorPositionLocator.swift
//  fastv
//
//  「跟随光标」位置定位：优先取焦点输入框的 caret 屏幕坐标（AX
//  AXBoundsForRange），失败兜底鼠标位置。供 WaveformWindowManager 在
//  `.followCursor` 模式下每 50ms 重算窗口 origin。
//
//  线程：所有方法主线程调用。AX 调用相对廉价，对每秒 20 次的轮询不会成为瓶颈。
//

import Foundation
import AppKit
import ApplicationServices

enum CursorPositionLocator {

    /// 解析当前最适合显示「光标旁悬浮指示器」的屏幕坐标（AppKit 坐标系，
    /// 即 Y 向上、原点在主屏左下角）。
    ///
    /// - 优先：focused element 的 caret bounds（输入框中光标的真实矩形）
    /// - 备选：focused element 整体的 position + size 中底部
    /// - 兜底：`NSEvent.mouseLocation`
    static func resolveAnchorPoint() -> NSPoint {
        if let caret = focusedCaretPoint() {
            return caret
        }
        return NSEvent.mouseLocation
    }

    /// 给定锚点（caret 或鼠标），把波形窗口放到「右下偏移」位置，
    /// 并 clamp 到锚点所在屏幕的 visibleFrame 内，避免被遮挡。
    /// - Parameters:
    ///   - anchor: AppKit 坐标的锚点（来自 `resolveAnchorPoint()`）
    ///   - windowSize: 窗口尺寸
    ///   - margin: 与屏幕边缘最小距离
    /// - Returns: 计算出的 NSRect origin
    static func windowFrame(anchor: NSPoint, windowSize: CGSize, margin: CGFloat = 8) -> NSRect {
        // 光标右下偏移：x +16，y -32（caret 在 y 向上的坐标里，"下方" 是 y 减小）
        let preferred = NSPoint(x: anchor.x + 16, y: anchor.y - 32 - windowSize.height)

        // 找锚点所在的屏幕（多显示器场景）
        let targetScreen = screenContaining(point: anchor) ?? NSScreen.main ?? NSScreen.screens.first
        let bounds = targetScreen?.visibleFrame ?? .zero

        return clampedRect(origin: preferred, size: windowSize, into: bounds, margin: margin)
    }

    // MARK: - 内部

    /// 把矩形 clamp 到 bounds 内，留出 margin。算法纯函数，可单测。
    static func clampedRect(
        origin: NSPoint,
        size: CGSize,
        into bounds: CGRect,
        margin: CGFloat
    ) -> NSRect {
        guard bounds.width > 0 && bounds.height > 0 else {
            return NSRect(origin: origin, size: size)
        }
        let minX = bounds.minX + margin
        let maxX = bounds.maxX - margin - size.width
        let minY = bounds.minY + margin
        let maxY = bounds.maxY - margin - size.height

        let x: CGFloat
        if maxX < minX {
            // 屏幕比窗口窄，居中放
            x = bounds.midX - size.width / 2
        } else {
            x = min(max(origin.x, minX), maxX)
        }
        let y: CGFloat
        if maxY < minY {
            y = bounds.midY - size.height / 2
        } else {
            y = min(max(origin.y, minY), maxY)
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func screenContaining(point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// 通过 AX 获取焦点输入框的 caret 屏幕坐标。失败返回 nil（让上层走鼠标兜底）。
    private static func focusedCaretPoint() -> NSPoint? {
        guard AXIsProcessTrusted() else { return nil }

        let sysWide = AXUIElementCreateSystemWide()

        // 1) 拿 focused element
        var focused: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            sysWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusedResult == .success,
              let focusedElement = focused else {
            return nil
        }
        let element = focusedElement as! AXUIElement

        // 2) 尝试 AXSelectedTextRange → AXBoundsForRange（最精确）
        if let rect = boundsForSelectedTextRange(element) {
            // AX 返回的矩形是 Quartz 坐标（Y 向下）；转 AppKit（Y 向上）
            return convertQuartzToAppKit(rect: rect).origin
        }

        // 3) 兜底：焦点元素自身 frame 的底部中点
        if let rect = elementFrame(element) {
            let appkit = convertQuartzToAppKit(rect: rect)
            return NSPoint(x: appkit.minX, y: appkit.minY)
        }
        return nil
    }

    /// 读 element 的 AXSelectedTextRange 然后查 AXBoundsForRange，转 CGRect。
    private static func boundsForSelectedTextRange(_ element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard rangeResult == .success, let rangeValue else { return nil }

        var boundsValue: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )
        guard boundsResult == .success, let boundsValue else { return nil }

        var rect = CGRect.zero
        if AXValueGetType(boundsValue as! AXValue) == .cgRect {
            AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect)
            return rect
        }
        return nil
    }

    /// 读 element 自身的 AXPosition + AXSize，组合成 CGRect。
    private static func elementFrame(_ element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let posResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard posResult == .success, let posValue,
              sizeResult == .success, let sizeValue else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        if AXValueGetType(posValue as! AXValue) == .cgPoint {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
        } else { return nil }
        if AXValueGetType(sizeValue as! AXValue) == .cgSize {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        } else { return nil }
        return CGRect(origin: pos, size: size)
    }

    /// AX 用 Quartz 坐标（左上为原点、Y 向下），AppKit 用左下为原点、Y 向上。
    /// 主屏高度作为翻转基准。
    private static func convertQuartzToAppKit(rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        let primaryHeight = primary.frame.height
        let newY = primaryHeight - rect.origin.y - rect.size.height
        return CGRect(x: rect.origin.x, y: newY, width: rect.size.width, height: rect.size.height)
    }
}
