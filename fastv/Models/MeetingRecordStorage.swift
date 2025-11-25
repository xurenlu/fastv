//
//  MeetingRecordStorage.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 会议记录存储管理器
@MainActor
class MeetingRecordStorage: ObservableObject {
    static let shared = MeetingRecordStorage()
    
    @Published private(set) var records: [MeetingRecord] = []
    
    private let storageKey = "meetingRecords"
    private let storageURL: URL
    
    private init() {
        // 存储路径：~/Library/Application Support/com.wxside.fastv2/meeting_records.json
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolderURL = appSupportURL.appendingPathComponent("com.wxside.fastv2", isDirectory: true)
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: appFolderURL, withIntermediateDirectories: true)
        
        storageURL = appFolderURL.appendingPathComponent("meeting_records.json")
        loadRecords()
    }
    
    /// 加载记录
    private func loadRecords() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([MeetingRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// 保存记录
    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else {
            print("❌ [MeetingRecordStorage] 保存记录失败：编码失败")
            return
        }
        
        do {
            try data.write(to: storageURL)
            print("✅ [MeetingRecordStorage] 记录已保存")
        } catch {
            print("❌ [MeetingRecordStorage] 保存记录失败：\(error)")
        }
    }
    
    /// 添加记录
    func add(_ record: MeetingRecord) {
        records.insert(record, at: 0)
        saveRecords()
    }
    
    /// 更新记录
    func update(_ record: MeetingRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            return
        }
        records[index] = record
        saveRecords()
    }
    
    /// 删除记录
    func delete(_ record: MeetingRecord) {
        records.removeAll { $0.id == record.id }
        saveRecords()
    }
    
    /// 删除所有记录
    func deleteAll() {
        records.removeAll()
        saveRecords()
    }
    
    /// 获取记录数量
    func count() -> Int {
        return records.count
    }
    
    /// 获取今日记录数量
    func todayCount() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return records.filter { calendar.startOfDay(for: $0.createdAt) == today }.count
    }
}

