//
//  VideoCompressionCalculator.swift
//  fastv
//
//  Created by rocky on 2025/12/25.
//

import Foundation
import CoreGraphics

/// 文件大小单位
enum FileSizeUnit: String, CaseIterable {
    case mb = "MB"
    case gb = "GB"
    
    var bytesMultiplier: Int64 {
        switch self {
        case .mb: return 1_000_000
        case .gb: return 1_000_000_000
        }
    }
}

/// 画质评级
enum QualityRating: String {
    case excellent = "优秀"
    case good = "良好"
    case fair = "一般"
    case poor = "较差"
    case veryPoor = "很差"
    
    var stars: String {
        switch self {
        case .excellent: return "★★★★★"
        case .good: return "★★★★☆"
        case .fair: return "★★★☆☆"
        case .poor: return "★★☆☆☆"
        case .veryPoor: return "★☆☆☆☆"
        }
    }
}

/// 压缩推荐参数
struct CompressionRecommendation {
    let targetBitrateMbps: Double
    let recommendedResolution: VideoResolution
    let recommendedFrameRate: Int?
    let recommendedCRF: Int?
    let compressionRatio: Double
    let qualityRating: QualityRating
    let estimatedFileSize: Int64
    
    var bitrateString: String {
        return String(format: "%.1f Mbps", targetBitrateMbps)
    }
    
    var compressionRatioString: String {
        return String(format: "%.0f%%", compressionRatio * 100)
    }
}

/// 视频压缩参数计算器
struct VideoCompressionCalculator {
    
    // 默认音频码率 (bps)
    private static let defaultAudioBitrate: Int64 = 192_000 // 192 kbps
    
    /// 根据目标文件大小计算推荐的压缩参数
    /// - Parameters:
    ///   - targetFileSize: 目标文件大小（字节）
    ///   - videoInfo: 原视频信息
    /// - Returns: 压缩推荐参数
    static func calculateRecommendation(
        targetFileSize: Int64,
        videoInfo: VideoInfo
    ) -> CompressionRecommendation {
        // 计算目标视频码率 (bps)
        let targetVideoBitrate = calculateTargetBitrate(
            targetFileSize: targetFileSize,
            duration: videoInfo.duration,
            audioBitrate: defaultAudioBitrate
        )
        
        // 转换为 Mbps
        let targetBitrateMbps = Double(targetVideoBitrate) / 1_000_000.0
        
        // 推荐分辨率
        let recommendedResolution = recommendResolution(
            originalResolution: videoInfo.resolution,
            targetBitrate: targetVideoBitrate
        )
        
        // 推荐帧率
        let recommendedFrameRate = recommendFrameRate(
            originalFrameRate: videoInfo.frameRate,
            targetBitrate: targetVideoBitrate,
            resolution: recommendedResolution
        )
        
        // 推荐 CRF（如果用户选择质量优先模式）
        let recommendedCRF = recommendCRF(targetBitrate: targetVideoBitrate)
        
        // 计算压缩比
        let compressionRatio = Double(targetFileSize) / Double(videoInfo.fileSize)
        
        // 评估画质
        let qualityRating = evaluateQuality(
            originalResolution: videoInfo.resolution,
            targetResolution: recommendedResolution,
            compressionRatio: compressionRatio,
            targetBitrate: targetVideoBitrate
        )
        
        return CompressionRecommendation(
            targetBitrateMbps: targetBitrateMbps,
            recommendedResolution: recommendedResolution,
            recommendedFrameRate: recommendedFrameRate,
            recommendedCRF: recommendedCRF,
            compressionRatio: compressionRatio,
            qualityRating: qualityRating,
            estimatedFileSize: targetFileSize
        )
    }
    
    /// 计算目标视频码率
    /// - Parameters:
    ///   - targetFileSize: 目标文件大小（字节）
    ///   - duration: 视频时长（秒）
    ///   - audioBitrate: 音频码率（bps）
    /// - Returns: 目标视频码率（bps）
    static func calculateTargetBitrate(
        targetFileSize: Int64,
        duration: TimeInterval,
        audioBitrate: Int64
    ) -> Int64 {
        // 公式: 目标视频码率 = (目标文件大小 × 8 / 视频时长) - 音频码率
        let totalBitrate = Int64(Double(targetFileSize * 8) / duration)
        let videoBitrate = totalBitrate - audioBitrate
        
        // 确保视频码率不为负数
        return max(videoBitrate, 100_000) // 最小 100 kbps
    }
    
