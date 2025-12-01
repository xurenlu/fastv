//
//  ExpenseItem.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// 记账类型
enum ExpenseType: String, Codable, CaseIterable {
    case income = "income"       // 收入
    case expense = "expense"     // 支出
    case transfer = "transfer"   // 转账
    
    var displayName: String {
        switch self {
        case .income:
            return "收入"
        case .expense:
            return "支出"
        case .transfer:
            return "转账"
        }
    }
    
    var icon: String {
        switch self {
        case .income:
            return "arrow.down.circle.fill"
        case .expense:
            return "arrow.up.circle.fill"
        case .transfer:
            return "arrow.left.arrow.right.circle.fill"
        }
    }
}

/// 记账条目
struct ExpenseItem: Identifiable, Codable {
    let id: UUID
    var amount: Decimal
    var type: ExpenseType
    var categoryId: UUID
    var note: String?
    var date: Date
    var imageData: Data?        // 票据图片（可选）
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        amount: Decimal,
        type: ExpenseType,
        categoryId: UUID,
        note: String? = nil,
        date: Date = Date(),
        imageData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.type = type
        self.categoryId = categoryId
        self.note = note
        self.date = date
        self.imageData = imageData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 更新信息
    mutating func update(
        amount: Decimal? = nil,
        type: ExpenseType? = nil,
        categoryId: UUID? = nil,
        note: String? = nil,
        date: Date? = nil
    ) {
        if let amount = amount {
            self.amount = amount
        }
        if let type = type {
            self.type = type
        }
        if let categoryId = categoryId {
            self.categoryId = categoryId
        }
        if let note = note {
            self.note = note
        }
        if let date = date {
            self.date = date
        }
        self.updatedAt = Date()
    }
}

/// 记账分类
struct ExpenseCategory: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String            // SF Symbol 名称
    var color: String           // Hex 颜色
    var isDefault: Bool
    var type: ExpenseType       // 归属类型
    var order: Int              // 排序顺序
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        color: String,
        isDefault: Bool = false,
        type: ExpenseType,
        order: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.isDefault = isDefault
        self.type = type
        self.order = order
        self.createdAt = createdAt
    }
}

