//
//  CandidateAppearanceView.swift
//  fastv
//
//  候选窗外观设置面板：方向 / 字体 / 字号 / 主题配色 / 圆角 / 间距 / 序号编码显隐，
//  附实时迷你预览。改动即时写入 IME 设置文件并通知输入法进程。
//

import SwiftUI

// MARK: - Color 互转

extension Color {
    init(_ c: CandidateColor) {
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}

extension CandidateColor {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(Double(ns.redComponent), Double(ns.greenComponent),
                  Double(ns.blueComponent), Double(ns.alphaComponent))
    }
}

// MARK: - 主面板

struct CandidateAppearanceView: View {
    @ObservedObject private var store = InputMethodSettingsStore.shared

    /// 预览用的深浅色切换（不改设置，只切预览）
    @State private var previewDark = false

    private var appearance: CandidateAppearance { store.settings.appearance }

    private func update(_ mutate: (inout CandidateAppearance) -> Void) {
        var a = appearance
        mutate(&a)
        store.setAppearance(a.sanitized())
    }

    private var editingPalette: Binding<CandidatePalette> {
        Binding(
            get: { previewDark ? appearance.darkPalette : appearance.lightPalette },
            set: { newPalette in
                update { a in
                    if previewDark { a.darkPalette = newPalette } else { a.lightPalette = newPalette }
                }
            }
        )
    }

