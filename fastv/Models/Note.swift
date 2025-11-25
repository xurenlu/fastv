//
//  Note.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 笔记模型
struct Note: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var content: String
    let createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), title: String, content: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 从语音输入创建笔记
    static func fromVoiceInput(_ text: String) -> Note {
        // 使用前30个字符作为标题
        let title = String(text.prefix(30))
        return Note(
            title: title.isEmpty ? "无标题" : title,
            content: text
        )
    }
}

/// 笔记管理器
@MainActor
class NoteManager: ObservableObject {
    static let shared = NoteManager()
    
    @Published private(set) var notes: [Note] = []
    
    private let storageKey = "voiceNotes"
    private let storageURL: URL
    
    private init() {
        // 存储路径：~/Library/Application Support/com.wxside.fastv2/notes.json
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolderURL = appSupportURL.appendingPathComponent("com.wxside.fastv2", isDirectory: true)
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: appFolderURL, withIntermediateDirectories: true)
        
        storageURL = appFolderURL.appendingPathComponent("notes.json")
        loadNotes()
    }
    
    /// 加载笔记
    private func loadNotes() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else {
            notes = []
            return
        }
        notes = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    /// 保存笔记
    private func saveNotes() {
        guard let data = try? JSONEncoder().encode(notes) else {
            print("❌ [NoteManager] 保存笔记失败：编码失败")
            return
        }
        
        do {
            try data.write(to: storageURL)
            print("✅ [NoteManager] 笔记已保存")
        } catch {
            print("❌ [NoteManager] 保存笔记失败：\(error)")
        }
    }
    
    /// 添加笔记
    func add(_ note: Note) {
        notes.insert(note, at: 0) // 插入到最前面
        saveNotes()
    }
    
    /// 更新笔记
    func update(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else {
            return
        }
        var updatedNote = note
        updatedNote = Note(
            id: note.id,
            title: note.title,
            content: note.content,
            createdAt: note.createdAt,
            updatedAt: Date()
        )
        notes[index] = updatedNote
        saveNotes()
    }
    
    /// 删除笔记
    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        saveNotes()
    }
    
    /// 删除所有笔记
    func deleteAll() {
        notes.removeAll()
        saveNotes()
    }
    
    /// 获取笔记数量
    func count() -> Int {
        return notes.count
    }
    
    /// 获取今日笔记数量
    func todayCount() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return notes.filter { calendar.startOfDay(for: $0.createdAt) == today }.count
    }
}

