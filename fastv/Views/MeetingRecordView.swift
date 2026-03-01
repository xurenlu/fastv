//
//  MeetingRecordView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import AppKit

/// 会议记录主视图
struct MeetingRecordView: View {
    @StateObject private var service = MeetingRecordService.shared
    @State private var selectedRecordId: UUID?
    @State private var showDeleteConfirm = false
    @State private var recordToDelete: MeetingRecord?
    @State private var searchText = ""

    private var filteredRecords: [MeetingRecord] {
        if searchText.isEmpty {
            return service.records
        }
        return service.records.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.originalText.localizedCaseInsensitiveContains(searchText) ||
            $0.correctedText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HSplitView {
            // 左侧：录音控制 + 记录列表
            leftPanel
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                .frame(maxHeight: .infinity)

            // 右侧：记录详情
            Group {
                if let recordId = selectedRecordId,
                   let record = service.getRecord(id: recordId) {
                    MeetingRecordDetailView(record: record, service: service)
                } else {
                    emptyDetailView
                }
            }
            .frame(minWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog("删除记录", isPresented: $showDeleteConfirm, presenting: recordToDelete) { record in
            Button("删除", role: .destructive) {
                withAnimation(.easeOut(duration: 0.2)) {
                    service.delete(record)
                    if selectedRecordId == record.id {
                        selectedRecordId = nil
                    }
                }
            }
        } message: { _ in
            Text("确定要删除这条记录吗？此操作无法撤销。")
        }
    }

    // MARK: - 左侧面板

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // 录音控制区
            recordingControlSection

            Divider()

            // 搜索 + 列表
            VStack(spacing: 0) {
                searchBar
                recordsList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 录音控制区

    private var recordingControlSection: some View {
        VStack(spacing: 16) {
            if service.isRecording {
                // 录音中状态
                HStack(spacing: 12) {
                    recordingIndicator
                    VStack(alignment: .leading, spacing: 2) {
                        Text("录音中")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(formatDuration(service.recordingDuration))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        }
                }

                HStack(spacing: 10) {
                    Button(action: { Task { await service.stopRecording() } }) {
                        Label("停止", systemImage: "stop.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: { Task { await service.cancelRecording() } }) {
                        Label("取消", systemImage: "xmark")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.08))
                            .foregroundStyle(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // 待机状态
                Button(action: {
                    Task {
                        try? await service.startRecording()
                        if let currentId = service.currentRecordingId {
                            selectedRecordId = currentId
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "mic.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("开始录音")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("会议、访谈、笔记…")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(16)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private var recordingIndicator: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .symbolEffect(.pulse)
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            TextField("搜索记录", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 记录列表

    private var recordsList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if filteredRecords.isEmpty {
                    emptyListPlaceholder
                } else {
                    ForEach(filteredRecords) { record in
                        MeetingRecordRow(
                            record: record,
                            isRecording: service.isRecording && service.currentRecordingId == record.id,
                            isSelected: selectedRecordId == record.id
                        )
                        .onTapGesture {
                            selectedRecordId = record.id
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                recordToDelete = record
                                showDeleteConfirm = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyListPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "暂无会议记录" : "未找到匹配记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - 空详情视图

    private var emptyDetailView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.image")
                .font(.system(size: 56))
                .foregroundStyle(.quaternary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("选择一条记录")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("在左侧列表中点击记录查看转写内容与 AI 整理")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 格式化时长

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0f秒", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d", minutes, secs)
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return String(format: "%d:%02d", hours, minutes)
        }
    }
}

// MARK: - 记录列表行

struct MeetingRecordRow: View {
    let record: MeetingRecord
    let isRecording: Bool
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左侧指示
            if isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(record.title.isEmpty ? "未命名记录" : record.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(record.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(record.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 4)
                    Text("\(record.characterCount) 字")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }

                if !isRecording {
                    let previewText = record.correctedText.isEmpty ? record.originalText : record.correctedText
                    if !previewText.isEmpty {
                        Text(previewText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        if isHovered {
            return Color.secondary.opacity(0.06)
        }
        return Color.clear
    }
}

// MARK: - 记录详情视图

struct MeetingRecordDetailView: View {
    @ObservedObject var service: MeetingRecordService
    let record: MeetingRecord
    @State private var isEditingTitle = false
    @State private var editedTitle: String
    @State private var showFullText = true
    @State private var isProcessing = false
    @State private var processingTask: String?

    init(record: MeetingRecord, service: MeetingRecordService) {
        self.record = record
        self.service = service
        self._editedTitle = State(initialValue: record.title)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // 标题 + 元数据
                headerSection

                // AI 功能区
                if !record.isRecording {
                    aiActionsSection
                }

                // 摘要
                if !record.summary.isEmpty {
                    summarySection
                }

                // 行动项
                if !record.actionItems.isEmpty {
                    actionItemsSection
                }

                // 全文
                textContentSection
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !record.isRecording {
                    Menu {
                        Button("复制全文") {
                            copyFullText()
                        }
                        Divider()
                        Menu("导出为") {
                            Button("PDF 文档") {
                                MeetingRecordExporter.export(record, format: .pdf)
                            }
                            Button("纯文本 (.txt)") {
                                MeetingRecordExporter.export(record, format: .txt)
                            }
                            Button("Markdown (.md)") {
                                MeetingRecordExporter.export(record, format: .markdown)
                            }
                            Button("网页 (.html)") {
                                MeetingRecordExporter.export(record, format: .html)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // MARK: - 标题区

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack(alignment: .top, spacing: 10) {
                if isEditingTitle {
                    TextField("记录标题", text: $editedTitle)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .onSubmit { saveTitle() }
                } else {
                    Text(record.title.isEmpty ? "未命名记录" : record.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Button(action: {
                    if isEditingTitle { saveTitle() } else { isEditingTitle = true }
                }) {
                    Image(systemName: isEditingTitle ? "checkmark.circle.fill" : "pencil")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }

            // 元数据标签
            HStack(spacing: 12) {
                metadataPill(icon: "calendar", text: record.formattedDate)
                metadataPill(icon: "clock", text: record.formattedDuration)
                metadataPill(icon: "character", text: "\(record.characterCount) 字")
            }
        }
    }

    private func metadataPill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color.secondary.opacity(0.08))
        }
    }

    // MARK: - AI 功能区

    private var aiActionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI 整理")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                aiActionButton(
                    icon: "doc.text",
                    title: "摘要",
                    isActive: processingTask == "summary",
                    hasResult: !record.summary.isEmpty
                ) { Task { await generateSummary() } }

                aiActionButton(
                    icon: "checklist",
                    title: "行动项",
                    isActive: processingTask == "actionItems",
                    hasResult: !record.actionItems.isEmpty
                ) { Task { await extractActionItems() } }

                aiActionButton(
                    icon: "sparkles",
                    title: "完整整理",
                    isActive: processingTask == "organize",
                    hasResult: !record.summary.isEmpty && !record.actionItems.isEmpty
                ) { Task { await organizeContent() } }
            }
        }
    }

    private func aiActionButton(
        icon: String,
        title: String,
        isActive: Bool,
        hasResult: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isActive {
                    ProgressView()
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .symbolRenderingMode(hasResult ? .palette : .hierarchical)
                        .foregroundStyle(hasResult ? Color.accentColor : .secondary)
                    if hasResult {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(title)
                    .font(.subheadline)
            }
            .foregroundStyle(isActive ? .secondary : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hasResult ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
        .disabled(isActive)
    }

    // MARK: - 摘要区

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("摘要", systemImage: "doc.text")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(record.summary)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor.opacity(0.5))
                        .frame(width: 3)
                        .padding(.leading, 12)
                }
        }
    }

    // MARK: - 行动项区

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("行动项 (\(record.actionItems.count))", systemImage: "checklist")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(record.actionItems.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor)
                            .clipShape(Circle())

                        Text(item)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineSpacing(4)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        }
    }

    // MARK: - 文本内容区

    private var textContentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: { showFullText.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: showFullText ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                    Text("全文")
                        .font(.subheadline.weight(.medium))
                    Text("(\(record.characterCount) 字)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            if showFullText {
                Text(record.correctedText.isEmpty ? record.originalText : record.correctedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(8)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - 辅助方法

    private func saveTitle() {
        var updated = record
        updated.title = editedTitle
        updated.updatedAt = Date()
        service.update(updated)
        isEditingTitle = false
    }

    private func copyFullText() {
        let text = record.correctedText.isEmpty ? record.originalText : record.correctedText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func generateSummary() async {
        processingTask = "summary"
        isProcessing = true
        defer { isProcessing = false; processingTask = nil }
        do { try await service.generateSummary(for: record.id) }
        catch { print("生成摘要失败: \(error)") }
    }

    private func extractActionItems() async {
        processingTask = "actionItems"
        isProcessing = true
        defer { isProcessing = false; processingTask = nil }
        do { try await service.extractActionItems(for: record.id) }
        catch { print("提取行动项失败: \(error)") }
    }

    private func organizeContent() async {
        processingTask = "organize"
        isProcessing = true
        defer { isProcessing = false; processingTask = nil }
        do { try await service.organizeContent(for: record.id) }
        catch { print("完整整理失败: \(error)") }
    }
}

#Preview {
    MeetingRecordView()
}
