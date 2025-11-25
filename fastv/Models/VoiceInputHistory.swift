//
//  VoiceInputHistory.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AppKit
import Combine

/// 语音输入历史记录项
struct VoiceInputHistoryItem: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    let duration: Double // 输入时长（秒）
    
    init(text: String, timestamp: Date = Date(), duration: Double = 0) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
    }
    
    /// 字符数（不包括空格）
    var characterCount: Int {
        text.replacingOccurrences(of: " ", with: "").count
    }
    
    /// 总字符数（包括空格）
    var totalCharacterCount: Int {
        text.count
    }
}

/// 语音输入历史记录管理器
@MainActor
class VoiceInputHistory: ObservableObject {
    static let shared = VoiceInputHistory()
    
    @Published private(set) var items: [VoiceInputHistoryItem] = []
    
    private let maxItems = 10000 // 最多保存10000条记录
    private let displayLimit = 100 // 显示限制100条
    private let storageKey = "voiceInputHistory"
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 2.0 // 延迟2秒保存，避免频繁写入
    
    /// 用于显示的记录（只返回前100条）
    var displayedItems: [VoiceInputHistoryItem] {
        Array(items.prefix(displayLimit))
    }
    
    /// 全部记录（用于导出）
    var allItems: [VoiceInputHistoryItem] {
        items
    }
    
    private init() {
        loadHistory()
    }
    
    /// 添加新的历史记录
    func add(_ text: String, duration: Double = 0) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let item = VoiceInputHistoryItem(text: text, duration: duration)
        items.insert(item, at: 0)
        
        // 限制记录数量（优化：只删除超出部分，避免重建整个数组）
        if items.count > maxItems {
            items.removeSubrange(maxItems..<items.count)
        }
        
        // 延迟保存，避免频繁写入
        scheduleSave()
    }
    
    /// 延迟保存
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.saveHistory()
            }
        }
    }
    
    /// 删除指定记录
    func remove(_ item: VoiceInputHistoryItem) {
        items.removeAll { $0.id == item.id }
        scheduleSave()
    }
    
    /// 清空所有记录
    func clear() {
        items.removeAll()
        saveTimer?.invalidate()
        saveHistory() // 清空操作立即保存
    }
    
    /// 获取今日记录数量
    func todayCount() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return items.filter { calendar.startOfDay(for: $0.timestamp) == today }.count
    }
    
    /// 复制文本到剪贴板
    func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    // MARK: - Statistics
    
    /// 总字数（不包括空格）- 使用全部记录
    func totalCharacters() -> Int {
        items.reduce(0) { $0 + $1.characterCount }
    }
    
    /// 总时长（分钟）- 使用全部记录
    func totalDuration() -> Double {
        let totalSeconds = items.reduce(0.0) { $0 + $1.duration }
        return totalSeconds / 60.0
    }
    
    /// 每分钟字数 - 使用全部记录
    func charactersPerMinute() -> Int {
        let totalChars = totalCharacters()
        let totalMinutes = totalDuration()
        guard totalMinutes > 0 else { return 0 }
        return Int(Double(totalChars) / totalMinutes)
    }
    
    // MARK: - Persistence
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            items = []
            return
        }
        
        // 尝试解码新格式（带 duration）
        if let decoded = try? JSONDecoder().decode([VoiceInputHistoryItem].self, from: data) {
            items = decoded
            return
        }
        
        // 兼容旧格式（不带 duration）
        // 定义旧版本的临时结构体
        struct LegacyVoiceInputHistoryItem: Codable {
            let id: UUID
            let text: String
            let timestamp: Date
        }
        
        if let legacyItems = try? JSONDecoder().decode([LegacyVoiceInputHistoryItem].self, from: data) {
            // 转换为新格式，duration 设为 0
            items = legacyItems.map { legacyItem in
                VoiceInputHistoryItem(text: legacyItem.text, timestamp: legacyItem.timestamp, duration: 0)
            }
            // 保存转换后的数据
            saveHistory()
        } else {
            items = []
        }
    }
}

