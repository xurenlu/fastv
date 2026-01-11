//
//  VideoToolsConstants.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation

/// 视频工具模块常量配置
enum VideoToolsConstants {
    
    // MARK: - 超时设置（秒）
    
    /// 音频提取超时
    static let audioExtractionTimeout: TimeInterval = 300 // 5分钟
    
    /// 音频转写超时
    static let transcriptionTimeout: TimeInterval = 600 // 10分钟
    
    /// 视频压缩超时
    static let compressionTimeout: TimeInterval = 1800 // 30分钟
    
    /// 视频格式转换超时
    static let formatConversionTimeout: TimeInterval = 1800 // 30分钟
    
    /// 帧提取超时
    static let frameExtractionTimeout: TimeInterval = 120 // 2分钟
    
    /// 场景检测超时
    static let sceneDetectionTimeout: TimeInterval = 600 // 10分钟
    
    /// 水印添加超时
    static let watermarkTimeout: TimeInterval = 1800 // 30分钟
    
    /// 视频变换超时
    static let transformTimeout: TimeInterval = 1800 // 30分钟
    
    /// 模糊处理超时
    static let blurTimeout: TimeInterval = 1800 // 30分钟
    
    /// 字幕处理超时
    static let subtitleTimeout: TimeInterval = 600 // 10分钟
    
    /// 颜色调整超时
    static let colorAdjustmentTimeout: TimeInterval = 1800 // 30分钟
    
    /// 卡通化超时
    static let cartoonTimeout: TimeInterval = 3600 // 60分钟（AI处理较慢）
    
    // MARK: - 进度更新间隔
    
    /// 进度更新间隔（纳秒）
    static let progressUpdateInterval: UInt64 = 100_000_000 // 0.1秒
    
    /// 防抖延迟（秒）- 用于预览更新
    static let debounceDelay: TimeInterval = 0.3
    
    // MARK: - 文件大小限制
    
    /// 最大处理文件大小（字节）
    static let maxFileSize: Int64 = 50 * 1024 * 1024 * 1024 // 50GB
    
    /// 临时文件清理延迟（秒）
    static let tempFileCleanupDelay: TimeInterval = 5
    
    // MARK: - UI 相关
    
    /// 进度条动画时长
    static let progressAnimationDuration: TimeInterval = 0.2
    
    /// 状态消息最大长度
    static let maxStatusMessageLength: Int = 100
    
    // MARK: - 视频处理默认值
    
    /// 默认 CRF 值
    static let defaultCRF: Int = 23
    
    /// 默认音频比特率
    static let defaultAudioBitrate: String = "192k"
    
    /// 默认帧率
    static let defaultFrameRate: Int = 30
    
    /// 默认预设
    static let defaultPreset: String = "medium"
}
