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
    case diarizing = "正在分离说话人..."
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
    
    // 音频电平（用于波形显示）
    @Published var audioLevel: Float = 0.0
    
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
    
    // 会议检测和系统音频捕获
    private let meetingDetector = MeetingSoftwareDetector.shared
    private let systemAudioCapture = SystemAudioCaptureService.shared
    @Published var showMeetingDetectionAlert = false
    @Published var detectedMeeting: MeetingSoftware?
    @Published var shouldCaptureSystemAudio = false
    private var systemAudioFileURL: URL?
    
    // WAV 文件实时保存
    private var wavFileURL: URL?
    private var wavFileHandle: FileHandle?
    private var wavDataSize: UInt32 = 0  // 已写入的音频数据大小
    private var wavSaveTimer: Timer?  // 定期保存音频数据的定时器
    private var wavSampleRate: Double = 16000
    private var wavChannels: UInt16 = 1
    
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
        
        // 设置会议检测回调
        setupMeetingDetection()
    }
    
    /// 设置会议检测
    private func setupMeetingDetection() {
        meetingDetector.setOnMeetingDetected { [weak self] meeting in
            Task { @MainActor in
                // 如果已经在录音，不提示
                guard let self = self, !self.isRecording else { return }
                
                self.detectedMeeting = meeting
                
                // 检查是否启用了自动开始录音
                if self.preferences.enableAutoStartRecording {
                    // 自动开始录音，不显示提示窗口
                    print("🤖 [MeetingRecordViewModel] 检测到会议软件，自动开始录音")
                    let captureSystemAudio = self.preferences.autoStartCaptureSystemAudio
                    self.handleMeetingDetectionStart(captureSystemAudio: captureSystemAudio)
                } else {
                    // 显示提示窗口，让用户手动确认
                    self.showMeetingDetectionAlert = true
                    self.showMeetingDetectionWindow()
                }
            }
        }
    }
    
    /// 处理会议检测提示 - 开始记录
    func handleMeetingDetectionStart(captureSystemAudio: Bool) {
        guard detectedMeeting != nil else { return }
        
        shouldCaptureSystemAudio = captureSystemAudio
        
        // 如果启用系统音频捕获，先启动
        if captureSystemAudio {
            Task {
                // 确保 BlackHole 检查已完成
                await systemAudioCapture.checkBlackHoleAvailability()
                
                if systemAudioCapture.isBlackHoleAvailable {
                    do {
                        let tempDir = FileManager.default.temporaryDirectory
                        let systemAudioURL = tempDir.appendingPathComponent("system_audio_\(UUID().uuidString).wav")
                        self.systemAudioFileURL = systemAudioURL
                        
                        try await systemAudioCapture.startCapture(to: systemAudioURL)
                        print("✅ [MeetingRecordViewModel] 系统音频捕获已启动")
                    } catch {
                        print("⚠️ [MeetingRecordViewModel] 系统音频捕获启动失败: \(error)")
                        // 即使系统音频捕获失败，也继续录音
                    }
                } else {
                    print("⚠️ [MeetingRecordViewModel] BlackHole 不可用，跳过系统音频捕获")
                }
                
                // 开始正常录音
                await MainActor.run {
                    startRecording()
                }
            }
        } else {
            // 直接开始录音
            startRecording()
        }
        
        showMeetingDetectionAlert = false
        detectedMeeting = nil
    }
    
    /// 处理会议检测提示 - 取消
    func handleMeetingDetectionCancel() {
        showMeetingDetectionAlert = false
        detectedMeeting = nil
    }
    
    /// 显示会议检测提示窗口
    func showMeetingDetectionWindow() {
        guard let meeting = detectedMeeting else { return }
        
        MeetingDetectionWindowManager.shared.showAlert(
            meeting: meeting,
            onStartRecording: { [weak self] captureSystemAudio in
                self?.handleMeetingDetectionStart(captureSystemAudio: captureSystemAudio)
            },
            onDismiss: { [weak self] in
                self?.handleMeetingDetectionCancel()
            }
        )
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
            
            // 立即保存到管理器，这样后续更新才能找到记录
            recordManager.add(newRecord)
            
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
            
            // 初始化 WAV 文件保存（如果启用了说话人分离）
            if preferences.enableSpeakerDiarization {
                initializeWAVFile(for: newRecord.id)
                startRealtimeWAVSaving()
            }
            
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
        
        // 停止 WAV 保存定时器
        wavSaveTimer?.invalidate()
        wavSaveTimer = nil
        
        // 清除实时保存回调
        voiceService.onConvertedAudioData = nil
        
        // 关闭 WAV 文件（如果已打开）
        if preferences.enableSpeakerDiarization {
            // 最后保存一次剩余的音频数据（如果有）
            saveRemainingAudioToWAV()
            // 注意：closeWAVFile 会在 processRecording 中使用 WAV 文件后调用
            // 这里不立即关闭，因为 processRecording 还需要使用
        }
        
        // 禁用防睡眠断言
        sleepWakeNotifier.disablePreventSleep()
        
        // 停止系统音频捕获（如果有）
        if systemAudioCapture.isCapturing {
            systemAudioCapture.stopCapture()
        }
        
        // 创建处理任务
        processingTask = Task { @MainActor in
            await processRecording(record: &record)
        }
    }
    
    /// 将录音保存为 WAV 文件
    private func saveRecordingToWAV(recording: VoiceRecording, to url: URL) async throws {
        // WAV 文件头结构
        let sampleRate = UInt32(recording.sampleRate)
        let channels = UInt16(recording.channelCount)
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(recording.pcmData.count)
        let fileSize = 36 + dataSize
        
        var wavData = Data()
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // fmt chunk size
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // audio format (PCM)
        wavData.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wavData.append(recording.pcmData)
        
        // 写入文件
        try wavData.write(to: url)
    }
    
    /// 处理录音（内部方法）
    private func processRecording(record: inout MeetingRecord) async {
        isProcessing = true
        canCancelProcessing = true
        processingProgress = 0.0
        
        // 停止录音
        processingStage = .transcribing
        processingProgress = 0.1
        
        // 停止录音并获取音频数据
        // 注意：如果启用了实时 WAV 保存，数据已经在录音过程中转换并保存
        guard let recording = try? await voiceService.stopRecording() else {
            errorMessage = "停止录音失败"
            currentRecord = nil
            isProcessing = false
            canCancelProcessing = false
            processingStage = nil
            return
        }
        
        // 如果启用了说话人分离且已有实时保存的 WAV 文件，直接使用
        // 否则，在需要时保存 WAV 文件（在说话人分离时）
        
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
                        scenario: .voiceInputOptimization,
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
            
            // 说话人分离（如果启用）
            if preferences.enableSpeakerDiarization {
                processingStage = .diarizing
                processingProgress = 0.65
                
                do {
                    // 保存录音到临时文件
                    let tempDir = FileManager.default.temporaryDirectory
                    let audioURL = tempDir.appendingPathComponent("\(record.id.uuidString).wav")
                    
                    // 如果已经有实时保存的 WAV 文件，直接使用；否则保存
                    if let existingWAVURL = wavFileURL, FileManager.default.fileExists(atPath: existingWAVURL.path) {
                        // 使用已实时保存的 WAV 文件（文件头已更新）
                        try FileManager.default.copyItem(at: existingWAVURL, to: audioURL)
                        print("✅ [MeetingRecordViewModel] 使用实时保存的 WAV 文件")
                    } else {
                        // 降级方案：将录音数据保存为 WAV 文件
                        try await saveRecordingToWAV(recording: recording, to: audioURL)
                        print("✅ [MeetingRecordViewModel] 使用降级方案保存 WAV 文件")
                    }
                    
                    // 执行说话人分离
                    let segments = try await SpeakerDiarizationService.shared.diarize(
                        audioURL: audioURL,
                        minSpeakers: preferences.diarizationMinSpeakers,
                        maxSpeakers: preferences.diarizationMaxSpeakers
                    )
                    
                    // 转换为 SpeakerSegmentInfo
                    record.speakerSegments = segments.map { segment in
                        SpeakerSegmentInfo(
                            start: segment.start,
                            end: segment.end,
                            speaker: segment.speaker,
                            duration: segment.duration
                        )
                    }
                    
                    // 清理临时文件
                    try? FileManager.default.removeItem(at: audioURL)
                    
                    // 关闭实时保存的 WAV 文件
                    closeWAVFile()
                    
                    print("✅ [MeetingRecordViewModel] 说话人分离完成，识别到 \(record.speakerSegments.count) 个片段")
                } catch {
                    if Task.isCancelled {
                        currentRecord = nil
                        isProcessing = false
                        canCancelProcessing = false
                        processingStage = nil
                        return
                    }
                    print("⚠️ [MeetingRecordViewModel] 说话人分离失败: \(error.localizedDescription)")
                    // 说话人分离失败不影响保存记录
                }
            }
            
            // 生成摘要和待办事项（如果启用会议记录 AI 摘要）
            if preferences.enableMeetingSummaryAI {
                processingStage = .summarizing
                processingProgress = 0.8
                
                do {
                    let markdownSummary = try await OllamaService.shared.generateMeetingSummary(
                        text: record.correctedText,
                        scenario: .meetingSummary,
                        timeout: preferences.getConfig(for: .meetingSummary).timeout * 2 // 摘要生成可能需要更长时间
                    )
                    
                    // 检查是否已取消
                    guard !Task.isCancelled else {
                        currentRecord = nil
                        isProcessing = false
                        canCancelProcessing = false
                        processingStage = nil
                        return
                    }
                    
                    // 解析 Markdown 摘要，提取摘要内容和待办事项
                    let (_, actionItems) = parseMarkdownSummary(markdownSummary)
                    
                    record.summary = markdownSummary  // 保存完整的 markdown 格式
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
            
            // 更新记录（记录已经在 startRecording 时添加，这里只需要更新）
            recordManager.update(record)
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
        
        // 设置增量转写更新回调：当段落转写完成时，实时更新会议记录
        incrementalTranscription.onTranscriptionUpdated = { [weak self] fullText in
            guard let self = self else { return }
            Task { @MainActor in
                // 如果正在录音且有当前记录，更新记录的文本
                if self.isRecording, var record = self.currentRecord {
                    record.originalText = fullText
                    record.correctedText = fullText  // 先使用原始文本，后续会进行修正
                    record.updatedAt = Date()
                    self.currentRecord = record
                    
                    // 实时更新到记录管理器（如果记录已存在）
                    if let existingRecord = self.recordManager.records.first(where: { $0.id == record.id }) {
                        var updatedRecord = existingRecord
                        updatedRecord.originalText = fullText
                        updatedRecord.correctedText = fullText
                        updatedRecord.updatedAt = Date()
                        self.recordManager.update(updatedRecord)
                    }
                    
                    print("📝 [MeetingRecordViewModel] 实时更新会议记录文本，长度: \(fullText.count)")
                }
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
        
        // 从 preferences 读取配置并应用到 SilenceDetector
        silenceDetector.silenceThreshold = preferences.silenceThreshold
        silenceDetector.relativeThreshold = preferences.silenceRelativeThreshold
        silenceDetector.minimumSilenceDuration = preferences.silenceDetectionDuration
        
        print("✅ [MeetingRecordViewModel] 静音检测已启动 (绝对阈值=\(preferences.silenceThreshold), 相对阈值=\(Int(preferences.silenceRelativeThreshold * 100))%, 最小时长=\(preferences.silenceDetectionDuration)秒)")
        
        // 连接音频电平回调
        voiceService.onAudioData = { [weak self] level in
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
        voiceService.onAudioData = nil
        audioLevel = 0.0
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
    
    /// 解析 Markdown 格式的摘要，提取摘要文本和待办事项
    /// - Parameter markdownSummary: Markdown 格式的摘要字符串
    /// - Returns: (摘要文本, 待办事项列表)
    private func parseMarkdownSummary(_ markdownSummary: String) -> (summaryText: String, actionItems: [String]) {
        var summaryText = ""
        var actionItems: [String] = []
        
        let lines = markdownSummary.components(separatedBy: .newlines)
        var currentSection: String? = nil
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 检测章节标题
            if trimmed.hasPrefix("## ") {
                let sectionName = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if sectionName == "会议摘要" {
                    currentSection = "summary"
                } else if sectionName == "待办事项" {
                    currentSection = "actionItems"
                } else {
                    currentSection = nil
                }
                continue
            }
            
            // 根据当前章节处理内容
            if currentSection == "summary" {
                if !trimmed.isEmpty {
                    if summaryText.isEmpty {
                        summaryText = trimmed
                    } else {
                        summaryText += "\n" + trimmed
                    }
                }
            } else if currentSection == "actionItems" {
                // 提取待办事项（支持 "- " 和 "• " 开头）
                if trimmed.hasPrefix("- ") {
                    let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !item.isEmpty {
                        actionItems.append(item)
                    }
                } else if trimmed.hasPrefix("• ") {
                    let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !item.isEmpty {
                        actionItems.append(item)
                    }
                }
            }
        }
        
        return (summaryText, actionItems)
    }
    
    /// 初始化 WAV 文件并写入文件头
    private func initializeWAVFile(for recordId: UUID) {
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let audioURL = tempDir.appendingPathComponent("\(recordId.uuidString).wav")
            
            // 如果文件已存在，删除它
            if FileManager.default.fileExists(atPath: audioURL.path) {
                try FileManager.default.removeItem(at: audioURL)
            }
            
            // 创建文件
            FileManager.default.createFile(atPath: audioURL.path, contents: nil, attributes: nil)
            
            guard let fileHandle = try? FileHandle(forWritingTo: audioURL) else {
                print("⚠️ [MeetingRecordViewModel] 无法创建 WAV 文件句柄")
                return
            }
            
            wavFileURL = audioURL
            wavFileHandle = fileHandle
            wavDataSize = 0
            
            // 写入 WAV 文件头（预留空间，稍后更新）
            let sampleRate = UInt32(wavSampleRate)
            let channels = wavChannels
            let bitsPerSample: UInt16 = 16
            let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
            let blockAlign = channels * bitsPerSample / 8
            
            var header = Data()
            
            // RIFF header
            header.append("RIFF".data(using: .ascii)!)
            header.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) }) // 文件大小，稍后更新
            header.append("WAVE".data(using: .ascii)!)
            
            // fmt chunk
            header.append("fmt ".data(using: .ascii)!)
            header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // fmt chunk size
            header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // audio format (PCM)
            header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Data($0) })
            header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
            header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
            header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
            header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
            
            // data chunk header
            header.append("data".data(using: .ascii)!)
            header.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) }) // 数据大小，稍后更新
            
            try fileHandle.write(contentsOf: header)
            
            print("✅ [MeetingRecordViewModel] WAV 文件已初始化: \(audioURL.path)")
        } catch {
            print("⚠️ [MeetingRecordViewModel] 初始化 WAV 文件失败: \(error)")
            wavFileHandle = nil
            wavFileURL = nil
        }
    }
    
    /// 启动实时 WAV 文件保存
    private func startRealtimeWAVSaving() {
        // 停止之前的定时器（如果有）
        wavSaveTimer?.invalidate()
        
        // 设置 VoiceInputService 的回调，实时获取转换后的音频数据
        voiceService.onConvertedAudioData = { [weak self] pcmData in
            guard let self = self else { return }
            Task { @MainActor in
                self.appendAudioDataToWAV(pcmData)
            }
        }
        
        print("✅ [MeetingRecordViewModel] 实时 WAV 保存已启动")
    }
    
    /// 保存剩余的音频数据到 WAV 文件
    private func saveRemainingAudioToWAV() {
        // 这个方法会在 stopRecording 时调用
        // 由于 VoiceInputService 在 stopRecording 时会返回转换后的数据
        // 如果实时保存过程中有遗漏的数据，在这里补充保存
        // 但实际上，由于转换是在 stopRecording 时进行的，这里主要是确保文件头已更新
    }
    
    /// 追加音频数据到 WAV 文件
    private func appendAudioDataToWAV(_ pcmData: Data) {
        guard let fileHandle = wavFileHandle else {
            return
        }
        
        do {
            // 追加数据到文件末尾
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: pcmData)
            
            // 更新数据大小
            wavDataSize += UInt32(pcmData.count)
            
            // 定期更新文件头（每1MB更新一次，避免频繁写入）
            if wavDataSize % (1024 * 1024) < UInt32(pcmData.count) {
                updateWAVFileHeader()
            }
        } catch {
            print("⚠️ [MeetingRecordViewModel] 追加音频数据到 WAV 文件失败: \(error)")
        }
    }
    
    /// 更新 WAV 文件头
    private func updateWAVFileHeader() {
        guard let fileHandle = wavFileHandle else {
            return
        }
        
        do {
            let fileSize = 36 + wavDataSize
            let dataSize = wavDataSize
            
            // 更新 RIFF chunk size (位置 4-7)
            try fileHandle.seek(toOffset: 4)
            let fileSizeBytes = withUnsafeBytes(of: fileSize.littleEndian) { Data($0) }
            try fileHandle.write(contentsOf: fileSizeBytes)
            
            // 更新 data chunk size (位置 40-43)
            try fileHandle.seek(toOffset: 40)
            let dataSizeBytes = withUnsafeBytes(of: dataSize.littleEndian) { Data($0) }
            try fileHandle.write(contentsOf: dataSizeBytes)
            
            // 重置到文件末尾
            try fileHandle.seekToEnd()
        } catch {
            print("⚠️ [MeetingRecordViewModel] 更新 WAV 文件头失败: \(error)")
        }
    }
    
    /// 关闭 WAV 文件并更新文件头
    private func closeWAVFile() {
        guard let fileHandle = wavFileHandle else {
            return
        }
        
        do {
            // 最终更新文件头
            updateWAVFileHeader()
            
            // 关闭文件
            try fileHandle.close()
            
            print("✅ [MeetingRecordViewModel] WAV 文件已关闭并更新文件头，总大小: \(wavDataSize) 字节")
        } catch {
            print("⚠️ [MeetingRecordViewModel] 关闭 WAV 文件失败: \(error)")
        }
        
        wavFileHandle = nil
        wavFileURL = nil
        wavDataSize = 0
    }
}

