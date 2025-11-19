//
//  VideoProcessingError.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

enum VideoProcessingError: LocalizedError {
    case noVideoTrack
    case noAudioTrack
    case compositionFailed
    case exportFailed
    case invalidVideoFile
    case fileSaveFailed
    case downloadFailed(String)
    case transcriptionFailed(String)
    case modelLoadFailed(String)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "视频文件中没有找到视频轨道"
        case .noAudioTrack:
            return "视频文件中没有找到音频轨道"
        case .compositionFailed:
            return "创建音频组合失败"
        case .exportFailed:
            return "导出失败"
        case .invalidVideoFile:
            return "无效的视频文件"
        case .fileSaveFailed:
            return "文件保存失败"
        case .downloadFailed(let message):
            return "下载失败: \(message)"
        case .transcriptionFailed(let message):
            return "语音转文字失败: \(message)"
        case .modelLoadFailed(let message):
            return "模型加载失败: \(message)"
        case .unknown(let error):
            return "未知错误: \(error.localizedDescription)"
        }
    }
}

