//
//  VoiceInputHistoryRecord.swift
//  fastv
//
//  语音输入历史记录
//

import Foundation

/// 单条语音输入历史记录
struct VoiceInputHistoryRecord: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    /// 语音时长（秒），nil 表示旧数据无此字段
    let audioDurationSeconds: TimeInterval?
    /// 识别耗时（秒），nil 表示旧数据无此字段
    let transcriptionDurationSeconds: TimeInterval?

    init(
        text: String,
        timestamp: Date = Date(),
        audioDurationSeconds: TimeInterval? = nil,
        transcriptionDurationSeconds: TimeInterval? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.audioDurationSeconds = audioDurationSeconds
        self.transcriptionDurationSeconds = transcriptionDurationSeconds
    }
}
