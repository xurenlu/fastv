//
//  MeetingRecordViewModel.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 处理进度阶段
enum ProcessingStage: String {
    case transcribing = "正在转文字..."
    case correcting = "正在修正文本..."
    case optimizing = "正在优化文本..."
    case summarizing = "正在生成摘要..."
    case saving = "正在保存..."
}

/// 会议记录视图模型
@MainActor
class MeetingRecordViewModel: ObservableObject {
    @Published var currentRecord: MeetingRecord?
    @Published var isRecording = false
    @Published var recordingDuration: Double = 0
    @Published var isProcessing = false
    @Published var processingStage: ProcessingStage?
    @Published var processingProgress: Double = 0.0
    @Published var errorMessage: String?
    @Published var canCancelProcessing = false
    
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var processingTask: Task<Void, Never>?
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
    func stopRecording() {
        guard isRecording, var record = currentRecord else { return }
        
        // 停止时长计时器
        stopDurationTimer()
        
        // 创建处理任务
        processingTask = Task { @MainActor in
            await processRecording(record: &record)
        }
    }
    
    /// 处理录音（内部方法）
    private func processRecording(record: inout MeetingRecord) async {
        isProcessing = true
        canCancelProcessing = true
        processingProgress = 0.0
        
        // 停止录音
        processingStage = .transcribing
        processingProgress = 0.1
        
        guard let recording = try? await voiceService.stopRecording() else {
            errorMessage = "停止录音失败"
            currentRecord = nil
            isProcessing = false
            canCancelProcessing = false
            processingStage = nil
            return
        }
        
        // 更新记录状态
        record.isRecording = false
        record.endTime = Date()
        record.duration = recordingDuration
        
        // 检查是否已取消
        guard !Task.isCancelled else {
            currentRecord = nil
            isProcessing = false
            canCancelProcessing = false
            processingStage = nil
            return
        }
        
        // 语音转文字
        do {
            let languageString = preferences.voiceInputLanguage
            let language = TranscriptLanguage(rawValue: languageString) ?? .zh
            
            processingProgress = 0.2
            var text = try await SpeechTranscriber.transcribe(recording: recording, language: language)
            record.originalText = text
            
            // 检查是否已取消
            guard !Task.isCancelled else {
                currentRecord = nil
                isProcessing = false
                canCancelProcessing = false
                processingStage = nil
                return
            }
            
            // 快速纠错
            processingStage = .correcting
            processingProgress = 0.4
            
            if preferences.enableFastCorrection {
                text = TextCorrectionService.shared.correctText(text)
            }
            
            // 常错词修正
            let mistakeManager = CommonMistakeManager.shared
            if mistakeManager.enableAutoCorrection {
                text = mistakeManager.applyCorrections(to: text)
            }
            
            record.correctedText = text
            
            // AI 修正文本（如果启用 AI 文本优化）
            if preferences.enableAIOptimization {
                processingStage = .optimizing
                processingProgress = 0.6
                
                do {
                    let optimizedText = try await OllamaService.shared.optimizeTranscript(
                        text: text,
                        endpoint: preferences.aiAPIEndpoint,
                        model: preferences.aiModel,
                        apiToken: preferences.aiAPIToken.isEmpty ? nil : preferences.aiAPIToken,
                        timeout: preferences.aiTimeout,
                        systemPrompt: preferences.aiSystemPrompt,
                        useMistakes: true,
                        useHighFrequencyWords: true
                    )
                    
                    // 检查是否已取消
                    guard !Task.isCancelled else {
                        currentRecord = nil
                        isProcessing = false
                        canCancelProcessing = false
                        processingStage = nil
                        return
                    }
                    
                    record.correctedText = optimizedText
                } catch {
                    if Task.isCancelled {
                        currentRecord = nil
                        isProcessing = false
                        canCancelProcessing = false
                        processingStage = nil
                        return
                    }
                    print("⚠️ [MeetingRecordViewModel] AI 修正失败，使用原始文本: \(error.localizedDescription)")
                }
            }
            
            // 生成摘要和待办事项（如果启用会议记录 AI 摘要）
            if preferences.enableMeetingSummaryAI {
                processingStage = .summarizing
                processingProgress = 0.8
                
                do {
                    let (summary, actionItems) = try await OllamaService.shared.generateMeetingSummary(
                        text: record.correctedText,
                        endpoint: preferences.aiAPIEndpoint,
                        model: preferences.aiModel,
                        apiToken: preferences.aiAPIToken.isEmpty ? nil : preferences.aiAPIToken,
                        timeout: preferences.aiTimeout * 2 // 摘要生成可能需要更长时间
                    )
                    
                    // 检查是否已取消
                    guard !Task.isCancelled else {
                        currentRecord = nil
                        isProcessing = false
                        canCancelProcessing = false
                        processingStage = nil
                        return
                    }
                    
                    record.summary = summary
                    record.actionItems = actionItems
                } catch {
                    if Task.isCancelled {
                        currentRecord = nil
                        isProcessing = false
                        canCancelProcessing = false
                        processingStage = nil
                        return
                    }
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
            processingStage = .saving
            processingProgress = 0.9
            
            // 检查是否已取消
            guard !Task.isCancelled else {
                currentRecord = nil
                isProcessing = false
                canCancelProcessing = false
                processingStage = nil
                return
            }
            
            recordManager.add(record)
            currentRecord = nil
            processingProgress = 1.0
            
            print("✅ [MeetingRecordViewModel] 会议记录已保存")
        } catch {
            if Task.isCancelled {
                currentRecord = nil
                isProcessing = false
                canCancelProcessing = false
                processingStage = nil
                return
            }
            errorMessage = "语音转文字失败: \(error.localizedDescription)"
            print("❌ [MeetingRecordViewModel] 处理失败: \(error)")
            currentRecord = nil
        }
        
        isProcessing = false
        canCancelProcessing = false
        processingStage = nil
        processingProgress = 0.0
    }
    
    /// 取消处理
    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        canCancelProcessing = false
        processingStage = nil
        processingProgress = 0.0
        currentRecord = nil
        errorMessage = "处理已取消"
    }
    
    /// 取消录音
    func cancelRecording() {
        guard isRecording else { return }
        
        stopDurationTimer()
        voiceService.cancelRecording()
        currentRecord = nil
        recordingStartTime = nil
        recordingDuration = 0
        
        // 如果正在处理，也取消处理
        if isProcessing {
            cancelProcessing()
        }
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

