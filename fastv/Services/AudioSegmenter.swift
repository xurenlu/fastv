//
//  AudioSegmenter.swift
//  fastv
//
//  Created by rocky on 2025/01/11.
//
//  音频分段服务：检测静音并将长音频分割成短片段进行处理
//

import Foundation
import Accelerate

/// VAD（语音活动检测）分割后的音频片段信息
struct VADSegment {
    /// 起始样本索引
    let startSample: Int
    /// 结束样本索引
    let endSample: Int
    /// 起始时间（秒）
    let startTime: TimeInterval
    /// 结束时间（秒）
    let endTime: TimeInterval
    /// 音频样本数据
    let samples: [Float]
    /// 片段索引
    let index: Int
    
    /// 片段时长（秒）
    var duration: TimeInterval {
        return endTime - startTime
    }
}

/// 静音区域信息
struct SilenceRegion {
    /// 起始样本索引
    let startSample: Int
    /// 结束样本索引
    let endSample: Int
    /// 起始时间（秒）
    let startTime: TimeInterval
    /// 结束时间（秒）
    let endTime: TimeInterval
    
    /// 静音时长（秒）
    var duration: TimeInterval {
        return endTime - startTime
    }
    
    /// 静音区域的中点样本索引（用于分割）
    var midpointSample: Int {
        return (startSample + endSample) / 2
    }
}

/// 分段配置
struct SegmentationConfig {
    /// 目标片段时长（秒）- 理想情况下在此时间附近分割
    var targetDuration: TimeInterval = 40
    
    /// 最大片段时长（秒）- 超过此长度强制分割
    var maxDuration: TimeInterval = 60
    
    /// 最小片段时长（秒）- 小于此长度不再分割
    var minDuration: TimeInterval = 10
    
    /// 静音检测的 RMS 阈值
    var silenceThreshold: Float = 0.01
    
    /// 最短静音时长（秒）- 低于此值不认为是静音
    var minSilenceDuration: TimeInterval = 0.3
    
    /// 分段重叠时长（秒）- 避免边界词被截断
    var overlapDuration: TimeInterval = 0.1
    
    /// 默认配置（用于视频转录等非实时场景）
    static let `default` = SegmentationConfig()
    
    /// 实时场景配置（会议记录、直播转录）
    /// 目标40秒，最长60秒，优先选择较长的静音段
    static let realtime = SegmentationConfig(
        targetDuration: 40,
        maxDuration: 60,
        minDuration: 10,
        silenceThreshold: 0.01,
        minSilenceDuration: 0.5,  // 实时场景需要更长的静音才分割
        overlapDuration: 0.1
    )
    
    /// 视频转录配置（较短片段，更快响应）
    static let videoTranscription = SegmentationConfig(
        targetDuration: 25,
        maxDuration: 40,
        minDuration: 8,
        silenceThreshold: 0.01,
        minSilenceDuration: 0.3,
        overlapDuration: 0.1
    )
}

/// 音频分段器
struct AudioSegmenter {
    
    // MARK: - 配置参数（保持向后兼容）
    
    /// 目标片段时长（秒）
    static let targetSegmentDuration: TimeInterval = 40
    
    /// 最大片段时长（秒）- 超过此长度强制分割
    static let maxSegmentDuration: TimeInterval = 60
    
    /// 最小片段时长（秒）- 小于此长度不再分割
    static let minSegmentDuration: TimeInterval = 10
    
    /// 静音检测的 RMS 阈值
    static let silenceThreshold: Float = 0.01
    
    /// 最短静音时长（秒）- 低于此值不认为是静音
    static let minSilenceDuration: TimeInterval = 0.3
    
    /// 分段重叠时长（秒）- 避免边界词被截断
    static let overlapDuration: TimeInterval = 0.1
    
    /// 静音检测窗口大小（秒）
    static let silenceWindowDuration: TimeInterval = 0.05  // 50ms
    
    /// 采样率
    static let sampleRate: Double = 16000
    
    // MARK: - 公共方法
    
    /// 判断音频是否需要分段处理
    /// - Parameter samples: 音频样本
    /// - Returns: 是否需要分段
    static func needsSegmentation(samples: [Float]) -> Bool {
        let duration = Double(samples.count) / sampleRate
        return duration > maxSegmentDuration
    }
    
    /// 判断音频是否需要分段处理（使用自定义配置）
    /// - Parameters:
    ///   - samples: 音频样本
    ///   - config: 分段配置
    /// - Returns: 是否需要分段
    static func needsSegmentation(samples: [Float], config: SegmentationConfig) -> Bool {
        let duration = Double(samples.count) / sampleRate
        return duration > config.maxDuration
    }
    
