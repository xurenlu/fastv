//
//  GoogleOAuthService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import AppKit
import AuthenticationServices

/// Google OAuth 2.0 认证服务
/// 用于获取 Gmail API 访问令牌
@MainActor
class GoogleOAuthService {
    static let shared = GoogleOAuthService()
    
    // Gmail API 需要的权限范围
    let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/gmail.modify"
    ]
    
    // 需要从 Google Cloud Console 获取
    var clientId: String = "" // 需要配置
    var clientSecret: String = "" // 需要配置
    var redirectURI: String = "com.fastv:/oauth/callback"
    
    private init() {}
    
    /// 启动 OAuth 流程
    func startOAuthFlow() async throws -> String {
        // 构建授权 URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"), // 获取 refresh token
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        guard let authURL = components.url else {
            throw OAuthError.invalidURL
        }
        
        // 在浏览器中打开授权页面
        NSWorkspace.shared.open(authURL)
        
        // 等待回调（实际实现需要使用 URL scheme 或本地服务器）
        // 这里简化处理，实际需要监听 redirect URI
        throw OAuthError.notImplemented("需要实现 OAuth 回调处理")
    }
    
    /// 使用授权码交换访问令牌
    func exchangeCodeForToken(_ code: String) async throws -> OAuthTokenResponse {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuthError.tokenExchangeFailed
        }
        
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }
}

struct OAuthTokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

enum OAuthError: LocalizedError {
    case invalidURL
    case notImplemented(String)
    case tokenExchangeFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .notImplemented(let message):
            return "未实现: \(message)"
        case .tokenExchangeFailed:
            return "令牌交换失败"
        }
    }
}

