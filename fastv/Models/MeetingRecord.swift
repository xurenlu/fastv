//
//  MeetingRecord.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 说话人片段信息
struct SpeakerSegmentInfo: Codable, Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let speaker: String
    let duration: TimeInterval
}

/// 会议记录数据模型
struct MeetingRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var originalText: String
    var correctedText: String
    var summary: String
    var actionItems: [String]
    var speakerSegments: [SpeakerSegmentInfo] // 说话人分离结果
    /// 实时图文文档（Markdown）。录音过程中由 MeetingRichDocPipeline 持续 AI 生成。
    var richDocumentMarkdown: String
    /// 已消费到 correctedText（或 originalText）的字符索引；下次增量生成只用 cursor 之后的新增片段。
    var richDocCursor: Int
    /// 上一次成功流式生成图文文档的时间，用于节流。
    var lastRichDocAt: Date?
    /// 当前是否正在流式生成图文文档（用于 UI 显示打字动画）。
    var isRichDocStreaming: Bool
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
        speakerSegments: [SpeakerSegmentInfo] = [],
        richDocumentMarkdown: String = "",
        richDocCursor: Int = 0,
        lastRichDocAt: Date? = nil,
        isRichDocStreaming: Bool = false,
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
        self.speakerSegments = speakerSegments
        self.richDocumentMarkdown = richDocumentMarkdown
        self.richDocCursor = richDocCursor
        self.lastRichDocAt = lastRichDocAt
        self.isRichDocStreaming = isRichDocStreaming
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.isRecording = isRecording
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Codable（向后兼容旧记录）

    private enum CodingKeys: String, CodingKey {
        case id, title, originalText, correctedText, summary, actionItems, speakerSegments
        case richDocumentMarkdown, richDocCursor, lastRichDocAt, isRichDocStreaming
        case startTime, endTime, duration, isRecording, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        originalText = try c.decodeIfPresent(String.self, forKey: .originalText) ?? ""
        correctedText = try c.decodeIfPresent(String.self, forKey: .correctedText) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        actionItems = try c.decodeIfPresent([String].self, forKey: .actionItems) ?? []
        speakerSegments = try c.decodeIfPresent([SpeakerSegmentInfo].self, forKey: .speakerSegments) ?? []
        richDocumentMarkdown = try c.decodeIfPresent(String.self, forKey: .richDocumentMarkdown) ?? ""
        richDocCursor = try c.decodeIfPresent(Int.self, forKey: .richDocCursor) ?? 0
        lastRichDocAt = try c.decodeIfPresent(Date.self, forKey: .lastRichDocAt)
        // 旧文件里没有 isRichDocStreaming；即使有，加载时也应该被视为非流式中
        isRichDocStreaming = false
        startTime = try c.decode(Date.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(Date.self, forKey: .endTime)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        isRecording = try c.decodeIfPresent(Bool.self, forKey: .isRecording) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
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