    /// 检测音频中的静音区域
    /// - Parameters:
    ///   - samples: 音频样本数据（归一化到 -1.0 ~ 1.0）
    ///   - sampleRate: 采样率
    /// - Returns: 静音区域列表
    static func detectSilenceRegions(samples: [Float], sampleRate: Double = sampleRate) -> [SilenceRegion] {
        return detectSilenceRegions(
            samples: samples,
            sampleRate: sampleRate,
            silenceThreshold: silenceThreshold,
            minSilenceDuration: minSilenceDuration
        )
    }
    
    /// 检测音频中的静音区域（可自定义参数）
    /// - Parameters:
    ///   - samples: 音频样本数据（归一化到 -1.0 ~ 1.0）
    ///   - sampleRate: 采样率
    ///   - silenceThreshold: 静音阈值
    ///   - minSilenceDuration: 最短静音时长
    /// - Returns: 静音区域列表
    static func detectSilenceRegions(
        samples: [Float],
        sampleRate: Double,
        silenceThreshold: Float,
        minSilenceDuration: TimeInterval
    ) -> [SilenceRegion] {
        guard !samples.isEmpty else { return [] }
        
        let windowSize = Int(silenceWindowDuration * sampleRate)
        guard windowSize > 0 else { return [] }
        
        var silenceRegions: [SilenceRegion] = []
        var currentSilenceStart: Int? = nil
        
        // 使用滑动窗口计算 RMS
        var offset = 0
        while offset + windowSize <= samples.count {
            let windowEnd = min(offset + windowSize, samples.count)
            let window = Array(samples[offset..<windowEnd])
            
            // 计算 RMS
            let rms = calculateRMS(window)
            
            if rms < silenceThreshold {
                // 当前窗口是静音
                if currentSilenceStart == nil {
                    currentSilenceStart = offset
                }
            } else {
                // 当前窗口不是静音
                if let start = currentSilenceStart {
                    let silenceEndSample = offset
                    let startTime = Double(start) / sampleRate
                    let endTime = Double(silenceEndSample) / sampleRate
                    let duration = endTime - startTime
                    
                    // 只记录足够长的静音段
                    if duration >= minSilenceDuration {
                        silenceRegions.append(SilenceRegion(
                            startSample: start,
                            endSample: silenceEndSample,
                            startTime: startTime,
                            endTime: endTime
                        ))
                    }
                    currentSilenceStart = nil
                }
            }
            
            offset += windowSize
        }
        
        // 处理末尾的静音
        if let start = currentSilenceStart {
            let silenceEndSample = samples.count
            let startTime = Double(start) / sampleRate
            let endTime = Double(silenceEndSample) / sampleRate
            let duration = endTime - startTime
            
            if duration >= minSilenceDuration {
                silenceRegions.append(SilenceRegion(
                    startSample: start,
                    endSample: silenceEndSample,
                    startTime: startTime,
                    endTime: endTime
                ))
            }
        }
        
        #if DEBUG
        print("🔇 检测到 \(silenceRegions.count) 个静音区域")
        for (index, region) in silenceRegions.prefix(10).enumerated() {
            print("  静音[\(index)]: \(String(format: "%.2f", region.startTime))s - \(String(format: "%.2f", region.endTime))s (时长: \(String(format: "%.2f", region.duration))s)")
        }
        if silenceRegions.count > 10 {
            print("  ... 还有 \(silenceRegions.count - 10) 个静音区域")
        }
        #endif
        
        return silenceRegions
    }
    
    /// 将音频分割成多个片段（使用默认配置）
    /// - Parameters:
    ///   - samples: 音频样本数据
    ///   - sampleRate: 采样率
    /// - Returns: 音频片段列表
    static func segmentAudio(samples: [Float], sampleRate: Double = sampleRate) -> [VADSegment] {
        return segmentAudio(samples: samples, sampleRate: sampleRate, config: .default)
    }
    
