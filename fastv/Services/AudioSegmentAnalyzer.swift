//
//  AudioSegmentAnalyzer.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AVFoundation

/// 音频分段分析结果
struct AudioSegment {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let transcript: String
    let topic: String?  // AI 分析的主题
    let semanticChange: Bool  // 是否发生语义变化
}

/// 音频分段分析服务
struct AudioSegmentAnalyzer {
    /// 分析音频分段并识别话题变化
    /// - Parameters:
    ///   - videoURL: 视频文件URL
    ///   - segmentDuration: 每个分段的时长（秒，默认5秒）
    ///   - endpoint: AI API 端点
    ///   - model: AI 模型名称
    ///   - apiToken: API Token（可选）
    ///   - progressHandler: 进度回调
    /// - Returns: 音频分段列表
    static func analyzeAudioSegments(
        from videoURL: URL,
        segmentDuration: TimeInterval = 5.0,
        endpoint: String,
        model: String,
        apiToken: String?,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> [AudioSegment] {
        print("🎵 [AudioSegmentAnalyzer] 开始分析音频分段")
        
        // 1. 提取音频
        progressHandler(0.1, "正在提取音频...")
        let tempAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        
        defer {
            // 清理临时文件
            try? FileManager.default.removeItem(at: tempAudioURL)
        }
        
        try await AudioExtractor.extractAudio(
            from: videoURL,
            to: tempAudioURL,
            format: .wav
        ) { progress in
            progressHandler(0.1 + progress * 0.2, "正在提取音频... \(Int(progress * 100))%")
        }
        
        // 2. 获取音频时长
        let asset = AVAsset(url: tempAudioURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        guard durationSeconds > 0 else {
            throw VideoProcessingError.invalidVideoFile
        }
        
        // 3. 分段转录
        let segmentCount = Int(ceil(durationSeconds / segmentDuration))
        var segments: [AudioSegment] = []
        var previousTopic: String? = nil
        
        for i in 0..<segmentCount {
            let startTime = Double(i) * segmentDuration
            let endTime = min(startTime + segmentDuration, durationSeconds)
            
            let progress = 0.3 + (Double(i) / Double(segmentCount)) * 0.5
            progressHandler(progress, "正在分析音频分段 \(i + 1)/\(segmentCount)...")
            
            // 提取音频分段
            let segmentURL = try await extractAudioSegment(
                from: tempAudioURL,
                startTime: startTime,
                endTime: endTime,
                segmentIndex: i
            )
            
            defer {
                try? FileManager.default.removeItem(at: segmentURL)
            }
            
            // 转录分段
            let transcript = try await SpeechTranscriber.transcribe(
                audioURL: segmentURL,
                language: .auto
            )
            
            // 使用 AI 分析话题（如果启用）
            var topic: String? = nil
            var semanticChange = false
            
            if !transcript.isEmpty {
                topic = try? await analyzeTopic(
                    transcript: transcript,
                    endpoint: endpoint,
                    model: model,
                    apiToken: apiToken
                )
                
                // 判断是否发生语义变化
                if let currentTopic = topic, let prevTopic = previousTopic {
                    semanticChange = currentTopic != prevTopic
                } else if previousTopic == nil && topic != nil {
                    semanticChange = true  // 第一个有效话题
                }
                
                previousTopic = topic
            }
            
            let segment = AudioSegment(
                startTime: startTime,
                endTime: endTime,
                transcript: transcript,
                topic: topic,
                semanticChange: semanticChange
            )
            
            segments.append(segment)
        }
        
        progressHandler(1.0, "音频分析完成，发现 \(segments.filter { $0.semanticChange }.count) 个话题变化点")
        
        return segments
    }
    
    /// 提取音频分段
    private static func extractAudioSegment(
        from audioURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval,
        segmentIndex: Int
    ) async throws -> URL {
        let asset = AVAsset(url: audioURL)
        let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        )
        
        guard let exportSession = exportSession else {
            throw VideoProcessingError.exportFailed
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("segment_\(segmentIndex)")
            .appendingPathExtension("m4a")
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
        let endCMTime = CMTime(seconds: endTime, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startCMTime, end: endCMTime)
        
        exportSession.timeRange = timeRange
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            throw VideoProcessingError.exportFailed
        }
        
        return outputURL
    }
    
    /// 使用 AI 分析话题
    private static func analyzeTopic(
        transcript: String,
        endpoint: String,
        model: String,
        apiToken: String?
    ) async throws -> String {
        let prompt = """
        请分析以下文本片段的主要话题或主题，用一句话简洁概括（不超过10个字）。
        
        文本：\(transcript)
        
        只返回话题，不要其他解释。
        """
        
        let preferences = UserPreferences.shared
        let systemPrompt = "你是一个话题分析助手，擅长从文本中提取主要话题。"
        
        // 注意：这里用于提取主题，不需要使用常错词和高频词
        let topic = try await OllamaService.shared.optimizeTranscript(
            text: prompt,
            endpoint: endpoint,
            model: model,
            apiToken: apiToken,
            timeout: 5.0,
            systemPrompt: systemPrompt,
            useMistakes: false,  // 主题提取不需要常错词
            useHighFrequencyWords: false  // 主题提取不需要高频词
        )
        
        return topic.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

