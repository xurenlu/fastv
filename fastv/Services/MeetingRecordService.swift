//
//  MeetingRecordService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine
import OSLog

/// 会议记录服务
/// 负责管理会议记录的持久化存储、实时录音和转录
@MainActor
class MeetingRecordService: ObservableObject {
    static let shared = MeetingRecordService()

    @Published private(set) var records: [MeetingRecord] = []
    @Published private(set) var isRecording = false
    @Published private(set) var currentRecordingId: UUID?
    /// 录音中的当前时长（1Hz 刷新）。**只在当前录音期间有意义**，不会写回 records[index].duration，
    /// 避免每秒触发整个 records 数组重新 publish 导致左侧列表全列重渲染。
    @Published private(set) var recordingDuration: TimeInterval = 0

    private let logger = Logger(subsystem: "com.fastv.meeting", category: "MeetingRecord")
    private let saveQueue = DispatchQueue(label: "com.fastv.meeting.save", qos: .userInitiated)
    private let documentsURL: URL
    private let recordsFileURL: URL

    // 落盘节流
    private var saveDebounceTask: Task<Void, Never>?
    private let saveDebounceInterval: TimeInterval = 1.0

    // 实时转录相关
    private var incrementalTranscriptTimer: Timer?
    private var currentTranscriptSegments: [String] = []
    private var accumulatedTranscript: String = ""  // 已累积转写，避免每次 joined("") 重拼 O(n²)
    private let transcriptInterval: TimeInterval = 15.0 // 每15秒进行一次转录
    private var lastTranscriptTime: Date?

    // 音频录制
    private var voiceService: VoiceInputService

    // 语言设置
    private var language: TranscriptLanguage {
        TranscriptLanguage(rawValue: UserPreferences.shared.voiceInputLanguage) ?? .zh
    }

    private init() {
        // 获取文档目录
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        documentsURL = paths[0].appendingPathComponent("MeetingRecords", isDirectory: true)
        recordsFileURL = documentsURL.appendingPathComponent("records.json")

        // 创建目录
        try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)

        voiceService = VoiceInputService.shared

