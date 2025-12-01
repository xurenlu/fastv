//
//  EmailDatabase.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import GRDB

/// 邮箱数据库管理器
class EmailDatabase {
    static let shared = EmailDatabase()
    
    private var dbQueue: DatabaseQueue?
    private let dbPath: String
    
    private init() {
        // 数据库文件路径
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDirectory = appSupport.appendingPathComponent("fastv/Email")
        
        // 创建目录（如果不存在）
        try? FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        
        dbPath = dbDirectory.appendingPathComponent("email.db").path
        
        // 初始化数据库
        do {
            dbQueue = try DatabaseQueue(path: dbPath)
            try setupDatabase()
        } catch {
            print("❌ [EmailDatabase] 初始化数据库失败: \(error)")
        }
    }
    
    /// 设置数据库表结构
    private func setupDatabase() throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            // 创建账号表
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS email_accounts (
                    id TEXT PRIMARY KEY,
                    email_address TEXT NOT NULL,
                    display_name TEXT,
                    service_type TEXT NOT NULL,
                    imap_host TEXT NOT NULL,
                    imap_port INTEGER NOT NULL,
                    imap_encryption TEXT NOT NULL,
                    smtp_host TEXT NOT NULL,
                    smtp_port INTEGER NOT NULL,
                    smtp_encryption TEXT NOT NULL,
                    is_enabled INTEGER NOT NULL DEFAULT 1,
                    is_default INTEGER NOT NULL DEFAULT 0,
                    last_sync_date REAL,
                    connection_status TEXT NOT NULL DEFAULT 'disconnected',
                    password_keychain_identifier TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                )
            """)
            
            // 创建文件夹表
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS email_folders (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    type TEXT NOT NULL,
                    path TEXT NOT NULL,
                    unread_count INTEGER NOT NULL DEFAULT 0,
                    total_count INTEGER NOT NULL DEFAULT 0,
                    last_sync_date REAL,
                    FOREIGN KEY(account_id) REFERENCES email_accounts(id) ON DELETE CASCADE
                )
            """)
            
            // 创建邮件表
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS email_messages (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    folder_id TEXT,
                    uid INTEGER,
                    message_id TEXT,
                    thread_id TEXT,
                    subject TEXT NOT NULL,
                    from_name TEXT,
                    from_email TEXT NOT NULL,
                    to_contacts TEXT,
                    cc_contacts TEXT,
                    bcc_contacts TEXT,
                    reply_to_contacts TEXT,
                    text_body TEXT,
                    html_body TEXT,
                    preview TEXT,
                    date REAL NOT NULL,
                    received_date REAL,
                    is_read INTEGER NOT NULL DEFAULT 0,
                    is_starred INTEGER NOT NULL DEFAULT 0,
                    is_important INTEGER NOT NULL DEFAULT 0,
                    is_no_reply INTEGER NOT NULL DEFAULT 0,
                    has_attachments INTEGER NOT NULL DEFAULT 0,
                    is_spam INTEGER NOT NULL DEFAULT 0,
                    is_deleted INTEGER NOT NULL DEFAULT 0,
                    contains_remote_resources INTEGER NOT NULL DEFAULT 0,
                    tags TEXT,
                    ai_tags TEXT,
                    ai_summary TEXT,
                    ai_priority TEXT,
                    synced_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    is_body_loaded INTEGER NOT NULL DEFAULT 0,
                    body_cached_at REAL,
                    FOREIGN KEY(account_id) REFERENCES email_accounts(id) ON DELETE CASCADE,
                    FOREIGN KEY(folder_id) REFERENCES email_folders(id) ON DELETE SET NULL
                )
            """)
            
            // 迁移：添加新字段（如果表已存在）
            try migrateDatabase(db: db)
            
            // 创建附件表
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS email_attachments (
                    id TEXT PRIMARY KEY,
                    message_id TEXT NOT NULL,
                    filename TEXT NOT NULL,
                    mime_type TEXT NOT NULL,
                    size INTEGER NOT NULL DEFAULT 0,
                    content_id TEXT,
                    is_inline INTEGER NOT NULL DEFAULT 0,
                    local_path TEXT,
                    FOREIGN KEY(message_id) REFERENCES email_messages(id) ON DELETE CASCADE
                )
            """)
            
            // 创建索引
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_messages_account_folder ON email_messages(account_id, folder_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_messages_date ON email_messages(date DESC)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_messages_thread ON email_messages(thread_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_messages_uid ON email_messages(account_id, folder_id, uid)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_folders_account ON email_folders(account_id)")
        }
    }
    
    /// 数据库迁移：添加新字段
    private func migrateDatabase(db: Database) throws {
        guard try db.tableExists("email_messages") else { return }
        
        // 检查列是否存在（通过尝试查询来判断）
        let columns = try db.columns(in: "email_messages")
        let columnNames = Set(columns.map { $0.name })
        
        // 添加 is_spam 字段
        if !columnNames.contains("is_spam") {
            try db.execute(sql: "ALTER TABLE email_messages ADD COLUMN is_spam INTEGER NOT NULL DEFAULT 0")
        }
        
        // 添加 is_deleted 字段
        if !columnNames.contains("is_deleted") {
            try db.execute(sql: "ALTER TABLE email_messages ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0")
        }
        
        // 添加 contains_remote_resources 字段
        if !columnNames.contains("contains_remote_resources") {
            try db.execute(sql: "ALTER TABLE email_messages ADD COLUMN contains_remote_resources INTEGER NOT NULL DEFAULT 0")
        }
        
        // 添加 body_cached_at 字段（正文缓存时间）
        if !columnNames.contains("body_cached_at") {
            try db.execute(sql: "ALTER TABLE email_messages ADD COLUMN body_cached_at REAL")
        }
    }
    
    /// 获取数据库队列（用于异步操作）
    func getQueue() -> DatabaseQueue? {
        return dbQueue
    }
    
    /// 执行写入操作(同步)
    func write<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        guard let dbQueue = dbQueue else {
            throw EmailDatabaseError.notInitialized
        }
        return try dbQueue.write(block)
    }
    
    /// 执行写入操作(异步,不阻塞调用线程)
    func asyncWrite<T: Sendable>(_ block: @escaping @Sendable (Database) throws -> T) async throws -> T {
        guard let dbQueue = dbQueue else {
            throw EmailDatabaseError.notInitialized
        }
        // 使用 Task.detached 确保在后台线程执行
        return try await Task.detached(priority: .utility) {
            try dbQueue.write(block)
        }.value
    }
    
    /// 执行读取操作(同步)
    func read<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        guard let dbQueue = dbQueue else {
            throw EmailDatabaseError.notInitialized
        }
        return try dbQueue.read(block)
    }
    
    /// 执行读取操作(异步,不阻塞调用线程)
    func asyncRead<T: Sendable>(_ block: @escaping @Sendable (Database) throws -> T) async throws -> T {
        guard let dbQueue = dbQueue else {
            throw EmailDatabaseError.notInitialized
        }
        // 使用 Task.detached 确保在后台线程执行
        return try await Task.detached(priority: .utility) {
            try dbQueue.read(block)
        }.value
    }
}

enum EmailDatabaseError: Error {
    case notInitialized
    case invalidData
    
    var localizedDescription: String {
        switch self {
        case .notInitialized:
            return "数据库未初始化"
        case .invalidData:
            return "无效的数据"
        }
    }
}

// MARK: - GRDB Codable支持
// 注意：EmailAccount, EmailFolder, EmailMessage 等类型已经在定义时声明了 Codable
// 这里不需要再次声明，Swift 会自动合成 Codable 实现

