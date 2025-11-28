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
    
    // 实时转写相关
    @Published var realtimeTranscript: String = ""  // 实时转写的文本
    @Published var transcriptionProgress: String = "" // 转写进度描述
    
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var processingTask: Task<Void, Never>?
    private let voiceService = VoiceInputService.shared
    private let recordManager = MeetingRecordManager.shared
    private let preferences = UserPreferences.shared
    
    // 实时转写组件
    private let silenceDetector = SilenceDetector()
    private let incrementalTranscription = IncrementalTranscriptionManager()
    private let sleepWakeNotifier = SleepWakeNotifier.shared
    
    private var silenceCheckTask: Task<Void, Never>?
    private var transcriptUpdateTask: Task<Void, Never>?
    
    init() {
        // 监听录音状态变化
        voiceService.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)
        
        // 监听录音时长变化
        voiceService.$recordingDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$recordingDuration)
        
        // 设置静音检测回调
        setupSilenceDetection()
        
        // 设置睡眠/唤醒监听
        setupSleepWakeHandling()
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
            realtimeTranscript = ""
            transcriptionProgress = ""
            
            // 重置增量转写管理器
            incrementalTranscription.clear()
            
            // 重置静音检测器
            silenceDetector.reset()
            
            // 启用防睡眠断言
            sleepWakeNotifier.enablePreventSleep(reason: "会议录音中")
            
            // 开始录音
            try voiceService.startRecording()
            
            // 启动静音检测
            startSilenceDetection()
            
            print("✅ [MeetingRecordViewModel] 开始录音(已启用防睡眠)")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [MeetingRecordViewModel] 开始录音失败: \(error)")
        }
    }
    
    /// 停止录音并处理
    func stopRecording() {
        guard isRecording, var record = currentRecord else { return }
        
        // 停止静音检测
        stopSilenceDetection()
        
        // 禁用防睡眠断言
        sleepWakeNotifier.disablePreventSleep()
        
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
        
        // 语音转文字 - 优先使用增量转写结果
        do {
            let languageString = preferences.voiceInputLanguage
            let language = TranscriptLanguage(rawValue: languageString) ?? .zh
            
            processingProgress = 0.2
            
            // 检查是否有增量转写的结果
            let incrementalText = incrementalTranscription.getFullTranscript()
            var text: String
            
            if !incrementalText.isEmpty {
                // 使用增量转写的结果
                print("✅ [MeetingRecordViewModel] 使用增量转写结果,共 \(incrementalTranscription.segments.count) 个段落")
                text = incrementalText
                
                // 只转写最后未完成的部分(如果有的话)
                if recording.pcmData.count > 1000 {  // 至少有一些数据
                    print("🔄 [MeetingRecordViewModel] 转写最后剩余部分...")
                    let lastPartText = try await SpeechTranscriber.transcribe(recording: recording, language: language)
                    if !lastPartText.isEmpty {
                        text += "\n" + lastPartText
                    }
                }
            } else {
                // 没有增量转写结果,进行完整转写
                print("🔄 [MeetingRecordViewModel] 进行完整转写...")
                text = try await SpeechTranscriber.transcribe(recording: recording, language: language)
            }
            
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
        
        // 停止静音检测
        stopSilenceDetection()
        
        // 禁用防睡眠断言
        sleepWakeNotifier.disablePreventSleep()
        
        voiceService.cancelRecording()
        currentRecord = nil
        recordingStartTime = nil
        recordingDuration = 0
        realtimeTranscript = ""
        transcriptionProgress = ""
        
        // 清空增量转写
        incrementalTranscription.clear()
        
        // 如果正在处理，也取消处理
        if isProcessing {
            cancelProcessing()
        }
    }
    
    // MARK: - Private Methods
    
    /// 设置静音检测
    private func setupSilenceDetection() {
        // 当检测到有效静音段时触发
        silenceDetector.onSilenceDetected = { [weak self] duration in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleSilenceDetected()
            }
        }
    }
    
    /// 设置睡眠/唤醒处理
    private func setupSleepWakeHandling() {
        sleepWakeNotifier.onSystemWillSleep = { @MainActor [weak self] in
            guard let self = self else { return }
            if self.isRecording {
                print("⚠️ [MeetingRecordViewModel] 系统即将睡眠,但录音中,已启用防睡眠断言应该能阻止")
            }
        }
        
        sleepWakeNotifier.onSystemDidWake = { @MainActor [weak self] in
            guard let self = self else { return }
            if self.isRecording {
                print("✅ [MeetingRecordViewModel] 系统唤醒,录音继续进行")
            }
        }
    }
    
    /// 启动静音检测
    private func startSilenceDetection() {
        silenceCheckTask?.cancel()
        
        // 连接音频电平回调
        voiceService.onAudioData = { [weak self] level in
            guard let self = self else { return }
            Task { @MainActor in
                self.silenceDetector.processAudioLevel(level)
            }
        }
        
        print("✅ [MeetingRecordViewModel] 静音检测已启动")
    }
    
    /// 停止静音检测
    private func stopSilenceDetection() {
        silenceCheckTask?.cancel()
        silenceCheckTask = nil
        transcriptUpdateTask?.cancel()
        transcriptUpdateTask = nil
        voiceService.onAudioData = nil
        print("✅ [MeetingRecordViewModel] 静音检测已停止")
    }
    
    /// 处理检测到的静音段
    private func handleSilenceDetected() async {
        print("🔇 [MeetingRecordViewModel] 检测到静音段,开始提取并转写")
        
        do {
            // 提取当前段落的音频
            guard let segmentRecording = try await voiceService.extractCurrentSegment() else {
                print("⚠️ [MeetingRecordViewModel] 段落音频为空,跳过")
                return
            }
            
            let startTime = voiceService.getLastSegmentTime()
            let endTime = voiceService.getCurrentDuration()
            
            print("📊 [MeetingRecordViewModel] 提取段落: \(String(format: "%.1f", startTime))s - \(String(format: "%.1f", endTime))s")
            
            // 获取语言设置
            let languageString = preferences.voiceInputLanguage
            let language = TranscriptLanguage(rawValue: languageString) ?? .zh
            
            // 添加到增量转写管理器
            incrementalTranscription.addSegment(
                audioData: segmentRecording.pcmData,
                sampleRate: segmentRecording.sampleRate,
                channelCount: segmentRecording.channelCount,
                startTime: startTime,
                endTime: endTime,
                language: language
            )
            
            // 更新实时转写内容
            updateRealtimeTranscript()
            
        } catch {
            print("❌ [MeetingRecordViewModel] 提取段落失败: \(error)")
        }
    }
    
    /// 更新实时转写文本
    private func updateRealtimeTranscript() {
        // 获取所有已完成的转写文本
        let fullText = incrementalTranscription.getFullTranscript()
        realtimeTranscript = fullText
        
        // 更新进度描述
        transcriptionProgress = incrementalTranscription.getProgressDescription()
        
        // 启动定期更新任务(如果还没有启动)
        if transcriptUpdateTask == nil && isRecording {
            transcriptUpdateTask = Task { @MainActor in
                while isRecording {
                    // 获取所有已完成的转写文本
                    let fullText = incrementalTranscription.getFullTranscript()
                    realtimeTranscript = fullText
                    
                    // 更新进度描述
                    transcriptionProgress = incrementalTranscription.getProgressDescription()
                    
                    // 每秒更新一次
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                transcriptUpdateTask = nil
            }
        }
    }
}