    /// 根据目标码率推荐分辨率
    /// - Parameters:
    ///   - originalResolution: 原始分辨率
    ///   - targetBitrate: 目标码率（bps）
    /// - Returns: 推荐的分辨率
    static func recommendResolution(
        originalResolution: CGSize,
        targetBitrate: Int64
    ) -> VideoResolution {
        let bitrateMbps = Double(targetBitrate) / 1_000_000.0
        
        // 根据码率推荐分辨率的经验值
        // 4K: 至少 20 Mbps
        // 1080p: 至少 5 Mbps
        // 720p: 至少 2.5 Mbps
        // 480p: 至少 1 Mbps
        // 360p: 0.5 Mbps 以上
        
        let originalPixels = originalResolution.width * originalResolution.height
        
        if bitrateMbps >= 20 && originalPixels >= 3840 * 2160 {
            return .uhd4k
        } else if bitrateMbps >= 5 && originalPixels >= 1920 * 1080 {
            return .fhd1080p
        } else if bitrateMbps >= 2.5 && originalPixels >= 1280 * 720 {
            return .hd720p
        } else if bitrateMbps >= 1.0 && originalPixels >= 854 * 480 {
            return .sd480p
        } else {
            return .sd360p
        }
    }
    
    /// 根据目标码率推荐帧率
    /// - Parameters:
    ///   - originalFrameRate: 原始帧率
    ///   - targetBitrate: 目标码率（bps）
    ///   - resolution: 目标分辨率
    /// - Returns: 推荐的帧率（nil 表示保持原帧率）
    static func recommendFrameRate(
        originalFrameRate: Float,
        targetBitrate: Int64,
        resolution: VideoResolution
    ) -> Int? {
        let bitrateMbps = Double(targetBitrate) / 1_000_000.0
        
        // 如果原帧率已经较低（≤30fps），保持原帧率
        if originalFrameRate <= 30 {
            return nil
        }
        
        // 根据码率和分辨率决定是否降低帧率
        switch resolution {
        case .uhd4k:
            // 4K 视频，如果码率低于 15 Mbps，建议降到 30fps
            if bitrateMbps < 15 {
                return 30
            }
        case .fhd1080p:
            // 1080p 视频，如果码率低于 4 Mbps，建议降到 30fps
            if bitrateMbps < 4 {
                return 30
            }
        case .hd720p:
            // 720p 视频，如果码率低于 2 Mbps，建议降到 24fps
            if bitrateMbps < 2 {
                return 24
            }
        case .sd480p, .sd360p:
            // 低分辨率视频，建议降到 24fps
            return 24
        case .original:
            break
        }
        
        return nil // 保持原帧率
    }
    
    /// 推荐 CRF 值
    /// - Parameter targetBitrate: 目标码率（bps）
    /// - Returns: 推荐的 CRF 值
    static func recommendCRF(targetBitrate: Int64) -> Int {
        let bitrateMbps = Double(targetBitrate) / 1_000_000.0
        
        // CRF 值越小，质量越高，文件越大
        // 根据目标码率推荐合适的 CRF 值
        if bitrateMbps >= 10 {
            return 20 // 高质量
        } else if bitrateMbps >= 5 {
            return 23 // 良好质量
        } else if bitrateMbps >= 2 {
            return 26 // 一般质量
        } else {
            return 28 // 较低质量
        }
    }
    
    /// 评估压缩后的画质
    /// - Parameters:
    ///   - originalResolution: 原始分辨率
    ///   - targetResolution: 目标分辨率
    ///   - compressionRatio: 压缩比
    ///   - targetBitrate: 目标码率（bps）
    /// - Returns: 画质评级
    static func evaluateQuality(
        originalResolution: CGSize,
        targetResolution: VideoResolution,
        compressionRatio: Double,
        targetBitrate: Int64
    ) -> QualityRating {
        let bitrateMbps = Double(targetBitrate) / 1_000_000.0
        
        // 计算分辨率降低比例
        let originalPixels = originalResolution.width * originalResolution.height
        let targetPixels: CGFloat
        if let width = targetResolution.width, let height = targetResolution.height {
            targetPixels = CGFloat(width * height)
        } else {
            targetPixels = originalPixels
        }
        let resolutionRatio = targetPixels / originalPixels
        
        // 综合评估
        // 1. 如果分辨率保持较高且码率充足
        if resolutionRatio >= 0.9 && bitrateMbps >= 5 {
            return .excellent
        }
        
        // 2. 如果分辨率适中且码率合理
        if resolutionRatio >= 0.5 && bitrateMbps >= 2.5 {
            return .good
        }
        
        // 3. 如果压缩比适中
        if compressionRatio >= 0.3 && bitrateMbps >= 1.5 {
            return .fair
        }
        
        // 4. 如果压缩比较大或码率较低
        if compressionRatio >= 0.15 || bitrateMbps >= 0.8 {
            return .poor
        }
        
        // 5. 其他情况
        return .veryPoor
    }
    
    /// 根据码率估算文件大小
    /// - Parameters:
    ///   - videoBitrate: 视频码率（bps）
    ///   - audioBitrate: 音频码率（bps）
    ///   - duration: 视频时长（秒）
    /// - Returns: 估算的文件大小（字节）
    static func estimateFileSize(
        videoBitrate: Int64,
        audioBitrate: Int64,
        duration: TimeInterval
    ) -> Int64 {
        let totalBitrate = videoBitrate + audioBitrate
        return Int64(Double(totalBitrate) * duration / 8.0)
    }
}

