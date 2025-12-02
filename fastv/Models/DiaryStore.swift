//
//  DiaryStore.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import Combine

/// 日记存储管理器
@MainActor
class DiaryStore: ObservableObject {
    static let shared = DiaryStore()
    
    @Published private(set) var entries: [DiaryEntry] = []
    
    private let storageKey = "diaryEntries"
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 1.0
    
    private init() {
        loadEntries()
    }
    
    // MARK: - CRUD Operations
    
    /// 添加日记
    func add(_ entry: DiaryEntry) {
        entries.append(entry)
        scheduleSave()
    }
    
    /// 更新日记
    func update(_ entry: DiaryEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            scheduleSave()
        }
    }
    
    /// 删除日记
    func delete(_ entry: DiaryEntry) {
        entries.removeAll { $0.id == entry.id }
        scheduleSave()
    }
    
    /// 根据日期获取日记
    func entries(for date: Date) -> [DiaryEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    /// 根据日期范围获取日记
    func entries(from startDate: Date, to endDate: Date) -> [DiaryEntry] {
        return entries.filter { $0.date >= startDate && $0.date <= endDate }
    }
    
    /// 搜索日记（搜索标题和内容）
    func searchEntries(query: String) -> [DiaryEntry] {
        guard !query.isEmpty else {
            return entries
        }
        let lowercasedQuery = query.lowercased()
        return entries.filter { entry in
            entry.title.lowercased().contains(lowercasedQuery) ||
            entry.content.lowercased().contains(lowercasedQuery)
        }
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
           let decoded = try? JSONDecoder().decode([DiaryEntry].self, from: data) {
            entries = decoded.sorted { $0.date > $1.date }
        }
    }
}

