//
//  CommonMistake.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

/// 常错词
struct CommonMistake: Identifiable, Codable {
    let id: UUID
    var wrong: String // 错误词（语音识别结果）
    var correct: String // 正确词（用户修正后的）
    var frequency: Int // 出现次数
    var confidence: Double // 置信度（0.0-1.0）
    var createdAt: Date // 创建时间
    var lastUpdated: Date // 最后更新时间
    
    init(
        wrong: String,
        correct: String,
        frequency: Int = 1,
        confidence: Double = 0.5,
        createdAt: Date = Date(),
        lastUpdated: Date = Date()
    ) {
        self.id = UUID()
        self.wrong = wrong
        self.correct = correct
        self.frequency = frequency
        self.confidence = confidence
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
    }
    
    /// 更新频率和置信度
    mutating func update(frequency: Int, confidence: Double) {
        self.frequency = frequency
        self.confidence = confidence
        self.lastUpdated = Date()
    }
}

