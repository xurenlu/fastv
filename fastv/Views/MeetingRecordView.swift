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
    @State private var isRecording = false
    @State private var recordingText = ""
    @State private var accumulatedText = "" // 累积的文本
    @State private var isGeneratingSummary = false
    
    private let voiceService = VoiceInputService.shared
    private let history = VoiceInputHistory.shared
    
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
    
    private func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        recordingText = ""
        accumulatedText = ""
        
        // 禁用分段转文字（会议录音需要持续录音，不插入文本）
        voiceService.enableSegmentTranscription = false
        
        // 设置分段回调为空（会议录音不插入文本）
        voiceService.onSegmentReady = nil
        
        do {
            try voiceService.startRecording()
            print("🎤 [MeetingRecordView] 开始会议录音")
            
            // 设置音频数据回调（用于实时显示）
            voiceService.onAudioData = { level in
                // 可以在这里更新UI显示音频电平
            }
        } catch {
            print("❌ [MeetingRecordView] 开始录音失败: \(error)")
            isRecording = false
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        
        Task {
            // 停止录音
            guard let recording = try? await voiceService.stopRecording() else {
                print("❌ [MeetingRecordView] 停止录音失败")
                return
            }
            
            print("✅ [MeetingRecordView] 录音已停止，开始转文字...")
            
            // 转文字
            do {
                let languageString = preferences.voiceInputLanguage
                let language = TranscriptLanguage(rawValue: languageString) ?? .zh
                
                var text = try await SpeechTranscriber.transcribe(recording: recording, language: language)
                
                // 快速纠错
                if preferences.enableFastCorrection {
                    text = TextCorrectionService.shared.correctText(text)
                }
                
                // 常错词修正
                let mistakeManager = CommonMistakeManager.shared
                if mistakeManager.enableAutoCorrection {
                    text = mistakeManager.applyCorrections(to: text)
                }
                
                recordingText = text
                accumulatedText = text
                
                // 创建会议记录
                let record = MeetingRecord(
                    app: meetingDetector.detectedMeetingApp?.displayName ?? "未知",
                    text: text,
                    createdAt: Date()
                )
                recordStorage.add(record)
                
                // 调用AI总结
                if preferences.enableAIOptimization && !text.isEmpty {
                    await generateSummary(for: record)
                }
            } catch {
                print("❌ [MeetingRecordView] 转文字失败: \(error)")
            }
        }
        
        print("🛑 [MeetingRecordView] 停止会议录音")
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
                text: record.text,
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
}

/// 会议记录模型
struct MeetingRecord: Identifiable, Codable {
    var id: UUID
    var app: String
    var text: String
    var summary: String?
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
            
            Text(record.text)
                .font(.body)
                .lineLimit(3)
            
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
}

