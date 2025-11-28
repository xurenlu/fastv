//
//  MeetingRecordViewModel.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 会议记录视图模型
@MainActor
class MeetingRecordViewModel: ObservableObject {
    @Published var currentRecord: MeetingRecord?
    @Published var isRecording = false
    @Published var recordingDuration: Double = 0
    @Published var isProcessing = false
    @Published var errorMessage: String?
    
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private let voiceService = VoiceInputService.shared
    private let recordManager = MeetingRecordManager.shared
    private let preferences = UserPreferences.shared
    
    init() {
        // 监听录音状态变化
        voiceService.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)
    }
    
    /// 开始录音
    func startRecording() {
        guard !isRecording else { return }
        
        do {
            // 创建新的会议记录
            let newRecord = MeetingRecord(
                title: MeetingRecord.generateDefaultTitle(),
                isRecording: true
            )
            currentRecord = newRecord
            recordingStartTime = Date()
            recordingDuration = 0
            
            // 开始录音
            try voiceService.startRecording()
            
            // 启动时长计时器
            startDurationTimer()
            
            print("✅ [MeetingRecordViewModel] 开始录音")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [MeetingRecordViewModel] 开始录音失败: \(error)")
        }
    }
    
    /// 停止录音并处理
    func stopRecording() async {
        guard isRecording, var record = currentRecord else { return }
        
        // 停止时长计时器
        stopDurationTimer()
        
        // 停止录音
        guard let recording = try? await voiceService.stopRecording() else {
            errorMessage = "停止录音失败"
            currentRecord = nil
            return
        }
        
        // 更新记录状态
        record.isRecording = false
        record.endTime = Date()
        record.duration = recordingDuration
        
        isProcessing = true
        
        // 语音转文字
        do {
            let languageString = preferences.voiceInputLanguage
            let language = TranscriptLanguage(rawValue: languageString) ?? .zh
            
            var text = try await SpeechTranscriber.transcribe(recording: recording, language: language)
            record.originalText = text
            
            // 快速纠错
            if preferences.enableFastCorrection {
                text = TextCorrectionService.shared.correctText(text)
            }
            
            // 常错词修正
            let mistakeManager = CommonMistakeManager.shared
            if mistakeManager.enableAutoCorrection {
                text = mistakeManager.applyCorrections(to: text)
            }
            
            record.correctedText = text
            
            // AI 修正和摘要生成（如果启用）
            if preferences.enableAIOptimization {
                // AI 修正文本
                do {
                    let optimizedText = try await OllamaService.shared.optimizeTranscript(
                        text: text,
                        endpoint: preferences.aiAPIEndpoint,
                        model: preferences.aiModel,
                        apiToken: preferences.aiAPIToken.isEmpty ? nil : preferences.aiAPIToken,
                        timeout: preferences.aiTimeout,
                        systemPrompt: preferences.aiSystemPrompt
                    )
                    record.correctedText = optimizedText
                } catch {
                    print("⚠️ [MeetingRecordViewModel] AI 修正失败，使用原始文本: \(error.localizedDescription)")
                }
                
                // 生成摘要和代办事项
                do {
                    let (summary, actionItems) = try await OllamaService.shared.generateMeetingSummary(
                        text: record.correctedText,
                        endpoint: preferences.aiAPIEndpoint,
                        model: preferences.aiModel,
                        apiToken: preferences.aiAPIToken.isEmpty ? nil : preferences.aiAPIToken,
                        timeout: preferences.aiTimeout * 2 // 摘要生成可能需要更长时间
                    )
                    record.summary = summary
                    record.actionItems = actionItems
                } catch {
                    print("⚠️ [MeetingRecordViewModel] 摘要生成失败: \(error.localizedDescription)")
                    // 摘要生成失败不影响保存记录
                }
            }
            
            // 如果标题还是默认的，尝试从文本中提取
            if record.title == MeetingRecord.generateDefaultTitle() && !record.correctedText.isEmpty {
                let firstLine = record.correctedText.components(separatedBy: .newlines).first ?? record.correctedText
                if firstLine.count > 5 && firstLine.count < 50 {
                    record.title = String(firstLine.prefix(50))
                }
            }
            
            // 保存记录
            recordManager.add(record)
            currentRecord = nil
            
            print("✅ [MeetingRecordViewModel] 会议记录已保存")
        } catch {
            errorMessage = "语音转文字失败: \(error.localizedDescription)"
            print("❌ [MeetingRecordViewModel] 处理失败: \(error)")
            currentRecord = nil
        }
        
        isProcessing = false
    }
    
    /// 取消录音
    func cancelRecording() {
        guard isRecording else { return }
        
        stopDurationTimer()
        voiceService.cancelRecording()
        currentRecord = nil
        recordingStartTime = nil
        recordingDuration = 0
    }
    
    // MARK: - Private Methods
    
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            self.recordingDuration = Date().timeIntervalSince(startTime)
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

