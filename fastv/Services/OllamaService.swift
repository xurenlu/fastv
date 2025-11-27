//
//  OllamaService.swift
//  fastv
//
//  Created by rocky on 2025/11/21.
//

import Foundation
import AppKit

/// Ollama AI 服务
@MainActor
class OllamaService {
    static let shared = OllamaService()
    
    private init() {}
    
    /// 优化转录文本
    /// - Parameters:
    ///   - text: 原始转录文本
    ///   - endpoint: API 端点地址
    ///   - model: 使用的模型名称
    ///   - apiToken: API Token（可选）
    ///   - timeout: 超时时间（秒）
    ///   - systemPrompt: 系统提示词
    /// - Returns: 优化后的文本
    func optimizeTranscript(
        text: String,
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 5.0,
        systemPrompt: String
    ) async throws -> String {
        print("🤖 [OllamaService] 开始优化文本，长度: \(text.count)")
        print("🤖 [OllamaService] API 端点: \(endpoint)")
        print("🤖 [OllamaService] 模型: \(model)")
        
        // 构建请求体
        let requestBody: [String: Any] = [
            "model": model,
            "prompt": text,
            "system": systemPrompt,
            "stream": false,
            "options": [
                "temperature": 0.3,  // 较低的温度使输出更确定
                "top_p": 0.9
            ]
        ]
        
        // 构建 URL
        guard let url = URL(string: "\(endpoint)/api/generate") else {
            throw OllamaError.invalidEndpoint
        }
        
        // 构建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 如果有 API Token，添加到请求头
        if let token = apiToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // 设置请求体
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // 设置超时时间
        request.timeoutInterval = timeout
        
        print("🤖 [OllamaService] 发送请求到 Ollama（超时: \(timeout)秒）...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        
        print("🤖 [OllamaService] 收到响应，状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [OllamaService] 请求失败: \(errorMessage)")
            throw OllamaError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? String else {
            print("❌ [OllamaService] 无法解析响应")
            throw OllamaError.invalidResponse
        }
        
        // 直接使用返回的文本，不需要解析 JSON
        let optimizedText = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("✅ [OllamaService] 文本优化完成，优化后长度: \(optimizedText.count)")
        
        return optimizedText
    }
    
    /// 测试 API 连接
    func testConnection(endpoint: String, apiToken: String?) async throws -> Bool {
        print("🤖 [OllamaService] 测试连接: \(endpoint)")
        
        guard let url = URL(string: "\(endpoint)/api/tags") else {
            throw OllamaError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let token = apiToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.timeoutInterval = 10
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        
        print("🤖 [OllamaService] 连接测试响应状态码: \(httpResponse.statusCode)")
        
        return httpResponse.statusCode == 200
    }
    
    /// 测试文本优化功能（发送实际文本测试）
    /// - Parameters:
    ///   - endpoint: API 端点地址
    ///   - model: 使用的模型名称
    ///   - apiToken: API Token（可选）
    ///   - timeout: 超时时间（秒）
    ///   - systemPrompt: 系统提示词
    /// - Returns: (优化后的文本, 耗时)
    func testOptimization(
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval,
        systemPrompt: String
    ) async throws -> (optimizedText: String, duration: TimeInterval) {
        print("🤖 [OllamaService] 测试文本优化功能")
        
        // 使用一个简单的测试文本
        let testText = "嗯那个我今天想去超市买点东西然后呢顺便看看有没有什么优惠活动"
        
        let startTime = Date()
        
        let optimizedText = try await optimizeTranscript(
            text: testText,
            endpoint: endpoint,
            model: model,
            apiToken: apiToken,
            timeout: timeout,
            systemPrompt: systemPrompt
        )
        
        let duration = Date().timeIntervalSince(startTime)
        
        print("✅ [OllamaService] 测试完成，耗时: \(String(format: "%.2f", duration))秒")
        print("📝 [OllamaService] 原文: \(testText)")
        print("📝 [OllamaService] 优化后: \(optimizedText)")
        
        return (optimizedText, duration)
    }
    
    /// 获取可用的模型列表
    func fetchModels(endpoint: String, apiToken: String?) async throws -> [String] {
        print("🤖 [OllamaService] 获取模型列表: \(endpoint)")
        
        guard let url = URL(string: "\(endpoint)/api/tags") else {
            throw OllamaError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let token = apiToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed(httpResponse.statusCode, "获取模型列表失败")
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw OllamaError.invalidResponse
        }
        
        let modelNames = models.compactMap { $0["name"] as? String }
        print("✅ [OllamaService] 获取到 \(modelNames.count) 个模型")
        
        return modelNames
    }
    
    /// 分析图片内容（使用视觉模型）
    /// - Parameters:
    ///   - image: 要分析的图片
    ///   - prompt: 分析提示词
    ///   - endpoint: API 端点地址
    ///   - model: 视觉模型名称（如 llava, qwen-vl）
    ///   - apiToken: API Token（可选）
    ///   - timeout: 超时时间（秒）
    /// - Returns: AI 对图片的描述和分析
    func analyzeImage(
        image: NSImage,
        prompt: String,
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 30.0
    ) async throws -> String {
        print("🤖 [OllamaService] 开始分析图片，模型: \(model)")
        
        // 将 NSImage 转换为 base64
        guard let imageData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: imageData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw OllamaError.invalidImage
        }
        
        let base64Image = pngData.base64EncodedString()
        
        // 构建请求体（Ollama 视觉模型格式）
        let requestBody: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "images": [base64Image],
            "stream": false,
            "options": [
                "temperature": 0.2,  // 较低温度以获得更确定的描述
                "top_p": 0.9
            ]
        ]
        
        // 构建 URL
        guard let url = URL(string: "\(endpoint)/api/generate") else {
            throw OllamaError.invalidEndpoint
        }
        
        // 构建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 如果有 API Token，添加到请求头
        if let token = apiToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // 设置请求体
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // 设置超时时间（视觉模型通常需要更长时间）
        request.timeoutInterval = timeout
        
        print("🤖 [OllamaService] 发送图片分析请求（超时: \(timeout)秒）...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        
        print("🤖 [OllamaService] 收到响应，状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [OllamaService] 请求失败: \(errorMessage)")
            throw OllamaError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            print("❌ [OllamaService] 无法解析响应")
            throw OllamaError.invalidResponse
        }
        
        let analysis = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("✅ [OllamaService] 图片分析完成，描述长度: \(analysis.count)")
        
        return analysis
    }
    
