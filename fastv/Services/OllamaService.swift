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
    
    /// API 类型
    enum APIType {
        case ollama
        case openAI
    }
    
    /// 检测 API 类型
    static func detectAPIType(endpoint: String) -> APIType {
        let lowercased = endpoint.lowercased()
        if lowercased.contains("/chat/completions") ||
           lowercased.contains("/v1/chat") ||
           lowercased.contains("openai") ||
           lowercased.contains("anthropic") ||
           lowercased.contains("dashscope") {
            return .openAI
        }
        return .ollama
    }
    
    /// 检测是否为 DashScope API
    static func isDashScope(endpoint: String) -> Bool {
        let lowercased = endpoint.lowercased()
        return lowercased.contains("dashscope")
    }
    
    /// 智能构建 API URL，如果 endpoint 已经包含完整路径则直接使用，否则根据 API 类型拼接
    /// - Parameter endpoint: API 端点地址
    /// - Parameter useChatCompletions: 是否使用 chat/completions 端点（默认根据 API 类型自动判断）
    /// - Returns: 完整的 API URL
    static func buildAPIURL(endpoint: String, useChatCompletions: Bool? = nil) throws -> URL {
        // 去除末尾的斜杠
        var cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanEndpoint.hasSuffix("/") {
            cleanEndpoint = String(cleanEndpoint.dropLast())
        }
        
        // 检查是否已经包含完整路径
        let lowercased = cleanEndpoint.lowercased()
        if lowercased.contains("/api/generate") ||
           lowercased.contains("/chat/completions") ||
           lowercased.contains("/v1/chat") ||
           lowercased.contains("/completions") {
            // 已经包含完整路径，直接使用
            guard let url = URL(string: cleanEndpoint) else {
                throw OllamaError.invalidEndpoint
            }
            return url
        }
        
        // 根据 API 类型或参数决定拼接的路径
        let apiType = detectAPIType(endpoint: cleanEndpoint)
        let shouldUseChat = useChatCompletions ?? (apiType == .openAI)
        let path = shouldUseChat ? "/v1/chat/completions" : "/api/generate"
        
        guard let url = URL(string: "\(cleanEndpoint)\(path)") else {
            throw OllamaError.invalidEndpoint
        }
        return url
    }
    
    /// 优化转录文本（带常错词和高频词支持）
    /// - Parameters:
    ///   - text: 原始转录文本
    ///   - endpoint: API 端点地址
    ///   - model: 使用的模型名称
    ///   - apiToken: API Token（可选）
    ///   - timeout: 超时时间（秒）
    ///   - systemPrompt: 系统提示词
    ///   - useMistakes: 是否使用常错词
    ///   - useHighFrequencyWords: 是否使用高频词
    /// - Returns: 优化后的文本
    func optimizeTranscript(
        text: String,
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 5.0,
        systemPrompt: String,
        useMistakes: Bool = true,
        useHighFrequencyWords: Bool = true
    ) async throws -> String {
        print("🤖 [OllamaService] 开始优化文本，长度: \(text.count)")
        print("🤖 [OllamaService] API 端点: \(endpoint)")
        print("🤖 [OllamaService] 模型: \(model)")
        
        // 构建增强的系统提示词
        var enhancedSystemPrompt = systemPrompt
        
        if useMistakes {
            let mistakeManager = CommonMistakeManager.shared
            if !mistakeManager.mistakes.isEmpty {
                let mistakesList = mistakeManager.mistakes.prefix(20).map { "\($0.wrong) -> \($0.correct)" }.joined(separator: ", ")
                enhancedSystemPrompt += "\n\n用户常错词映射（语音识别错误 -> 正确词）：\(mistakesList)"
                print("📝 [OllamaService] 已加载 \(min(20, mistakeManager.mistakes.count)) 个常错词")
            }
        }
        
        if useHighFrequencyWords {
            let wordExtractor = HighFrequencyWordExtractor.shared
            if !wordExtractor.highFrequencyWords.isEmpty {
                let wordsDescription = wordExtractor.getWordsDescription()
                enhancedSystemPrompt += "\n\n\(wordsDescription)"
                print("📝 [OllamaService] 已加载高频词信息")
            }
        }
        
        // 检测 API 类型
        let apiType = Self.detectAPIType(endpoint: endpoint)
        
        // 构建 URL
        let url = try Self.buildAPIURL(endpoint: endpoint)
        
        // 根据 API 类型构建不同的请求体
        let requestBody: [String: Any]
        
        if apiType == .openAI {
            // OpenAI 兼容格式（使用 messages）
            requestBody = [
                "model": model,
                "messages": [
                    [
                        "role": "system",
                        "content": enhancedSystemPrompt
                    ],
                    [
                        "role": "user",
                        "content": text
                    ]
                ],
                "temperature": 0.3,
                "top_p": 0.9
            ]
        } else {
            // Ollama 格式（使用 prompt 和 system）
            requestBody = [
                "model": model,
                "prompt": text,
                "system": enhancedSystemPrompt,
                "stream": false,
                "options": [
                    "temperature": 0.3,  // 较低的温度使输出更确定
                    "top_p": 0.9
                ]
            ]
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
        
        let isDashScope = Self.isDashScope(endpoint: endpoint)
        let apiTypeName = isDashScope ? "DashScope" : (apiType == .openAI ? "OpenAI" : "Ollama")
        print("🤖 [OllamaService] 发送请求到 AI（超时: \(timeout)秒，类型: \(apiTypeName)）...")
        
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
        
        // 解析响应 - 根据 API 类型解析不同的响应格式
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [OllamaService] 无法解析响应 JSON")
            throw OllamaError.invalidResponse
        }
        
        let optimizedText: String
        
        if isDashScope {
            // DashScope 格式：响应在 output.choices[0].message.content 或 output.text
            if let output = json["output"] as? [String: Any] {
                // 先检查文本生成端点格式（output.text）
                if let text = output["text"] as? String {
                    optimizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                // 再检查聊天端点格式（output.choices[0].message.content）
                else if let choices = output["choices"] as? [[String: Any]],
                        let firstChoice = choices.first,
                        let message = firstChoice["message"] as? [String: Any] {
                    // 提取 content（可能是字符串或数组）
                    if let contentArray = message["content"] as? [[String: Any]] {
                        // 多模态响应：提取文本部分
                        var textParts: [String] = []
                        for item in contentArray {
                            if let text = item["text"] as? String {
                                textParts.append(text)
                            }
                        }
                        optimizedText = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let content = message["content"] as? String {
                        optimizedText = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        print("❌ [OllamaService] DashScope 格式响应解析失败：无法找到 content")
                        print("📄 [OllamaService] message 对象内容: \(message)")
                        throw OllamaError.invalidResponse
                    }
                } else {
                    print("❌ [OllamaService] DashScope 格式响应解析失败：output 中没有 text 或 choices")
                    print("📄 [OllamaService] output 对象内容: \(output)")
                    throw OllamaError.invalidResponse
                }
            } else {
                print("❌ [OllamaService] DashScope 格式响应解析失败：json 中没有 output 字段")
                print("📄 [OllamaService] json 对象内容: \(json)")
                throw OllamaError.invalidResponse
            }
        } else if apiType == .openAI {
            // OpenAI 格式：响应在 choices[0].message.content
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                optimizedText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                print("❌ [OllamaService] OpenAI 格式响应解析失败")
                print("📄 [OllamaService] json 对象内容: \(json)")
                throw OllamaError.invalidResponse
            }
        } else {
            // Ollama 格式：响应在 response 字段
            guard let responseText = json["response"] as? String else {
                print("❌ [OllamaService] Ollama 格式响应解析失败")
                print("📄 [OllamaService] json 对象内容: \(json)")
                throw OllamaError.invalidResponse
            }
            optimizedText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        print("✅ [OllamaService] 文本优化完成（\(apiTypeName)），优化后长度: \(optimizedText.count)")
        
        return optimizedText
    }
    
    /// 测试 API 连接
    func testConnection(endpoint: String, apiToken: String?) async throws -> Bool {
        print("🤖 [OllamaService] 测试连接: \(endpoint)")
        
        let apiType = Self.detectAPIType(endpoint: endpoint)
        
        if apiType == .openAI {
            // OpenAI 兼容 API：使用 chat/completions 端点测试
            return try await testConnectionWithChatCompletions(endpoint: endpoint, apiToken: apiToken)
        } else {
            // Ollama API：优先使用 /api/tags 端点（更轻量）
            if let result = try? await testConnectionWithTags(endpoint: endpoint, apiToken: apiToken) {
                return result
            }
            // 如果失败，尝试 /api/generate（兼容模式）
            return try await testConnectionWithGenerate(endpoint: endpoint, apiToken: apiToken)
        }
    }
    
    /// 使用 chat/completions 端点测试连接（OpenAI 兼容格式）
    private func testConnectionWithChatCompletions(endpoint: String, apiToken: String?) async throws -> Bool {
        do {
            let url = try Self.buildAPIURL(endpoint: endpoint, useChatCompletions: true)
            
            // 发送一个最小的测试请求
            let requestBody: [String: Any] = [
                "model": "test",  // 使用 "test" 作为占位模型名
                "messages": [
                    ["role": "user", "content": "test"]
                ]
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            if let token = apiToken, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            request.timeoutInterval = 10
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }
            
            print("🤖 [OllamaService] OpenAI 格式测试响应状态码: \(httpResponse.statusCode)")
            
            // 对于 OpenAI 兼容 API，200 或 400（参数错误）都算连接成功
            // 401/403 表示认证问题，也算连接成功但需要正确的 token
            if httpResponse.statusCode == 200 {
                return true
            } else if httpResponse.statusCode == 400 {
                // 400 通常表示请求格式正确但参数有问题（如模型不存在），说明 API 连接正常
                let errorMessage = String(data: data, encoding: .utf8) ?? ""
                print("⚠️ [OllamaService] API 返回 400，但连接正常: \(errorMessage)")
                return true
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                // 认证错误，但说明 API 连接正常
                print("⚠️ [OllamaService] API 认证失败，但连接正常")
                return true
            } else {
                return false
            }
        } catch {
            // 网络错误或其他错误
            throw error
        }
    }
    
    /// 使用 /api/tags 端点测试连接（Ollama 标准方式）
    private func testConnectionWithTags(endpoint: String, apiToken: String?) async throws -> Bool {
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
        
        print("🤖 [OllamaService] /api/tags 测试响应状态码: \(httpResponse.statusCode)")
        
        return httpResponse.statusCode == 200
    }
    
    /// 使用 /api/generate 端点测试连接（兼容模式，适用于 Ollama）
    private func testConnectionWithGenerate(endpoint: String, apiToken: String?) async throws -> Bool {
        let url = try Self.buildAPIURL(endpoint: endpoint, useChatCompletions: false)
        
        // 发送一个最小的测试请求（Ollama 格式）
        let requestBody: [String: Any] = [
            "model": "test",  // 使用 "test" 作为占位模型名
            "prompt": "test",
            "stream": false
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = apiToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }
            
            print("🤖 [OllamaService] /api/generate 测试响应状态码: \(httpResponse.statusCode)")
            
            // 对于 DashScope，即使模型不存在，也可能返回 200，但会有错误信息
            // 我们主要检查是否能连接到 API，所以 200 或 400（参数错误）都算连接成功
            // 401/403 表示认证问题，也算连接成功但需要正确的 token
            // 404/500 等才表示连接失败
            if httpResponse.statusCode == 200 {
                return true
            } else if httpResponse.statusCode == 400 {
                // 400 通常表示请求格式正确但参数有问题（如模型不存在），说明 API 连接正常
                let errorMessage = String(data: data, encoding: .utf8) ?? ""
                print("⚠️ [OllamaService] API 返回 400，但连接正常: \(errorMessage)")
                return true
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                // 认证错误，但说明 API 连接正常
                print("⚠️ [OllamaService] API 认证失败，但连接正常")
                return true
            } else {
                return false
            }
        } catch {
            // 网络错误或其他错误
            throw error
        }
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
        let url = try Self.buildAPIURL(endpoint: endpoint)
        
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
        let url = try Self.buildAPIURL(endpoint: endpoint)
        
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
    
    /// 生成会议摘要和待办事项（Markdown 格式）
    /// - Parameters:
    ///   - text: 会议转录文本
    ///   - endpoint: API 端点地址
    ///   - model: 使用的模型名称
    ///   - apiToken: API Token（可选）
    ///   - timeout: 超时时间（秒）
    /// - Returns: Markdown 格式的摘要（包含摘要和待办事项章节）
    func generateMeetingSummary(
        text: String,
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 30.0
    ) async throws -> String {
        print("🤖 [OllamaService] 开始生成会议摘要，文本长度: \(text.count)")
        
        let systemPrompt = """
        你是一个专业的会议记录助手。请分析以下会议转录文本，生成：
        1. 简洁的会议摘要（200字以内）
        2. 明确的待办事项列表（每项一行，使用"- "开头）
        
        请以 JSON 格式返回：
        {
          "summary": "会议摘要内容",
          "actionItems": ["待办事项1", "待办事项2"]
        }
        
        只返回 JSON，不要其他内容。如果没有待办事项，actionItems 为空数组。
        """
        
        // 检测 API 类型
        let apiType = Self.detectAPIType(endpoint: endpoint)
        let isDashScopeAPI = Self.isDashScope(endpoint: endpoint)
        
        // 构建 URL
        let url = try Self.buildAPIURL(endpoint: endpoint, useChatCompletions: apiType == .openAI)
        
        // 构建请求体 - 根据 API 类型使用不同格式
        let requestBody: [String: Any]
        
        if isDashScopeAPI {
            // DashScope 格式：使用 input.messages
            requestBody = [
                "model": model,
                "input": [
                    "messages": [
                        [
                            "role": "system",
                            "content": [["text": systemPrompt]]
                        ],
                        [
                            "role": "user",
                            "content": [["text": "请分析以下会议转录文本，生成摘要和待办事项：\n\n\(text)"]]
                        ]
                    ]
                ],
                "parameters": [
                    "temperature": 0.3,
                    "top_p": 0.9
                ]
            ]
        } else if apiType == .openAI {
            // OpenAI 兼容格式：使用 messages
            requestBody = [
                "model": model,
                "messages": [
                    [
                        "role": "system",
                        "content": systemPrompt
                    ],
                    [
                        "role": "user",
                        "content": "请分析以下会议转录文本，生成摘要和待办事项：\n\n\(text)"
                    ]
                ],
                "temperature": 0.3,
                "top_p": 0.9
            ]
        } else {
            // Ollama 格式：使用 prompt 和 system
            requestBody = [
                "model": model,
                "prompt": text,
                "system": systemPrompt,
                "stream": false,
                "options": [
                    "temperature": 0.3,
                    "top_p": 0.9
                ]
            ]
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
        
        print("🤖 [OllamaService] 发送会议摘要生成请求（超时: \(timeout)秒）...")
        
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
        
        // 解析响应 - 根据 API 类型解析不同的响应格式
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [OllamaService] 无法解析响应 JSON")
            throw OllamaError.invalidResponse
        }
        
        let rawResponse: String
        
        if isDashScopeAPI {
            // DashScope 格式：响应在 output.choices[0].message.content 或 output.text
            if let output = json["output"] as? [String: Any] {
                // 先检查文本生成端点格式（output.text）
                if let text = output["text"] as? String {
                    rawResponse = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                // 再检查聊天端点格式（output.choices[0].message.content）
                else if let choices = output["choices"] as? [[String: Any]],
                        let firstChoice = choices.first,
                        let message = firstChoice["message"] as? [String: Any] {
                    // 提取 content（可能是字符串或数组）
                    if let contentArray = message["content"] as? [[String: Any]] {
                        // 多模态响应：提取文本部分
                        var textParts: [String] = []
                        for item in contentArray {
                            if let text = item["text"] as? String {
                                textParts.append(text)
                            }
                        }
                        rawResponse = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let content = message["content"] as? String {
                        rawResponse = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        print("❌ [OllamaService] DashScope 格式响应解析失败：无法找到 content")
                        print("📄 [OllamaService] message 对象内容: \(message)")
                        throw OllamaError.invalidResponse
                    }
                } else {
                    print("❌ [OllamaService] DashScope 格式响应解析失败：output 中没有 text 或 choices")
                    print("📄 [OllamaService] output 对象内容: \(output)")
                    throw OllamaError.invalidResponse
                }
            } else {
                print("❌ [OllamaService] DashScope 格式响应解析失败：json 中没有 output 字段")
                print("📄 [OllamaService] json 对象内容: \(json)")
                throw OllamaError.invalidResponse
            }
        } else if apiType == .openAI {
            // OpenAI 格式：响应在 choices[0].message.content
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                rawResponse = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                print("❌ [OllamaService] OpenAI 格式响应解析失败")
                print("📄 [OllamaService] json 对象内容: \(json)")
                throw OllamaError.invalidResponse
            }
        } else {
            // Ollama 格式：响应在 response 字段
            guard let responseText = json["response"] as? String else {
                print("❌ [OllamaService] Ollama 格式响应解析失败")
                print("📄 [OllamaService] json 对象内容: \(json)")
                throw OllamaError.invalidResponse
            }
            rawResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 尝试解析 JSON（可能包含在代码块中）
        var jsonString = rawResponse
        
        // 移除可能的 markdown 代码块标记
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 尝试解析 JSON
        if let jsonData = jsonString.data(using: .utf8),
           let parsedJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let summary = parsedJson["summary"] as? String,
           let actionItems = parsedJson["actionItems"] as? [String] {
            // 构建 Markdown 格式的摘要
            var markdownSummary = "## 会议摘要\n\n\(summary)"
            
            if !actionItems.isEmpty {
                markdownSummary += "\n\n## 待办事项\n\n"
                for item in actionItems {
                    markdownSummary += "- \(item)\n"
                }
            }
            
            print("✅ [OllamaService] 会议摘要生成完成")
            return markdownSummary
        }
        
        // 如果 JSON 解析失败，尝试从文本中提取
        print("⚠️ [OllamaService] JSON 解析失败，尝试从文本中提取信息")
        
        // 降级方案：使用原始响应作为摘要，尝试提取待办事项
        var summary = rawResponse
        var actionItems: [String] = []
        
        // 尝试提取待办事项（查找以 "- " 开头的行）
        let lines = rawResponse.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2))
                if !item.isEmpty {
                    actionItems.append(item)
                }
            } else if trimmed.hasPrefix("• ") {
                let item = String(trimmed.dropFirst(2))
                if !item.isEmpty {
                    actionItems.append(item)
                }
            }
        }
        
        // 如果没有找到待办事项，尝试查找包含"待办"、"任务"等关键词的行
        if actionItems.isEmpty {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("待办") || trimmed.contains("任务") {
                    if trimmed.count > 5 && trimmed.count < 100 {
                        actionItems.append(trimmed)
                    }
                }
            }
        }
        
        // 如果还是没有，使用前几行作为摘要
        if actionItems.isEmpty && summary.count > 200 {
            summary = String(summary.prefix(200)) + "..."
        }
        
            // 构建 Markdown 格式的摘要
            var markdownSummary = "## 会议摘要\n\n\(summary)"
            
            if !actionItems.isEmpty {
                markdownSummary += "\n\n## 待办事项\n\n"
                for item in actionItems {
                    markdownSummary += "- \(item)\n"
                }
            }
        
        print("✅ [OllamaService] 会议摘要生成完成（降级模式）")
        return markdownSummary
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

