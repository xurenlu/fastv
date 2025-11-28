//
//  LiveTranscriptionRecord.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 直播转录记录数据模型
struct LiveTranscriptionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var transcript: String  // 转录文本（原始）
    var optimizedTranscript: String?  // AI优化后的文本（包含标点、修正错别字、分段）
    var summary: String?  // 摘要
    let startTime: Date
    var endTime: Date?
    var duration: Double
    var isTranscribing: Bool
    var isOptimizing: Bool = false  // 是否正在AI优化中
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String = "",
        transcript: String = "",
        optimizedTranscript: String? = nil,
        summary: String? = nil,
        startTime: Date = Date(),
        endTime: Date? = nil,
        duration: Double = 0,
        isTranscribing: Bool = false,
        isOptimizing: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.transcript = transcript
        self.optimizedTranscript = optimizedTranscript
        self.summary = summary
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.isTranscribing = isTranscribing
        self.isOptimizing = isOptimizing
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 获取显示用的文本（优先使用优化后的文本）
    var displayText: String {
        optimizedTranscript ?? transcript
    }
    
    /// 自动生成标题（基于时间）
    static func generateDefaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "直播转录 \(formatter.string(from: Date()))"
    }
    
    /// 字符数（不包括空格，使用显示文本）
    var characterCount: Int {
        displayText.replacingOccurrences(of: " ", with: "").count
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

