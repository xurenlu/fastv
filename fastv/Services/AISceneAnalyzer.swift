//
//  AISceneAnalyzer.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AVFoundation
import AppKit

/// AI 场景分析结果
struct AISceneChangePoint {
    let timestamp: TimeInterval
    let frameNumber: Int
    let confidence: Double  // 置信度（0-1）
    let visualDescription: String?  // 视觉分析描述
    let audioTopic: String?  // 音频话题
    let semanticDescription: String  // 综合语义描述
    let thumbnailImage: NSImage?
}

/// AI 场景分析服务（多模态融合）
struct AISceneAnalyzer {
    /// 使用 AI 分析视频场景变化
    /// - Parameters:
    ///   - videoURL: 视频文件URL
    ///   - frameRate: 视频帧率
    ///   - visionModel: 视觉模型名称（如 llava, qwen-vl）
    ///   - textModel: 文本模型名称（用于音频分析）
    ///   - endpoint: AI API 端点
    ///   - apiToken: API Token（可选）
    ///   - frameInterval: 帧分析间隔（秒，默认2秒）
    ///   - audioSegmentDuration: 音频分段时长（秒，默认5秒）
    ///   - extractThumbnails: 是否提取截图
    ///   - progressHandler: 进度回调
    /// - Returns: AI 分析的关键转折点列表
    static func analyzeSceneChanges(
        from videoURL: URL,
        frameRate: Float? = nil,
        visionModel: String,
        textModel: String,
        endpoint: String,
        apiToken: String?,
        frameInterval: TimeInterval = 2.0,
        audioSegmentDuration: TimeInterval = 5.0,
        extractThumbnails: Bool = true,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> [AISceneChangePoint] {
        print("🤖 [AISceneAnalyzer] 开始 AI 多模态场景分析")
        
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        guard durationSeconds > 0 else {
            throw VideoProcessingError.invalidVideoFile
        }
        
        // 获取视频帧率
        let actualFrameRate: Float
        if let frameRate = frameRate {
            actualFrameRate = frameRate
        } else {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if let videoTrack = videoTracks.first {
                actualFrameRate = try await videoTrack.load(.nominalFrameRate)
            } else {
                throw VideoProcessingError.noVideoTrack
            }
        }
        
        // 并行执行视觉和音频分析
        async let visualAnalysis = analyzeVisualChanges(
            from: videoURL,
            frameRate: actualFrameRate,
            frameInterval: frameInterval,
            visionModel: visionModel,
            endpoint: endpoint,
            apiToken: apiToken,
            extractThumbnails: extractThumbnails,
            progressHandler: { progress, status in
                progressHandler(progress * 0.5, "视觉分析: \(status)")
            }
        )
        
        async let audioAnalysis = AudioSegmentAnalyzer.analyzeAudioSegments(
            from: videoURL,
            segmentDuration: audioSegmentDuration,
            endpoint: endpoint,
            model: textModel,
            apiToken: apiToken,
            progressHandler: { progress, status in
                progressHandler(0.5 + progress * 0.3, "音频分析: \(status)")
            }
        )
        
        // 等待两个分析完成
        let (visualResults, audioSegments) = try await (visualAnalysis, audioAnalysis)
        
        // 融合分析结果
        progressHandler(0.8, "正在融合视觉和音频分析结果...")
        let fusedResults = fuseAnalysisResults(
            visualResults: visualResults,
            audioSegments: audioSegments,
            duration: durationSeconds
        )
        
        progressHandler(1.0, "AI 分析完成，发现 \(fusedResults.count) 个关键转折点")
        
        return fusedResults
    }
    
    /// 分析视觉变化
    private static func analyzeVisualChanges(
        from videoURL: URL,
        frameRate: Float,
        frameInterval: TimeInterval,
        visionModel: String,
        endpoint: String,
        apiToken: String?,
        extractThumbnails: Bool,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> [(timestamp: TimeInterval, description: String, image: NSImage?)] {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        let totalSamples = Int(durationSeconds / frameInterval) + 1
        var results: [(timestamp: TimeInterval, description: String, image: NSImage?)] = []
        var previousImage: NSImage? = nil
        var previousDescription: String? = nil
        var failedFrames = 0  // 记录失败的帧数
        var aiFailedFrames = 0  // 记录AI分析失败的帧数
        
        for i in 0..<totalSamples {
            let time = Double(i) * frameInterval
            let timePoint = CMTime(seconds: time, preferredTimescale: 600)
            let clampedTime = CMTimeClampToRange(timePoint, range: CMTimeRange(start: .zero, duration: duration))
            
            let progress = Double(i) / Double(totalSamples)
            let timestamp = CMTimeGetSeconds(clampedTime)
            
            // 显示失败帧的统计信息
            let failInfo = (failedFrames > 0 || aiFailedFrames > 0) ? " (已跳过 \(failedFrames + aiFailedFrames) 个无法处理的帧)" : ""
            progressHandler(progress, "分析帧 \(i + 1)/\(totalSamples) (时间: \(String(format: "%.1f", timestamp))秒)\(failInfo)")
            
            // 提取帧 - 添加错误处理，避免单个帧失败导致整个分析停止
            var cgImage: CGImage?
            do {
                cgImage = try await imageGenerator.image(at: clampedTime).image
            } catch {
                // 如果提取帧失败，记录错误并跳过该帧
                print("⚠️ [AISceneAnalyzer] 无法提取第 \(i + 1) 帧 (时间: \(String(format: "%.1f", timestamp))秒): \(error.localizedDescription)")
                failedFrames += 1
                // 跳过该帧，继续分析下一帧
                continue
            }
            
            guard let cgImage = cgImage else {
                failedFrames += 1
                continue
            }
            
            let currentImage = NSImage(cgImage: cgImage, size: .zero)
            
            // 分析当前帧 - 添加错误处理，避免AI分析失败导致整个分析停止
            var description: String?
            do {
                if let prevImage = previousImage, let prevDesc = previousDescription {
                    // 比较两张图片
                    description = try await OllamaService.shared.compareImages(
                        image1: prevImage,
                        image2: currentImage,
                        endpoint: endpoint,
                        model: visionModel,
                        apiToken: apiToken,
                        timeout: 30.0
                    )
                } else {
                    // 分析第一帧
                    let prompt = "请描述这张图片中的场景、人物、动作和主要元素。用简洁的中文描述。"
                    description = try await OllamaService.shared.analyzeImage(
                        image: currentImage,
                        prompt: prompt,
                        endpoint: endpoint,
                        model: visionModel,
                        apiToken: apiToken,
                        timeout: 30.0
                    )
                }
            } catch {
                // 如果AI分析失败，记录错误并跳过该帧
                print("⚠️ [AISceneAnalyzer] AI分析第 \(i + 1) 帧失败 (时间: \(String(format: "%.1f", timestamp))秒): \(error.localizedDescription)")
                aiFailedFrames += 1
                // 跳过该帧，继续分析下一帧
                continue
            }
            
            guard let description = description else {
                aiFailedFrames += 1
                continue
            }
            
            // 判断是否有显著变化
            if let prevDesc = previousDescription, description != prevDesc {
                // 有变化，记录
                let thumbnail = extractThumbnails ? currentImage : nil
                results.append((timestamp: timestamp, description: description, image: thumbnail))
            }
            
            previousImage = currentImage
            previousDescription = description
        }
        
        print("✅ [AISceneAnalyzer] 视觉分析完成: 总样本数=\(totalSamples), 成功=\(totalSamples - failedFrames - aiFailedFrames), 提取失败=\(failedFrames), AI分析失败=\(aiFailedFrames), 变化点=\(results.count)")
        
        return results
    }
    
    /// 融合视觉和音频分析结果
    private static func fuseAnalysisResults(
        visualResults: [(timestamp: TimeInterval, description: String, image: NSImage?)],
        audioSegments: [AudioSegment],
        duration: TimeInterval
    ) -> [AISceneChangePoint] {
        var changePoints: [AISceneChangePoint] = []
        
        // 收集所有变化时间点
        var changeTimestamps: Set<TimeInterval> = []
        
        // 添加视觉变化点
        for visual in visualResults {
            changeTimestamps.insert(visual.timestamp)
        }
        
        // 添加音频话题变化点
        for audio in audioSegments where audio.semanticChange {
            changeTimestamps.insert(audio.startTime)
        }
        
        // 为每个变化点创建综合描述
        for timestamp in changeTimestamps.sorted() {
            // 找到最近的视觉描述
            let visualDesc = visualResults
                .min(by: { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) })?
                .description
            
            // 找到对应的音频话题
            let audioTopic = audioSegments.first(where: { 
                timestamp >= $0.startTime && timestamp <= $0.endTime 
            })?.topic
            
            // 计算置信度
            var confidence: Double = 0.5
            
            // 如果视觉和音频都检测到变化，置信度更高
            let hasVisualChange = visualResults.contains { abs($0.timestamp - timestamp) < 1.0 }
            let hasAudioChange = audioSegments.contains { 
                $0.semanticChange && abs($0.startTime - timestamp) < 2.0 
            }
            
            if hasVisualChange && hasAudioChange {
                confidence = 0.9
            } else if hasVisualChange || hasAudioChange {
                confidence = 0.7
            }
            
            // 生成综合描述
            var semanticDesc = ""
            if let visual = visualDesc {
                semanticDesc = "画面变化: \(visual)"
            }
            if let topic = audioTopic {
                if !semanticDesc.isEmpty {
                    semanticDesc += " | 话题: \(topic)"
                } else {
                    semanticDesc = "话题变化: \(topic)"
                }
            }
            
            if semanticDesc.isEmpty {
                semanticDesc = "检测到场景变化"
            }
            
            // 获取缩略图
            let thumbnail = visualResults.first(where: { abs($0.timestamp - timestamp) < 1.0 })?.image
            
            let changePoint = AISceneChangePoint(
                timestamp: timestamp,
                frameNumber: Int(timestamp * 30),  // 假设30fps
                confidence: confidence,
                visualDescription: visualDesc,
                audioTopic: audioTopic,
                semanticDescription: semanticDesc,
                thumbnailImage: thumbnail
            )
            
            changePoints.append(changePoint)
        }
        
        return changePoints.sorted { $0.timestamp < $1.timestamp }
    }
}

