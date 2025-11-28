//
//  LiveTranscriptionManager.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 直播转录记录管理器
@MainActor
class LiveTranscriptionManager: ObservableObject {
    static let shared = LiveTranscriptionManager()
    
    @Published private(set) var records: [LiveTranscriptionRecord] = []
    
    private let maxRecords = 1000 // 最多保存1000条记录
    private let storageKey = "liveTranscriptionRecords"
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 2.0 // 延迟2秒保存，避免频繁写入
    
    private init() {
        // 异步加载，避免阻塞启动
        Task { @MainActor in
            await loadRecords()
        }
    }
    
    /// 添加新的直播转录记录
    func add(_ record: LiveTranscriptionRecord) {
        records.insert(record, at: 0)
        
        // 限制记录数量
        if records.count > maxRecords {
            records.removeSubrange(maxRecords..<records.count)
        }
        
        scheduleSave()
    }
    
    /// 更新直播转录记录
    func update(_ record: LiveTranscriptionRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            return
        }
        
        var updatedRecord = record
        updatedRecord.updatedAt = Date()
        records[index] = updatedRecord
        scheduleSave()
    }
    
    /// 删除指定记录
    func remove(_ record: LiveTranscriptionRecord) {
        records.removeAll { $0.id == record.id }
        scheduleSave()
    }
    
    /// 清空所有记录
    func clear() {
        records.removeAll()
        saveTimer?.invalidate()
        saveRecords() // 清空操作立即保存
    }
    
    /// 获取记录总数
    func totalCount() -> Int {
        records.count
    }
    
    /// 总时长（秒）
    func totalDuration() -> Double {
        records.reduce(0.0) { $0 + $1.duration }
    }
    
    /// 按时间范围查询记录
    func records(from startDate: Date, to endDate: Date) -> [LiveTranscriptionRecord] {
        records.filter { record in
            record.startTime >= startDate && record.startTime <= endDate
        }
    }
    
    /// 导出所有记录为JSON
    func exportToJSON() -> Data? {
        try? JSONEncoder().encode(records)
    }
    
    // MARK: - Persistence
    
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            self?.saveRecords()
        }
    }
    
    private func saveRecords() {
        let recordsToSave = records // 捕获当前状态
        Task.detached(priority: .background) {
            if let encoded = try? JSONEncoder().encode(recordsToSave) {
                UserDefaults.standard.set(encoded, forKey: self.storageKey)
            }
        }
    }
    
    private func loadRecords() async {
        // 在后台线程解码
        let data = UserDefaults.standard.data(forKey: storageKey)
        
        guard let data = data else {
            await MainActor.run {
                records = []
            }
            return
        }
        
        let decoded = await Task.detached(priority: .userInitiated) {
            try? JSONDecoder().decode([LiveTranscriptionRecord].self, from: data)
        }.value
        
        await MainActor.run {
            records = decoded ?? []
        }
    }
}

