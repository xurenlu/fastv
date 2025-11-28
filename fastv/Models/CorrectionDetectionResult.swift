//
//  CorrectionDetectionResult.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 错误检测结果项
struct CorrectionDetectionItem: Identifiable, Codable {
    let id: UUID
    var wrongText: String  // 识别错误的文本
    var correctText: String  // 正确的文本
    var context: String  // 上下文（用于显示）
    var confidence: Double  // 置信度（0.0-1.0）
    var isConfirmed: Bool  // 用户是否确认
    
    init(
        wrongText: String,
        correctText: String,
        context: String,
        confidence: Double = 0.5,
        isConfirmed: Bool = false
    ) {
        self.id = UUID()
        self.wrongText = wrongText
        self.correctText = correctText
        self.context = context
        self.confidence = confidence
        self.isConfirmed = isConfirmed
    }
}

/// 错误检测结果
struct CorrectionDetectionResult: Codable {
    var items: [CorrectionDetectionItem]
    var originalText: String  // 原始识别文本
    var correctedText: String  // 修正后的文本
    var detectionModel: String  // 使用的模型
    
    init(
        items: [CorrectionDetectionItem] = [],
        originalText: String = "",
        correctedText: String = "",
        detectionModel: String = ""
    ) {
        self.items = items
        self.originalText = originalText
        self.correctedText = correctedText
        self.detectionModel = detectionModel
    }
}

