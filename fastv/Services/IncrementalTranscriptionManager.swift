//
//  IncrementalTranscriptionManager.swift
//  fastv
//
//  Created by rocky on 2025/11/28.
//

import Foundation
import AVFoundation
import Combine

/// 增量转写段落
struct TranscriptionSegment: Identifiable, Codable {
    let id: UUID
    let startTime: TimeInterval      // 相对于录音开始的时间
    let endTime: TimeInterval
    let audioDataSize: Int           // 音频数据大小(字节)
    var transcript: String?          // 转写文本(可能还未完成)
    var isTranscribing: Bool         // 是否正在转写中
    var transcriptionError: String?  // 转写错误信息
    
    init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, audioDataSize: Int) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.audioDataSize = audioDataSize
        self.transcript = nil
        self.isTranscribing = false
        self.transcriptionError = nil
    }
    
    var duration: TimeInterval {
        endTime - startTime
    }
}

/// 增量转写管理器 - 管理录音过程中的分段转写
@MainActor
class IncrementalTranscriptionManager: ObservableObject {
    @Published private(set) var segments: [TranscriptionSegment] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var currentSegmentIndex: Int?
    @Published private(set) var pendingSegmentsCount: Int = 0  // 等待转写的片段数
    
    // 转写配置（新策略：30-60秒切分）
    static let minimumAccumulatedDuration: TimeInterval = 30.0  // 最小累积时长，达到后才允许切分
    static let targetSegmentDuration: TimeInterval = 40.0       // 目标片段时长
    static let maximumSegmentDuration: TimeInterval = 60.0      // 最大片段时长，超过强制切分
    static let minimumSegmentDuration: TimeInterval = 5.0       // 最短段落时长，低于此时长跳过
    
    // 转写队列 - 支持并发处理多个片段
    private var transcriptionQueue: [(id: UUID, audioData: Data, sampleRate: Double, channelCount: Int, language: TranscriptLanguage)] = []
    private var currentTranscriptionTask: Task<Void, Never>?
    private var isProcessingQueue = false
    
    // 转写完成回调：当段落转写完成时调用，参数是完整的转录文本
    var onTranscriptionUpdated: ((String) -> Void)?
    
    // 新增：片段开始转写回调
    var onSegmentStarted: ((Int, Int) -> Void)?  // (当前片段索引, 总片段数)
    
    init() {}
    
    /// 添加新的音频段落
    /// - Parameters:
    ///   - audioData: 音频PCM数据
    ///   - sampleRate: 采样率
    ///   - channelCount: 声道数
    ///   - startTime: 开始时间(相对于录音开始)
    ///   - endTime: 结束时间
    ///   - language: 识别语言
    func addSegment(
        audioData: Data,
        sampleRate: Double,
        channelCount: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        language: TranscriptLanguage
    ) {
        let duration = endTime - startTime
        
        // 检查段落时长是否合理
        guard duration >= Self.minimumSegmentDuration else {
            print("⚠️ [IncrementalTranscription] 段落时长过短(\(String(format: "%.2f", duration))s < \(Self.minimumSegmentDuration)s),跳过")
            return
        }
        
        // 检查音频数据是否为空
        guard !audioData.isEmpty else {
            print("⚠️ [IncrementalTranscription] 音频数据为空,跳过")
            return
        }
        
        let segment = TranscriptionSegment(
            startTime: startTime,
            endTime: endTime,
            audioDataSize: audioData.count
        )
        
        segments.append(segment)
        
        // 添加到转写队列
        transcriptionQueue.append((id: segment.id, audioData: audioData, sampleRate: sampleRate, channelCount: channelCount, language: language))
        pendingSegmentsCount = transcriptionQueue.count
        
        print("📝 [IncrementalTranscription] 添加新段落 #\(segments.count): 时长=\(String(format: "%.2f", duration))s, 队列中=\(transcriptionQueue.count)个")
        
        // 立即开始处理队列（如果没有正在处理）
        processQueue()
    }
    
    /// 处理转写队列
    private func processQueue() {
        guard !isProcessingQueue else { return }
        guard !transcriptionQueue.isEmpty else { return }
        
        isProcessingQueue = true
        
        // 取出队列中的第一个任务
        let task = transcriptionQueue.removeFirst()
        pendingSegmentsCount = transcriptionQueue.count
        
        // 开始转写
        startTranscription(for: task.id, audioData: task.audioData, sampleRate: task.sampleRate, channelCount: task.channelCount, language: task.language)
    }
    
