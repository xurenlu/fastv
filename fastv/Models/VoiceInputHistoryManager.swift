//
//  VoiceInputHistoryManager.swift
//  fastv
//
//  语音输入历史记录管理器
//

import Combine
import Foundation

/// 语音输入历史记录管理器
@MainActor
class VoiceInputHistoryManager: ObservableObject {
    static let shared = VoiceInputHistoryManager()

    @Published private(set) var records: [VoiceInputHistoryRecord] = []

    private let maxRecords = 500
    private let storageKey = "voiceInputHistoryRecords"

    private init() {
        loadRecords()
    }

    /// 添加一条语音输入记录
    /// - Parameters:
    ///   - text: 识别文本
    ///   - audioDurationSeconds: 语音时长（秒），用于统计输入速度
    ///   - transcriptionDurationSeconds: 识别耗时（秒），用于统计识别速度
    func add(
        text: String,
        audioDurationSeconds: TimeInterval? = nil,
        transcriptionDurationSeconds: TimeInterval? = nil
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let record = VoiceInputHistoryRecord(
            text: text,
            audioDurationSeconds: audioDurationSeconds,
            transcriptionDurationSeconds: transcriptionDurationSeconds
        )
        records.insert(record, at: 0)

        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }

        saveRecords()
    }

    /// 删除指定记录
    func remove(_ record: VoiceInputHistoryRecord) {
        records.removeAll { $0.id == record.id }
        saveRecords()
    }

    /// 清空所有记录
    func clear() {
        records.removeAll()
        saveRecords()
    }

    /// 获取记录总数
    var totalCount: Int {
        records.count
    }

    /// 今日字数（按本地日历「今天」筛选）
    var todayCharacterCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return records
            .filter { calendar.startOfDay(for: $0.timestamp) == today }
            .reduce(0) { $0 + $1.text.count }
    }

    /// 总字数
    var totalCharacterCount: Int {
        records.reduce(0) { $0 + $1.text.count }
    }

    /// 平均每条字数（字/条）
    var averageCharactersPerRecord: Double {
        guard !records.isEmpty else { return 0 }
        return Double(totalCharacterCount) / Double(records.count)
    }

    // MARK: - 全部统计（含输入速度、识别速度）

    /// 全部：有音频时长记录的总字数
    private var totalCharacterCountWithDuration: Int {
        records
            .filter { $0.audioDurationSeconds != nil && ($0.audioDurationSeconds ?? 0) > 0 }
            .reduce(0) { $0 + $1.text.count }
    }

    /// 全部：有音频时长记录的总语音时长（秒）
    private var totalAudioSecondsWithDuration: TimeInterval {
        records
            .compactMap { $0.audioDurationSeconds }
            .filter { $0 > 0 }
            .reduce(0, +)
    }

    /// 全部：有识别耗时记录的总识别耗时（秒）
    private var totalTranscriptionSecondsWithDuration: TimeInterval {
        records
            .compactMap { $0.transcriptionDurationSeconds }
            .filter { $0 > 0 }
            .reduce(0, +)
    }

    /// 全部：字/分钟（语音输入速度），无有效数据时返回 nil
    var totalCharactersPerMinute: Double? {
        let seconds = totalAudioSecondsWithDuration
        guard seconds > 0 else { return nil }
        return Double(totalCharacterCountWithDuration) * 60 / seconds
    }

    /// 全部：总识别语音时长（秒）
    var totalAudioSeconds: TimeInterval { totalAudioSecondsWithDuration }

    /// 全部：总识别耗时（秒）
    var totalTranscriptionSeconds: TimeInterval { totalTranscriptionSecondsWithDuration }

    /// 全部：实时率（每秒识别多少秒语音），无有效数据时返回 nil
    var totalRealtimeFactor: Double? {
        let trans = totalTranscriptionSecondsWithDuration
        guard trans > 0 else { return nil }
        return totalAudioSecondsWithDuration / trans
    }

    // MARK: - 今日统计

    /// 今日：有音频时长记录的字数
    private var todayCharacterCountWithDuration: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return records
            .filter { calendar.startOfDay(for: $0.timestamp) == today }
            .filter { $0.audioDurationSeconds != nil && ($0.audioDurationSeconds ?? 0) > 0 }
            .reduce(0) { $0 + $1.text.count }
    }

    /// 今日：有音频时长记录的总语音时长（秒）
    private var todayAudioSecondsWithDuration: TimeInterval {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return records
            .filter { calendar.startOfDay(for: $0.timestamp) == today }
            .compactMap { $0.audioDurationSeconds }
            .filter { $0 > 0 }
            .reduce(0, +)
    }

    /// 今日：有识别耗时记录的总识别耗时（秒）
    private var todayTranscriptionSecondsWithDuration: TimeInterval {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return records
            .filter { calendar.startOfDay(for: $0.timestamp) == today }
            .compactMap { $0.transcriptionDurationSeconds }
            .filter { $0 > 0 }
            .reduce(0, +)
    }

    /// 今日：字/分钟（语音输入速度），无有效数据时返回 nil
    var todayCharactersPerMinute: Double? {
        let seconds = todayAudioSecondsWithDuration
        guard seconds > 0 else { return nil }
        return Double(todayCharacterCountWithDuration) * 60 / seconds
    }

    /// 今日：总识别语音时长（秒）
    var todayAudioSeconds: TimeInterval { todayAudioSecondsWithDuration }

    /// 今日：总识别耗时（秒）
    var todayTranscriptionSeconds: TimeInterval { todayTranscriptionSecondsWithDuration }

    /// 今日：实时率（每秒识别多少秒语音），无有效数据时返回 nil
    var todayRealtimeFactor: Double? {
        let trans = todayTranscriptionSecondsWithDuration
        guard trans > 0 else { return nil }
        return todayAudioSecondsWithDuration / trans
    }

    // MARK: - Persistence

    private func saveRecords() {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            records = []
            return
        }

        if let decoded = try? JSONDecoder().decode([VoiceInputHistoryRecord].self, from: data) {
            records = Array(decoded.prefix(maxRecords))
            if decoded.count > maxRecords {
                saveRecords()
            }
        } else {
            records = []
        }
    }
}
