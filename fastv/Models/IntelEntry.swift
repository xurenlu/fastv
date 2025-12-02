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
    var keywords: [String]       // 关键词（公司名、主题等）
    var entities: [String: [String]]  // 实体分类（如 {"公司": ["苹果", "英伟达"], "主题": [...]}）
    var date: Date               // 日期（仅按天比较）
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        summary: String,
        body: String,
        sources: [String] = [],
        keywords: [String] = [],
        entities: [String: [String]] = [:],
        date: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.summary = summary
        self.body = body
        self.sources = sources
        self.keywords = keywords
        self.entities = entities
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 更新内容
    mutating func update(summary: String? = nil, body: String? = nil, sources: [String]? = nil, keywords: [String]? = nil, entities: [String: [String]]? = nil) {
        if let summary = summary {
            self.summary = summary
        }
        if let body = body {
            self.body = body
        }
        if let sources = sources {
            self.sources = sources
        }
        if let keywords = keywords {
            self.keywords = keywords
        }
        if let entities = entities {
            self.entities = entities
        }
        self.updatedAt = Date()
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id
        case summary
        case body
        case sources
        case keywords
        case entities
        case date
        case createdAt
        case updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        summary = try container.decode(String.self, forKey: .summary)
        body = try container.decode(String.self, forKey: .body)
        sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        entities = try container.decodeIfPresent([String: [String]].self, forKey: .entities) ?? [:]
        date = try container.decode(Date.self, forKey: .date)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(summary, forKey: .summary)
        try container.encode(body, forKey: .body)
        try container.encode(sources, forKey: .sources)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(entities, forKey: .entities)
        try container.encode(date, forKey: .date)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

