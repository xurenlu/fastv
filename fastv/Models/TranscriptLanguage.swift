//
//  TranscriptLanguage.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

/// FunASR/SenseVoice 支持的语言类型
enum TranscriptLanguage: String, CaseIterable {
    case auto = "auto"
    case zh = "zh"
    case en = "en"
    case yue = "yue"
    case ja = "ja"
    case ko = "ko"
    case nospeech = "nospeech"
    
    /// 显示名称（中文）
    var displayName: String {
        switch self {
        case .auto:
            return "自动检测"
        case .zh:
            return "中文"
        case .en:
            return "英文"
        case .yue:
            return "粤语"
        case .ja:
            return "日文"
        case .ko:
            return "韩文"
        case .nospeech:
            return "无语音"
        }
    }
    
    /// 转换为 FunASR 模型使用的语言 ID（Int32）
    /// SenseVoice lid_dict: {"auto": 0, "zh": 3, "en": 4, "yue": 7, "ja": 11, "ko": 12, "nospeech": 13}
    var languageID: Int32 {
        switch self {
        case .auto:
            return 0
        case .zh:
            return 3
        case .en:
            return 4
        case .yue:
            return 7
        case .ja:
            return 11
        case .ko:
            return 12
        case .nospeech:
            return 13
        }
    }
}

