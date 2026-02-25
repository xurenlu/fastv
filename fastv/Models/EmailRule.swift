//
//  EmailRule.swift
//  fastv
//
//  Created for Email Rule Management
//

import Foundation

/// 邮件规则模型
struct EmailRule: Identifiable, Codable {
    let id: UUID
    let accountId: UUID
    var name: String
    var conditions: RuleConditions
    var actions: RuleActions
    var isEnabled: Bool
    var luaCode: String? // 自定义Lua代码（可选）
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        accountId: UUID,
        name: String,
        conditions: RuleConditions = RuleConditions(),
        actions: RuleActions = RuleActions(),
        isEnabled: Bool = true,
        luaCode: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.conditions = conditions
        self.actions = actions
        self.isEnabled = isEnabled
        self.luaCode = luaCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 规则条件
struct RuleConditions: Codable {
    var fromContains: String?
    var subjectContains: String?
    var bodyContains: String?
    var hasAttachments: Bool?
    var isRead: Bool?
    var folderId: UUID?
    
    init(
        fromContains: String? = nil,
        subjectContains: String? = nil,
        bodyContains: String? = nil,
        hasAttachments: Bool? = nil,
        isRead: Bool? = nil,
        folderId: UUID? = nil
    ) {
        self.fromContains = fromContains
        self.subjectContains = subjectContains
        self.bodyContains = bodyContains
        self.hasAttachments = hasAttachments
        self.isRead = isRead
        self.folderId = folderId
    }
}

/// 规则动作
struct RuleActions: Codable {
    var markAsRead: Bool?
    var markAsImportant: Bool?
    var markAsSpam: Bool?
    var moveToFolder: UUID?
    var addTags: [String]
    var delete: Bool?
    
    init(
        markAsRead: Bool? = nil,
        markAsImportant: Bool? = nil,
        markAsSpam: Bool? = nil,
        moveToFolder: UUID? = nil,
        addTags: [String] = [],
        delete: Bool? = nil
    ) {
        self.markAsRead = markAsRead
        self.markAsImportant = markAsImportant
        self.markAsSpam = markAsSpam
        self.moveToFolder = moveToFolder
        self.addTags = addTags
        self.delete = delete
    }
}

