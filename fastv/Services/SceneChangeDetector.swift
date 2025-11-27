//
//  SceneChangeDetector.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AVFoundation
import AppKit
import CoreImage

struct SceneChangeDetector {
    /// 检测视频画面变更点（支持时间间隔或帧数间隔）
    /// - Parameters:
    ///   - videoURL: 视频文件URL
    ///   - frameRate: 视频帧率（如果为nil，则从视频中获取）
    ///   - threshold: 变更阈值（0-1，默认0.3，即30%差异）
    ///   - extractThumbnails: 是否提取关键点的截图（默认true）
    ///   - analysisInterval: 分析时间间隔（秒，如果为nil且frameSkip也为nil，则使用默认0.1秒）
    ///   - frameSkip: 跳帧数（每N帧分析一次，如果设置则优先使用此参数）
    ///   - progressHandler: 进度回调
    /// - Returns: 变更点列表（包含截图）
    static func detectSceneChanges(
        from videoURL: URL,
        frameRate: Float? = nil,
        threshold: Double = 0.3,
        extractThumbnails: Bool = true,
        analysisInterval: Double? = nil,
        frameSkip: Int? = nil,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> [SceneChangePoint] {
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
            // 从视频轨道获取帧率
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if let videoTrack = videoTracks.first {
                actualFrameRate = try await videoTrack.load(.nominalFrameRate)
            } else {
                throw VideoProcessingError.noVideoTrack
            }
        }
        
        guard actualFrameRate > 0 else {
            throw VideoProcessingError.invalidVideoFile
        }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        // 计算需要分析的帧数和间隔
        let totalFrames = Int(durationSeconds * Double(actualFrameRate)) + 1
        let skipFrames: Int
        let totalSamples: Int
        
        if let frameSkip = frameSkip, frameSkip > 0 {
            // 使用帧数间隔
            skipFrames = frameSkip
            totalSamples = totalFrames / skipFrames + (totalFrames % skipFrames > 0 ? 1 : 0)
        } else {
            // 使用时间间隔
            let interval = analysisInterval ?? 0.1  // 默认0.1秒
            skipFrames = max(1, Int(Double(actualFrameRate) * interval))
            totalSamples = Int(durationSeconds / interval) + 1
        }
        
        var changePoints: [SceneChangePoint] = []
        var previousHistogram: [Float]?
        var sampleIndex = 0
        
        // 使用CoreImage进行图像处理
        let context = CIContext()
        
        for i in 0..<totalSamples {
            // 计算当前分析的帧号
            let frameIndex = i * skipFrames
            let time = Double(frameIndex) / Double(actualFrameRate)
            let timePoint = CMTime(seconds: time, preferredTimescale: 600)
            let clampedTime = CMTimeClampToRange(timePoint, range: CMTimeRange(start: .zero, duration: duration))
            
            // 更新进度
            let progress = Double(i) / Double(totalSamples)
            let timestamp = CMTimeGetSeconds(clampedTime)
            progressHandler(progress, "正在分析... \(i + 1)/\(totalSamples) (时间: \(String(format: "%.1f", timestamp))秒, 每\(skipFrames)帧分析一次)")
            
            // 提取帧
            let cgImage = try await imageGenerator.image(at: clampedTime).image
            
            // 转换为灰度图并计算直方图
            let histogram = try computeHistogram(from: cgImage, context: context)
            
            // 与上一帧比较
            if let prevHist = previousHistogram {
                let difference = computeHistogramDifference(histogram, prevHist)
                
                // 如果差异超过阈值，记录为变更点
                if difference >= threshold {
                    // 提取该帧的截图（如果需要）
                    var thumbnailImage: NSImage? = nil
                    if extractThumbnails {
                        thumbnailImage = NSImage(cgImage: cgImage, size: .zero)
                    }
                    
                    // 计算实际帧号（基于时间戳和帧率）
                    let actualFrameNumber = Int(timestamp * Double(actualFrameRate))
                    
                    let changePoint = SceneChangePoint(
                        timestamp: timestamp,
                        frameNumber: actualFrameNumber,
                        changeIntensity: min(difference, 1.0),
                        description: String(format: "第%.1f秒：画面大幅变更（差异%.1f%%）", timestamp, difference * 100),
                        thumbnailImage: thumbnailImage
                    )
                    changePoints.append(changePoint)
                }
            }
            
            previousHistogram = histogram
            sampleIndex += 1
        }
        
        progressHandler(1.0, "检测完成，发现 \(changePoints.count) 个变更点")
        
        return changePoints
    }
    
