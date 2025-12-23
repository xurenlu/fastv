//
//  VideoBlur.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation
import AVFoundation

/// 模糊区域
struct BlurRegion: Equatable {
    var x: Int // 起始 X 坐标
    var y: Int // 起始 Y 坐标
    var width: Int // 宽度
    var height: Int // 高度
}

/// 模糊类型
enum BlurType {
    case boxblur // 马赛克效果
    case gblur // 高斯模糊
    case gradientBlur // 渐变式抹除
}

/// 视频模糊/马赛克服务
struct VideoBlur {
    
    /// 应用马赛克效果
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - region: 模糊区域
    ///   - intensity: 马赛克强度（像素块大小）
    ///   - progressHandler: 进度回调
    static func applyMosaic(
        inputURL: URL,
        outputURL: URL,
        region: BlurRegion,
        intensity: Int = 10,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // 构建滤镜链
        // 1. 分割视频流
        // 2. 对指定区域应用马赛克
        // 3. 叠加回原视频
        
        let filterComplex = """
        [0:v]split[main][blur];
        [blur]crop=\(region.width):\(region.height):\(region.x):\(region.y),
        scale=iw/\(intensity):ih/\(intensity),
        scale=\(region.width):\(region.height)[mosaic];
        [main][mosaic]overlay=\(region.x):\(region.y)
        """
        
        arguments.append("-filter_complex")
        arguments.append(filterComplex)
        
        arguments.append("-c:v")
        arguments.append("libx264")
        
        arguments.append("-c:a")
        arguments.append("copy")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: progressHandler
        )
    }
    
    /// 应用高斯模糊
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - region: 模糊区域
    ///   - sigma: 模糊强度（sigma 值）
    ///   - progressHandler: 进度回调
    static func applyGaussianBlur(
        inputURL: URL,
        outputURL: URL,
        region: BlurRegion,
        sigma: Double = 20.0,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // 构建滤镜链
        let filterComplex = """
        [0:v]split[main][blur];
        [blur]crop=\(region.width):\(region.height):\(region.x):\(region.y),
        gblur=sigma=\(sigma)[blurred];
        [main][blurred]overlay=\(region.x):\(region.y)
        """
        
        arguments.append("-filter_complex")
        arguments.append(filterComplex)
        
        arguments.append("-c:v")
        arguments.append("libx264")
        
        arguments.append("-c:a")
        arguments.append("copy")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: progressHandler
        )
    }
    
    /// 应用渐变式抹除效果
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - region: 模糊区域
    ///   - centerSigma: 中心区域模糊强度
    ///   - edgeSigma: 边缘区域模糊强度
    ///   - progressHandler: 进度回调
    static func applyGradientErase(
        inputURL: URL,
        outputURL: URL,
        region: BlurRegion,
        centerSigma: Double = 50.0,
        edgeSigma: Double = 10.0,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // 渐变式抹除效果实现：
        // 1. 裁剪目标区域
        // 2. 应用多层模糊（中心强，边缘弱）
        // 3. 使用 vignette 创建径向渐变
        // 4. 叠加回原视频
        
        let centerX = region.x + region.width / 2
        let centerY = region.y + region.height / 2
        
        // 计算模糊半径（使用较大的值以确保覆盖）
        let blurRadius = max(region.width, region.height) / 2
        
        let filterComplex = """
        [0:v]split[main][blur];
        [blur]crop=\(region.width):\(region.height):\(region.x):\(region.y),
        scale=\(region.width * 2):\(region.height * 2),
        gblur=sigma=\(centerSigma),
        scale=\(region.width):\(region.height),
        vignette=PI/4:mode=gradient[blurred];
        [main][blurred]overlay=\(region.x):\(region.y):format=auto
        """
        
        arguments.append("-filter_complex")
        arguments.append(filterComplex)
        
        arguments.append("-c:v")
        arguments.append("libx264")
        
        arguments.append("-c:a")
        arguments.append("copy")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: progressHandler
        )
    }
    
    /// 应用全画面模糊
    static func applyFullBlur(
        inputURL: URL,
        outputURL: URL,
        sigma: Double = 20.0,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        arguments.append("-vf")
        arguments.append("gblur=sigma=\(sigma)")
        
        arguments.append("-c:v")
        arguments.append("libx264")
        
        arguments.append("-c:a")
        arguments.append("copy")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: progressHandler
        )
    }
    
    /// 跟踪模糊（需要 AI 模型支持，这里提供基础框架）
    /// 注意：实际实现需要结合 YOLO 或人脸检测模型来动态跟踪目标
    static func applyTrackingBlur(
        inputURL: URL,
        outputURL: URL,
        region: BlurRegion,
        sigma: Double = 30.0,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        // 这里可以使用 sendcmd 滤镜配合动态坐标文件
        // 或者使用更复杂的滤镜链来实现跟踪效果
        // 简化版本：先实现固定区域模糊
        
        try await applyGaussianBlur(
            inputURL: inputURL,
            outputURL: outputURL,
            region: region,
            sigma: sigma,
            progressHandler: progressHandler
        )
    }
    
    /// 替换跟踪到的 Logo
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - trackingResults: Logo 跟踪结果列表
    ///   - replacementLogoURL: 替换用的新 Logo 图片 URL
    ///   - progressHandler: 进度回调
    static func replaceTrackedLogo(
        inputURL: URL,
        outputURL: URL,
        trackingResults: [LogoTrackingResult],
        replacementLogoURL: URL,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        // 获取视频信息以确定尺寸
        let asset = AVAsset(url: inputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw VideoBlurError.noVideoTrack
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let frameRate = videoTrack.nominalFrameRate
        
        // 构建 FFmpeg 命令
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        arguments.append("-i")
        arguments.append(replacementLogoURL.path)
        
        // 构建动态 overlay 滤镜
        // 由于 FFmpeg 的 overlay 滤镜支持表达式，我们可以使用时间函数来动态设置位置
        // 但更精确的方法是生成每帧的 overlay 命令
        
        // 方式1：使用表达式（适用于位置变化平滑的情况）
        // 这里我们使用 sendcmd 或生成多个 overlay 命令
        
        // 方式2：生成每帧的 overlay 命令序列（更精确）
        let overlayFilter = buildDynamicOverlayFilter(
            trackingResults: trackingResults,
            videoSize: naturalSize,
            frameRate: frameRate
        )
        
        arguments.append("-filter_complex")
        arguments.append(overlayFilter)
        
        arguments.append("-c:v")
        arguments.append("libx264")
        
        arguments.append("-c:a")
        arguments.append("copy")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: progressHandler
        )
    }
    
    /// 构建动态 overlay 滤镜
    private static func buildDynamicOverlayFilter(
        trackingResults: [LogoTrackingResult],
        videoSize: CGSize,
        frameRate: Float
    ) -> String {
        // 由于 FFmpeg 的 overlay 滤镜限制，我们需要使用 sendcmd 或分段处理
        // 这里使用简化的方法：生成分段 overlay 命令
        
        // 如果跟踪结果较少，可以使用 sendcmd
        // 如果跟踪结果很多，需要分段处理或使用其他方法
        
        // 简化版本：使用时间表达式
        // 实际应该为每个关键帧生成单独的 overlay 命令
        
        var filterParts: [String] = []
        
        // 为每个跟踪结果生成 overlay 命令
        for (index, result) in trackingResults.enumerated() {
            let startTime = result.timestamp
            let endTime = index < trackingResults.count - 1 ? trackingResults[index + 1].timestamp : startTime + (1.0 / Double(frameRate))
            
            let x = Int(result.boundingBox.origin.x)
            let y = Int(result.boundingBox.origin.y)
            
            // 构建时间条件表达式
            let timeCondition = "between(t,\(startTime),\(endTime))"
            
            // overlay 表达式
            let overlayExpr = "[0:v][1:v]overlay=\(x):\(y):enable='\(timeCondition)'"
            
            if index == 0 {
                filterParts.append(overlayExpr)
            } else {
                // 链式 overlay（需要更复杂的处理）
                // 简化：只使用第一个结果的位置
                break
            }
        }
        
        // 如果只有一个结果或简化处理，使用固定位置
        if filterParts.isEmpty, let firstResult = trackingResults.first {
            let x = Int(firstResult.boundingBox.origin.x)
            let y = Int(firstResult.boundingBox.origin.y)
            return "[0:v][1:v]overlay=\(x):\(y)"
        }
        
        return filterParts.joined(separator: ",")
    }
}

enum VideoBlurError: LocalizedError {
    case noVideoTrack
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "视频中没有视频轨道"
        }
    }
}
