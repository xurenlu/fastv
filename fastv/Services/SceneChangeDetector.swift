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
    /// 检测视频画面变更点
    /// - Parameters:
    ///   - videoURL: 视频文件URL
    ///   - sampleRate: 采样率（每秒采样帧数，默认1帧/秒）
    ///   - threshold: 变更阈值（0-1，默认0.3，即30%差异）
    ///   - progressHandler: 进度回调
    /// - Returns: 变更点列表
    static func detectSceneChanges(
        from videoURL: URL,
        sampleRate: Double = 1.0,
        threshold: Double = 0.3,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> [SceneChangePoint] {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        guard durationSeconds > 0 else {
            throw VideoProcessingError.invalidVideoFile
        }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        // 计算采样间隔
        let sampleInterval = 1.0 / sampleRate
        let totalSamples = Int(durationSeconds * sampleRate) + 1
        
        var changePoints: [SceneChangePoint] = []
        var previousHistogram: [Float]?
        var frameNumber = 0
        
        // 使用CoreImage进行图像处理
        let context = CIContext()
        
        for i in 0..<totalSamples {
            let time = CMTime(seconds: Double(i) * sampleInterval, preferredTimescale: 600)
            let clampedTime = CMTimeClampToRange(time, range: CMTimeRange(start: .zero, duration: duration))
            
            // 更新进度
            let progress = Double(i) / Double(totalSamples)
            progressHandler(progress, "正在检测画面变更... \(i + 1)/\(totalSamples)")
            
            // 提取帧
            let cgImage = try await imageGenerator.image(at: clampedTime).image
            
            // 转换为灰度图并计算直方图
            let histogram = try computeHistogram(from: cgImage, context: context)
            
            // 与上一帧比较
            if let prevHist = previousHistogram {
                let difference = computeHistogramDifference(histogram, prevHist)
                
                // 如果差异超过阈值，记录为变更点
                if difference >= threshold {
                    let timestamp = CMTimeGetSeconds(clampedTime)
                    let changePoint = SceneChangePoint(
                        timestamp: timestamp,
                        frameNumber: frameNumber,
                        changeIntensity: min(difference, 1.0),
                        description: String(format: "第%.1f秒：画面大幅变更（差异%.1f%%）", timestamp, difference * 100)
                    )
                    changePoints.append(changePoint)
                }
            }
            
            previousHistogram = histogram
            frameNumber += 1
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

