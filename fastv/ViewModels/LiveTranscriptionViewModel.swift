//
//  LiveTranscriptionViewModel.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 直播转录视图模型
@MainActor
class LiveTranscriptionViewModel: ObservableObject {
    @Published var currentRecord: LiveTranscriptionRecord?
    @Published var isTranscribing = false
    @Published var transcribingDuration: Double = 0
    @Published var errorMessage: String?
    
    // 实时转写相关
    @Published var realtimeTranscript: String = ""  // 实时转写的文本
    @Published var transcriptionProgress: String = "" // 转写进度描述
    
    // 音频电平（用于波形显示）
    @Published var audioLevel: Float = 0.0
    
    private var transcribingStartTime: Date?
    private var durationTimer: Timer?
    private let audioService = LiveTranscriptionAudioService.shared
    private let recordManager = LiveTranscriptionManager.shared
    private let preferences = UserPreferences.shared
    
    // 实时转写组件
    private let silenceDetector = SilenceDetector()
    private let incrementalTranscription = IncrementalTranscriptionManager()
    private let sleepWakeNotifier = SleepWakeNotifier.shared
    
    private var silenceCheckTask: Task<Void, Never>?
    private var transcriptUpdateTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 监听捕获状态变化
        audioService.$isCapturing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isTranscribing)
        
        // 监听捕获时长变化
        audioService.$capturingDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$transcribingDuration)
        
        // 监听增量转写更新
        incrementalTranscription.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRealtimeTranscript()
            }
            .store(in: &cancellables)
        
        // 设置静音检测回调
        setupSilenceDetection()
        
        // 设置睡眠/唤醒监听
        setupSleepWakeHandling()
    }
    
    /// 开始转录
    func startTranscribing() {
        guard !isTranscribing else { return }
        
        do {
            // 创建新的直播转录记录
            let newRecord = LiveTranscriptionRecord(
                title: LiveTranscriptionRecord.generateDefaultTitle(),
                isTranscribing: true
            )
            currentRecord = newRecord
            transcribingStartTime = Date()
            transcribingDuration = 0
            realtimeTranscript = ""
            transcriptionProgress = ""
            
            // 重置增量转写管理器
            incrementalTranscription.clear()
            
            // 重置静音检测器
            silenceDetector.reset()
            
            // 启用防睡眠断言
            sleepWakeNotifier.enablePreventSleep(reason: "直播转录中")
            
            // 开始捕获系统音频（异步）
            Task {
                do {
                    try await audioService.startCapturing()
                    
                    // 启动静音检测
                    await MainActor.run {
                        startSilenceDetection()
                    }
                    
                    await MainActor.run {
                        print("✅ [LiveTranscriptionViewModel] 开始转录(已启用防睡眠)")
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        print("❌ [LiveTranscriptionViewModel] 开始转录失败: \(error)")
                    }
                }
            }
            
            print("✅ [LiveTranscriptionViewModel] 开始转录(已启用防睡眠)")
        }
    }
    
    /// 停止转录并保存
    func stopTranscribing() {
        guard isTranscribing, var record = currentRecord else { return }
        
        // 停止静音检测
        stopSilenceDetection()
        
        // 禁用防睡眠断言
        sleepWakeNotifier.disablePreventSleep()
        
        // 停止捕获
        Task { @MainActor in
            await processTranscribing(record: &record)
        }
    }
    
    /// 处理转录（内部方法）
    private func processTranscribing(record: inout LiveTranscriptionRecord) async {
        // 停止捕获
        guard let recording = try? await audioService.stopCapturing() else {
            errorMessage = "停止捕获失败"
            currentRecord = nil
            return
        }
        
        // 更新记录状态
        record.isTranscribing = false
        record.endTime = Date()
        record.duration = transcribingDuration
        
        // 获取语言设置
        let languageString = preferences.voiceInputLanguage
        let language = TranscriptLanguage(rawValue: languageString) ?? .zh
        
        // 检查是否有增量转写的结果
        let incrementalText = incrementalTranscription.getFullTranscript()
        var text: String
        
        if !incrementalText.isEmpty {
            // 使用增量转写的结果
            print("✅ [LiveTranscriptionViewModel] 使用增量转写结果,共 \(incrementalTranscription.segments.count) 个段落")
            text = incrementalText
            
            // 只转写最后未完成的部分(如果有的话)
            if recording.pcmData.count > 1000 {  // 至少有一些数据
                print("🔄 [LiveTranscriptionViewModel] 转写最后剩余部分...")
                do {
                    let lastPartText = try await SpeechTranscriber.transcribe(recording: recording, language: language)
                    if !lastPartText.isEmpty {
                        text += "\n" + lastPartText
                    }
                } catch {
                    print("⚠️ [LiveTranscriptionViewModel] 最后部分转写失败: \(error)")
                }
            }
        } else {
            // 没有增量转写结果,进行完整转写
            print("🔄 [LiveTranscriptionViewModel] 进行完整转写...")
            do {
                text = try await SpeechTranscriber.transcribe(recording: recording, language: language)
            } catch {
                errorMessage = "语音转文字失败: \(error.localizedDescription)"
                print("❌ [LiveTranscriptionViewModel] 转写失败: \(error)")
                currentRecord = nil
                return
            }
        }
        
        record.transcript = text
        
        // 保存记录（先保存原始文本）
        recordManager.add(record)
        
        // 异步进行AI优化、标题和摘要生成
        // 创建 record 的副本，避免在 escaping closure 中捕获 inout 参数
        let recordCopy = record
        Task { @MainActor in
            await optimizeAndGenerateMetadata(for: recordCopy)
        }
        
        currentRecord = nil
        
        print("✅ [LiveTranscriptionViewModel] 直播转录记录已保存")
    }
    
    /// 取消转录
    func cancelTranscribing() {
        guard isTranscribing else { return }
        
        // 停止静音检测
        stopSilenceDetection()
        
        // 禁用防睡眠断言
        sleepWakeNotifier.disablePreventSleep()
        
        audioService.cancelCapturing()
        currentRecord = nil
        transcribingStartTime = nil
        transcribingDuration = 0
        realtimeTranscript = ""
        transcriptionProgress = ""
        
        // 清空增量转写
        incrementalTranscription.clear()
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
            if self.isTranscribing {
                print("⚠️ [LiveTranscriptionViewModel] 系统即将睡眠,但转录中,已启用防睡眠断言应该能阻止")
            }
        }
        
        sleepWakeNotifier.onSystemDidWake = { @MainActor [weak self] in
            guard let self = self else { return }
            if self.isTranscribing {
                print("✅ [LiveTranscriptionViewModel] 系统唤醒,转录继续进行")
            }
        }
    }
    
    /// 启动静音检测
    private func startSilenceDetection() {
        silenceCheckTask?.cancel()
        
        // 从 preferences 读取配置并应用到 SilenceDetector
        silenceDetector.silenceThreshold = preferences.silenceThreshold
        silenceDetector.relativeThreshold = preferences.silenceRelativeThreshold
        silenceDetector.minimumSilenceDuration = preferences.silenceDetectionDuration
        
        print("✅ [LiveTranscriptionViewModel] 静音检测已启动 (绝对阈值=\(preferences.silenceThreshold), 相对阈值=\(Int(preferences.silenceRelativeThreshold * 100))%, 最小时长=\(preferences.silenceDetectionDuration)秒)")
        
        // 连接音频电平回调
        audioService.onAudioData = { [weak self] level in
            guard let self = self else { return }
            Task { @MainActor in
                // 更新音频电平（用于波形显示）
                self.audioLevel = level
                // 处理静音检测
                self.silenceDetector.processAudioLevel(level)
            }
        }
    }
    
    /// 停止静音检测
    private func stopSilenceDetection() {
        silenceCheckTask?.cancel()
        silenceCheckTask = nil
        transcriptUpdateTask?.cancel()
        transcriptUpdateTask = nil
        audioService.onAudioData = nil
        audioLevel = 0.0
        print("✅ [LiveTranscriptionViewModel] 静音检测已停止")
    }
    
    /// 处理检测到的静音段
    private func handleSilenceDetected() async {
        print("🔇 [LiveTranscriptionViewModel] 检测到静音段,开始提取并转写")
        
        do {
            // 提取当前段落的音频
            guard let segmentRecording = try await audioService.extractCurrentSegment() else {
                print("⚠️ [LiveTranscriptionViewModel] 段落音频为空,跳过")
                return
            }
            
            let startTime = audioService.getLastSegmentTime()
            let endTime = audioService.getCurrentDuration()
            
            print("📊 [LiveTranscriptionViewModel] 提取段落: \(String(format: "%.1f", startTime))s - \(String(format: "%.1f", endTime))s")
            
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
            print("❌ [LiveTranscriptionViewModel] 提取段落失败: \(error)")
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
        if transcriptUpdateTask == nil && isTranscribing {
            transcriptUpdateTask = Task { @MainActor in
                while isTranscribing {
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
    
    /// AI优化文本并生成标题和摘要
    private func optimizeAndGenerateMetadata(for record: LiveTranscriptionRecord) async {
        guard !record.transcript.isEmpty else {
            print("⚠️ [LiveTranscriptionViewModel] 转录文本为空，跳过AI优化")
            return
        }
        
        // 检查是否启用AI优化
        guard preferences.enableAIOptimization else {
            print("ℹ️ [LiveTranscriptionViewModel] AI优化未启用，跳过")
            return
        }
        
        // 更新记录状态为优化中
        var updatedRecord = record
        updatedRecord.isOptimizing = true
        recordManager.update(updatedRecord)
        
        print("🤖 [LiveTranscriptionViewModel] 开始AI优化和元数据生成...")
        
        do {
            // 1. AI优化文本（添加标点、修正错别字、分段）
            let optimizedText = try await OllamaService.shared.optimizeTranscript(
                text: record.transcript,
                scenario: .voiceInputOptimization,
                systemPrompt: preferences.aiSystemPrompt,
                useMistakes: true,
                useHighFrequencyWords: true
            )
            
            updatedRecord.optimizedTranscript = optimizedText
            print("✅ [LiveTranscriptionViewModel] AI优化完成")
            
            // 2. 生成标题
            let generatedTitle = await generateTitle(for: optimizedText)
            if !generatedTitle.isEmpty {
                updatedRecord.title = generatedTitle
                print("✅ [LiveTranscriptionViewModel] 标题生成完成: \(generatedTitle)")
            }
            
            // 3. 生成摘要
            let generatedSummary = await generateSummary(for: optimizedText)
            if !generatedSummary.isEmpty {
                updatedRecord.summary = generatedSummary
                print("✅ [LiveTranscriptionViewModel] 摘要生成完成")
            }
            
            // 更新记录
            updatedRecord.isOptimizing = false
            updatedRecord.updatedAt = Date()
            recordManager.update(updatedRecord)
            
            print("✅ [LiveTranscriptionViewModel] AI优化和元数据生成完成")
        } catch {
            print("❌ [LiveTranscriptionViewModel] AI优化失败: \(error.localizedDescription)")
            // 即使优化失败，也要更新状态
            updatedRecord.isOptimizing = false
            recordManager.update(updatedRecord)
        }
    }
    
    /// 生成标题
    private func generateTitle(for text: String) async -> String {
        guard !text.isEmpty else { return "" }
        
        // 如果文本较短，直接使用前50个字符
        if text.count <= 50 {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 使用AI生成标题
        do {
            let systemPrompt = """
            你是一个专业的标题生成助手。根据用户提供的文本内容，生成一个简洁、准确的标题。
            
            要求：
            1. 标题长度控制在10-30个字符之间
            2. 准确概括文本的核心内容
            3. 使用简洁明了的语言
            4. 只返回标题，不要添加任何说明或引号
            """
            
            let messages: [[String: Any]] = [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "请为以下文本生成标题：\n\n\(text)"]
            ]
            
            let config = preferences.getConfig(for: .voiceInputOptimization)
            let title = try await ChatAIService.shared.sendMessage(
                messages: messages,
                profile: config.profile,
                model: config.model,
                timeout: config.timeout
            )
            
            return title.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("⚠️ [LiveTranscriptionViewModel] 标题生成失败，使用默认标题: \(error.localizedDescription)")
            // 降级方案：使用文本的前50个字符
            return String(text.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    /// 生成摘要
    private func generateSummary(for text: String) async -> String {
        guard !text.isEmpty else { return "" }
        
        // 如果文本较短，直接返回
        if text.count <= 100 {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 使用AI生成摘要
        do {
            let systemPrompt = """
            你是一个专业的摘要生成助手。根据用户提供的文本内容，生成一个简洁的摘要。
            
            要求：
            1. 摘要长度控制在50-150个字符之间
            2. 准确概括文本的核心内容和要点
            3. 使用简洁明了的语言
            4. 只返回摘要，不要添加任何说明或引号
            """
            
            let messages: [[String: Any]] = [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "请为以下文本生成摘要：\n\n\(text)"]
            ]
            
            let config = preferences.getConfig(for: .voiceInputOptimization)
            let summary = try await ChatAIService.shared.sendMessage(
                messages: messages,
                profile: config.profile,
                model: config.model,
                timeout: config.timeout
            )
            
            return summary.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("⚠️ [LiveTranscriptionViewModel] 摘要生成失败: \(error.localizedDescription)")
            // 降级方案：使用文本的前150个字符
            return String(text.prefix(150)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

