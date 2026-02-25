//
//  GmailAPIService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// Gmail API 服务
/// 使用 Gmail REST API 实现邮件收发功能
/// 文档：https://developers.google.com/gmail/api
@MainActor
class GmailAPIService {
    static let shared = GmailAPIService()
    
    private let baseURL = "https://gmail.googleapis.com/gmail/v1"
    private var accessToken: String?
    
    private init() {}
    
    /// 设置访问令牌（OAuth 2.0）
    func setAccessToken(_ token: String) {
        accessToken = token
    }
    
    /// 获取邮件列表
    func fetchMessages(userId: String = "me", maxResults: Int = 50, pageToken: String? = nil) async throws -> GmailMessagesResponse {
        var urlString = "\(baseURL)/users/\(userId)/messages?maxResults=\(maxResults)"
        if let pageToken = pageToken {
            urlString += "&pageToken=\(pageToken)"
        }
        
        guard let url = URL(string: urlString),
              let token = accessToken else {
            throw GmailAPIError.missingToken
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GmailAPIError.requestFailed(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(GmailMessagesResponse.self, from: data)
    }
    
    /// 获取邮件详情
    func fetchMessage(userId: String = "me", messageId: String) async throws -> GmailMessage {
        let urlString = "\(baseURL)/users/\(userId)/messages/\(messageId)?format=full"
        
        guard let url = URL(string: urlString),
              let token = accessToken else {
            throw GmailAPIError.missingToken
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        return try JSONDecoder().decode(GmailMessage.self, from: data)
    }
    
    /// 发送邮件
    func sendMessage(userId: String = "me", rawMessage: String) async throws -> GmailSendResponse {
        let urlString = "\(baseURL)/users/\(userId)/messages/send"
        
        guard let url = URL(string: urlString),
              let token = accessToken else {
            throw GmailAPIError.missingToken
        }
        
        let body: [String: Any] = ["raw": rawMessage]
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        return try JSONDecoder().decode(GmailSendResponse.self, from: data)
    }
    
    /// 获取文件夹列表
    func fetchLabels(userId: String = "me") async throws -> GmailLabelsResponse {
        let urlString = "\(baseURL)/users/\(userId)/labels"
        
        guard let url = URL(string: urlString),
              let token = accessToken else {
            throw GmailAPIError.missingToken
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailAPIError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        return try JSONDecoder().decode(GmailLabelsResponse.self, from: data)
    }
}

// MARK: - Gmail API Models

struct GmailMessagesResponse: Codable {
    let messages: [GmailMessageReference]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct GmailMessageReference: Codable {
    let id: String
    let threadId: String
}

struct GmailMessage: Codable {
    let id: String
    let threadId: String
    let labelIds: [String]
    let snippet: String
    let payload: GmailMessagePayload
    let sizeEstimate: Int
    let historyId: String
    let internalDate: String
}

struct GmailMessagePayload: Codable {
    let partId: String?
    let mimeType: String?
    let filename: String?
    let headers: [GmailHeader]
    let body: GmailBody?
    let parts: [GmailMessagePayload]?
}

struct GmailHeader: Codable {
    let name: String
    let value: String
}

struct GmailBody: Codable {
    let attachmentId: String?
    let size: Int?
    let data: String? // Base64 encoded
}

struct GmailSendResponse: Codable {
    let id: String
    let threadId: String
    let labelIds: [String]
}

struct GmailLabelsResponse: Codable {
    let labels: [GmailLabel]
}

struct GmailLabel: Codable {
    let id: String
    let name: String
    let type: String // "system" or "user"
    let messageListVisibility: String?
    let labelListVisibility: String?
}

enum GmailAPIError: LocalizedError {
    case missingToken
    case invalidResponse
    case requestFailed(Int)
    case decodeError
    
    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "缺少访问令牌"
        case .invalidResponse:
            return "无效的响应"
        case .requestFailed(let code):
            return "请求失败，状态码: \(code)"
        case .decodeError:
            return "数据解析失败"
        }
    }
}

