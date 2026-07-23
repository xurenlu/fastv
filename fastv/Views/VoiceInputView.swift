//
//  VoiceInputView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

private struct MainWindowPaletteKey: EnvironmentKey {
    static let defaultValue = MainWindowSkinPalette.systemDefault
}

private extension EnvironmentValues {
    var mainWindowPalette: MainWindowSkinPalette {
        get { self[MainWindowPaletteKey.self] }
        set { self[MainWindowPaletteKey.self] = newValue }
    }
}

struct VoiceInputView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var historyManager = VoiceInputHistoryManager.shared
    @State private var errorMessage: String?
    @State private var testInputText: String = ""
    @FocusState private var isTestInputFocused: Bool
    @State private var showModelDownload = false
    @State private var isModelDownloaded = false
    @State private var showClearHistoryConfirm = false
    @ObservedObject private var downloader = ModelDownloader.shared
    @State private var copiedRecordId: UUID?

    var body: some View {
        let palette = MainWindowSkinPalette.systemDefault

        VStack(spacing: 0) {
            // 模型未下载提示横幅 - Apple 风格：克制、信息优先
            if !isModelDownloaded {
                ModelDownloadBanner(onTap: {
                    showModelDownload = true
                })
            }

            // 主内容区
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 1. 测试输入区 - 核心操作区，视觉焦点
                    TestInputSection(
                        testInputText: $testInputText,
                        isTestInputFocused: $isTestInputFocused
                    )

                    // 2. 统计数据 - 卡片式，信息层次清晰
                    StatsSection(historyManager: historyManager)

                    // 3. 历史记录
                    HistorySection(
                        historyManager: historyManager,
                        copiedRecordId: $copiedRecordId,
                        showClearHistoryConfirm: $showClearHistoryConfirm,
                        onCopyRecord: copyRecord
                    )
                }
                .padding(24)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            LinearGradient(
                colors: palette.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .environment(\.mainWindowPalette, palette)
        .preferredColorScheme(palette.preferredColorScheme)
        .navigationTitle(NSLocalizedString("voice.input", comment: ""))
        .alert(NSLocalizedString("error", comment: ""), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(NSLocalizedString("ok", comment: ""), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(isPresented: $showModelDownload) {
            OnboardingView()
        }
        .confirmationDialog(NSLocalizedString("clear.all.confirm.title", comment: ""), isPresented: $showClearHistoryConfirm) {
            Button(NSLocalizedString("clear.all", comment: ""), role: .destructive) {
                historyManager.clear()
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("clear.all.confirm.message", comment: ""))
        }
        .onAppear {
            checkModelStatus()
        }
        .onChange(of: preferences.isModelDownloaded) { _, _ in
            checkModelStatus()
        }
        .onChange(of: downloader.isDownloading) { oldValue, newValue in
            if oldValue && !newValue {
                checkModelStatus()
            }
        }
    }

    private func checkModelStatus() {
        isModelDownloaded = ModelDownloader.shared.checkModelFilesExist()
    }

    private func copyRecord(_ record: VoiceInputHistoryRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.text, forType: .string)
        copiedRecordId = record.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copiedRecordId = nil
        }
    }
}

// MARK: - 模型下载横幅（Apple 风格：克制、可点击）
private struct ModelDownloadBanner: View {
    let onTap: () -> Void
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(palette.accentColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("model.not.downloaded.title", comment: ""))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.primaryTextColor)
                    Text(NSLocalizedString("model.not.downloaded.message", comment: ""))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(palette.elevatedSurfaceColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 测试输入区
private struct TestInputSection: View {
    @Binding var testInputText: String
    @FocusState.Binding var isTestInputFocused: Bool
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 提示：简洁、不喧宾夺主
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryTextColor)
                    .symbolRenderingMode(.hierarchical)
                Text(NSLocalizedString("main.usage.hint", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryTextColor)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.elevatedSurfaceColor)
            )

            // 输入框
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("test.input.label", comment: ""))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.secondaryTextColor)

                TextField(NSLocalizedString("test.input.placeholder", comment: ""), text: $testInputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .focused($isTestInputFocused)
                    .foregroundStyle(palette.primaryTextColor)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.fieldColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(isTestInputFocused ? palette.accentColor.opacity(0.62) : palette.borderColor, lineWidth: isTestInputFocused ? 1.5 : 1)
                            )
                    )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.surfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.borderColor, lineWidth: 1)
                )
        )
    }
}

// MARK: - 统计区（卡片式，Apple 风格）
private struct StatsSection: View {
    @ObservedObject var historyManager: VoiceInputHistoryManager
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 今日 / 累计 双卡片
            HStack(spacing: 16) {
                VoiceInputStatCard(
                    title: NSLocalizedString("stats.today", comment: ""),
                    characterCount: historyManager.todayCharacterCount,
                    charactersPerMinute: historyManager.todayCharactersPerMinute,
                    audioSeconds: historyManager.todayAudioSeconds,
                    transcriptionSeconds: historyManager.todayTranscriptionSeconds,
                    realtimeFactor: historyManager.todayRealtimeFactor
                )
                VoiceInputStatCard(
                    title: NSLocalizedString("stats.all", comment: ""),
                    characterCount: historyManager.totalCharacterCount,
                    charactersPerMinute: historyManager.totalCharactersPerMinute,
                    audioSeconds: historyManager.totalAudioSeconds,
                    transcriptionSeconds: historyManager.totalTranscriptionSeconds,
                    realtimeFactor: historyManager.totalRealtimeFactor
                )
            }

