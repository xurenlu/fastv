//
//  TextCorrectionManager.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import Combine

/// 校正记录管理器
@MainActor
class TextCorrectionManager: ObservableObject {
    static let shared = TextCorrectionManager()
    
    @Published private(set) var records: [TextCorrectionRecord] = []
    
    private let maxRecords = 10000 // 最多保存10000条记录
    private let storageKey = "textCorrectionRecords"
    
    private init() {
        loadRecords()
    }
    
    /// 添加校正记录
    func add(_ record: TextCorrectionRecord) {
        records.insert(record, at: 0)
        
        // 限制记录数量
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        
        saveRecords()
    }
    
    /// 删除指定记录
    func remove(_ record: TextCorrectionRecord) {
        records.removeAll { $0.id == record.id }
        saveRecords()
    }
    
    /// 清空所有记录
    func clear() {
        records.removeAll()
        saveRecords()
    }
    
    /// 获取记录总数
    func totalCount() -> Int {
        records.count
    }
    
    /// 按时间范围查询记录
    func records(from startDate: Date, to endDate: Date) -> [TextCorrectionRecord] {
        records.filter { record in
            record.timestamp >= startDate && record.timestamp <= endDate
        }
    }
    
    /// 导出所有记录为JSON
    func exportToJSON() -> Data? {
        try? JSONEncoder().encode(records)
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
        
        if let decoded = try? JSONDecoder().decode([TextCorrectionRecord].self, from: data) {
            records = decoded
        } else {
            records = []
        }
    }
}

