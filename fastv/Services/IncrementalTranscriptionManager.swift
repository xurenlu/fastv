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
    
    // 转写配置
    private let minimumSegmentDuration: TimeInterval = 3.0  // 最短段落时长(秒)
    private let maximumSegmentDuration: TimeInterval = 60.0 // 最长段落时长(秒)
    
    // 转写队列
    private var transcriptionQueue: [UUID] = []
    private var currentTranscriptionTask: Task<Void, Never>?
    
    // 转写完成回调：当段落转写完成时调用，参数是完整的转录文本
    var onTranscriptionUpdated: ((String) -> Void)?
    
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
        guard duration >= minimumSegmentDuration else {
            print("⚠️ [IncrementalTranscription] 段落时长过短(\(String(format: "%.2f", duration))s),跳过")
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
        print("📝 [IncrementalTranscription] 添加新段落: 时长=\(String(format: "%.2f", duration))s, 数据大小=\(audioData.count)字节")
        
        // 立即开始转写
        startTranscription(for: segment.id, audioData: audioData, sampleRate: sampleRate, channelCount: channelCount, language: language)
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
            return
        }
        
        // 标记为转写中
        segments[index].isTranscribing = true
        currentSegmentIndex = index
        isProcessing = true
        
        print("🔄 [IncrementalTranscription] 开始转写段落 #\(index + 1)")
        
        // 创建转写任务
        currentTranscriptionTask = Task { @MainActor in
            do {
                // 构造VoiceRecording
                let recording = VoiceRecording(
                    pcmData: audioData,
                    sampleRate: sampleRate,
                    channelCount: channelCount
                )
                
                // 调用转写服务
                let transcript = try await SpeechTranscriber.transcribe(recording: recording, language: language)
                
                // 更新段落
                if let idx = segments.firstIndex(where: { $0.id == segmentId }) {
                    segments[idx].transcript = transcript
                    segments[idx].isTranscribing = false
                    print("✅ [IncrementalTranscription] 段落 #\(idx + 1) 转写完成: \(transcript.prefix(30))...")
                    
                    // 通知观察者更新（在主线程）
                    await MainActor.run {
                        self.objectWillChange.send()
                        
                        // 触发转写更新回调，传递完整的转录文本
                        let fullText = self.getFullTranscript()
                        self.onTranscriptionUpdated?(fullText)
                    }
                }
            } catch {
                // 记录错误
                if let idx = segments.firstIndex(where: { $0.id == segmentId }) {
                    segments[idx].transcriptionError = error.localizedDescription
                    segments[idx].isTranscribing = false
                    print("❌ [IncrementalTranscription] 段落 #\(idx + 1) 转写失败: \(error)")
                }
            }
            
            currentSegmentIndex = nil
            isProcessing = false
        }
    }
    
    /// 获取所有已完成转写的文本(按时间顺序拼接)
    func getFullTranscript() -> String {
        segments
            .compactMap { $0.transcript }
            .joined(separator: "\n")
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
        return "已完成 \(stats.completed)/\(stats.total) 段"
    }
    
    /// 清空所有段落
    func clear() {
        currentTranscriptionTask?.cancel()
        currentTranscriptionTask = nil
        segments.removeAll()
        transcriptionQueue.removeAll()
        currentSegmentIndex = nil
        isProcessing = false
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

