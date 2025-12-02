//
//  DiaryEntry.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// 日记心情标签
enum DiaryMood: String, Codable, CaseIterable {
    case happy = "happy"
    case calm = "calm"
    case sad = "sad"
    case anxious = "anxious"
    case excited = "excited"
    case tired = "tired"
    
    var displayName: String {
        switch self {
        case .happy:
            return "开心"
        case .calm:
            return "平静"
        case .sad:
            return "难过"
        case .anxious:
            return "焦虑"
        case .excited:
            return "兴奋"
        case .tired:
            return "疲惫"
        }
    }
    
    var icon: String {
        switch self {
        case .happy:
            return "face.smiling.fill"
        case .calm:
            return "leaf.fill"
        case .sad:
            return "cloud.rain.fill"
        case .anxious:
            return "exclamationmark.triangle.fill"
        case .excited:
            return "star.fill"
        case .tired:
            return "moon.zzz.fill"
        }
    }
}

/// 日记条目
struct DiaryEntry: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String
    var date: Date
    var mood: DiaryMood?
    var aiSummary: String?      // AI 生成的摘要
    var aiMoodAnalysis: String? // AI 情绪分析
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        date: Date = Date(),
        mood: DiaryMood? = nil,
        aiSummary: String? = nil,
        aiMoodAnalysis: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.date = date
        self.mood = mood
        self.aiSummary = aiSummary
        self.aiMoodAnalysis = aiMoodAnalysis
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 更新内容
    mutating func update(title: String? = nil, content: String? = nil, mood: DiaryMood? = nil) {
        if let title = title {
            self.title = title
        }
        if let content = content {
            self.content = content
        }
        if let mood = mood {
            self.mood = mood
        }
        self.updatedAt = Date()
    }
}