    /// 将音频分割成多个片段（使用自定义配置）
    /// - Parameters:
    ///   - samples: 音频样本数据
    ///   - sampleRate: 采样率
    ///   - config: 分段配置
    /// - Returns: 音频片段列表
    static func segmentAudio(samples: [Float], sampleRate: Double = sampleRate, config: SegmentationConfig) -> [VADSegment] {
        let totalDuration = Double(samples.count) / sampleRate
        
        // 如果音频很短，不需要分段
        if totalDuration <= config.maxDuration {
            #if DEBUG
            print("📊 音频时长 \(String(format: "%.2f", totalDuration))s，无需分段")
            #endif
            return [VADSegment(
                startSample: 0,
                endSample: samples.count,
                startTime: 0,
                endTime: totalDuration,
                samples: samples,
                index: 0
            )]
        }
        
        // 检测静音区域（使用配置的阈值）
        let silenceRegions = detectSilenceRegions(
            samples: samples,
            sampleRate: sampleRate,
            silenceThreshold: config.silenceThreshold,
            minSilenceDuration: config.minSilenceDuration
        )
        
        // 分段
        var segments: [VADSegment] = []
        var currentStart = 0
        var segmentIndex = 0
        
        while currentStart < samples.count {
            let currentStartTime = Double(currentStart) / sampleRate
            let targetEndTime = currentStartTime + config.targetDuration
            let maxEndTime = currentStartTime + config.maxDuration
            
            // 如果剩余音频不足最小片段时长，合并到上一个片段
            let remainingDuration = totalDuration - currentStartTime
            if remainingDuration <= config.minDuration && !segments.isEmpty {
                // 修改最后一个片段，扩展到末尾
                let lastSegment = segments.removeLast()
                let extendedSamples = Array(samples[lastSegment.startSample..<samples.count])
                segments.append(VADSegment(
                    startSample: lastSegment.startSample,
                    endSample: samples.count,
                    startTime: lastSegment.startTime,
                    endTime: totalDuration,
                    samples: extendedSamples,
                    index: lastSegment.index
                ))
                break
            }
            
            // 在目标时间附近寻找最佳静音点
            // 策略：优先选择更长的静音段，同时尽量让片段更长（接近 maxDuration）
            var bestSplitSample: Int? = nil
            var bestSilenceScore: Double = 0
            
            for region in silenceRegions {
                let silenceMidTime = (region.startTime + region.endTime) / 2
                
                // 只考虑在最小片段时长和最大时间之间的静音点
                if silenceMidTime > currentStartTime + config.minDuration && silenceMidTime <= maxEndTime {
                    // 计算分数：
                    // 1. 静音越长越好（权重 50%）
                    // 2. 片段越长越好（越接近 maxDuration 越好）（权重 30%）
                    // 3. 如果超过目标时长，优先选择（权重 20%）
                    
                    let silenceDurationScore = min(region.duration / 2.0, 1.0)  // 2秒静音给满分
                    
                    let segmentLength = silenceMidTime - currentStartTime
                    let lengthScore = segmentLength / config.maxDuration  // 越接近 maxDuration 越好
                    
                    let beyondTargetBonus: Double = silenceMidTime > targetEndTime ? 0.2 : 0.0
                    
                    let score = silenceDurationScore * 0.5 + lengthScore * 0.3 + beyondTargetBonus
                    
                    if score > bestSilenceScore {
                        bestSilenceScore = score
                        bestSplitSample = region.midpointSample
                    }
                }
            }
            
            // 确定分割点
            let splitSample: Int
            if let best = bestSplitSample {
                splitSample = best
            } else {
                // 没有找到合适的静音点，强制在最大时长处分割
                splitSample = min(currentStart + Int(config.maxDuration * sampleRate), samples.count)
                #if DEBUG
                print("⚠️ 未找到合适静音点，在 \(String(format: "%.2f", Double(splitSample) / sampleRate))s 处强制分割")
                #endif
            }
            
            // 创建片段
            let segmentSamples = Array(samples[currentStart..<splitSample])
            let startTime = Double(currentStart) / sampleRate
            let endTime = Double(splitSample) / sampleRate
            
            segments.append(VADSegment(
                startSample: currentStart,
                endSample: splitSample,
                startTime: startTime,
                endTime: endTime,
                samples: segmentSamples,
                index: segmentIndex
            ))
            
            segmentIndex += 1
            
            // 下一个片段的起点（有重叠）
            let overlapSamples = Int(config.overlapDuration * sampleRate)
            currentStart = max(splitSample - overlapSamples, splitSample)
            
            // 如果已经到达末尾
            if currentStart >= samples.count {
                break
            }
        }
        
        #if DEBUG
        print("📊 音频分段完成: 总时长 \(String(format: "%.2f", totalDuration))s，分成 \(segments.count) 个片段")
        for segment in segments {
            print("  片段[\(segment.index)]: \(String(format: "%.2f", segment.startTime))s - \(String(format: "%.2f", segment.endTime))s (时长: \(String(format: "%.2f", segment.duration))s)")
        }
        #endif
        
        return segments
    }
    
    // MARK: - 私有方法
    
    /// 计算 RMS（均方根）
    private static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        
        var sumOfSquares: Float = 0
        vDSP_svesq(samples, 1, &sumOfSquares, vDSP_Length(samples.count))
        return sqrt(sumOfSquares / Float(samples.count))
    }
}
