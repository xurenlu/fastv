//
//  VideoConverter.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation

/// 视频格式
enum VideoFormat: String, CaseIterable {
    case mp4 = "mp4"
    case mov = "mov"
    case avi = "avi"
    case mkv = "mkv"
    case webm = "webm"
    
    var displayName: String {
        switch self {
        case .mp4: return "MP4"
        case .mov: return "MOV"
        case .avi: return "AVI"
        case .mkv: return "MKV"
        case .webm: return "WebM"
        }
    }
    
    var mimeType: String {
        switch self {
        case .mp4: return "video/mp4"
        case .mov: return "video/quicktime"
        case .avi: return "video/x-msvideo"
        case .mkv: return "video/x-matroska"
        case .webm: return "video/webm"
        }
    }
}

/// 视频编码器
enum VideoCodec: String, CaseIterable {
    case h264 = "libx264"
    case h265 = "libx265"
    case vp9 = "libvpx-vp9"
    case av1 = "libaom-av1"
    
    var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .h265: return "H.265/HEVC"
        case .vp9: return "VP9"
        case .av1: return "AV1"
        }
    }
}

/// 视频转换器
struct VideoConverter {
    
    /// 转换视频格式
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - format: 目标格式
    ///   - codec: 视频编码器（默认使用用户设置）
    ///   - crf: CRF 值（默认使用用户设置）
    ///   - progressHandler: 进度回调
    static func convert(
        inputURL: URL,
        outputURL: URL,
        format: VideoFormat,
        codec: VideoCodec? = nil,
        crf: Int? = nil,
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
        
        // CRF 质量设置
        arguments.append("-crf")
        arguments.append("\(selectedCRF)")
        
        // 预设（加快编码速度）
        arguments.append("-preset")
        arguments.append("medium")
        
        // 音频编码（复制或重新编码）
        arguments.append("-c:a")
        arguments.append("aac")
        arguments.append("-b:a")
        arguments.append("192k")
        
        // 覆盖输出文件
        arguments.append("-y")
        
        // 输出文件
        arguments.append(outputURL.path)
        
        // 执行转换
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
    
    /// 转换视频格式（简化版本，使用默认设置）
    static func convert(
        inputURL: URL,
        outputURL: URL,
        format: VideoFormat,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws {
        try await convert(
            inputURL: inputURL,
            outputURL: outputURL,
            format: format,
            codec: nil,
            crf: nil,
            progressHandler: progressHandler
        )
    }
    
    /// 获取视频信息（使用 ffprobe）
    static func getVideoInfo(inputURL: URL) async throws -> VideoInfo {
        // 这里可以调用 ffprobe 获取详细信息
        // 暂时使用现有的 VideoInfoService
        return try await VideoInfoService.getVideoInfo(from: inputURL)
    }
}

/// 视频转换错误
enum VideoConversionError: LocalizedError {
    case ffmpegNotAvailable
    case invalidInputFile
    case conversionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .ffmpegNotAvailable:
            return "FFmpeg 不可用，请先安装 FFmpeg"
        case .invalidInputFile:
            return "无效的输入文件"
        case .conversionFailed(let message):
            return "转换失败: \(message)"
        }
    }
}