    var body: some View {
        Section {
            // 实时预览
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(NSLocalizedString("ime.cand.preview", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $previewDark) {
                        Text(NSLocalizedString("ime.cand.preview.light", comment: "")).tag(false)
                        Text(NSLocalizedString("ime.cand.preview.dark", comment: "")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .labelsHidden()
                }
                CandidatePreview(appearance: appearance, isDark: previewDark)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .padding(10)
                    .background(previewDark ? Color(white: 0.10) : Color(white: 0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // 排列方向
            Picker(NSLocalizedString("ime.cand.layout", comment: ""),
                   selection: Binding(get: { appearance.layout },
                                      set: { v in update { $0.layout = v } })) {
                ForEach(CandidateLayout.allCases, id: \.self) { layout in
                    Text(NSLocalizedString(layout.displayNameKey, comment: "")).tag(layout)
                }
            }
            .pickerStyle(.segmented)

            // 字体
            Picker(NSLocalizedString("ime.cand.font", comment: ""),
                   selection: Binding(get: { appearance.fontName ?? "" },
                                      set: { v in update { $0.fontName = v.isEmpty ? nil : v } })) {
                Text(NSLocalizedString("ime.cand.font.system", comment: "")).tag("")
                ForEach(Self.fontChoices, id: \.self) { name in
                    Text(name).tag(name)
                }
            }

            // 字号
            sliderRow(titleKey: "ime.cand.fontSize", value: appearance.fontSize, range: 12...48, step: 1) { v in
                update { $0.fontSize = v }
            }
            sliderRow(titleKey: "ime.cand.labelFontSize", value: appearance.labelFontSize, range: 8...24, step: 1) { v in
                update { $0.labelFontSize = v }
            }

            // 圆角 / 间距 / 内边距
            sliderRow(titleKey: "ime.cand.corner", value: appearance.cornerRadius, range: 0...24, step: 1) { v in
                update { $0.cornerRadius = v }
            }
            sliderRow(titleKey: "ime.cand.spacing", value: appearance.itemSpacing, range: 0...40, step: 1) { v in
                update { $0.itemSpacing = v }
            }
            sliderRow(titleKey: "ime.cand.padding", value: appearance.padding, range: 2...40, step: 1) { v in
                update { $0.padding = v }
            }

            // 显隐
            Toggle(NSLocalizedString("ime.cand.showLabel", comment: ""),
                   isOn: Binding(get: { appearance.showLabel }, set: { v in update { $0.showLabel = v } }))
            Toggle(NSLocalizedString("ime.cand.showComment", comment: ""),
                   isOn: Binding(get: { appearance.showComment }, set: { v in update { $0.showComment = v } }))
            Toggle(NSLocalizedString("ime.cand.followDark", comment: ""),
                   isOn: Binding(get: { appearance.followSystemDarkMode }, set: { v in update { $0.followSystemDarkMode = v } }))

            // 配色（跟随 previewDark 编辑对应那套）
            Group {
                Text(previewDark
                     ? NSLocalizedString("ime.cand.colors.dark", comment: "")
                     : NSLocalizedString("ime.cand.colors.light", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                colorRow("ime.cand.color.bg", editingPalette.background)
                colorRow("ime.cand.color.text", editingPalette.text)
                colorRow("ime.cand.color.hlBg", editingPalette.highlightBackground)
                colorRow("ime.cand.color.hlText", editingPalette.highlightText)
                colorRow("ime.cand.color.comment", editingPalette.comment)
                colorRow("ime.cand.color.label", editingPalette.label)
                colorRow("ime.cand.color.border", editingPalette.border)
            }

            Button(NSLocalizedString("ime.cand.reset", comment: "")) {
                store.resetAppearance()
            }
        } header: {
            Text(NSLocalizedString("ime.cand.section", comment: ""))
        }
        .onAppear { store.reload() }
    }

    private func sliderRow(titleKey: String, value: Double, range: ClosedRange<Double>, step: Double,
                           onChange: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(NSLocalizedString(titleKey, comment: ""))
            Spacer()
            Text("\(Int(value))").foregroundStyle(.secondary).monospacedDigit().frame(width: 32, alignment: .trailing)
            Slider(value: Binding(get: { value }, set: onChange), in: range, step: step)
                .frame(width: 180)
        }
    }

    private func colorRow(_ titleKey: String, _ binding: Binding<CandidateColor>) -> some View {
        ColorPicker(
            NSLocalizedString(titleKey, comment: ""),
            selection: Binding(get: { Color(binding.wrappedValue) },
                               set: { binding.wrappedValue = CandidateColor($0) }),
            supportsOpacity: false
        )
    }

    /// 常用中文字体候选（存在才有意义，缺失时系统回退）
    private static let fontChoices: [String] = {
        let want = ["PingFang SC", "Hiragino Sans GB", "Songti SC", "STSong",
                    "Kaiti SC", "Heiti SC", "Menlo", "SF Mono"]
        let available = Set(NSFontManager.shared.availableFontFamilies)
        return want.filter { available.contains($0) }
    }()
}

// MARK: - 迷你预览（SwiftUI 复刻自绘窗观感，用于设置面板即时反馈）

private struct CandidatePreview: View {
    let appearance: CandidateAppearance
    let isDark: Bool

    private var palette: CandidatePalette { isDark ? appearance.darkPalette : appearance.lightPalette }
    private let samples: [(String, String)] = [("轻", "tlg"), ("语", "yg"), ("输", "wqvb"), ("入", "tyg")]

    private var font: Font {
        if let name = appearance.fontName { return .custom(name, size: appearance.fontSize) }
        return .system(size: appearance.fontSize)
    }

    var body: some View {
        let content = ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
            HStack(spacing: 2) {
                if appearance.showLabel {
                    Text("\(index + 1)").font(.system(size: appearance.labelFontSize))
                        .foregroundStyle(index == 0 ? Color(palette.highlightText) : Color(palette.label))
                }
                Text(sample.0).font(font)
                    .foregroundStyle(index == 0 ? Color(palette.highlightText) : Color(palette.text))
                if appearance.showComment {
                    Text(sample.1).font(.system(size: appearance.labelFontSize))
                        .foregroundStyle(index == 0 ? Color(palette.highlightText) : Color(palette.comment))
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(index == 0 ? Color(palette.highlightBackground) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: max(appearance.cornerRadius - 3, 2)))
        }

        Group {
            if appearance.layout == .horizontal {
                HStack(spacing: appearance.itemSpacing) { content }
            } else {
                VStack(alignment: .leading, spacing: appearance.itemSpacing) { content }
            }
        }
        .padding(appearance.padding)
        .background(Color(palette.background))
        .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius).stroke(Color(palette.border), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: appearance.cornerRadius))
    }
}
