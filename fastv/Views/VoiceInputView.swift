//
//  VoiceInputView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

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
        VStack(spacing: 0) {
            // 模型未下载提示横幅
            if !isModelDownloaded {
                Button(action: {
                    showModelDownload = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("model.not.downloaded.title", comment: ""))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            Text(NSLocalizedString("model.not.downloaded.message", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.orange.opacity(0.1))
                            .overlay {
                                RoundedRectangle(cornerRadius: 0)
                                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
                .onHover { _ in }
            }
            
            // 主内容区：垂直布局 - 输入框 → 统计 → 历史记录
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. 顶部：测试输入框
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                            Text(NSLocalizedString("main.usage.hint", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.orange.opacity(0.1))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("test.input.label", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField(NSLocalizedString("test.input.placeholder", comment: ""), text: $testInputText, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...2)
                                .focused($isTestInputFocused)
                                .frame(height: 50)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    // 2. 统计数据（今日 / 累计 双维度）
                    VStack(alignment: .leading, spacing: 16) {
                        StatSection(
                            title: NSLocalizedString("stats.today", comment: ""),
                            characterCount: historyManager.todayCharacterCount,
                            charactersPerMinute: historyManager.todayCharactersPerMinute,
                            audioSeconds: historyManager.todayAudioSeconds,
                            transcriptionSeconds: historyManager.todayTranscriptionSeconds,
                            realtimeFactor: historyManager.todayRealtimeFactor
                        )
                        StatSection(
                            title: NSLocalizedString("stats.all", comment: ""),
                            characterCount: historyManager.totalCharacterCount,
                            charactersPerMinute: historyManager.totalCharactersPerMinute,
                            audioSeconds: historyManager.totalAudioSeconds,
                            transcriptionSeconds: historyManager.totalTranscriptionSeconds,
                            realtimeFactor: historyManager.totalRealtimeFactor
                        )
                        HStack(spacing: 24) {
                            StatItem(
                                title: NSLocalizedString("avg.characters.per.record", comment: ""),
                                value: String(format: "%.0f", historyManager.averageCharactersPerRecord)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    
                    // 3. 历史记录
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(NSLocalizedString("voice.input.history", comment: ""))
                                .font(.headline)
                            Text("(\(historyManager.totalCount) \(NSLocalizedString("records", comment: "")))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !historyManager.records.isEmpty {
                                Button(action: { showClearHistoryConfirm = true }) {
                                    Text(NSLocalizedString("clear.all", comment: ""))
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        
                        Divider()
                        
                        if historyManager.records.isEmpty {
                            Text(NSLocalizedString("no.records", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(historyManager.records) { record in
                                    HistoryRecordRow(
                                        record: record,
                                        isCopied: copiedRecordId == record.id,
                                        onCopy: { copyRecord(record) },
                                        onDelete: { historyManager.remove(record) }
                                    )
                                    if record.id != historyManager.records.last?.id {
                                        Divider()
                                            .padding(.leading, 16)
                                    }
                                }
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

// MARK: - 统计区块（今日/累计）
private struct StatSection: View {
    let title: String
    let characterCount: Int
    let charactersPerMinute: Double?
    let audioSeconds: TimeInterval
    let transcriptionSeconds: TimeInterval
    let realtimeFactor: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            HStack(spacing: 20) {
                StatItem(title: NSLocalizedString("stats.characters", comment: ""), value: "\(characterCount)")
                StatItem(
                    title: NSLocalizedString("stats.chars.per.min", comment: ""),
                    value: charsPerMinDisplay
                )
                StatItem(
                    title: NSLocalizedString("stats.audio.seconds", comment: ""),
                    value: formatSeconds(audioSeconds)
                )
                StatItem(
                    title: NSLocalizedString("stats.transcription.seconds", comment: ""),
                    value: formatSeconds(transcriptionSeconds)
                )
                StatItem(
                    title: NSLocalizedString("stats.realtime.factor", comment: ""),
                    value: realtimeFactorDisplay
                )
            }
        }
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
private struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - 历史记录行
private struct HistoryRecordRow: View {
    let record: VoiceInputHistoryRecord
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.text)
                    .font(.body)
                    .lineLimit(5)
                    .textSelection(.enabled)
                Text(record.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.leading, 16)

            Button(action: onCopy) {
                if isCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(NSLocalizedString("copy.success", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
        }
        .contextMenu {
            Button(action: onCopy) {
                Text(NSLocalizedString("copy", comment: ""))
            }
            Button(role: .destructive, action: onDelete) {
                Text(NSLocalizedString("delete", comment: ""))
            }
        }
    }
}

#Preview {
    VoiceInputView()
}
