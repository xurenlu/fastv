//
//  EmailSignatureService.swift
//  fastv
//
//  Created for Email Signature Management Service
//

import Foundation
import GRDB

/// 邮件签名管理服务
@MainActor
class EmailSignatureService {
    static let shared = EmailSignatureService()
    
    private let database = EmailDatabase.shared
    
    private init() {}
    
    // MARK: - CRUD Operations
    
    /// 获取账号的所有签名
    func getSignatures(for accountId: UUID) async throws -> [EmailSignature] {
        return try await database.asyncRead { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM email_signatures
                WHERE account_id = ?
                ORDER BY is_default DESC, updated_at DESC
            """, arguments: [accountId.uuidString])
            
            return try rows.map { row in
                try self.parseSignature(from: row)
            }
        }
    }
    
    /// 获取默认签名
    func getDefaultSignature(for accountId: UUID) async throws -> EmailSignature? {
        return try await database.asyncRead { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT * FROM email_signatures
                WHERE account_id = ? AND is_default = 1
                LIMIT 1
            """, arguments: [accountId.uuidString])
            
            guard let row = row else { return nil }
            return try self.parseSignature(from: row)
        }
    }
    
    /// 获取签名
    func getSignature(id: UUID) async throws -> EmailSignature? {
        return try await database.asyncRead { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT * FROM email_signatures
                WHERE id = ?
            """, arguments: [id.uuidString])
            
            guard let row = row else { return nil }
            return try self.parseSignature(from: row)
        }
    }
    
    /// 保存签名
    func saveSignature(_ signature: EmailSignature) async throws {
        var updated = signature
        updated.updatedAt = Date()
        
        try await database.asyncWrite { db in
            try self.saveSignatureToDB(updated, db: db)
            
            // 如果设为默认，取消其他默认签名
            if updated.isDefault {
                try db.execute(sql: """
                    UPDATE email_signatures
                    SET is_default = 0
                    WHERE account_id = ? AND id != ?
                """, arguments: [updated.accountId.uuidString, updated.id.uuidString])
            }
        }
    }
    
    /// 删除签名
    func deleteSignature(id: UUID) async throws {
        try await database.asyncWrite { db in
            try db.execute(sql: """
                DELETE FROM email_signatures
                WHERE id = ?
            """, arguments: [id.uuidString])
        }
    }
    
    /// 设置默认签名
    func setDefaultSignature(id: UUID, accountId: UUID) async throws {
        try await database.asyncWrite { db in
            // 先取消所有默认签名
            try db.execute(sql: """
                UPDATE email_signatures
                SET is_default = 0
                WHERE account_id = ?
            """, arguments: [accountId.uuidString])
            
            // 设置新的默认签名
            try db.execute(sql: """
                UPDATE email_signatures
                SET is_default = 1, updated_at = ?
                WHERE id = ?
            """, arguments: [Date().timeIntervalSince1970, id.uuidString])
        }
    }
    
    // MARK: - Signature Rendering
    
    /// 渲染签名（替换变量）
    func renderSignature(_ signature: EmailSignature, for account: EmailAccount) -> String {
        var content = signature.content
        
        // 替换变量
        content = content.replacingOccurrences(of: SignatureVariable.name.rawValue, with: account.displayName)
        content = content.replacingOccurrences(of: SignatureVariable.email.rawValue, with: account.emailAddress)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        content = content.replacingOccurrences(of: SignatureVariable.date.rawValue, with: dateFormatter.string(from: Date()))
        
        dateFormatter.dateFormat = "HH:mm"
        content = content.replacingOccurrences(of: SignatureVariable.time.rawValue, with: dateFormatter.string(from: Date()))
        
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        content = content.replacingOccurrences(of: SignatureVariable.dateTime.rawValue, with: dateFormatter.string(from: Date()))
        
        return content
    }
    
    /// 将签名插入到邮件正文
    func insertSignature(_ signature: EmailSignature, into body: String, htmlBody: String?, for account: EmailAccount) -> (body: String, htmlBody: String?) {
        let renderedSignature = renderSignature(signature, for: account)
        
        var newBody = body
        var newHtmlBody = htmlBody
        
        if signature.isHtml {
            // HTML签名
            let signatureHtml = "<br><br>\(renderedSignature)"
            if let html = htmlBody {
                newHtmlBody = html + signatureHtml
            } else {
                // 如果没有HTML正文，创建HTML版本
                let escapedBody = body.replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                    .replacingOccurrences(of: "\n", with: "<br>")
                newHtmlBody = escapedBody + signatureHtml
            }
            // 纯文本版本也添加签名（转换为纯文本）
            let plainSignature = renderedSignature.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
            newBody = body + "\n\n" + plainSignature
        } else {
            // 纯文本签名
            newBody = body + "\n\n" + renderedSignature
            if let html = htmlBody {
                let escapedSignature = renderedSignature.replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                    .replacingOccurrences(of: "\n", with: "<br>")
                newHtmlBody = html + "<br><br>" + escapedSignature
            }
        }
        
        return (newBody, newHtmlBody)
    }
    
    // MARK: - Private Helpers
    
    private func saveSignatureToDB(_ signature: EmailSignature, db: Database) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO email_signatures (
                id, account_id, name, content, is_html, is_default, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            signature.id.uuidString,
            signature.accountId.uuidString,
            signature.name,
            signature.content,
            signature.isHtml ? 1 : 0,
            signature.isDefault ? 1 : 0,
            signature.createdAt.timeIntervalSince1970,
            signature.updatedAt.timeIntervalSince1970
        ])
    }
    
    private func parseSignature(from row: Row) throws -> EmailSignature {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let accountIdString = row["account_id"] as? String,
              let accountId = UUID(uuidString: accountIdString),
              let name = row["name"] as? String,
              let content = row["content"] as? String else {
            throw EmailDatabaseError.invalidData
        }
        
        let isHtml = (row["is_html"] as? Int64 ?? 0) != 0
        let isDefault = (row["is_default"] as? Int64 ?? 0) != 0
        let createdAt = Date(timeIntervalSince1970: row["created_at"] as? Double ?? 0)
        let updatedAt = Date(timeIntervalSince1970: row["updated_at"] as? Double ?? 0)
        
        return EmailSignature(
            id: id,
            accountId: accountId,
            name: name,
            content: content,
            isHtml: isHtml,
            isDefault: isDefault,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

