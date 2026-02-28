//
//  MeetingRecordView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

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
        NavigationSplitView {
            // 左侧：记录列表
            recordsList
        } detail: {
            // 右侧：记录详情
            if let recordId = selectedRecordId,
               let record = service.getRecord(id: recordId) {
                MeetingRecordDetailView(record: record, service: service)
            } else {
                emptyDetailView
            }
        }
        .navigationTitle("会议记录")
        .searchable(text: $searchText, prompt: "搜索记录")
    }

    // MARK: - 记录列表

    @ViewBuilder
    private var recordsList: some View {
        List(selection: $selectedRecordId) {
            // 录音控制区
            Section {
                recordingControlCard
            }

            // 记录列表
            Section {
                if filteredRecords.isEmpty {
                    Text("暂无会议记录")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(filteredRecords) { record in
                        MeetingRecordRow(
                            record: record,
                            isRecording: service.isRecording && service.currentRecordingId == record.id
                        )
                        .tag(record.id)
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
            } header: {
                if !filteredRecords.isEmpty {
                    Text("历史记录")
                }
            }
        }
        .listStyle(.sidebar)
        .confirmationDialog("删除记录", isPresented: $showDeleteConfirm, presenting: recordToDelete) { record in
            Button("删除", role: .destructive) {
                withAnimation {
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

    // MARK: - 录音控制卡片

    @ViewBuilder
    private var recordingControlCard: some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Text("会议录音")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }

            // 状态显示
            HStack(spacing: 12) {
                if service.isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .symbolEffect(.pulse)

                    Text("录音中...")
                        .foregroundStyle(.red)

                    Spacer()

                    Text(formatDuration(service.recordingDuration))
                        .font(.monospaced(.body))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "mic.circle.fill")
                        .foregroundStyle(.secondary)

                    Text("点击开始录音")
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
            .font(.subheadline)

            // 控制按钮
            HStack(spacing: 16) {
                if service.isRecording {
                    // 停止按钮
                    Button(action: {
                        Task {
                            await service.stopRecording()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.circle.fill")
                            Text("停止")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    // 取消按钮
                    Button(action: {
                        Task {
                            await service.cancelRecording()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle")
                            Text("取消")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.secondary.opacity(0.15))
                        .foregroundStyle(.secondary)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                } else {
                    // 开始按钮
                    Button(action: {
                        Task {
                            try? await service.startRecording()
                            if let currentId = service.currentRecordingId {
                                selectedRecordId = currentId
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "record.circle")
                            Text("开始录音")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }

    // MARK: - 空详情视图

    @ViewBuilder
    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("选择一条记录查看详情")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标题行
            HStack {
                if isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                        .symbolEffect(.pulse)
                }

                Text(record.title.isEmpty ? "未命名记录" : record.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }

            // 时间和时长
            HStack(spacing: 8) {
                Text(record.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text(record.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                // 字数
                Text("\(record.characterCount) 字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 预览文本
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
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovered
        }
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.secondary.opacity(0.08))
            }
        }
    }
}

// MARK: - 记录详情视图

struct MeetingRecordDetailView: View {
    @ObservedObject var service: MeetingRecordService
    let record: MeetingRecord
    @State private var isEditingTitle = false
    @State private var editedTitle: String
    @State private var showFullText = false
    @State private var isProcessing = false
    @State private var processingTask: String?

    init(record: MeetingRecord, service: MeetingRecordService) {
        self.record = record
        self.service = service
        self._editedTitle = State(initialValue: record.title)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题区
                titleSection

                // 元数据区
                metadataSection

                // AI 功能区
                if !record.isRecording {
                    aiActionsSection
                }

                // 摘要区
                if !record.summary.isEmpty {
                    summarySection
                }

                // 行动项区
                if !record.actionItems.isEmpty {
                    actionItemsSection
                }

                // 文本内容区
                textContentSection
            }
            .padding(24)
        }
        .navigationTitle(record.isRecording ? "录音中" : "记录详情")
        .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private var titleSection: some View {
        HStack(spacing: 12) {
            if isEditingTitle {
                TextField("记录标题", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        saveTitle()
                    }
            } else {
                Text(record.title.isEmpty ? "未命名记录" : record.title)
                    .font(.title2.bold())
            }

            Button(action: {
                if isEditingTitle {
                    saveTitle()
                } else {
                    isEditingTitle = true
                }
            }) {
                Image(systemName: isEditingTitle ? "checkmark.circle.fill" : "pencil.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - 元数据区

    @ViewBuilder
    private var metadataSection: some View {
        HStack(spacing: 16) {
            MetadataItem(icon: "calendar", label: "开始时间", value: record.formattedDate)
            MetadataItem(icon: "clock", label: "时长", value: record.formattedDuration)
            MetadataItem(icon: "text.alignleft", label: "字数", value: "\(record.characterCount)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.secondary.opacity(0.1))
        }
    }

    // MARK: - AI 功能区

    @ViewBuilder
    private var aiActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI 整理")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                // 生成摘要
                ActionButton(
                    icon: "doc.text",
                    title: "生成摘要",
                    isProcessing: isProcessing && processingTask == "summary",
                    hasResult: !record.summary.isEmpty
                ) {
                    Task {
                        await generateSummary()
                    }
                }

                // 提取行动项
                ActionButton(
                    icon: "checklist",
                    title: "提取行动项",
                    isProcessing: isProcessing && processingTask == "actionItems",
                    hasResult: !record.actionItems.isEmpty
                ) {
                    Task {
                        await extractActionItems()
                    }
                }

                // 完整整理
                ActionButton(
                    icon: "sparkles",
                    title: "完整整理",
                    isProcessing: isProcessing && processingTask == "organize",
                    hasResult: !record.summary.isEmpty && !record.actionItems.isEmpty
                ) {
                    Task {
                        await organizeContent()
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.accentColor.opacity(0.3), lineWidth: hasAIResults ? 2 : 0)
        }
    }

    private var hasAIResults: Bool {
        !record.summary.isEmpty || !record.actionItems.isEmpty
    }

    // MARK: - 摘要区

    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.blue)
                Text("摘要")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }

            Text(record.summary)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.blue.opacity(0.08))
        }
    }

    // MARK: - 行动项区

    @ViewBuilder
    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundStyle(.green)
                Text("行动项")
                    .font(.subheadline.weight(.medium))
                Text("(\(record.actionItems.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ForEach(Array(record.actionItems.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(.green)
                        .clipShape(Circle())

                    Text(item)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.green.opacity(0.08))
        }
    }

    // MARK: - 文本内容区

    @ViewBuilder
    private var textContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: { showFullText.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: showFullText ? "chevron.up" : "chevron.down")
                        Text("全文")
                        Text("(\(record.characterCount) 字)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)

                Spacer()
            }

            if showFullText {
                Divider()

                Text(record.correctedText.isEmpty ? record.originalText : record.correctedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
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
        defer {
            isProcessing = false
            processingTask = nil
        }

        do {
            try await service.generateSummary(for: record.id)
        } catch {
            print("生成摘要失败: \(error)")
        }
    }

    private func extractActionItems() async {
        processingTask = "actionItems"
        isProcessing = true
        defer {
            isProcessing = false
            processingTask = nil
        }

        do {
            try await service.extractActionItems(for: record.id)
        } catch {
            print("提取行动项失败: \(error)")
        }
    }

    private func organizeContent() async {
        processingTask = "organize"
        isProcessing = true
        defer {
            isProcessing = false
            processingTask = nil
        }

        do {
            try await service.organizeContent(for: record.id)
        } catch {
            print("完整整理失败: \(error)")
        }
    }
}

// MARK: - 元数据项视图

struct MetadataItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - 操作按钮视图

struct ActionButton: View {
    let icon: String
    let title: String
    let isProcessing: Bool
    let hasResult: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: hasResult ? icon : icon)
                        .symbolRenderingMode(.hierarchical)
                    if hasResult {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Text(title)
            }
            .font(.subheadline)
            .foregroundStyle(isProcessing ? .secondary : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hasResult ? .green.opacity(0.15) : .secondary.opacity(0.1))
            }
            .overlay {
                if hasResult {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.green.opacity(0.5), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }
}

#Preview {
    MeetingRecordView()
}
