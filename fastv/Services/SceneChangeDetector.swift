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
    ///   - onDetectedPoint: 检测到关键帧时的实时回调（可选）
    /// - Returns: 变更点列表（包含截图）
    static func detectSceneChanges(
        from videoURL: URL,
        frameRate: Float? = nil,
        threshold: Double = 0.3,
        extractThumbnails: Bool = true,
        analysisInterval: Double? = nil,
        frameSkip: Int? = nil,
        progressHandler: @escaping (Double, String) -> Void,
        onDetectedPoint: ((SceneChangePoint) -> Void)? = nil
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
        var skippedFrames = 0  // 记录跳过的帧数
        var failedFrames = 0   // 记录失败的帧数
        
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
            
            // 显示跳过帧的统计信息
            let skipInfo = failedFrames > 0 ? " (已跳过 \(failedFrames) 个无法提取的帧)" : ""
            progressHandler(progress, "正在分析... \(i + 1)/\(totalSamples) (时间: \(String(format: "%.1f", timestamp))秒, 每\(skipFrames)帧分析一次)\(skipInfo)")
            
            // 提取帧 - 添加错误处理，避免单个帧失败导致整个分析停止
            var cgImage: CGImage?
            do {
                cgImage = try await imageGenerator.image(at: clampedTime).image
            } catch {
                // 如果提取帧失败，记录错误并跳过该帧
                print("⚠️ [SceneChangeDetector] 无法提取第 \(i + 1) 帧 (时间: \(String(format: "%.1f", timestamp))秒): \(error.localizedDescription)")
                failedFrames += 1
                // 跳过该帧，继续分析下一帧
                continue
            }
            
            guard let cgImage = cgImage else {
                failedFrames += 1
                continue
            }
            
            // 转换为灰度图并计算直方图 - 添加错误处理
            var histogram: [Float]?
            do {
                histogram = try computeHistogram(from: cgImage, context: context)
            } catch {
                // 如果计算直方图失败，记录错误并跳过该帧
                print("⚠️ [SceneChangeDetector] 无法计算第 \(i + 1) 帧的直方图 (时间: \(String(format: "%.1f", timestamp))秒): \(error.localizedDescription)")
                failedFrames += 1
                // 跳过该帧，继续分析下一帧
                continue
            }
            
            guard let histogram = histogram else {
                failedFrames += 1
                continue
            }
            
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
                    
                    // 实时回调，通知检测到关键帧
                    onDetectedPoint?(changePoint)
                }
            }
            
            previousHistogram = histogram
            sampleIndex += 1
        }
        
        // 完成信息，包含统计
        var completionMessage = "检测完成，发现 \(changePoints.count) 个变更点"
        if failedFrames > 0 {
            completionMessage += "（跳过了 \(failedFrames) 个无法处理的帧）"
        }
        progressHandler(1.0, completionMessage)
        
        print("✅ [SceneChangeDetector] 分析完成: 总样本数=\(totalSamples), 成功=\(sampleIndex), 失败=\(failedFrames), 变更点=\(changePoints.count)")
        
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
    
    /// 两阶段智能检测：先粗扫描找候选节点，再精细定位关键帧
    /// - Parameters:
    ///   - videoURL: 视频文件URL
    ///   - frameRate: 视频帧率（如果为nil，则从视频中获取）
    ///   - threshold: 变更阈值（0-1，默认0.3）
    ///   - extractThumbnails: 是否提取关键点的截图（默认true）
    ///   - coarseInterval: 粗扫描间隔（秒，默认3.9秒）
    ///   - fineRangeBefore: 精细检测范围：候选节点前多少秒（默认15秒）
    ///   - fineRangeAfter: 精细检测范围：候选节点后多少秒（默认10秒）
    ///   - fineInterval: 精细检测间隔（秒，默认1.1秒）
    ///   - progressHandler: 进度回调
    ///   - onDetectedPoint: 检测到关键帧时的实时回调（可选）
    /// - Returns: 精确的关键帧列表
    static func detectSceneChangesTwoStage(
        from videoURL: URL,
        frameRate: Float? = nil,
        threshold: Double = 0.3,
        extractThumbnails: Bool = true,
        coarseInterval: Double = 3.9,
        fineRangeBefore: Double = 15.0,
        fineRangeAfter: Double = 10.0,
        fineInterval: Double = 1.1,
        progressHandler: @escaping (Double, String) -> Void,
        onDetectedPoint: ((SceneChangePoint) -> Void)? = nil
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
        
        let context = CIContext()
        var finalChangePoints: [SceneChangePoint] = []
        
        // ========== 第一阶段：粗扫描（10-15秒间隔）==========
        progressHandler(0.0, "第一阶段：快速扫描视频（每\(coarseInterval)秒检测一次）...")
        
        var candidateTimes: [TimeInterval] = []
        var previousHistogram: [Float]?
        let coarseSamples = Int(durationSeconds / coarseInterval) + 1
        
        for i in 0..<coarseSamples {
            let time = Double(i) * coarseInterval
            let clampedTime = min(time, durationSeconds)
            let timePoint = CMTime(seconds: clampedTime, preferredTimescale: 600)
            
            let progress = Double(i) / Double(coarseSamples) * 0.4  // 第一阶段占40%进度
            progressHandler(progress, "第一阶段：扫描 \(i + 1)/\(coarseSamples) (时间: \(String(format: "%.1f", clampedTime))秒)")
            
            // 提取帧
            guard let cgImage = try? await imageGenerator.image(at: timePoint).image else {
                continue
            }
            
            // 计算直方图
            guard let histogram = try? computeHistogram(from: cgImage, context: context) else {
                continue
            }
            
            // 与上一帧比较
            if let prevHist = previousHistogram {
                let difference = computeHistogramDifference(histogram, prevHist)
                
                // 如果差异超过阈值，记录为候选节点
                if difference >= threshold {
                    candidateTimes.append(clampedTime)
                    print("📍 [SceneChangeDetector] 第一阶段发现候选节点: \(String(format: "%.1f", clampedTime))秒 (差异: \(String(format: "%.1f%%", difference * 100)))")
                }
            }
            
            previousHistogram = histogram
        }
        
        progressHandler(0.4, "第一阶段完成，发现 \(candidateTimes.count) 个候选节点，开始精细定位...")
        
        // ========== 第二阶段：精细定位（在候选节点前后精细检测）==========
        let totalCandidates = candidateTimes.count
        guard totalCandidates > 0 else {
            progressHandler(1.0, "未发现关键帧")
            return []
        }
        
        for (index, candidateTime) in candidateTimes.enumerated() {
            let progress = 0.4 + (Double(index) / Double(totalCandidates)) * 0.6  // 第二阶段占60%进度
            progressHandler(progress, "第二阶段：精细定位 \(index + 1)/\(totalCandidates) (候选节点: \(String(format: "%.1f", candidateTime))秒)")
            
            // 计算精细检测的时间范围
            let fineStartTime = max(0, candidateTime - fineRangeBefore)
            let fineEndTime = min(durationSeconds, candidateTime + fineRangeAfter)
            let fineDuration = fineEndTime - fineStartTime
            let fineSamples = Int(fineDuration / fineInterval) + 1
            
            var bestPoint: SceneChangePoint?
            var maxDifference: Double = 0
            var previousFineHistogram: [Float]?
            
            // 在候选节点前后范围内进行精细检测
            for j in 0..<fineSamples {
                let fineTime = fineStartTime + Double(j) * fineInterval
                let clampedFineTime = min(fineTime, fineEndTime)
                let fineTimePoint = CMTime(seconds: clampedFineTime, preferredTimescale: 600)
                
                // 提取帧
                guard let cgImage = try? await imageGenerator.image(at: fineTimePoint).image else {
                    continue
                }
                
                // 计算直方图
                guard let histogram = try? computeHistogram(from: cgImage, context: context) else {
                    continue
                }
                
                // 与上一帧比较
                if let prevHist = previousFineHistogram {
                    let difference = computeHistogramDifference(histogram, prevHist)
                    
                    // 记录差异最大的点作为精确关键帧
                    if difference > maxDifference {
                        maxDifference = difference
                        
                        // 提取该帧的截图（如果需要）
                        var thumbnailImage: NSImage? = nil
                        if extractThumbnails {
                            thumbnailImage = NSImage(cgImage: cgImage, size: .zero)
                        }
                        
                        let actualFrameNumber = Int(clampedFineTime * Double(actualFrameRate))
                        
                        bestPoint = SceneChangePoint(
                            timestamp: clampedFineTime,
                            frameNumber: actualFrameNumber,
                            changeIntensity: min(difference, 1.0),
                            description: String(format: "第%.1f秒：画面大幅变更（差异%.1f%%）", clampedFineTime, difference * 100),
                            thumbnailImage: thumbnailImage
                        )
                    }
                }
                
                previousFineHistogram = histogram
            }
            
            // 如果找到了精确的关键帧，添加到结果列表
            if let point = bestPoint, maxDifference >= threshold {
                // 检查是否已存在时间相近的关键帧（去重：如果时间差小于2秒，认为是同一个关键帧）
                let isDuplicate = finalChangePoints.contains { existingPoint in
                    abs(existingPoint.timestamp - point.timestamp) < 2.0
                }
                
                if !isDuplicate {
                    finalChangePoints.append(point)
                    onDetectedPoint?(point)
                    print("✅ [SceneChangeDetector] 第二阶段精确定位: \(String(format: "%.1f", point.timestamp))秒 (差异: \(String(format: "%.1f%%", point.changeIntensity * 100)))")
                } else {
                    print("⚠️ [SceneChangeDetector] 跳过重复关键帧: \(String(format: "%.1f", point.timestamp))秒")
                }
            }
        }
        
        // 最终去重：按时间戳排序，并移除时间差小于2秒的重复项
        var deduplicatedPoints: [SceneChangePoint] = []
        let sortedPoints = finalChangePoints.sorted { $0.timestamp < $1.timestamp }
        
        for point in sortedPoints {
            if deduplicatedPoints.isEmpty {
                deduplicatedPoints.append(point)
            } else {
                let lastPoint = deduplicatedPoints.last!
                // 如果与上一个关键帧的时间差大于等于2秒，才添加
                if point.timestamp - lastPoint.timestamp >= 2.0 {
                    deduplicatedPoints.append(point)
                } else {
                    // 如果时间差小于2秒，保留差异度更大的那个
                    if point.changeIntensity > lastPoint.changeIntensity {
                        deduplicatedPoints[deduplicatedPoints.count - 1] = point
                    }
                }
            }
        }
        
        progressHandler(1.0, "检测完成，发现 \(deduplicatedPoints.count) 个关键帧")
        
        return deduplicatedPoints
    }
}