    /// 开始转写指定段落
    private func startTranscription(
        for segmentId: UUID,
        audioData: Data,
        sampleRate: Double,
        channelCount: Int,
        language: TranscriptLanguage
    ) {
        guard let index = segments.firstIndex(where: { $0.id == segmentId }) else {
            print("⚠️ [IncrementalTranscription] 未找到段落: \(segmentId)")
            isProcessingQueue = false
            processQueue()  // 继续处理队列中的下一个
            return
        }

        // 标记为转写中
        segments[index].isTranscribing = true
        currentSegmentIndex = index
        isProcessing = true

        // 通知片段开始转写
        onSegmentStarted?(index + 1, segments.count)

        print("🔄 [IncrementalTranscription] 开始转写段落 #\(index + 1)/\(segments.count)，队列剩余: \(transcriptionQueue.count)个")

        // 创建转写任务 - 使用 Task.detached 确保在后台线程执行，避免阻塞 UI
        currentTranscriptionTask = Task { @MainActor in
            let startTime = CFAbsoluteTimeGetCurrent()

            do {
                // 检查是否已取消
                guard !Task.isCancelled else {
                    print("⚠️ [IncrementalTranscription] 任务已取消，跳过转写")
                    await MainActor.run {
                        self.currentSegmentIndex = nil
                        self.isProcessingQueue = false
                        self.processQueue()
                    }
                    return
                }

                // 构造VoiceRecording
                let recording = VoiceRecording(
                    pcmData: audioData,
                    sampleRate: sampleRate,
                    channelCount: channelCount
                )

                // 使用 Task.detached 在后台线程执行转写，避免阻塞主线程
                // 传递父任务的检查函数，支持协作式取消
                let transcript = try await Task.detached(priority: .userInitiated) {
                    // 定期检查取消状态
                    let isCancelled = { Task.isCancelled }

                    return try await SpeechTranscriber.transcribe(
                        recording: recording,
                        language: language,
                        enableCTCDeduplication: nil,
                        cancellationCheck: isCancelled
                    )
                }.value

                let duration = CFAbsoluteTimeGetCurrent() - startTime

                // 回到主线程更新 UI
                await MainActor.run {
                    // 更新段落
                    if let idx = self.segments.firstIndex(where: { $0.id == segmentId }) {
                        self.segments[idx].transcript = transcript
                        self.segments[idx].isTranscribing = false
                        print("✅ [IncrementalTranscription] 段落 #\(idx + 1) 转写完成 (耗时\(String(format: "%.1f", duration))s): \(transcript.prefix(30))...")

                        self.objectWillChange.send()

                        // 触发转写更新回调，传递完整的转录文本
                        let fullText = self.getFullTranscript()
                        self.onTranscriptionUpdated?(fullText)
                    }
                }
            } catch {
                // 回到主线程记录错误
                await MainActor.run {
                    if let idx = self.segments.firstIndex(where: { $0.id == segmentId }) {
                        // 检查是否是取消错误
                        let nsError = error as NSError
                        if Task.isCancelled || nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
                            self.segments[idx].isTranscribing = false
                            print("⚠️ [IncrementalTranscription] 段落 #\(idx + 1) 转写已取消")
                        } else {
                            self.segments[idx].transcriptionError = error.localizedDescription
                            self.segments[idx].isTranscribing = false
                            print("❌ [IncrementalTranscription] 段落 #\(idx + 1) 转写失败: \(error)")
                        }
                    }
                }
            }

            await MainActor.run {
                self.currentSegmentIndex = nil
                self.isProcessing = self.transcriptionQueue.count > 0
                self.isProcessingQueue = false

                // 继续处理队列中的下一个任务
                self.processQueue()
            }
        }
    }
    
    /// 获取所有已完成转写的文本(按时间顺序拼接)
    func getFullTranscript() -> String {
        segments
            .compactMap { $0.transcript }
            .joined(separator: "\n")
    }
    
    /// 获取最近的转写文本（只返回最后 N 个片段）
    /// - Parameter count: 要返回的片段数量
    /// - Returns: 最近转写的文本
    func getRecentTranscript(count: Int = 2) -> String {
        let completedSegments = segments.filter { $0.transcript != nil }
        let recentSegments = completedSegments.suffix(count)
        return recentSegments.compactMap { $0.transcript }.joined(separator: "\n")
    }
    
    /// 获取当前正在转写的片段信息
    func getCurrentTranscribingInfo() -> String? {
        guard let index = currentSegmentIndex else { return nil }
        let segment = segments[index]
        return "正在转写: \(String(format: "%.0f", segment.startTime))s - \(String(format: "%.0f", segment.endTime))s"
    }
    
    /// 获取统计信息
    func getStatistics() -> (total: Int, completed: Int, transcribing: Int, failed: Int) {
        let total = segments.count
        let completed = segments.filter { $0.transcript != nil && !$0.isTranscribing }.count
        let transcribing = segments.filter { $0.isTranscribing }.count
        let failed = segments.filter { $0.transcriptionError != nil }.count
        return (total, completed, transcribing, failed)
    }
    
    /// 获取进度描述
    func getProgressDescription() -> String {
        let stats = getStatistics()
        if stats.total == 0 {
            return "暂无分段"
        }
        
        var desc = "已完成 \(stats.completed)/\(stats.total) 段"
        if stats.transcribing > 0 {
            desc += " (转写中...)"
        }
        if pendingSegmentsCount > 0 {
            desc += " [等待: \(pendingSegmentsCount)]"
        }
        return desc
    }
    
    /// 清空所有段落
    func clear() {
        currentTranscriptionTask?.cancel()
        currentTranscriptionTask = nil
        segments.removeAll()
        transcriptionQueue.removeAll()
        currentSegmentIndex = nil
        isProcessing = false
        isProcessingQueue = false
        pendingSegmentsCount = 0
    }
    
    /// 取消当前转写任务
    func cancelCurrentTranscription() {
        currentTranscriptionTask?.cancel()
        currentTranscriptionTask = nil
        
        if let index = currentSegmentIndex {
            segments[index].isTranscribing = false
        }
        
        currentSegmentIndex = nil
        isProcessing = false
    }
}