        // 异步加载，避免阻塞主线程冷启动
        Task { @MainActor [weak self] in
            await self?.loadRecordsAsync()
        }
    }

    // MARK: - 记录管理

    /// 异步加载所有记录（不阻塞主线程）
    private func loadRecordsAsync() async {
        let url = recordsFileURL
        let loaded: [MeetingRecord] = await withCheckedContinuation { continuation in
            saveQueue.async {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    continuation.resume(returning: [])
                    return
                }
                do {
                    let data = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let result = try decoder.decode([MeetingRecord].self, from: data)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
        self.records = loaded
        logger.log("加载了 \(loaded.count) 条会议记录")
    }

    /// 保存所有记录（节流：连续多次调用合并为一次磁盘写）
    private func saveRecords() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.saveDebounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.flushSaveNow()
        }
    }

    /// 立即落盘（停止/取消录音、关键节点用）。**在 MainActor 上**对 records 做 snapshot，
    /// 再传给后台队列编码，避免跨 actor 直接读 @Published 数组触发数据竞争。
    private func flushSaveNow() {
        let snapshot = records  // MainActor 上 CoW 拷贝
        saveQueue.async { [weak self, url = recordsFileURL] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.withoutEscapingSlashes]  // 去掉 prettyPrinted，体积更小
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
                self?.logger.log("保存了 \(snapshot.count) 条会议记录")
            } catch {
                self?.logger.error("保存会议记录失败: \(error.localizedDescription)")
            }
        }
    }

    /// 添加新记录
    func add(_ record: MeetingRecord) {
        records.append(record)
        saveRecords()
    }

    /// 更新记录
    func update(_ record: MeetingRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
            saveRecords()
        }
    }

    /// 删除记录
    func delete(_ record: MeetingRecord) {
        records.removeAll { $0.id == record.id }
        saveRecords()
    }

    /// 获取记录
    func getRecord(id: UUID) -> MeetingRecord? {
        records.first { $0.id == id }
    }

    // MARK: - 录音控制

    /// 开始录音
    func startRecording() async throws {
        guard !isRecording else {
            logger.log("已在录音中，忽略开始请求")
            return
        }

        logger.log("开始会议录音")

        // 创建新记录
        let newRecord = MeetingRecord(
            title: MeetingRecord.generateDefaultTitle(),
            startTime: Date(),
            isRecording: true
        )

        currentRecordingId = newRecord.id
        records.insert(newRecord, at: 0) // 新记录排在最前

        // 显示波形悬浮窗，便于确认正在拾音
        WaveformWindowManager.shared.show()

        do {
            try voiceService.startRecording()
        } catch {
            WaveformWindowManager.shared.hide()
            records.removeAll { $0.id == newRecord.id }
            saveRecords()
            currentRecordingId = nil
            throw error
        }

        isRecording = true
        recordingDuration = 0

        // 连接音频电平回调，驱动波形显示
        voiceService.onAudioData = { level in
            Task { @MainActor in
                WaveformWindowManager.shared.updateAudioLevel(level)
            }
        }

        // 启动实时转录定时器
        startIncrementalTranscription()

        // 启动时长更新定时器
        startDurationTimer()

        saveRecords()
    }

    /// 停止录音
    func stopRecording() async {
        guard isRecording, let recordId = currentRecordingId else {
            logger.log("没有在录音中，忽略停止请求")
            return
        }

        logger.log("停止会议录音")

        // 停止定时器
        incrementalTranscriptTimer?.invalidate()
        incrementalTranscriptTimer = nil

        // 停止录音并获取最终音频（完整录音数据）
        let finalRecording = try? await voiceService.stopRecording()

        // 确定最终文本：优先对完整音频做转写，避免短于 15 秒的录音因定时器未触发而丢失内容
        var fullText = accumulatedTranscript
        if let recording = finalRecording, !recording.pcmData.isEmpty {
            do {
                let transcribed = try await SpeechTranscriber.transcribe(
                    recording: recording,
                    language: language,
                    enableCTCDeduplication: nil
                )
                // 完整转写覆盖增量片段，确保不丢内容（短录音时 currentTranscriptSegments 为空）
                if !transcribed.isEmpty {
                    fullText = transcribed
                    logger.log("停止时对完整音频转写成功，\(transcribed.count) 字")
                }
            } catch {
                logger.error("停止时完整音频转写失败: \(error.localizedDescription)，使用增量片段")
            }
        }

        // 更新记录
        if let index = records.firstIndex(where: { $0.id == recordId }) {
            var record = records[index]
            record.isRecording = false
            record.endTime = Date()
            record.duration = recordingDuration
            record.updatedAt = Date()
            record.originalText = fullText
            record.correctedText = CommonMistakeManager.shared.enableAutoCorrection
                ? TextCorrectionService.shared.correctText(fullText)
                : fullText

            records[index] = record
            saveRecords()

            // 若配置了 AI 且内容非空，异步生成标题 + 收尾流式图文文档
            if !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { @MainActor in
                    await generateTitleIfConfigured(for: recordId, text: record.correctedText.isEmpty ? fullText : record.correctedText)
                }
                Task { @MainActor in
                    await MeetingRichDocPipeline.shared.finalize(recordId: recordId, in: self)
                }
            }
        }

        // 立即落盘（停录是关键节点，不走 debounce）
        flushSaveNow()

        // 重置状态
        isRecording = false
        currentRecordingId = nil
        recordingDuration = 0
        currentTranscriptSegments = []
        accumulatedTranscript = ""
        lastTranscriptTime = nil

        // 断开回调并隐藏波形窗口
        voiceService.onAudioData = nil
        WaveformWindowManager.shared.hide()
    }

    /// 取消录音（不保存）
    func cancelRecording() async {
        guard isRecording, let recordId = currentRecordingId else {
            return
        }

        logger.log("取消会议录音")

        incrementalTranscriptTimer?.invalidate()
        incrementalTranscriptTimer = nil

        voiceService.cancelRecording()

        // 取消图文文档流式
        MeetingRichDocPipeline.shared.cancel(recordId: recordId)

        // 删除临时记录并立即落盘（避免下次启动还能看到这条「半成品」）
        records.removeAll { $0.id == recordId }
        flushSaveNow()

        isRecording = false
        currentRecordingId = nil
        recordingDuration = 0
        currentTranscriptSegments = []
        accumulatedTranscript = ""
        lastTranscriptTime = nil

        // 断开回调并隐藏波形窗口
        voiceService.onAudioData = nil
        WaveformWindowManager.shared.hide()
    }

    // MARK: - 实时转录

    /// 启动增量转录定时器
    private func startIncrementalTranscription() {
        currentTranscriptSegments = []
        accumulatedTranscript = ""
        lastTranscriptTime = Date()

        incrementalTranscriptTimer = Timer.scheduledTimer(withTimeInterval: transcriptInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performIncrementalTranscription()
            }
        }
    }

    /// 执行增量转录
    private func performIncrementalTranscription() async {
        guard isRecording, let recordId = currentRecordingId else {
            return
        }

        // 提取当前段落音频
        guard let segment = try? await voiceService.extractCurrentSegment() else {
            return
        }

        // 转录
        do {
            var text = try await SpeechTranscriber.transcribe(
                recording: segment,
                language: language,
                enableCTCDeduplication: nil
            )

            // 自动纠错
            if CommonMistakeManager.shared.enableAutoCorrection {
                text = TextCorrectionService.shared.correctText(text)
            }

            guard !text.isEmpty else { return }

            logger.log("增量转录: \(text.prefix(30))...")
            currentTranscriptSegments.append(text)
            accumulatedTranscript += text  // O(1) append，替代每次 O(n²) joined("")

            // 更新记录文本
            if let index = records.firstIndex(where: { $0.id == recordId }) {
                var record = records[index]
                record.originalText = accumulatedTranscript
                record.correctedText = CommonMistakeManager.shared.enableAutoCorrection
                    ? TextCorrectionService.shared.correctText(accumulatedTranscript)
                    : accumulatedTranscript
                record.updatedAt = Date()
                records[index] = record
                saveRecords()
            }

            lastTranscriptTime = Date()

            // 触发图文文档流式管线
            MeetingRichDocPipeline.shared.onTranscriptUpdated(recordId: recordId, in: self)
        } catch {
            logger.error("增量转录失败: \(error.localizedDescription)")
        }
    }

    /// 时长更新定时器：只更新 `recordingDuration`，**不**写回 records[index].duration，
    /// 避免每秒触发 records 数组重新 publish 导致左侧列表整列重渲染。
    /// 录音停止时由 stopRecording 把最终 duration 写回当前 record。
    private func startDurationTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, self.isRecording else {
                timer.invalidate()
                return
            }
            self.recordingDuration += 1.0
        }
    }

    // MARK: - AI 功能

    /// 若已配置 AI，根据内容生成标题并更新记录
    private func generateTitleIfConfigured(for recordId: UUID, text: String) async {
        guard !text.isEmpty, text.count >= 5 else { return }
        guard let index = records.firstIndex(where: { $0.id == recordId }) else { return }

        let systemPrompt = """
        根据以下会议/录音内容，生成一个简短标题，概括主题或主要内容。
        要求：只输出标题文字，不超过 20 字，不要引号、不要序号、不要其他说明。
        """

        do {
            let title = try await OllamaService.shared.optimizeTranscript(
                text: String(text.prefix(800)),  // 限制长度，避免超长请求
                scenario: .meetingSummary,
                systemPrompt: systemPrompt,
                useMistakes: false,
                useHighFrequencyWords: false
            )
            // 取首行、去除常见前缀（如「标题：」）
            let trimmed = title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = trimmed
                .replacingOccurrences(of: "标题：", with: "")
                .replacingOccurrences(of: "标题:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty, cleaned.count <= 50 {
                records[index].title = cleaned
                records[index].updatedAt = Date()
                saveRecords()
                logger.log("AI 生成标题: \(cleaned)")
            }
        } catch {
            logger.log("AI 生成标题未执行或失败（可能未配置 AI）: \(error.localizedDescription)")
        }
    }

    /// 生成摘要
    func generateSummary(for recordId: UUID) async throws {
        guard let index = records.firstIndex(where: { $0.id == recordId }) else {
            return
        }

        let record = records[index]
        let text = record.correctedText.isEmpty ? record.originalText : record.correctedText

        guard !text.isEmpty else {
            throw MeetingRecordError.emptyContent
        }

        let systemPrompt = """
        你是一个专业的会议记录助手。请对以下会议内容进行摘要，要求：
        1. 提取主要议题和讨论内容
        2. 总结关键决策和结论
        3. 条理清晰，使用简洁的语言
        4. 使用中文输出，分段落组织
        """

        let summary = try await OllamaService.shared.optimizeTranscript(
            text: text,
            scenario: .meetingSummary,
            systemPrompt: systemPrompt,
            useMistakes: false,
            useHighFrequencyWords: false
        )

        var updatedRecord = record
        updatedRecord.summary = summary
        updatedRecord.updatedAt = Date()
        records[index] = updatedRecord
        saveRecords()
    }

    /// 提取行动项
    func extractActionItems(for recordId: UUID) async throws {
        guard let index = records.firstIndex(where: { $0.id == recordId }) else {
            return
        }

        let record = records[index]
        let text = record.correctedText.isEmpty ? record.originalText : record.correctedText

        guard !text.isEmpty else {
            throw MeetingRecordError.emptyContent
        }

        let systemPrompt = """
        你是一个专业的会议助手。请从以下会议内容中提取行动项（Action Items）：
        1. 找出需要执行的任务
        2. 识别任务负责人（如果有）
        3. 标注截止时间（如果有）
        4. 每个行动项单独成行
        5. 使用简洁的语言描述
        6. 输出格式：每行一个行动项，不需要序号
        """

        let result = try await OllamaService.shared.optimizeTranscript(
            text: text,
            scenario: .meetingSummary,
            systemPrompt: systemPrompt,
            useMistakes: false,
            useHighFrequencyWords: false
        )

        // 按行分割
        let actionItems = result.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var updatedRecord = record
        updatedRecord.actionItems = actionItems
        updatedRecord.updatedAt = Date()
        records[index] = updatedRecord
        saveRecords()
    }

    /// 完整整理（摘要 + 行动项）
    func organizeContent(for recordId: UUID) async throws {
        try await generateSummary(for: recordId)
        try await extractActionItems(for: recordId)
    }

    // MARK: - 实时图文文档（供 MeetingRichDocPipeline 写回）

    /// 设置 / 清除流式标记
    func setRichDocStreaming(_ streaming: Bool, for recordId: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordId }) else { return }
        records[index].isRichDocStreaming = streaming
        records[index].updatedAt = Date()
    }

    /// 流式过程中：把当前累计输出写回 record（不持久化，避免高频磁盘 IO）
    func applyRichDocStreamingChunk(_ accumulatedMarkdown: String, for recordId: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordId }) else { return }
        records[index].richDocumentMarkdown = accumulatedMarkdown
        records[index].isRichDocStreaming = true
        records[index].updatedAt = Date()
    }

    /// 流式收尾：落盘 + 推进 cursor + 记录触发时间
    func commitRichDocStream(
        finalMarkdown: String,
        cursor: Int,
        triggeredAt: Date,
        for recordId: UUID
    ) {
        guard let index = records.firstIndex(where: { $0.id == recordId }) else { return }
        records[index].richDocumentMarkdown = finalMarkdown
        records[index].richDocCursor = cursor
        records[index].lastRichDocAt = triggeredAt
        records[index].isRichDocStreaming = false
        records[index].updatedAt = Date()
        saveRecords()
    }

    /// 手动重新生成（用户点「重新生成」按钮）
    func regenerateRichDoc(for recordId: UUID) async {
        guard let index = records.firstIndex(where: { $0.id == recordId }) else { return }
        records[index].richDocumentMarkdown = ""
        records[index].richDocCursor = 0
        records[index].lastRichDocAt = nil
        saveRecords()
        await MeetingRichDocPipeline.shared.finalize(recordId: recordId, in: self)
    }
}

/// 会议记录错误
enum MeetingRecordError: LocalizedError {
    case emptyContent
    case notRecording
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "没有可整理的内容"
        case .notRecording:
            return "没有正在进行的录音"
        case .recordingFailed(let message):
            return "录音失败: \(message)"
        }
    }
}
