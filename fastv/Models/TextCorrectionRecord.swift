//
//  TextCorrectionRecord.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

/// 文本校正记录
struct TextCorrectionRecord: Identifiable, Codable {
    let id: UUID
    let originalText: String // 原始文本（语音识别结果）
    let correctedText: String // 校正后文本（用户修正后的）
    let timestamp: Date
    let appName: String? // 应用名称
    let appBundleId: String? // 应用Bundle ID
    
    init(
        originalText: String,
        correctedText: String,
        timestamp: Date = Date(),
        appName: String? = nil,
        appBundleId: String? = nil
    ) {
        self.id = UUID()
        self.originalText = originalText
        self.correctedText = correctedText
        self.timestamp = timestamp
        self.appName = appName
        self.appBundleId = appBundleId
    }
}

