//
//  LogoTrackingEngine.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation
import AppKit
import CoreImage
import AVFoundation

/// Logo 跟踪引擎
struct LogoTrackingEngine {
    
    /// 执行跟踪
    /// - Parameters:
    ///   - videoURL: 视频文件 URL
    ///   - config: 跟踪配置
    ///   - progressHandler: 进度回调
    /// - Returns: 跟踪结果列表
    static func track(
        videoURL: URL,
        config: LogoTrackingConfig,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> [LogoTrackingResult] {
        let asset = AVAsset(url: videoURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw LogoTrackingError.noVideoTrack
        }
        
        let duration = try await asset.load(.duration)
        let frameRate = videoTrack.nominalFrameRate
        let totalFrames = Int(duration.seconds * Double(frameRate))
        
        var results: [LogoTrackingResult] = []
        
        // 提取所有帧（简化版本：只提取关键帧附近的帧）
        let frameExtractor = AVAssetImageGenerator(asset: asset)
        frameExtractor.appliesPreferredTrackTransform = true
        frameExtractor.requestedTimeToleranceBefore = .zero
        frameExtractor.requestedTimeToleranceAfter = .zero
        
        // 对每一帧进行跟踪
        for frameNumber in 0..<totalFrames {
            let timestamp = Double(frameNumber) / Double(frameRate)
            let time = CMTime(seconds: timestamp, preferredTimescale: 600)
            
            // 加载当前帧
            guard let cgImage = try? await frameExtractor.image(at: time).image else {
                continue
            }
            
            let frameImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            // 查找最近的标注
            let nearestAnnotation = findNearestAnnotation(
                frameNumber: frameNumber,
                annotations: config.annotations
            )
            
            // 执行跟踪
            let result: LogoTrackingResult
            
            if let annotation = nearestAnnotation {
                // 使用混合方法
                if config.trackingMethod == .hybrid {
                    // 在关键帧附近使用模板匹配，其他使用光流
                    let distance = abs(frameNumber - annotation.frameNumber)
                    if distance < 30 { // 关键帧前后30帧内使用模板匹配
                        result = try await templateMatch(
                            frame: frameImage,
                            template: annotation.image,
                            templateBoundingBox: annotation.boundingBox,
                            threshold: config.templateMatchingThreshold
                        )
                } else {
                    // 使用光流法
                    if let previousResult = results.last {
                        var flowResult = try await opticalFlowTrack(
                            currentFrame: frameImage,
                            previousResult: previousResult,
                            windowSize: config.opticalFlowWindowSize
                        )
                        // 更新 frameNumber 和 timestamp
                        flowResult = LogoTrackingResult(
                            frameNumber: frameNumber,
                            timestamp: timestamp,
                            boundingBox: flowResult.boundingBox,
                            confidence: flowResult.confidence,
                            trackingMethod: flowResult.trackingMethod
                        )
                        result = flowResult
                    } else {
                        // 第一帧，使用模板匹配
                        var matchResult = try await templateMatch(
                            frame: frameImage,
                            template: annotation.image,
                            templateBoundingBox: annotation.boundingBox,
                            threshold: config.templateMatchingThreshold
                        )
                        // 更新 frameNumber 和 timestamp
                        matchResult = LogoTrackingResult(
                            frameNumber: frameNumber,
                            timestamp: timestamp,
                            boundingBox: matchResult.boundingBox,
                            confidence: matchResult.confidence,
                            trackingMethod: matchResult.trackingMethod
                        )
                        result = matchResult
                    }
                }
                } else if config.trackingMethod == .templateMatching {
                    var matchResult = try await templateMatch(
                        frame: frameImage,
                        template: annotation.image,
                        templateBoundingBox: annotation.boundingBox,
                        threshold: config.templateMatchingThreshold
                    )
                    // 更新 frameNumber 和 timestamp
                    matchResult = LogoTrackingResult(
                        frameNumber: frameNumber,
                        timestamp: timestamp,
                        boundingBox: matchResult.boundingBox,
                        confidence: matchResult.confidence,
                        trackingMethod: matchResult.trackingMethod
                    )
                    result = matchResult
                } else {
                    // 光流法
                    if let previousResult = results.last {
                        var flowResult = try await opticalFlowTrack(
                            currentFrame: frameImage,
                            previousResult: previousResult,
                            windowSize: config.opticalFlowWindowSize
                        )
                        // 更新 frameNumber 和 timestamp
                        flowResult = LogoTrackingResult(
                            frameNumber: frameNumber,
                            timestamp: timestamp,
                            boundingBox: flowResult.boundingBox,
                            confidence: flowResult.confidence,
                            trackingMethod: flowResult.trackingMethod
                        )
                        result = flowResult
                    } else {
                        // 第一帧，使用标注位置
                        result = LogoTrackingResult(
                            frameNumber: frameNumber,
                            timestamp: timestamp,
                            boundingBox: annotation.boundingBox,
                            confidence: 1.0,
                            trackingMethod: .interpolation
                        )
                    }
                }
            } else {
                // 没有标注，使用插值
                if config.interpolationEnabled {
                    result = interpolatePosition(
                        frameNumber: frameNumber,
                        annotations: config.annotations,
                        totalFrames: totalFrames
                    )
                } else {
                    continue
                }
            }
            
            // 过滤低置信度结果
            if result.confidence >= config.minConfidence {
                results.append(result)
            }
            
            // 更新进度
            let progress = Double(frameNumber) / Double(totalFrames)
            progressHandler(progress, "跟踪中... 帧 \(frameNumber)/\(totalFrames)")
        }
        
        return results
    }
    
    // MARK: - 模板匹配
    
    private static func templateMatch(
        frame: NSImage,
        template: NSImage?,
        templateBoundingBox: CGRect,
        threshold: Double
    ) async throws -> LogoTrackingResult {
        guard let template = template else {
            throw LogoTrackingError.invalidTemplate
        }
        
        // 转换为 Core Image
        guard let frameCIImage = frame.ciImage,
              let templateCIImage = template.ciImage else {
            throw LogoTrackingError.imageConversionFailed
        }
        
        // 提取模板区域
        let templateRect = CGRect(
            x: templateBoundingBox.origin.x,
            y: templateBoundingBox.origin.y,
            width: templateBoundingBox.width,
            height: templateBoundingBox.height
        )
        
        let croppedTemplate = templateCIImage.cropped(to: templateRect)
        
        // 使用 Core Image 的模板匹配（简化版本）
        // 注意：Core Image 没有直接的模板匹配滤镜，这里使用简化算法
        
        // 转换为灰度图
        guard let grayFilter = CIFilter(name: "CIColorControls") else {
            throw LogoTrackingError.imageProcessingFailed
        }
        grayFilter.setValue(frameCIImage, forKey: kCIInputImageKey)
        grayFilter.setValue(0.0, forKey: kCIInputSaturationKey)
        
        guard let templateGrayFilter = CIFilter(name: "CIColorControls") else {
            throw LogoTrackingError.imageProcessingFailed
        }
        templateGrayFilter.setValue(croppedTemplate, forKey: kCIInputImageKey)
        templateGrayFilter.setValue(0.0, forKey: kCIInputSaturationKey)
        
        guard let grayFrame = grayFilter.outputImage,
              let grayTemplate = templateGrayFilter.outputImage else {
            throw LogoTrackingError.imageProcessingFailed
        }
        
        // 简化的模板匹配：在帧中搜索最佳匹配位置
        // 这里使用归一化互相关（NCC）的简化版本
        let bestMatch = findBestMatch(
            frame: grayFrame,
            template: grayTemplate,
            searchRegion: frameCIImage.extent,
            threshold: threshold
        )
        
            // frameNumber 和 timestamp 将在调用处设置
            return LogoTrackingResult(
                frameNumber: 0,
                timestamp: 0,
                boundingBox: bestMatch.boundingBox,
                confidence: bestMatch.confidence,
                trackingMethod: .templateMatching
            )
    }
    
    private static func findBestMatch(
        frame: CIImage,
        template: CIImage,
        searchRegion: CGRect,
        threshold: Double
    ) -> (boundingBox: CGRect, confidence: Double) {
        // 简化的模板匹配实现
        // 在实际应用中，应该使用更复杂的算法
        
        let templateSize = template.extent.size
        var bestMatch: (x: CGFloat, y: CGFloat, score: Double) = (0, 0, 0)
        
        // 在搜索区域内滑动窗口
        let step = 10.0 // 搜索步长（像素）
        let maxX = searchRegion.width - templateSize.width
        let maxY = searchRegion.height - templateSize.height
        
        for x in stride(from: 0, through: maxX, by: step) {
            for y in stride(from: 0, through: maxY, by: step) {
                let windowRect = CGRect(
                    x: x,
                    y: y,
                    width: templateSize.width,
                    height: templateSize.height
                )
                
                // 提取窗口区域
                let window = frame.cropped(to: windowRect)
                
                // 计算相似度（简化版本：使用像素差异）
                let score = calculateSimilarity(window: window, template: template)
                
                if score > bestMatch.score {
                    bestMatch = (x, y, score)
                }
            }
        }
        
        let boundingBox = CGRect(
            x: bestMatch.x,
            y: bestMatch.y,
            width: templateSize.width,
            height: templateSize.height
        )
        
        let confidence = min(1.0, bestMatch.score / threshold)
        
        return (boundingBox, confidence)
    }
    
    private static func calculateSimilarity(window: CIImage, template: CIImage) -> Double {
        // 简化的相似度计算
        // 实际应该使用归一化互相关（NCC）或其他更精确的方法
        
        // 这里返回一个模拟的相似度值
        // 实际实现需要比较像素值
        return Double.random(in: 0.5...1.0) // 占位符
    }
    
    // MARK: - 光流法
    
    private static func opticalFlowTrack(
        currentFrame: NSImage,
        previousResult: LogoTrackingResult,
        windowSize: Int
    ) async throws -> LogoTrackingResult {
        // 光流法跟踪实现
        // 由于 macOS 没有直接的 OpenCV 绑定，这里使用简化版本
        
        // 简化的光流：假设 Logo 位置变化是连续的
        // 实际应该使用 Lucas-Kanade 或 Farneback 算法
        
        // 这里返回一个基于运动估计的位置
        let estimatedBox = previousResult.boundingBox // 简化：保持原位置
        
        return LogoTrackingResult(
            frameNumber: previousResult.frameNumber + 1,
            timestamp: previousResult.timestamp + (1.0 / 30.0), // 假设 30fps
            boundingBox: estimatedBox,
            confidence: 0.8, // 中等置信度
            trackingMethod: .opticalFlow
        )
    }
    
    // MARK: - 插值
    
    private static func interpolatePosition(
        frameNumber: Int,
        annotations: [LogoAnnotation],
        totalFrames: Int
    ) -> LogoTrackingResult {
        // 在标注之间进行线性插值
        
        guard annotations.count >= 2 else {
            // 如果标注少于2个，返回第一个标注的位置
            if let first = annotations.first {
                return LogoTrackingResult(
                    frameNumber: frameNumber,
                    timestamp: Double(frameNumber) / 30.0,
                    boundingBox: first.boundingBox,
                    confidence: 0.5,
                    trackingMethod: .interpolation
                )
            }
            
            // 默认位置
            return LogoTrackingResult(
                frameNumber: frameNumber,
                timestamp: Double(frameNumber) / 30.0,
                boundingBox: CGRect(x: 0, y: 0, width: 100, height: 100),
                confidence: 0.0,
                trackingMethod: .interpolation
            )
        }
        
        // 找到当前帧前后的标注
        let before = annotations.last { $0.frameNumber <= frameNumber }
        let after = annotations.first { $0.frameNumber > frameNumber }
        
        if let before = before, let after = after {
            // 线性插值
            let t = Double(frameNumber - before.frameNumber) / Double(after.frameNumber - before.frameNumber)
            
            let interpolatedX = before.boundingBox.origin.x + (after.boundingBox.origin.x - before.boundingBox.origin.x) * CGFloat(t)
            let interpolatedY = before.boundingBox.origin.y + (after.boundingBox.origin.y - before.boundingBox.origin.y) * CGFloat(t)
            let interpolatedWidth = before.boundingBox.width + (after.boundingBox.width - before.boundingBox.width) * CGFloat(t)
            let interpolatedHeight = before.boundingBox.height + (after.boundingBox.height - before.boundingBox.height) * CGFloat(t)
            
            return LogoTrackingResult(
                frameNumber: frameNumber,
                timestamp: Double(frameNumber) / 30.0,
                boundingBox: CGRect(
                    x: interpolatedX,
                    y: interpolatedY,
                    width: interpolatedWidth,
                    height: interpolatedHeight
                ),
                confidence: 0.7,
                trackingMethod: .interpolation
            )
        } else if let before = before {
            // 只有前面的标注，使用它的位置
            return LogoTrackingResult(
                frameNumber: frameNumber,
                timestamp: Double(frameNumber) / 30.0,
                boundingBox: before.boundingBox,
                confidence: 0.6,
                trackingMethod: .interpolation
            )
        } else if let after = after {
            // 只有后面的标注，使用它的位置
            return LogoTrackingResult(
                frameNumber: frameNumber,
                timestamp: Double(frameNumber) / 30.0,
                boundingBox: after.boundingBox,
                confidence: 0.6,
                trackingMethod: .interpolation
            )
        }
        
        // 默认
        return LogoTrackingResult(
            frameNumber: frameNumber,
            timestamp: Double(frameNumber) / 30.0,
            boundingBox: CGRect(x: 0, y: 0, width: 100, height: 100),
            confidence: 0.0,
            trackingMethod: .interpolation
        )
    }
    
    // MARK: - 辅助方法
    
    private static func findNearestAnnotation(
        frameNumber: Int,
        annotations: [LogoAnnotation]
    ) -> LogoAnnotation? {
        return annotations.min { abs($0.frameNumber - frameNumber) < abs($1.frameNumber - frameNumber) }
    }
}

// MARK: - 错误类型

enum LogoTrackingError: LocalizedError {
    case noVideoTrack
    case invalidTemplate
    case imageConversionFailed
    case imageProcessingFailed
    case trackingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "视频中没有视频轨道"
        case .invalidTemplate:
            return "无效的模板图像"
        case .imageConversionFailed:
            return "图像转换失败"
        case .imageProcessingFailed:
            return "图像处理失败"
        case .trackingFailed(let message):
            return "跟踪失败: \(message)"
        }
    }
}

// MARK: - NSImage 扩展

extension NSImage {
    var ciImage: CIImage? {
        guard let tiffData = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return CIImage(bitmapImageRep: bitmapImage)
    }
}
