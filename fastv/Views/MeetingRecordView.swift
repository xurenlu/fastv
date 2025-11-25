//
//  MeetingRecordView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 会议记录视图
struct MeetingRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var meetingDetector = MeetingDetector.shared
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var recordStorage = MeetingRecordStorage.shared
    @ObservedObject private var recordService = MeetingRecordService.shared
    @State private var isGeneratingSummary = false
    
    private var isRecording: Bool {
        recordService.isRecording
    }
    
    private var currentSegments: [MeetingSegment] {
        recordService.currentSegments
    }
    
    private var meetingRecords: [MeetingRecord] {
        recordStorage.records
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 会议信息
                if let app = meetingDetector.detectedMeetingApp {
                    HStack {
                        Image(systemName: "video.fill")
                            .foregroundStyle(.blue)
                        Text("检测到：\(app.displayName)")
                            .font(.headline)
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                }
                
                Divider()
                
                // 录音控制
                VStack(spacing: 16) {
                    if isRecording {
                        HStack {
                            Circle()
                                .fill(.red)
                                .frame(width: 12, height: 12)
                            Text("正在记录中...")
                                .font(.headline)
                                .foregroundStyle(.red)
                            
                            if !currentSegments.isEmpty {
                                Text("（已记录 \(currentSegments.count) 段）")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Button(action: {
                            Task {
                                await stopRecording()
                            }
                        }) {
                            Label("结束记录", systemImage: "stop.circle.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Text("会议记录将自动开始")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                
                Divider()
                
                // 实时对话显示
                if !currentSegments.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(currentSegments) { segment in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(formatTime(segment.timestamp))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                    
                                    Text(segment.text)
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 200)
                    
                    Divider()
                }
                
                // 历史记录
                if meetingRecords.isEmpty {
                    ContentUnavailableView {
                        Label("暂无会议记录", systemImage: "video.fill")
                    } description: {
                        Text("开始录音后，记录将显示在这里")
                    }
                } else {
                    List {
                        ForEach(Array(meetingRecords.enumerated()), id: \.element.id) { index, record in
                            MeetingRecordRow(
                                record: record,
                                isGeneratingSummary: isGeneratingSummary,
                                isFirstRecord: index == 0
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    recordStorage.delete(record)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("会议记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 700, height: 600)
    }
    
    private func stopRecording() async {
        guard let record = await recordService.stopRecording() else {
            return
        }
        
        // 保存记录
        recordStorage.add(record)
        
        // 如果启用AI优化，生成总结
        if preferences.enableAIOptimization && !record.segments.isEmpty {
            await generateSummary(for: record)
        }
    }
    
    private func generateSummary(for record: MeetingRecord) async {
        guard !isGeneratingSummary else { return }
        
        isGeneratingSummary = true
        
        do {
            let summary = try await OllamaService.shared.summarizeMeeting(
                text: record.text,
                endpoint: preferences.aiAPIEndpoint,
                model: preferences.aiModel,
                apiToken: preferences.aiAPIToken.isEmpty ? nil : preferences.aiAPIToken,
                timeout: preferences.aiTimeout
            )
            
            // 更新记录，添加总结
            let updatedRecord = MeetingRecord(
                id: record.id,
                app: record.app,
                segments: record.segments,
                summary: summary,
                createdAt: record.createdAt
            )
            recordStorage.update(updatedRecord)
            
            print("✅ [MeetingRecordView] AI总结完成")
        } catch {
            print("⚠️ [MeetingRecordView] AI总结失败: \(error)")
        }
        
        isGeneratingSummary = false
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// 会议对话片段
struct MeetingSegment: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    
    init(id: UUID = UUID(), text: String, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }
}

/// 会议记录模型
struct MeetingRecord: Identifiable, Codable {
    var id: UUID
    var app: String
    var segments: [MeetingSegment] // 多段对话
    var summary: String?
    let createdAt: Date
    
    // 兼容旧版本：从text字段读取
    var text: String {
        segments.map { $0.text }.joined(separator: "\n\n")
    }
    
    init(id: UUID = UUID(), app: String, segments: [MeetingSegment] = [], summary: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.app = app
        self.segments = segments
        self.summary = summary
        self.createdAt = createdAt
    }
    
    // 兼容旧版本的初始化方法
    init(id: UUID = UUID(), app: String, text: String, summary: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.app = app
        self.segments = [MeetingSegment(text: text, timestamp: createdAt)]
        self.summary = summary
        self.createdAt = createdAt
    }
}

/// 会议记录行视图
struct MeetingRecordRow: View {
    let record: MeetingRecord
    let isGeneratingSummary: Bool
    let isFirstRecord: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.app)
                    .font(.headline)
                Spacer()
                Text(record.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 显示多段对话
            if record.segments.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(record.segments.prefix(3)) { segment in
                        HStack(alignment: .top, spacing: 8) {
                            Text(formatTime(segment.timestamp))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)
                            
                            Text(segment.text)
                                .font(.body)
                                .lineLimit(2)
                        }
                    }
                    
                    if record.segments.count > 3 {
                        Text("...共 \(record.segments.count) 段对话")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(record.text)
                    .font(.body)
                    .lineLimit(3)
            }
            
            if let summary = record.summary {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI总结")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            } else if isGeneratingSummary && isFirstRecord {
                Divider()
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在生成总结...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

