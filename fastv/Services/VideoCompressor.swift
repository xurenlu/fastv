//
//  VideoCompressor.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation

/// 视频分辨率预设
enum VideoResolution: String, CaseIterable {
    case original = "original"
    case uhd4k = "3840x2160"
    case fhd1080p = "1920x1080"
    case hd720p = "1280x720"
    case sd480p = "854x480"
    case sd360p = "640x360"
    
    var displayName: String {
        switch self {
        case .original: return "原始分辨率"
        case .uhd4k: return "4K (3840x2160)"
        case .fhd1080p: return "1080p (1920x1080)"
        case .hd720p: return "720p (1280x720)"
        case .sd480p: return "480p (854x480)"
        case .sd360p: return "360p (640x360)"
        }
    }
    
    var width: Int? {
        switch self {
        case .original: return nil
        case .uhd4k: return 3840
        case .fhd1080p: return 1920
        case .hd720p: return 1280
        case .sd480p: return 854
        case .sd360p: return 640
        }
    }
    
    var height: Int? {
        switch self {
        case .original: return nil
        case .uhd4k: return 2160
        case .fhd1080p: return 1080
        case .hd720p: return 720
        case .sd480p: return 480
        case .sd360p: return 360
        }
    }
}

/// 视频压缩器
struct VideoCompressor {
    
    /// 压缩视频（调整分辨率、帧率、比特率）
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - resolution: 目标分辨率
    ///   - frameRate: 目标帧率（nil 表示保持原帧率）
    ///   - bitrate: 目标比特率（nil 表示使用 CRF）
    ///   - crf: CRF 值（默认使用用户设置）
    ///   - codec: 视频编码器（默认使用用户设置）
    ///   - progressHandler: 进度回调
    static func compress(
        inputURL: URL,
        outputURL: URL,
        resolution: VideoResolution,
        frameRate: Int? = nil,
        bitrate: String? = nil,
        crf: Int? = nil,
        codec: VideoCodec? = nil,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        let preferences = UserPreferences.shared
        let selectedCodec = codec ?? VideoCodec(rawValue: preferences.videoToolsDefaultCodec) ?? .h264
        let selectedCRF = crf ?? preferences.videoToolsDefaultCRF
        
        // 构建 FFmpeg 参数
        var arguments: [String] = []
        
        // 输入文件
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // 视频编码器
        arguments.append("-c:v")
        arguments.append(selectedCodec.rawValue)
        
        // 分辨率调整
        if let width = resolution.width, let height = resolution.height {
            arguments.append("-vf")
            arguments.append("scale=\(width):\(height)")
        }
        
        // 帧率调整
        if let fps = frameRate {
            arguments.append("-r")
            arguments.append("\(fps)")
        }
        
        // 比特率或 CRF
        if let bitrate = bitrate {
            arguments.append("-b:v")
            arguments.append(bitrate)
        } else {
            arguments.append("-crf")
            arguments.append("\(selectedCRF)")
        }
        
        // 预设
        arguments.append("-preset")
        arguments.append("medium")
        
        // 音频编码
        arguments.append("-c:a")
        arguments.append("aac")
        arguments.append("-b:a")
        arguments.append("192k")
        
        // 覆盖输出文件
        arguments.append("-y")
        
        // 输出文件
        arguments.append(outputURL.path)
        
        // 执行压缩
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: { progress, status in
                progressHandler(progress, status)
            },
            outputHandler: { output in
                // 可以在这里解析更详细的进度信息
            }
        )
    }
    
    /// 压缩视频（简化版本）
    static func compress(
        inputURL: URL,
        outputURL: URL,
        resolution: VideoResolution,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws {
        try await compress(
            inputURL: inputURL,
            outputURL: outputURL,
            resolution: resolution,
            frameRate: nil,
            bitrate: nil,
            crf: nil,
            codec: nil,
            progressHandler: progressHandler
        )
    }
    
    /// 调整帧率
    static func changeFrameRate(
        inputURL: URL,
        outputURL: URL,
        targetFrameRate: Int,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        arguments.append("-r")
        arguments.append("\(targetFrameRate)")
        
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
    
    /// 调整比特率
    static func changeBitrate(
        inputURL: URL,
        outputURL: URL,
        targetBitrate: String,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws {
        let preferences = UserPreferences.shared
        let codec = VideoCodec(rawValue: preferences.videoToolsDefaultCodec) ?? .h264
        
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        arguments.append("-c:v")
        arguments.append(codec.rawValue)
        
        arguments.append("-b:v")
        arguments.append(targetBitrate)
        
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
