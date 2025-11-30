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
                    tags TEXT,
                    ai_tags TEXT,
                    ai_summary TEXT,
                    ai_priority TEXT,
                    synced_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    is_body_loaded INTEGER NOT NULL DEFAULT 0,
                    FOREIGN KEY(account_id) REFERENCES email_accounts(id) ON DELETE CASCADE,
                    FOREIGN KEY(folder_id) REFERENCES email_folders(id) ON DELETE SET NULL
                )
            """)
            
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
    
    /// 获取数据库队列（用于异步操作）
    func getQueue() -> DatabaseQueue? {
        return dbQueue
    }
    
    /// 执行写入操作
    func write<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        guard let dbQueue = dbQueue else {
            throw EmailDatabaseError.notInitialized
        }
        return try dbQueue.write(block)
    }
    
    /// 执行读取操作
    func read<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        guard let dbQueue = dbQueue else {
            throw EmailDatabaseError.notInitialized
        }
        return try dbQueue.read(block)
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

