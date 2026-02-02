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
    case formatting = "正在整理文稿格式..."
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
    private var segmentCheckTimer: Timer?  // 定期检查是否需要切分
    
    // 延迟切分策略相关
    private var lastSegmentExtractTime: Date?  // 上次提取段落的时间
    private var pendingSilencePoints: [TimeInterval] = []  // 待处理的停顿点（相对于录音开始的时间）
    
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
    
    deinit {
        print("🧹 [MeetingRecordViewModel] deinit - 開始清理資源")
        
        // 取消所有定時器
        durationTimer?.invalidate()
        wavSaveTimer?.invalidate()
        segmentCheckTimer?.invalidate()
        
        // 取消所有異步任務
        processingTask?.cancel()
        silenceCheckTask?.cancel()
        transcriptUpdateTask?.cancel()
        
        // 關閉文件句柄
        try? wavFileHandle?.close()
        
        print("✅ [MeetingRecordViewModel] deinit 完成")
    }
    
    /// 清理資源（View 消失時調用）
    func cleanup() {
        print("🧹 [MeetingRecordViewModel] cleanup() - 清理資源")
        
        // 如果還在錄音，先停止
        if isRecording {
            print("⚠️ [MeetingRecordViewModel] 清理時仍在錄音，強制停止")
            // 清理 VoiceInputService 的回調
            voiceService.onConvertedAudioData = nil
            voiceService.onAudioData = nil
            voiceService.forceCleanup()
        }
        
        // 取消所有定時器
        durationTimer?.invalidate()
        durationTimer = nil
        wavSaveTimer?.invalidate()
        wavSaveTimer = nil
        segmentCheckTimer?.invalidate()
        segmentCheckTimer = nil
        
        // 取消所有異步任務
        processingTask?.cancel()
        processingTask = nil
        silenceCheckTask?.cancel()
        silenceCheckTask = nil
        transcriptUpdateTask?.cancel()
        transcriptUpdateTask = nil
        
        // 關閉文件句柄
        if let handle = wavFileHandle {
            try? handle.close()
            wavFileHandle = nil
        }
        
        // 停止靜音檢測
        stopSilenceDetection()
        
        // 停止系統音頻捕獲
        if systemAudioCapture.isCapturing {
            systemAudioCapture.stopCapture()
        }
        
        // 禁用防睡眠
        sleepWakeNotifier.disablePreventSleep()
        
        print("✅ [MeetingRecordViewModel] cleanup() 完成")
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
                
                // 只转写最后未完成的部分(如果有的话) - 在后台线程执行
                if recording.pcmData.count > 1000 {  // 至少有一些数据
                    print("🔄 [MeetingRecordViewModel] 转写最后剩余部分...")
                    let lastPartText = try await Task.detached(priority: .userInitiated) {
                        try await SpeechTranscriber.transcribe(recording: recording, language: language)
                    }.value
                    if !lastPartText.isEmpty {
                        text += "\n" + lastPartText
                    }
                }
            } else {
                // 没有增量转写结果,进行完整转写 - 在后台线程执行
                print("🔄 [MeetingRecordViewModel] 进行完整转写...")
                text = try await Task.detached(priority: .userInitiated) {
                    try await SpeechTranscriber.transcribe(recording: recording, language: language)
                }.value
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
            
            // 自动纠错（包含内置规则和用户自定义规则）
            processingStage = .correcting
            processingProgress = 0.4
            
            let mistakeManager = CommonMistakeManager.shared
            if mistakeManager.enableAutoCorrection {
                text = TextCorrectionService.shared.correctText(text)
            }
            
            record.correctedText = text
            
            // AI 修正文本（如果启用 AI 文本优化）- 在后台线程执行
            if preferences.enableAIOptimization {
                processingStage = .optimizing
                processingProgress = 0.5
                
                let currentText = text
                let systemPrompt = preferences.aiSystemPrompt
                
                do {
                    let optimizedText = try await Task.detached(priority: .userInitiated) {
                        try await OllamaService.shared.optimizeTranscript(
                            text: currentText,
                            scenario: .voiceInputOptimization,
                            systemPrompt: systemPrompt,
                            useMistakes: true,
                            useHighFrequencyWords: true
                        )
                    }.value
                    
                    // 检查是否已取消
                    guard !Task.isCancelled else {
                        currentRecord = nil
                        isProcessing = false
                        canCancelProcessing = false
                        processingStage = nil
                        return
                    }
                    
                    record.correctedText = optimizedText
                    text = optimizedText  // 更新 text 供后续使用
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
            
            // AI 文稿整理（修正错别字、添加换行、整理格式）- 在后台线程执行
            processingStage = .formatting
            processingProgress = 0.6
            
            let textToFormat = record.correctedText ?? text
            
            do {
                let formattedText = try await Task.detached(priority: .userInitiated) { [self] in
                    try await self.formatTranscriptWithAI(text: textToFormat)
                }.value
                
                // 检查是否已取消
                guard !Task.isCancelled else {
                    currentRecord = nil
                    isProcessing = false
                    canCancelProcessing = false
                    processingStage = nil
                    return
                }
                
                record.correctedText = formattedText
                print("✅ [MeetingRecordViewModel] AI 文稿整理完成")
            } catch {
                if Task.isCancelled {
                    currentRecord = nil
                    isProcessing = false
                    canCancelProcessing = false
                    processingStage = nil
                    return
                }
                print("⚠️ [MeetingRecordViewModel] AI 文稿整理失败: \(error.localizedDescription)")
            }
            
            // 说话人分离（如果启用）- 在后台线程执行
            if preferences.enableSpeakerDiarization {
                processingStage = .diarizing
                processingProgress = 0.65
                
                let recordId = record.id
                let existingWAVURL = wavFileURL
                let minSpeakers = preferences.diarizationMinSpeakers
                let maxSpeakers = preferences.diarizationMaxSpeakers
                
                do {
                    let segments = try await Task.detached(priority: .userInitiated) { [self] in
                        // 保存录音到临时文件
                        let tempDir = FileManager.default.temporaryDirectory
                        let audioURL = tempDir.appendingPathComponent("\(recordId.uuidString).wav")
                        
                        // 如果已经有实时保存的 WAV 文件，直接使用；否则保存
                        if let existingWAVURL = existingWAVURL, FileManager.default.fileExists(atPath: existingWAVURL.path) {
                            // 使用已实时保存的 WAV 文件（文件头已更新）
                            try FileManager.default.copyItem(at: existingWAVURL, to: audioURL)
                            print("✅ [MeetingRecordViewModel] 使用实时保存的 WAV 文件")
                        } else {
                            // 降级方案：将录音数据保存为 WAV 文件
                            try await self.saveRecordingToWAV(recording: recording, to: audioURL)
                            print("✅ [MeetingRecordViewModel] 使用降级方案保存 WAV 文件")
                        }
                        
                        // 执行说话人分离
                        let segments = try await SpeakerDiarizationService.shared.diarize(
                            audioURL: audioURL,
                            minSpeakers: minSpeakers,
                            maxSpeakers: maxSpeakers
                        )
                        
                        // 清理临时文件
                        try? FileManager.default.removeItem(at: audioURL)
                        
                        return segments
                    }.value
                    
                    // 转换为 SpeakerSegmentInfo
                    record.speakerSegments = segments.map { segment in
                        SpeakerSegmentInfo(
                            start: segment.start,
                            end: segment.end,
                            speaker: segment.speaker,
                            duration: segment.duration
                        )
                    }
                    
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
            
            // 生成摘要和待办事项（如果启用会议记录 AI 摘要）- 在后台线程执行
            if preferences.enableMeetingSummaryAI {
                processingStage = .summarizing
                processingProgress = 0.8
                
                let textForSummary = record.correctedText
                let summaryTimeout = preferences.getConfig(for: .meetingSummary).timeout * 2
                
                do {
                    let markdownSummary = try await Task.detached(priority: .userInitiated) {
                        try await OllamaService.shared.generateMeetingSummary(
                            text: textForSummary,
                            scenario: .meetingSummary,
                            timeout: summaryTimeout // 摘要生成可能需要更长时间
                        )
                    }.value
                    
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
        // 当检测到有效静音段时，记录停顿点（不立即切分）
        silenceDetector.onSilenceDetected = { [weak self] duration in
            guard let self = self else { return }
            Task { @MainActor in
                self.recordSilencePoint()
            }
        }
        
        // 设置片段开始转写回调，用于更新进度显示
        incrementalTranscription.onSegmentStarted = { [weak self] current, total in
            guard let self = self else { return }
            Task { @MainActor in
                self.transcriptionProgress = "转写中: 片段 \(current)/\(total)"
            }
        }
        
        // 设置增量转写更新回调：当段落转写完成时，实时更新会议记录
        incrementalTranscription.onTranscriptionUpdated = { [weak self] fullText in
            guard let self = self else { return }
            Task { @MainActor in
                // 更新实时转写文本显示（只显示最近的内容）
                self.realtimeTranscript = self.incrementalTranscription.getRecentTranscript(count: 2)
                self.transcriptionProgress = self.incrementalTranscription.getProgressDescription()
                
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
    
    /// 记录停顿点（延迟切分策略）
    private func recordSilencePoint() {
        let currentTime = recordingDuration
        pendingSilencePoints.append(currentTime)
        print("🔇 [MeetingRecordViewModel] 记录停顿点: \(String(format: "%.1f", currentTime))s (共 \(pendingSilencePoints.count) 个停顿点)")
    }
    
    /// 检查是否需要切分并转写（定期调用）
    private func checkAndExtractSegment() {
        guard isRecording else { return }
        
        let lastExtractTime = lastSegmentExtractTime ?? recordingStartTime ?? Date()
        let accumulatedDuration = Date().timeIntervalSince(lastExtractTime)
        
        let minDuration = IncrementalTranscriptionManager.minimumAccumulatedDuration
        let maxDuration = IncrementalTranscriptionManager.maximumSegmentDuration
        
        // 条件1: 累积超过30秒且有停顿点
        // 条件2: 累积超过60秒强制切分
        let shouldExtract = (accumulatedDuration >= minDuration && !pendingSilencePoints.isEmpty) ||
                           (accumulatedDuration >= maxDuration)
        
        if shouldExtract {
            let reason = accumulatedDuration >= maxDuration ? "达到最大时长\(Int(maxDuration))秒" : "累积\(Int(accumulatedDuration))秒且有停顿点"
            print("✂️ [MeetingRecordViewModel] 触发切分 (\(reason))")
            
            Task { @MainActor in
                await self.extractAndTranscribeSegment()
            }
        }
    }
    
    /// 提取并转写当前累积的音频段落
    private func extractAndTranscribeSegment() async {
        do {
            guard let segmentResult = try await voiceService.extractCurrentSegmentWithTiming() else {
                print("⚠️ [MeetingRecordViewModel] 段落音频为空,跳过")
                return
            }
            
            let startTime = segmentResult.startTime
            let endTime = segmentResult.endTime
            let duration = segmentResult.duration
            
            print("📊 [MeetingRecordViewModel] 提取段落: \(String(format: "%.1f", startTime))s - \(String(format: "%.1f", endTime))s (时长: \(String(format: "%.1f", duration))s)")
            
            // 清空已处理的停顿点
            pendingSilencePoints.removeAll()
            lastSegmentExtractTime = Date()
            
            // 获取语言设置
            let languageString = preferences.voiceInputLanguage
            let language = TranscriptLanguage(rawValue: languageString) ?? .zh
            
            // 添加到增量转写管理器
            incrementalTranscription.addSegment(
                audioData: segmentResult.recording.pcmData,
                sampleRate: segmentResult.recording.sampleRate,
                channelCount: segmentResult.recording.channelCount,
                startTime: startTime,
                endTime: endTime,
                language: language
            )
            
            // 更新进度显示
            transcriptionProgress = "正在转写第 \(incrementalTranscription.segments.count) 段..."
            
        } catch {
            print("❌ [MeetingRecordViewModel] 提取段落失败: \(error)")
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
        segmentCheckTimer?.invalidate()
        
        // 重置延迟切分状态
        lastSegmentExtractTime = Date()
        pendingSilencePoints.removeAll()
        
        // 从 preferences 读取配置并应用到 SilenceDetector
        silenceDetector.silenceThreshold = preferences.silenceThreshold
        silenceDetector.relativeThreshold = preferences.silenceRelativeThreshold
        silenceDetector.minimumSilenceDuration = preferences.silenceDetectionDuration
        
        print("✅ [MeetingRecordViewModel] 静音检测已启动 (绝对阈值=\(preferences.silenceThreshold), 相对阈值=\(Int(preferences.silenceRelativeThreshold * 100))%, 最小时长=\(preferences.silenceDetectionDuration)秒)")
        print("✅ [MeetingRecordViewModel] 延迟切分策略: 最小累积=\(Int(IncrementalTranscriptionManager.minimumAccumulatedDuration))秒, 最大=\(Int(IncrementalTranscriptionManager.maximumSegmentDuration))秒")
        
        // 连接音频电平回调
        voiceService.onAudioData = { [weak self] rawRms in
            guard let self = self else { return }
            Task { @MainActor in
                // 更新音频电平（用于波形显示）- 使用 service 已归一化的值
                self.audioLevel = self.voiceService.audioLevel
                // 处理静音检测（使用原始 RMS 值）
                self.silenceDetector.processAudioLevel(rawRms)
            }
        }
        
        // 启动定期检查定时器（每5秒检查一次是否需要切分）
        segmentCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.checkAndExtractSegment()
            }
        }
    }
    
    /// 停止静音检测
    private func stopSilenceDetection() {
        silenceCheckTask?.cancel()
        silenceCheckTask = nil
        transcriptUpdateTask?.cancel()
        transcriptUpdateTask = nil
        segmentCheckTimer?.invalidate()
        segmentCheckTimer = nil
        voiceService.onAudioData = nil
        audioLevel = 0.0
        pendingSilencePoints.removeAll()
        print("✅ [MeetingRecordViewModel] 静音检测已停止")
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
    
    /// 使用 AI 整理文稿格式（可在后台线程执行）
    /// - Parameter text: 原始转录文本
    /// - Returns: 整理后的文本（修正错别字、添加标点、适当换行）
    nonisolated private func formatTranscriptWithAI(text: String) async throws -> String {
        guard !text.isEmpty else { return text }
        
        // 构建专门用于文稿整理的 system prompt
        let formatSystemPrompt = """
        你是一个专业的文稿整理助手。请对语音转录文本进行整理，要求：
        1. 修正明显的错别字和同音字错误
        2. 添加适当的标点符号（逗号、句号、问号等）
        3. 在话题转换处适当添加段落分隔（空行）
        4. 保持原意不变，不要添加、删除或改变内容的含义
        5. 直接输出整理后的文本，不要添加任何说明或注释
        """
        
        // 调用 AI 服务进行格式整理
        let formattedText = try await OllamaService.shared.optimizeTranscript(
            text: text,
            scenario: .voiceInputOptimization,
            systemPrompt: formatSystemPrompt,
            useMistakes: true,
            useHighFrequencyWords: true
        )
        
        // 如果 AI 返回的结果为空或过短，返回原文
        if formattedText.isEmpty || formattedText.count < text.count / 2 {
            print("⚠️ [MeetingRecordViewModel] AI 文稿整理结果异常，使用原文")
            return text
        }
        
        return formattedText
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

