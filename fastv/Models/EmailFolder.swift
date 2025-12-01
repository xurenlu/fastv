//
//  EmailFolder.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 邮件文件夹类型
enum EmailFolderType: String, Codable {
    case inbox = "inbox"
    case sent = "sent"
    case drafts = "drafts"
    case trash = "trash"
    case spam = "spam"
    case archive = "archive"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .inbox:
            return "收件箱"
        case .sent:
            return "已发送"
        case .drafts:
            return "草稿"
        case .trash:
            return "已删除"
        case .spam:
            return "垃圾邮件"
        case .archive:
            return "归档"
        case .custom:
            return "自定义"
        }
    }
    
    var icon: String {
        switch self {
        case .inbox:
            return "tray.fill"
        case .sent:
            return "paperplane.fill"
        case .drafts:
            return "doc.text.fill"
        case .trash:
            return "trash.fill"
        case .spam:
            return "exclamationmark.triangle.fill"
        case .archive:
            return "archivebox.fill"
        case .custom:
            return "folder.fill"
        }
    }
}

/// 邮件文件夹模型
struct EmailFolder: Identifiable, Codable {
    let id: UUID
    let accountId: UUID
    var name: String
    var type: EmailFolderType
    var path: String // IMAP路径
    var unreadCount: Int
    var totalCount: Int
    var lastSyncDate: Date?
    
    init(
        id: UUID = UUID(),
        accountId: UUID,
        name: String,
        type: EmailFolderType = .custom,
        path: String = "",
        unreadCount: Int = 0,
        totalCount: Int = 0,
        lastSyncDate: Date? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.type = type
        self.path = path.isEmpty ? name : path
        self.unreadCount = unreadCount
        self.totalCount = totalCount
        self.lastSyncDate = lastSyncDate
    }
}

extension EmailFolder {
    /// 适合展示的名称（去掉 Gmail 前缀等）
    var displayTitle: String {
        if name.contains("/") {
            return name.split(separator: "/").last.map(String.init) ?? name
        }
        return name
    }
    
    /// 判断是否包含未正确解码的乱码
    var isGarbled: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        
        if trimmed.contains("=?") || trimmed.contains("?=") {
            return true
        }
        
        let pattern = #"&[A-Za-z0-9+,/]+-"#
        if trimmed.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
}

