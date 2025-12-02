//
//  IntelStore.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import Combine

/// 情报存储管理器
@MainActor
class IntelStore: ObservableObject {
    static let shared = IntelStore()
    
    @Published private(set) var entries: [IntelEntry] = []
    
    private let storageKey = "intelEntries"
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 1.0
    
    private init() {
        loadEntries()
        // 异步迁移历史数据（为没有关键词的旧数据提取关键词）
        Task { @MainActor in
            await migrateHistoricalKeywordsIfNeeded()
        }
    }
    
    /// 迁移历史数据，为没有关键词的条目提取关键词
    private func migrateHistoricalKeywordsIfNeeded() async {
        let keywordService = KeywordExtractionService.shared
        var needsSave = false
        
        for (index, entry) in entries.enumerated() {
            // 如果条目没有关键词，提取关键词
            if entry.keywords.isEmpty {
                let (keywords, entities) = keywordService.extractKeywordsAndEntities(
                    from: "\(entry.summary) \(entry.body)"
                )
                var updatedEntry = entry
                updatedEntry.keywords = keywords
                updatedEntry.entities = entities
                entries[index] = updatedEntry
                needsSave = true
            }
        }
        
        if needsSave {
            saveEntries()
        }
    }
    
    // MARK: - CRUD Operations
    
    /// 添加情报
    func add(_ entry: IntelEntry) {
        entries.append(entry)
        scheduleSave()
    }
    
    /// 更新情报
    func update(_ entry: IntelEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            scheduleSave()
        }
    }
    
    /// 删除情报
    func delete(_ entry: IntelEntry) {
        entries.removeAll { $0.id == entry.id }
        scheduleSave()
    }
    
    /// 根据日期获取情报
    func entries(for date: Date) -> [IntelEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    /// 设置指定日期的情报列表（整体覆盖）
    func setEntries(_ newEntries: [IntelEntry], for date: Date) {
        let calendar = Calendar.current
        
        // 删除该日期的所有现有条目
        entries.removeAll { calendar.isDate($0.date, inSameDayAs: date) }
        
        // 添加新条目（确保日期正确）
        let entriesWithCorrectDate = newEntries.map { entry -> IntelEntry in
            var updated = entry
            updated.date = date
            return updated
        }
        entries.append(contentsOf: entriesWithCorrectDate)
        
        scheduleSave()
    }
    
    /// 添加或更新情报（用于本地手工操作）
    func addOrUpdate(_ entry: IntelEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        scheduleSave()
    }
    
    /// 根据日期范围获取情报
    func entries(from startDate: Date, to endDate: Date) -> [IntelEntry] {
        return entries.filter { $0.date >= startDate && $0.date <= endDate }
    }
    
    // MARK: - Persistence
    
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.saveEntries()
            }
        }
    }
    
    private func saveEntries() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadEntries() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([IntelEntry].self, from: data) {
            entries = decoded.sorted { $0.date > $1.date }
        }
    }
}

