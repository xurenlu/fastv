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
    @State private var isRecording = false
    @State private var recordingText = ""
    @State private var meetingRecords: [MeetingRecord] = []
    
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
                            Text("正在录音...")
                                .font(.headline)
                                .foregroundStyle(.red)
                        }
                        
                        Button(action: {
                            stopRecording()
                        }) {
                            Label("结束录音", systemImage: "stop.circle.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button(action: {
                            startRecording()
                        }) {
                            Label("开始录音", systemImage: "record.circle.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(meetingDetector.detectedMeetingApp == nil)
                    }
                }
                .padding()
                
                Divider()
                
                // 实时文本显示
                if !recordingText.isEmpty {
                    ScrollView {
                        Text(recordingText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        ForEach(meetingRecords) { record in
                            MeetingRecordRow(record: record)
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
    
    private func startRecording() {
        // TODO: 实现会议录音功能
        isRecording = true
        recordingText = ""
        print("🎤 [MeetingRecordView] 开始会议录音")
    }
    
    private func stopRecording() {
        // TODO: 实现停止录音和AI总结
        isRecording = false
        
        if !recordingText.isEmpty {
            // 创建会议记录
            let record = MeetingRecord(
                app: meetingDetector.detectedMeetingApp?.displayName ?? "未知",
                text: recordingText,
                createdAt: Date()
            )
            meetingRecords.insert(record, at: 0)
            
            // TODO: 调用AI总结
            if preferences.enableAIOptimization {
                generateSummary(for: record)
            }
        }
        
        recordingText = ""
        print("🛑 [MeetingRecordView] 停止会议录音")
    }
    
    private func generateSummary(for record: MeetingRecord) {
        // TODO: 实现AI总结功能
        Task {
            // 调用AI服务生成总结
        }
    }
}

/// 会议记录模型
struct MeetingRecord: Identifiable {
    let id: UUID
    let app: String
    let text: String
    let summary: String?
    let createdAt: Date
    
    init(id: UUID = UUID(), app: String, text: String, summary: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.app = app
        self.text = text
        self.summary = summary
        self.createdAt = createdAt
    }
}

/// 会议记录行视图
struct MeetingRecordRow: View {
    let record: MeetingRecord
    
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
            
            Text(record.text)
                .font(.body)
                .lineLimit(3)
            
            if let summary = record.summary {
                Divider()
                Text("总结：\(summary)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 4)
    }
}