    /// 比较两张图片的差异（使用视觉模型）
    /// - Parameters:
    ///   - image1: 第一张图片
    ///   - image2: 第二张图片
    ///   - endpoint: API 端点地址
    ///   - model: 视觉模型名称
    ///   - apiToken: API Token（可选）
    ///   - timeout: 超时时间（秒）
    /// - Returns: AI 对两张图片差异的描述
    func compareImages(
        image1: NSImage,
        image2: NSImage,
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 30.0
    ) async throws -> String {
        print("🤖 [OllamaService] 开始比较两张图片，模型: \(model)")
        
        // 将两张图片转换为 base64
        guard let image1Data = image1.tiffRepresentation,
              let bitmap1 = NSBitmapImageRep(data: image1Data),
              let png1Data = bitmap1.representation(using: .png, properties: [:]) else {
            throw OllamaError.invalidImage
        }
        
        guard let image2Data = image2.tiffRepresentation,
              let bitmap2 = NSBitmapImageRep(data: image2Data),
              let png2Data = bitmap2.representation(using: .png, properties: [:]) else {
            throw OllamaError.invalidImage
        }
        
        let base64Image1 = png1Data.base64EncodedString()
        let base64Image2 = png2Data.base64EncodedString()
        
        // 构建比较提示词
        let prompt = """
        请仔细比较这两张图片，描述它们之间的主要差异。
        重点关注：
        1. 场景或背景的变化
        2. 人物或物体的出现/消失
        3. 动作或姿态的变化
        4. 整体氛围或情绪的变化
        
        请用简洁的中文描述主要变化。
        """
        
        // 构建请求体（Ollama 支持多图片输入）
        let requestBody: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "images": [base64Image1, base64Image2],
            "stream": false,
            "options": [
                "temperature": 0.2,
                "top_p": 0.9
            ]
        ]
        
        // 构建 URL
        guard let url = URL(string: "\(endpoint)/api/generate") else {
            throw OllamaError.invalidEndpoint
        }
        
        // 构建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = apiToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = timeout
        
        print("🤖 [OllamaService] 发送图片比较请求（超时: \(timeout)秒）...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        
        print("🤖 [OllamaService] 收到响应，状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [OllamaService] 请求失败: \(errorMessage)")
            throw OllamaError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            print("❌ [OllamaService] 无法解析响应")
            throw OllamaError.invalidResponse
        }
        
        let comparison = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("✅ [OllamaService] 图片比较完成")
        
        return comparison
    }
}

/// Ollama 服务错误
enum OllamaError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case requestFailed(Int, String)
    case networkError(Error)
    case invalidImage
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "无效的 API 端点地址"
        case .invalidResponse:
            return "无效的响应格式"
        case .requestFailed(let code, let message):
            return "请求失败 (状态码: \(code)): \(message)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidImage:
            return "无效的图片格式"
        }
    }
}

