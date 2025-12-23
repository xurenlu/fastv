//
//  VideoTransform.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation

/// 旋转角度
enum RotationAngle: Int, CaseIterable {
    case rotate90 = 90
    case rotate180 = 180
    case rotate270 = 270
    
    var displayName: String {
        return "\(rawValue)°"
    }
    
    /// 转换为 FFmpeg transpose 值
    /// transpose=1: 90度顺时针
    /// transpose=2: 90度逆时针
    /// transpose=3: 90度顺时针并水平翻转
    /// transpose=4: 90度逆时针并水平翻转
    func toTransposeValue() -> Int {
        switch self {
        case .rotate90:
            return 1 // 90度顺时针
        case .rotate270:
            return 2 // 90度逆时针（等同于270度顺时针）
        case .rotate180:
            return 0 // 180度需要两次旋转或使用其他方法
        }
    }
}

/// 裁剪区域
struct CropRegion: Equatable {
    var x: Int // 起始 X 坐标
    var y: Int // 起始 Y 坐标
    var width: Int // 宽度
    var height: Int // 高度
    
    /// 转换为 FFmpeg crop 滤镜参数
    func toCropFilter() -> String {
        return "crop=\(width):\(height):\(x):\(y)"
    }
}

/// 视频变换服务
struct VideoTransform {
    
    /// 裁剪视频
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - cropRegion: 裁剪区域
    ///   - progressHandler: 进度回调
    static func crop(
        inputURL: URL,
        outputURL: URL,
        cropRegion: CropRegion,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // 应用裁剪滤镜
        arguments.append("-vf")
        arguments.append(cropRegion.toCropFilter())
        
        // 视频编码
        arguments.append("-c:v")
        arguments.append("libx264")
        
        // 音频编码（复制）
        arguments.append("-c:a")
        arguments.append("copy")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: progressHandler
        )
    }
    
    /// 缩放视频
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - width: 目标宽度
    ///   - height: 目标高度
    ///   - keepAspectRatio: 是否保持宽高比
    ///   - progressHandler: 进度回调
    static func scale(
        inputURL: URL,
        outputURL: URL,
        width: Int,
        height: Int,
        keepAspectRatio: Bool = true,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // 构建缩放滤镜
        var scaleFilter = "scale=\(width):\(height)"
        if keepAspectRatio {
            // 保持宽高比，可能会添加黑边
            scaleFilter += ":force_original_aspect_ratio=decrease"
        }
        
        arguments.append("-vf")
        arguments.append(scaleFilter)
        
        // 视频编码
        arguments.append("-c:v")
        arguments.append("libx264")
        
        // 音频编码（复制）
        arguments.append("-c:a")
        arguments.append("copy")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: progressHandler
        )
    }
    
    /// 旋转视频
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - angle: 旋转角度
    ///   - progressHandler: 进度回调
    static func rotate(
        inputURL: URL,
        outputURL: URL,
        angle: RotationAngle,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // 构建旋转滤镜
        var rotateFilter: String
        
        switch angle {
        case .rotate90:
            rotateFilter = "transpose=1" // 90度顺时针
        case .rotate270:
            rotateFilter = "transpose=2" // 90度逆时针（等同于270度顺时针）
        case .rotate180:
            // 180度需要两次旋转
            rotateFilter = "transpose=1,transpose=1"
        }
        
        arguments.append("-vf")
        arguments.append(rotateFilter)
        
        // 视频编码
        arguments.append("-c:v")
        arguments.append("libx264")
        
        // 音频编码（复制）
        arguments.append("-c:a")
        arguments.append("copy")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: progressHandler
        )
    }
    
    /// 水平翻转
    static func flipHorizontal(
        inputURL: URL,
        outputURL: URL,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        arguments.append("-vf")
        arguments.append("hflip")
        
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
    
    /// 垂直翻转
    static func flipVertical(
        inputURL: URL,
        outputURL: URL,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        arguments.append("-vf")
        arguments.append("vflip")
        
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
    
    /// 添加填充（黑边/白边）
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - width: 目标宽度
    ///   - height: 目标高度
    ///   - color: 填充颜色（十六进制，如 000000 表示黑色）
    ///   - progressHandler: 进度回调
    static func pad(
        inputURL: URL,
        outputURL: URL,
        width: Int,
        height: Int,
        color: String = "000000",
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // pad 滤镜：pad=width:height:x:y:color
        // x 和 y 用于居中
        let padFilter = "pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2:0x\(color)"
        
        arguments.append("-vf")
        arguments.append(padFilter)
        
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
}
