//
//  CandidateContentView.swift
//  QechoIME
//
//  候选窗自绘视图：按外观设置布局并绘制候选、序号、编码提示、高亮背景与圆角边框。
//  横排从左到右、竖排从上到下；测量与绘制共用同一套布局，保证尺寸与点击命中一致。
//

import Cocoa

final class CandidateContentView: NSView {
    var onSelect: ((Int) -> Void)?

    private var items: [CandidateItem] = []
    private var highlightedIndex = 0
    private var style = CandidateAppearance.default
    private var isDark = false

    /// 每个候选的布局盒子（相对本视图坐标，AppKit 原点左下）；下标与 items 对齐
    private var itemFrames: [NSRect] = []

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    // MARK: - 配置

    func configure(items: [CandidateItem], highlightedIndex: Int, appearance: CandidateAppearance, isDark: Bool) {
        self.items = items
        self.highlightedIndex = highlightedIndex
        self.style = appearance
        self.isDark = isDark
        recomputeLayout()
    }

    private var palette: CandidatePalette {
        isDark ? style.darkPalette : style.lightPalette
    }

    private var textFont: NSFont {
        if let name = style.fontName, let f = NSFont(name: name, size: style.fontSize) {
            return f
        }
        return NSFont.systemFont(ofSize: style.fontSize)
    }

    private var labelFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: style.labelFontSize, weight: .regular)
    }

    private var commentFont: NSFont {
        NSFont.systemFont(ofSize: style.labelFontSize)
    }

    // MARK: - 布局测量

    /// 单个候选内容尺寸（不含盒子内边距）
    private func cellContentSize(_ index: Int) -> NSSize {
        let item = items[index]
        var width: CGFloat = 0
        var height: CGFloat = 0

        if style.showLabel {
            let label = "\(index + 1) " as NSString
            let s = label.size(withAttributes: [.font: labelFont])
            width += s.width
            height = max(height, s.height)
        }
        let textSize = (item.text as NSString).size(withAttributes: [.font: textFont])
        width += textSize.width
        height = max(height, textSize.height)

        if style.showComment, !item.comment.isEmpty {
            let comment = " \(item.comment)" as NSString
            let s = comment.size(withAttributes: [.font: commentFont])
            width += s.width
            height = max(height, s.height)
        }
        return NSSize(width: ceil(width), height: ceil(height))
    }

    private var cellInsetX: CGFloat { 8 }
    private var cellInsetY: CGFloat { 5 }

    private func recomputeLayout() {
        itemFrames.removeAll(keepingCapacity: true)
        let pad = CGFloat(style.padding)
        let spacing = CGFloat(style.itemSpacing)

        let cellSizes = (0..<items.count).map { index -> NSSize in
            let c = cellContentSize(index)
            return NSSize(width: c.width + cellInsetX * 2, height: c.height + cellInsetY * 2)
        }

        switch style.layout {
        case .horizontal:
            let rowHeight = cellSizes.map(\.height).max() ?? 0
            var x = pad
            for size in cellSizes {
                itemFrames.append(NSRect(x: x, y: pad, width: size.width, height: rowHeight))
                x += size.width + spacing
            }
            let totalWidth = x - spacing + pad
            let totalHeight = rowHeight + pad * 2
            frame = NSRect(x: frame.minX, y: frame.minY, width: totalWidth, height: totalHeight)
            // 横排 y 是同一行，已按 rowHeight 对齐

        case .vertical:
            let colWidth = cellSizes.map(\.width).max() ?? 0
            // 竖排从上往下：AppKit 原点左下，先算总高再逐个从顶部往下排
            let totalHeight = cellSizes.map(\.height).reduce(0, +)
                + spacing * CGFloat(max(0, items.count - 1)) + pad * 2
            var yTop = totalHeight - pad
            for size in cellSizes {
                let y = yTop - size.height
                itemFrames.append(NSRect(x: pad, y: y, width: colWidth, height: size.height))
                yTop = y - spacing
            }
            frame = NSRect(x: frame.minX, y: frame.minY, width: colWidth + pad * 2, height: totalHeight)
        }
    }

    /// 供 CandidateWindow 取窗口尺寸
    func intrinsicPanelSize() -> NSSize {
        NSSize(width: max(frame.width, 10), height: max(frame.height, 10))
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        let p = palette
        let radius = CGFloat(style.cornerRadius)

        // 背景 + 边框
        let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        p.background.nsColor.setFill()
        bgPath.fill()
        p.border.nsColor.setStroke()
        bgPath.lineWidth = 1
        bgPath.stroke()

        for (index, box) in itemFrames.enumerated() where index < items.count {
            let isHighlight = index == highlightedIndex
            if isHighlight {
                let hlPath = NSBezierPath(roundedRect: box, xRadius: max(radius - 3, 2), yRadius: max(radius - 3, 2))
                p.highlightBackground.nsColor.setFill()
                hlPath.fill()
            }
            drawCell(index: index, in: box, highlighted: isHighlight, palette: p)
        }
    }

    private func drawCell(index: Int, in box: NSRect, highlighted: Bool, palette p: CandidatePalette) {
        let item = items[index]
        var x = box.minX + cellInsetX
        let textColor = highlighted ? p.highlightText.nsColor : p.text.nsColor
        let labelColor = highlighted ? p.highlightText.nsColor.withAlphaComponent(0.85) : p.label.nsColor
        let commentColor = highlighted ? p.highlightText.nsColor.withAlphaComponent(0.85) : p.comment.nsColor

        func drawString(_ s: String, font: NSFont, color: NSColor) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let ns = s as NSString
            let size = ns.size(withAttributes: attrs)
            let y = box.minY + (box.height - size.height) / 2
            ns.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            x += size.width
        }

        if style.showLabel {
            drawString("\(index + 1) ", font: labelFont, color: labelColor)
        }
        drawString(item.text, font: textFont, color: textColor)
        if style.showComment, !item.comment.isEmpty {
            drawString(" \(item.comment)", font: commentFont, color: commentColor)
        }
    }

    // MARK: - 点击选字

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = itemFrames.firstIndex(where: { $0.contains(point) }) {
            onSelect?(index)
        }
    }
}

private extension CandidateColor {
    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
