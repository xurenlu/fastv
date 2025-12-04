//
//  EmailRuleService.swift
//  fastv
//
//  Created for Email Rule Management Service
//

import Foundation
import GRDB

/// 邮件规则管理服务
@MainActor
class EmailRuleService {
    static let shared = EmailRuleService()
    
    private let database = EmailDatabase.shared
    private let ruleEngine = EmailRuleEngine.shared
    
    private init() {}
    
    // MARK: - CRUD Operations
    
    /// 获取账号的所有规则
    func getRules(for accountId: UUID) async throws -> [EmailRule] {
        return try await database.asyncRead { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM email_rules
                WHERE account_id = ?
                ORDER BY created_at DESC
            """, arguments: [accountId.uuidString])
            
            return try rows.map { row in
                try self.parseRule(from: row)
            }
        }
    }
    
    /// 获取规则
    func getRule(id: UUID) async throws -> EmailRule? {
        return try await database.asyncRead { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT * FROM email_rules
                WHERE id = ?
            """, arguments: [id.uuidString])
            
            guard let row = row else { return nil }
            return try self.parseRule(from: row)
        }
    }
    
    /// 保存规则
    func saveRule(_ rule: EmailRule) async throws {
        var updated = rule
        updated.updatedAt = Date()
        
        try await database.asyncWrite { db in
            try self.saveRuleToDB(updated, db: db)
        }
        
        // 重新加载规则引擎
        await ruleEngine.loadRules()
    }
    
    /// 删除规则
    func deleteRule(id: UUID) async throws {
        try await database.asyncWrite { db in
            try db.execute(sql: """
                DELETE FROM email_rules
                WHERE id = ?
            """, arguments: [id.uuidString])
        }
        
        // 重新加载规则引擎
        await ruleEngine.loadRules()
    }
    
    /// 应用规则到邮件
    func applyRules(to message: EmailMessage) async throws -> EmailMessage {
        guard let accountId = message.accountId as UUID? else {
            return message
        }
        
        let rules = try await getRules(for: accountId)
        var updatedMessage = message
        
        for rule in rules where rule.isEnabled {
            if matchesConditions(rule.conditions, message: message) {
                updatedMessage = applyActions(rule.actions, to: updatedMessage)
            }
        }
        
        return updatedMessage
    }
    
    // MARK: - Rule Matching
    
    private func matchesConditions(_ conditions: RuleConditions, message: EmailMessage) -> Bool {
        if let fromContains = conditions.fromContains, !fromContains.isEmpty {
            if !message.from.email.localizedCaseInsensitiveContains(fromContains) &&
               !(message.from.name?.localizedCaseInsensitiveContains(fromContains) ?? false) {
                return false
            }
        }
        
        if let subjectContains = conditions.subjectContains, !subjectContains.isEmpty {
            if !message.subject.localizedCaseInsensitiveContains(subjectContains) {
                return false
            }
        }
        
        if let bodyContains = conditions.bodyContains, !bodyContains.isEmpty {
            let body = (message.textBody ?? "") + (message.htmlBody ?? "")
            if !body.localizedCaseInsensitiveContains(bodyContains) {
                return false
            }
        }
        
        if let hasAttachments = conditions.hasAttachments {
            if message.hasAttachments != hasAttachments {
                return false
            }
        }
        
        if let isRead = conditions.isRead {
            if message.isRead != isRead {
                return false
            }
        }
        
        if let folderId = conditions.folderId {
            if message.folderId != folderId {
                return false
            }
        }
        
        return true
    }
    
    private func applyActions(_ actions: RuleActions, to message: EmailMessage) -> EmailMessage {
        var updated = message
        
        if let markAsRead = actions.markAsRead {
            updated.isRead = markAsRead
        }
        
        if let markAsImportant = actions.markAsImportant {
            updated.isImportant = markAsImportant
        }
        
        if let markAsSpam = actions.markAsSpam {
            updated.isSpam = markAsSpam
        }
        
        // Note: folderId is a let constant, so we cannot modify it directly.
        // Moving messages to folders should be handled by EmailService instead.
        // if let moveToFolder = actions.moveToFolder {
        //     updated.folderId = moveToFolder
        // }
        
        for tag in actions.addTags {
            if !updated.tags.contains(tag) {
                updated.tags.append(tag)
            }
        }
        
        if actions.delete == true {
            updated.isDeleted = true
        }
        
        return updated
    }
    
    // MARK: - Private Helpers
    
    private func saveRuleToDB(_ rule: EmailRule, db: Database) throws {
        let conditionsData = try JSONEncoder().encode(rule.conditions)
        let conditionsString = String(data: conditionsData, encoding: .utf8) ?? "{}"
        
        let actionsData = try JSONEncoder().encode(rule.actions)
        let actionsString = String(data: actionsData, encoding: .utf8) ?? "{}"
        
        try db.execute(sql: """
            INSERT OR REPLACE INTO email_rules (
                id, account_id, name, conditions, actions,
                is_enabled, lua_code, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            rule.id.uuidString,
            rule.accountId.uuidString,
            rule.name,
            conditionsString,
            actionsString,
            rule.isEnabled ? 1 : 0,
            rule.luaCode,
            rule.createdAt.timeIntervalSince1970,
            rule.updatedAt.timeIntervalSince1970
        ])
    }
    
    private func parseRule(from row: Row) throws -> EmailRule {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let accountIdString = row["account_id"] as? String,
              let accountId = UUID(uuidString: accountIdString),
              let name = row["name"] as? String,
              let conditionsString = row["conditions"] as? String,
              let actionsString = row["actions"] as? String else {
            throw EmailDatabaseError.invalidData
        }
        
        let conditionsData = conditionsString.data(using: .utf8) ?? Data()
        let conditions = (try? JSONDecoder().decode(RuleConditions.self, from: conditionsData)) ?? RuleConditions()
        
        let actionsData = actionsString.data(using: .utf8) ?? Data()
        let actions = (try? JSONDecoder().decode(RuleActions.self, from: actionsData)) ?? RuleActions()
        
        let isEnabled = (row["is_enabled"] as? Int64 ?? 0) != 0
        let luaCode = row["lua_code"] as? String
        let createdAt = Date(timeIntervalSince1970: row["created_at"] as? Double ?? 0)
        let updatedAt = Date(timeIntervalSince1970: row["updated_at"] as? Double ?? 0)
        
        return EmailRule(
            id: id,
            accountId: accountId,
            name: name,
            conditions: conditions,
            actions: actions,
            isEnabled: isEnabled,
            luaCode: luaCode,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