            // 平均每条
            HStack(spacing: 8) {
                Text(NSLocalizedString("avg.characters.per.record", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryTextColor)
                Text(String(format: "%.0f", historyManager.averageCharactersPerRecord))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.elevatedSurfaceColor)
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.surfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.borderColor, lineWidth: 1)
                )
        )
    }
}

// MARK: - 统计卡片（语音输入专用，与 EmailDashboardView.StatCard 区分）
private struct VoiceInputStatCard: View {
    let title: String
    let characterCount: Int
    let charactersPerMinute: Double?
    let audioSeconds: TimeInterval
    let transcriptionSeconds: TimeInterval
    let realtimeFactor: Double?
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.secondaryTextColor)

            HStack(spacing: 16) {
                StatItemView(
                    title: NSLocalizedString("stats.characters", comment: ""),
                    value: "\(characterCount)"
                )
                StatItemView(
                    title: NSLocalizedString("stats.chars.per.min", comment: ""),
                    value: charsPerMinDisplay
                )
                StatItemView(
                    title: NSLocalizedString("stats.audio.seconds", comment: ""),
                    value: formatSeconds(audioSeconds)
                )
                StatItemView(
                    title: NSLocalizedString("stats.transcription.seconds", comment: ""),
                    value: formatSeconds(transcriptionSeconds)
                )
                StatItemView(
                    title: NSLocalizedString("stats.realtime.factor", comment: ""),
                    value: realtimeFactorDisplay
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.elevatedSurfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(palette.borderColor.opacity(0.7), lineWidth: 1)
                )
        )
    }

    private var charsPerMinDisplay: String {
        if let cpm = charactersPerMinute, cpm > 0 {
            return String(format: "%.0f", cpm)
        }
        return "—"
    }

    private var realtimeFactorDisplay: String {
        if let rtf = realtimeFactor, rtf > 0 {
            let unit = NSLocalizedString("stats.realtime.factor.unit", comment: "")
            return String(format: "%.2f%@", rtf, unit)
        }
        return "—"
    }

    private func formatSeconds(_ s: TimeInterval) -> String {
        guard s > 0 else { return "—" }
        if s >= 60 {
            let m = Int(s) / 60
            let sec = Int(s) % 60
            let minStr = NSLocalizedString("minute", comment: "")
            let secStr = NSLocalizedString("seconds.short", comment: "")
            return "\(m)\(minStr)\(sec)\(secStr)"
        }
        let secStr = NSLocalizedString("seconds.short", comment: "")
        return String(format: "%.1f", s) + secStr
    }
}

// MARK: - 统计项
private struct StatItemView: View {
    let title: String
    let value: String
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(palette.tertiaryTextColor)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.primaryTextColor)
        }
    }
}

// MARK: - 历史记录区
private struct HistorySection: View {
    @ObservedObject var historyManager: VoiceInputHistoryManager
    @Binding var copiedRecordId: UUID?
    @Binding var showClearHistoryConfirm: Bool
    let onCopyRecord: (VoiceInputHistoryRecord) -> Void
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题行
            HStack {
                Text(NSLocalizedString("voice.input.history", comment: ""))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.primaryTextColor)
                Text("(\(historyManager.totalCount) \(NSLocalizedString("records", comment: "")))")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryTextColor)
                Spacer()
                if !historyManager.records.isEmpty {
                    Button(action: { showClearHistoryConfirm = true }) {
                        Text(NSLocalizedString("clear.all", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if historyManager.records.isEmpty {
                ContentUnavailableView {
                    Label(NSLocalizedString("no.records", comment: ""), systemImage: "text.badge.plus")
                }
                .foregroundStyle(palette.secondaryTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                VStack(spacing: 0) {
                    ForEach(historyManager.records) { record in
                        HistoryRecordRow(
                            record: record,
                            isCopied: copiedRecordId == record.id,
                            onCopy: { onCopyRecord(record) },
                            onDelete: { historyManager.remove(record) }
                        )
                        if record.id != historyManager.records.last?.id {
                            Rectangle()
                                .fill(palette.borderColor)
                                .frame(height: 1)
                                .padding(.leading, 20)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.elevatedSurfaceColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(palette.borderColor, lineWidth: 1)
                        )
                )
            }
        }
    }
}

// MARK: - 历史记录行（Apple 风格：清晰、可操作）
private struct HistoryRecordRow: View {
    let record: VoiceInputHistoryRecord
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.text)
                    .font(.body)
                    .lineLimit(5)
                    .textSelection(.enabled)
                    .foregroundStyle(palette.primaryTextColor)
                Text(record.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryTextColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.leading, 20)

            Button(action: onCopy) {
                if isCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .symbolRenderingMode(.hierarchical)
                        Text(NSLocalizedString("copy.success", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .foregroundStyle(isHovered ? palette.primaryTextColor : palette.secondaryTextColor)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 20)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(action: onCopy) {
                Label(NSLocalizedString("copy", comment: ""), systemImage: "doc.on.doc")
            }
            Button(role: .destructive, action: onDelete) {
                Label(NSLocalizedString("delete", comment: ""), systemImage: "trash")
            }
        }
    }
}

#Preview {
    VoiceInputView()
}
