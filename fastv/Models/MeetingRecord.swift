//
//  MeetingRecord.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 会议记录数据模型
struct MeetingRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var originalText: String
    var correctedText: String
    var summary: String
    var actionItems: [String]
    let startTime: Date
    var endTime: Date?
    var duration: Double
    var isRecording: Bool
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String = "",
        originalText: String = "",
        correctedText: String = "",
        summary: String = "",
        actionItems: [String] = [],
        startTime: Date = Date(),
        endTime: Date? = nil,
        duration: Double = 0,
        isRecording: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.originalText = originalText
        self.correctedText = correctedText
        self.summary = summary
        self.actionItems = actionItems
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.isRecording = isRecording
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 自动生成标题（基于时间）
    static func generateDefaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "会议记录 \(formatter.string(from: Date()))"
    }
    
    /// 字符数（不包括空格）
    var characterCount: Int {
        correctedText.isEmpty ? originalText.replacingOccurrences(of: " ", with: "").count : correctedText.replacingOccurrences(of: " ", with: "").count
    }
    
    /// 格式化时长显示
    var formattedDuration: String {
        if duration < 60 {
            return String(format: "%.0f秒", duration)
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)分\(seconds)秒"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)小时\(minutes)分"
        }
    }
    
    /// 格式化日期显示
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: startTime)
    }
}