    /// 计算图像的直方图（用于比较）
    private static func computeHistogram(from cgImage: CGImage, context: CIContext) throws -> [Float] {
        // 创建CIImage
        let ciImage = CIImage(cgImage: cgImage)
        
        // 缩放图像以提高性能（缩放到较小尺寸）
        let scale = 0.25 // 缩放到25%大小
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // 转换为灰度图
        // 使用CIColorMonochrome转换为灰度
        guard let monochromeFilter = CIFilter(name: "CIColorMonochrome") else {
            throw VideoProcessingError.unknown(NSError(domain: "SceneChangeDetector", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法创建单色滤镜"]))
        }
        monochromeFilter.setValue(scaledImage, forKey: kCIInputImageKey)
        monochromeFilter.setValue(CIColor.gray, forKey: kCIInputColorKey)
        monochromeFilter.setValue(1.0, forKey: kCIInputIntensityKey)
        
        guard let grayImage = monochromeFilter.outputImage else {
            throw VideoProcessingError.unknown(NSError(domain: "SceneChangeDetector", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法生成灰度图"]))
        }
        
        // 计算直方图（使用简化方法：将图像分成网格，计算每个网格的平均亮度）
        let gridSize = 8 // 8x8网格
        var histogram: [Float] = []
        
        guard let cgGrayImage = context.createCGImage(grayImage, from: grayImage.extent) else {
            throw VideoProcessingError.unknown(NSError(domain: "SceneChangeDetector", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法创建CGImage"]))
        }
        
        let width = cgGrayImage.width
        let height = cgGrayImage.height
        let cellWidth = width / gridSize
        let cellHeight = height / gridSize
        
        // 获取像素数据
        guard let dataProvider = cgGrayImage.dataProvider,
              let pixelData = dataProvider.data else {
            throw VideoProcessingError.unknown(NSError(domain: "SceneChangeDetector", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取像素数据"]))
        }
        
        let data = CFDataGetBytePtr(pixelData)
        let bytesPerRow = cgGrayImage.bytesPerRow
        let bitsPerComponent = cgGrayImage.bitsPerComponent
        let components = cgGrayImage.bitsPerPixel / bitsPerComponent
        
        // 计算每个网格的平均亮度
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                var sum: Float = 0
                var count = 0
                
                let startX = col * cellWidth
                let startY = row * cellHeight
                let endX = min(startX + cellWidth, width)
                let endY = min(startY + cellHeight, height)
                
                for y in startY..<endY {
                    for x in startX..<endX {
                        if let pixel = data {
                            let offset = y * bytesPerRow + x * components
                            if offset < CFDataGetLength(pixelData) {
                                // 假设是灰度图，只取第一个通道
                                let gray = Float(pixel[offset]) / 255.0
                                sum += gray
                                count += 1
                            }
                        }
                    }
                }
                
                let avg = count > 0 ? sum / Float(count) : 0
                histogram.append(avg)
            }
        }
        
        return histogram
    }
    
    /// 计算两个直方图的差异
    private static func computeHistogramDifference(_ hist1: [Float], _ hist2: [Float]) -> Double {
        guard hist1.count == hist2.count else {
            return 1.0 // 如果长度不同，认为完全不同
        }
        
        var totalDifference: Float = 0
        for i in 0..<hist1.count {
            let diff = abs(hist1[i] - hist2[i])
            totalDifference += diff
        }
        
        // 归一化到0-1范围
        return Double(totalDifference / Float(hist1.count))
    }
}

