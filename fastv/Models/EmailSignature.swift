//
//  EmailSignature.swift
//  fastv
//
//  Created for Email Signature Management
//

import Foundation

/// 邮件签名模型
struct EmailSignature: Identifiable, Codable {
    let id: UUID
    let accountId: UUID
    var name: String
    var content: String // 签名内容（HTML或纯文本）
    var isHtml: Bool // 是否为HTML格式
    var isDefault: Bool // 是否为默认签名
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        accountId: UUID,
        name: String,
        content: String,
        isHtml: Bool = false,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.content = content
        self.isHtml = isHtml
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 签名变量（用于替换）
enum SignatureVariable: String, CaseIterable {
    case name = "{{name}}"
    case email = "{{email}}"
    case company = "{{company}}"
    case phone = "{{phone}}"
    case title = "{{title}}"
    case position = "{{position}}"
    case website = "{{website}}"
    case address = "{{address}}"
    case date = "{{date}}"
    case time = "{{time}}"
    case dateTime = "{{datetime}}"
    
    var displayName: String {
        switch self {
        case .name:
            return "姓名"
        case .email:
            return "邮箱地址"
        case .company:
            return "公司名称"
        case .phone:
            return "电话号码"
        case .title:
            return "职位/头衔"
        case .position:
            return "职位（同title）"
        case .website:
            return "网站地址"
        case .address:
            return "公司地址"
        case .date:
            return "日期"
        case .time:
            return "时间"
        case .dateTime:
            return "日期时间"
        }
    }
    
    var description: String {
        switch self {
        case .name:
            return "发件人显示名称"
        case .email:
            return "发件人邮箱地址"
        case .company:
            return "公司或组织名称"
        case .phone:
            return "联系电话号码"
        case .title:
            return "职位或头衔（如：产品经理、CEO等）"
        case .position:
            return "职位（与title相同）"
        case .website:
            return "公司或个人网站地址"
        case .address:
            return "公司或办公地址"
        case .date:
            return "当前日期（YYYY-MM-DD）"
        case .time:
            return "当前时间（HH:mm）"
        case .dateTime:
            return "当前日期时间"
        }
    }
}

