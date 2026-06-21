//
//  CommonMistake.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

/// 纠错规则类别
enum CorrectionCategory: String, Codable, CaseIterable {
    case repetition = "重复词"
    case filler = "填充词"
    case number = "数字"
    case punctuation = "标点"
    case time = "时间"
    case location = "地点"
    case pronoun = "人称"
    case terminology = "术语"
    case other = "其他"

    var displayName: String { rawValue }

    /// 是否属于「术语包」语义（专有名词、产品名、技术词等）。
    /// 术语类条目在替换管线中优先级高于普通错字纠正，且采用大小写不敏感匹配，
    /// 这样用户说 "open ai" 也能命中 "OpenAI" 这条术语。
    var isTerminology: Bool { self == .terminology }
}

/// 常错词/纠错规则
struct CommonMistake: Identifiable, Codable {
    let id: UUID
    var wrong: String // 错误词（语音识别结果）
    var correct: String // 正确词（用户修正后的）
    var frequency: Int // 出现次数
    var confidence: Double // 置信度（0.0-1.0）
    var createdAt: Date // 创建时间
    var lastUpdated: Date // 最后更新时间
    var isBuiltIn: Bool // 是否为内置规则
    var isEnabled: Bool // 是否启用（仅对内置规则有效）
    var category: CorrectionCategory // 规则类别
    
    init(
        wrong: String,
        correct: String,
        frequency: Int = 1,
        confidence: Double = 0.5,
        createdAt: Date = Date(),
        lastUpdated: Date = Date(),
        isBuiltIn: Bool = false,
        isEnabled: Bool = true,
        category: CorrectionCategory = .other
    ) {
        self.id = UUID()
        self.wrong = wrong
        self.correct = correct
        self.frequency = frequency
        self.confidence = confidence
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.category = category
    }
    
    /// 更新频率和置信度
    mutating func update(frequency: Int, confidence: Double) {
        self.frequency = frequency
        self.confidence = confidence
        self.lastUpdated = Date()
    }
}

