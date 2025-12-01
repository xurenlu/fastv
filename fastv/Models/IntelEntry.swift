//
//  IntelEntry.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// 情报条目
struct IntelEntry: Identifiable, Codable {
    let id: UUID
    var summary: String          // 概要
    var body: String             // 完整正文
    var sources: [String]         // 情报来源标签
    var date: Date               // 日期（仅按天比较）
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        summary: String,
        body: String,
        sources: [String] = [],
        date: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.summary = summary
        self.body = body
        self.sources = sources
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 更新内容
    mutating func update(summary: String? = nil, body: String? = nil, sources: [String]? = nil) {
        if let summary = summary {
            self.summary = summary
        }
        if let body = body {
            self.body = body
        }
        if let sources = sources {
            self.sources = sources
        }
        self.updatedAt = Date()
    }
}

