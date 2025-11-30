//
//  ChatAIService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 聊天AI服务错误
enum ChatAIError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case requestFailed(Int, String)
    case networkError(Error)
    
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
        }
    }
}

/// 聊天AI服务
@MainActor
class ChatAIService {
    static let shared = ChatAIService()
    
    private init() {}
    
    /// 检测是否是 DashScope API
    private func isDashScopeEndpoint(_ endpoint: String) -> Bool {
        let lowercased = endpoint.lowercased()
        return lowercased.hasPrefix("https://dashscope.aliyuncs.com") ||
               lowercased.contains("dashscope.aliyuncs.com")
    }
    
    /// 检测模型是否支持 thinking（qwen3 系列）
    private func supportsThinking(_ model: String) -> Bool {
        let lowercased = model.lowercased()
        return lowercased.contains("qwen3")
    }
    
    /// 构建 DashScope 多模态内容格式
    private func buildDashScopeContent(text: String, attachments: [ChatAttachment]) -> [[String: Any]] {
        var contentArray: [[String: Any]] = []
        
        // 添加附件（图片、视频、音频）
        for attachment in attachments {
            switch attachment.type {
            case .image:
                if let url = attachment.url {
                    contentArray.append(["image": url])
                } else if let base64Data = attachment.base64Data, !base64Data.isEmpty {
                    // DashScope 支持 base64，格式：data:image/png;base64,...
                    let mimeType = attachment.mimeType ?? "image/png"
                    let dataUrl = "data:\(mimeType);base64,\(base64Data)"
                    contentArray.append(["image": dataUrl])
                }
            case .video:
                if let url = attachment.url {
                    // DashScope 视频格式：数组形式
                    contentArray.append(["video": [url]])
                } else if let base64Data = attachment.base64Data, !base64Data.isEmpty {
                    let mimeType = attachment.mimeType ?? "video/mp4"
                    let dataUrl = "data:\(mimeType);base64,\(base64Data)"
                    contentArray.append(["video": [dataUrl]])
                }
            case .audio:
                if let url = attachment.url {
                    contentArray.append(["audio": url])
                } else if let base64Data = attachment.base64Data, !base64Data.isEmpty {
                    let mimeType = attachment.mimeType ?? "audio/mpeg"
                    let dataUrl = "data:\(mimeType);base64,\(base64Data)"
                    contentArray.append(["audio": dataUrl])
                }
            default:
                break
            }
        }
        
        // 添加文本内容（如果有）
        if !text.isEmpty {
            contentArray.append(["text": text])
        }
        
        return contentArray
    }
    
    /// 发送聊天消息（使用新的配置系统）
    /// - Parameters:
    ///   - messages: 消息历史（包含当前消息）
    ///   - profile: AI 服务配置
    ///   - model: 模型名称（覆盖 profile 默认模型）
    ///   - timeout: 超时时间（覆盖 profile 默认超时）
    ///   - preferences: 用户偏好设置（用于获取参数）
    /// - Returns: AI回复内容和思考过程（如果有）
    func sendMessage(
        messages: [[String: Any]],
        profile: AIServiceProfile,
        model: String? = nil,
        timeout: Double? = nil,
        preferences: UserPreferences? = nil
    ) async throws -> (content: String, thinking: String?) {
        let effectiveModel = model ?? profile.defaultModel
        let effectiveTimeout = timeout ?? profile.timeout
        
        let adapter = AIServiceAdapter.shared
        let url = try adapter.buildAPIURL(for: profile, useChatCompletions: true, model: effectiveModel)
        
        // 对于 DashScope 原生模式，需要转换消息格式
        let endpoint = profile.effectiveEndpoint.lowercased()
        let usesDashScopeCompatibleMode = endpoint.contains("compatible-mode") || endpoint.contains("/chat/completions")
        
        let convertedMessages: [[String: Any]]
        if profile.protocolType == .dashScope && !usesDashScopeCompatibleMode {
            convertedMessages = messages.map { msg in
                var dashScopeMsg = msg
                if let content = msg["content"] as? String {
                    // 将字符串内容转换为 DashScope 数组格式
                    dashScopeMsg["content"] = [["text": content]]
                } else if let contentArray = msg["content"] as? [[String: Any]] {
                    // 已经是数组格式，检查是否需要转换
                    let dashScopeContent = contentArray.map { item -> [String: Any] in
                        if item["type"] as? String == "text", let text = item["text"] as? String {
                            return ["text": text]
                        } else if item["type"] as? String == "image_url",
                                  let imageUrl = item["image_url"] as? [String: Any],
                                  let url = imageUrl["url"] as? String {
                            return ["image": url]
                        } else if item["type"] as? String == "audio_url",
                                  let audioUrl = item["audio_url"] as? [String: Any],
                                  let url = audioUrl["url"] as? String {
                            return ["audio": url]
                        } else if item["type"] as? String == "video_url",
                                  let videoUrl = item["video_url"] as? [String: Any],
                                  let url = videoUrl["url"] as? String {
                            return ["video": [url]]
                        } else {
                            return item
                        }
                    }
                    dashScopeMsg["content"] = dashScopeContent
                }
                return dashScopeMsg
            }
        } else {
            convertedMessages = messages
        }
        
        let requestBody = adapter.buildRequestBody(
            for: profile,
            messages: convertedMessages,
            model: effectiveModel,
            temperature: preferences?.chatTemperature,
            topP: preferences?.chatTopP,
            maxTokens: preferences?.chatMaxTokens,
            additionalParams: buildAdditionalParams(for: profile, preferences: preferences)
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let headers = adapter.buildRequestHeaders(for: profile)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = effectiveTimeout
        
        print("💬 [ChatAIService] 发送请求到 AI（超时: \(effectiveTimeout)秒），协议: \(profile.protocolType.displayName)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAIError.invalidResponse
        }
        
        print("💬 [ChatAIService] 收到响应，状态码: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            let preview = responseString.count > 2000 ? String(responseString.prefix(2000)) + "..." : responseString
            print("💬 [ChatAIService] 响应内容预览: \(preview)")
        } else {
            print("💬 [ChatAIService] 响应内容无法解析为字符串")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [ChatAIService] 请求失败: \(errorMessage)")
            throw ChatAIError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        return try adapter.parseResponse(data: data, for: profile)
    }
    
    /// 构建额外参数
    private func buildAdditionalParams(for profile: AIServiceProfile, preferences: UserPreferences?) -> [String: Any]? {
        guard let prefs = preferences else { return nil }
        var params: [String: Any] = [:]
        
        // DashScope 特殊参数
        if profile.protocolType == .dashScope {
            if prefs.chatEnableSearch {
                params["enable_search"] = true
            }
            if supportsThinking(profile.defaultModel) && prefs.chatEnableThinking {
                params["thinking"] = true
            }
        }
        
        return params.isEmpty ? nil : params
    }
    
    /// 发送聊天消息（旧版兼容方法）
    /// - Parameters:
    ///   - messages: 消息历史（包含当前消息）
    ///   - endpoint: API 端点
    ///   - model: 模型名称
    ///   - apiToken: API Token（可选）
    ///   - timeout: 超时时间
    ///   - preferences: 用户偏好设置（用于获取参数）
    /// - Returns: AI回复内容和思考过程（如果有）
    func sendMessageLegacy(
        messages: [[String: Any]],
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 30.0,
        preferences: UserPreferences? = nil
    ) async throws -> (content: String, thinking: String?) {
        print("💬 [ChatAIService] 开始发送聊天消息（旧版兼容），消息数量: \(messages.count)")
        
        let prefs = preferences ?? UserPreferences.shared
        let isDashScope = isDashScopeEndpoint(endpoint)
        let supportsThinkingFeature = supportsThinking(model)
        
        // 构建 URL
        let url: URL
        if isDashScope {
            // DashScope API：检测是否有附件，决定使用哪个端点
            let hasMultimodalContent = messages.contains { msg in
                if let content = msg["content"] as? [[String: Any]] {
                    return content.contains { item in
                        item["image"] != nil || item["video"] != nil || item["audio"] != nil ||
                        item["image_url"] != nil || item["video_url"] != nil || item["audio_url"] != nil
                    }
                }
                return false
            }
            
            if hasMultimodalContent {
                // 多模态端点
                guard let multimodalURL = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation") else {
                    throw ChatAIError.invalidEndpoint
                }
                url = multimodalURL
            } else {
                // 文本生成端点
                guard let textURL = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation") else {
                    throw ChatAIError.invalidEndpoint
                }
                url = textURL
            }
        } else {
            // 使用原有的 URL 构建逻辑
            url = try AITodoAIService.buildAPIURL(endpoint: endpoint)
        }
        
        // 检测 API 类型
        let apiType = AITodoAIService.detectAPIType(endpoint: endpoint)
        
        // 构建请求体
        let requestBody: [String: Any]
        
        if isDashScope {
            // DashScope 格式
            var dashScopeMessages: [[String: Any]] = []
            
            for msg in messages {
                let role = msg["role"] as? String ?? "user"
                var dashScopeMsg: [String: Any] = ["role": role]
                
                if let content = msg["content"] as? String {
                    // 纯文本
                    dashScopeMsg["content"] = [["text": content]]
                } else if let contentArray = msg["content"] as? [[String: Any]] {
                    // 多模态内容：转换为 DashScope 格式
                    var dashScopeContent: [[String: Any]] = []
                    
                    for item in contentArray {
                        if let text = item["text"] as? String {
                            dashScopeContent.append(["text": text])
                        } else if let imageUrl = item["image_url"] as? [String: Any],
                                  let urlString = imageUrl["url"] as? String {
                            // 支持 data URL 和普通 URL
                            dashScopeContent.append(["image": urlString])
                        } else if let audioUrl = item["audio_url"] as? [String: Any],
                                  let urlString = audioUrl["url"] as? String {
                            // 支持 data URL 和普通 URL
                            dashScopeContent.append(["audio": urlString])
                        } else if let videoUrl = item["video_url"] as? [String: Any],
                                  let urlString = videoUrl["url"] as? String {
                            // DashScope 视频格式：数组形式
                            dashScopeContent.append(["video": [urlString]])
                        } else if let image = item["image"] as? String {
                            // 直接是 image 字段（DashScope 格式）
                            dashScopeContent.append(["image": image])
                        } else if let audio = item["audio"] as? String {
                            // 直接是 audio 字段（DashScope 格式）
                            dashScopeContent.append(["audio": audio])
                        } else if let video = item["video"] as? [String] {
                            // 直接是 video 字段（DashScope 格式，数组）
                            dashScopeContent.append(["video": video])
                        }
                    }
                    
                    dashScopeMsg["content"] = dashScopeContent
                } else {
                    // 降级为文本
                    dashScopeMsg["content"] = [["text": ""]]
                }
                
                dashScopeMessages.append(dashScopeMsg)
            }
            
            var requestBodyDict: [String: Any] = [
                "model": model,
                "input": [
                    "messages": dashScopeMessages
                ]
            ]
            
            // 添加参数
            var parameters: [String: Any] = [:]
            
            if prefs.chatTemperature > 0 {
                parameters["temperature"] = prefs.chatTemperature
            }
            if prefs.chatTopP > 0 {
                parameters["top_p"] = prefs.chatTopP
            }
            if prefs.chatTopK > 0 {
                parameters["top_k"] = prefs.chatTopK
            }
            if prefs.chatMaxTokens > 0 {
                // 确保 max_tokens 在有效范围内 [1, 8192]
                let maxTokens = min(max(prefs.chatMaxTokens, 1), 8192)
                parameters["max_tokens"] = maxTokens
            }
            
            // 默认启用搜索
            if prefs.chatEnableSearch {
                parameters["enable_search"] = true
            }
            
            // 如果模型支持 thinking 且用户启用了 thinking
            if supportsThinkingFeature && prefs.chatEnableThinking {
                parameters["thinking"] = true
            }
            
            if !parameters.isEmpty {
                requestBodyDict["parameters"] = parameters
            }
            
            requestBody = requestBodyDict
        } else if apiType == .openAI {
            // OpenAI 兼容格式（使用 messages）
            var openAIBody: [String: Any] = [
                "model": model,
                "messages": messages
            ]
            
            // 添加参数
            if prefs.chatTemperature > 0 {
                openAIBody["temperature"] = prefs.chatTemperature
            }
            if prefs.chatTopP > 0 {
                openAIBody["top_p"] = prefs.chatTopP
            }
            if prefs.chatMaxTokens > 0 {
                // 确保 max_tokens 在有效范围内 [1, 8192]
                let maxTokens = min(max(prefs.chatMaxTokens, 1), 8192)
                openAIBody["max_tokens"] = maxTokens
            }
            
            requestBody = openAIBody
        } else {
            // Ollama 格式 - 需要将 messages 转换为 prompt
            // 提取最后一条用户消息作为 prompt
            let lastUserMessage = messages.last { msg in
                (msg["role"] as? String) == "user"
            }
            
            let prompt = if let content = lastUserMessage?["content"] as? String {
                content
            } else if let contentArray = lastUserMessage?["content"] as? [[String: Any]],
                      let firstContent = contentArray.first,
                      let text = firstContent["text"] as? String {
                text
            } else {
                ""
            }
            
            // 构建 system prompt（如果有）
            let systemMessages = messages.filter { msg -> Bool in
                (msg["role"] as? String) == "system"
            }
            let systemPrompt = systemMessages.compactMap { msg -> String? in
                if let content = msg["content"] as? String {
                    return content
                }
                return nil
            }.joined(separator: "\n")
            
            var ollamaBody: [String: Any] = [
                "model": model,
                "prompt": prompt,
                "stream": false
            ]
            
            if !systemPrompt.isEmpty {
                ollamaBody["system"] = systemPrompt
            }
            
            var options: [String: Any] = [:]
            if prefs.chatTemperature > 0 {
                options["temperature"] = prefs.chatTemperature
            }
            if prefs.chatTopP > 0 {
                options["top_p"] = prefs.chatTopP
            }
            if !options.isEmpty {
                ollamaBody["options"] = options
            }
            
            requestBody = ollamaBody.compactMapValues { $0 }
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
        
        // 调试：打印请求体（仅打印消息数量，不打印完整内容以避免日志过长）
        if let messagesArray = requestBody["messages"] as? [[String: Any]] {
            print("💬 [ChatAIService] 发送请求到 AI（超时: \(timeout)秒），消息数量: \(messagesArray.count)，API类型: \(apiType == .openAI ? "OpenAI" : "Ollama")")
            // 打印每条消息的摘要
            for (index, msg) in messagesArray.enumerated() {
                let role = msg["role"] as? String ?? "unknown"
                if let content = msg["content"] as? String {
                    print("  - 消息 \(index): role=\(role), content长度=\(content.count)")
                } else if let contentArray = msg["content"] as? [[String: Any]] {
                    print("  - 消息 \(index): role=\(role), content类型=数组(\(contentArray.count)项)")
                } else {
                    print("  - 消息 \(index): role=\(role), content类型=\(type(of: msg["content"]))")
                }
            }
        } else {
            print("💬 [ChatAIService] 发送请求到 AI（超时: \(timeout)秒），API类型: \(apiType == .openAI ? "OpenAI" : "Ollama")")
        }
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAIError.invalidResponse
        }
        
        print("💬 [ChatAIService] 收到响应，状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [ChatAIService] 请求失败: \(errorMessage)")
            throw ChatAIError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let rawString = String(data: data, encoding: .utf8) ?? "无法转换为字符串"
            print("❌ [ChatAIService] 无法解析响应 JSON")
            print("📄 [ChatAIService] 原始响应内容: \(rawString)")
            throw ChatAIError.invalidResponse
        }
        
        // 打印完整的 JSON 响应（用于调试）
        if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📄 [ChatAIService] 完整响应 JSON:\n\(jsonString)")
        }
        
        let responseText: String
        var thinking: String? = nil
        
        if isDashScope {
            // DashScope 格式：有两种可能的响应格式
            // 1. 文本生成端点：output.text
            // 2. 聊天端点：output.choices[0].message.content
            if let output = json["output"] as? [String: Any] {
                // 先检查文本生成端点格式（output.text）
                if let text = output["text"] as? String {
                    responseText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                // 再检查聊天端点格式（output.choices[0].message.content）
                else if let choices = output["choices"] as? [[String: Any]],
                        let firstChoice = choices.first,
                        let message = firstChoice["message"] as? [String: Any] {
                    
                    // 提取 content
                    if let contentArray = message["content"] as? [[String: Any]] {
                        // 多模态响应：提取文本部分
                        var textParts: [String] = []
                        for item in contentArray {
                            if let text = item["text"] as? String {
                                textParts.append(text)
                            }
                        }
                        responseText = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let content = message["content"] as? String {
                        responseText = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        print("❌ [ChatAIService] DashScope 格式响应解析失败：无法找到 content")
                        print("📄 [ChatAIService] message 对象内容: \(message)")
                        throw ChatAIError.invalidResponse
                    }
                    
                    // 提取 thinking（如果有）
                    if let thinkingContent = message["thinking"] as? String {
                        thinking = thinkingContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } else {
                    print("❌ [ChatAIService] DashScope 格式响应解析失败：output 中没有 text 或 choices")
                    print("📄 [ChatAIService] output 对象内容: \(output)")
                    throw ChatAIError.invalidResponse
                }
            } else {
                print("❌ [ChatAIService] DashScope 格式响应解析失败：json 中没有 output 字段")
                print("📄 [ChatAIService] json 对象内容: \(json)")
                throw ChatAIError.invalidResponse
            }
        } else if apiType == .openAI {
            // OpenAI 格式：响应在 choices[0].message.content
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                responseText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                print("❌ [ChatAIService] OpenAI 格式响应解析失败")
                print("📄 [ChatAIService] json 对象内容: \(json)")
                throw ChatAIError.invalidResponse
            }
        } else {
            // Ollama 格式：响应在 response 字段
            guard let responseTextValue = json["response"] as? String else {
                print("❌ [ChatAIService] Ollama 格式响应解析失败")
                print("📄 [ChatAIService] json 对象内容: \(json)")
                throw ChatAIError.invalidResponse
            }
            responseText = responseTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        print("✅ [ChatAIService] AI 回复成功，长度: \(responseText.count)" + (thinking != nil ? "，思考过程长度: \(thinking!.count)" : ""))
        return (content: responseText, thinking: thinking)
    }
    
    /// 构建多模态消息内容（OpenAI 格式）
    /// - Parameters:
    ///   - text: 文本内容
    ///   - attachments: 附件列表
    /// - Returns: 消息内容（可能是字符串或数组）
    func buildMessageContent(text: String, attachments: [ChatAttachment]) -> Any {
        // 如果没有附件，直接返回文本（确保不为空）
        if attachments.isEmpty {
            return text.isEmpty ? " " : text
        }
        
        // 构建多模态内容数组
        var contentArray: [[String: Any]] = []
        
        // 添加文本内容（如果有）
        if !text.isEmpty {
            contentArray.append([
                "type": "text",
                "text": text
            ])
        }
        
        // 添加附件
        var validAttachmentCount = 0
        for attachment in attachments {
            switch attachment.type {
            case .image:
                // 图片：优先使用URL，否则使用base64
                if let url = attachment.url {
                    contentArray.append([
                        "type": "image_url",
                        "image_url": [
                            "url": url
                        ]
                    ])
                    validAttachmentCount += 1
                } else if let base64Data = attachment.base64Data, !base64Data.isEmpty {
                    // Base64格式：data:image/png;base64,...
                    let mimeType = attachment.mimeType ?? "image/png"
                    let dataUrl = "data:\(mimeType);base64,\(base64Data)"
                    contentArray.append([
                        "type": "image_url",
                        "image_url": [
                            "url": dataUrl
                        ]
                    ])
                    validAttachmentCount += 1
                }
                
            case .audio:
                // 音频：优先使用URL，否则使用base64
                if let url = attachment.url {
                    contentArray.append([
                        "type": "audio_url",
                        "audio_url": [
                            "url": url
                        ]
                    ])
                    validAttachmentCount += 1
                } else if let base64Data = attachment.base64Data, !base64Data.isEmpty {
                    // Base64格式：data:audio/mpeg;base64,...
                    let mimeType = attachment.mimeType ?? "audio/mpeg"
                    let dataUrl = "data:\(mimeType);base64,\(base64Data)"
                    contentArray.append([
                        "type": "audio_url",
                        "audio_url": [
                            "url": dataUrl
                        ]
                    ])
                    validAttachmentCount += 1
                }
                
            case .video:
                // 视频：优先使用URL，否则使用base64
                if let url = attachment.url {
                    contentArray.append([
                        "type": "video_url",
                        "video_url": [
                            "url": url
                        ]
                    ])
                    validAttachmentCount += 1
                } else if let base64Data = attachment.base64Data, !base64Data.isEmpty {
                    // Base64格式：data:video/mp4;base64,...
                    let mimeType = attachment.mimeType ?? "video/mp4"
                    let dataUrl = "data:\(mimeType);base64,\(base64Data)"
                    contentArray.append([
                        "type": "video_url",
                        "video_url": [
                            "url": dataUrl
                        ]
                    ])
                    validAttachmentCount += 1
                }
                
            default:
                break
            }
        }
        
        // 如果数组为空（没有有效的文本和附件），返回占位符文本
        if contentArray.isEmpty {
            return validAttachmentCount > 0 ? "[附件]" : (text.isEmpty ? " " : text)
        }
        
        // 如果只有一个文本项，直接返回文本字符串
        if contentArray.count == 1, let textItem = contentArray.first, textItem["type"] as? String == "text" {
            return text
        }
        
        return contentArray
    }
    
    /// 将ChatMessage转换为API消息格式
    /// - Parameter message: 聊天消息
    /// - Returns: API消息字典
    func convertToAPIMessage(_ message: ChatMessage) -> [String: Any] {
        var apiMessage: [String: Any] = [
            "role": message.role.rawValue
        ]
        
        // 构建内容
        let content = buildMessageContent(text: message.content, attachments: message.attachments)
        
        // 确保content是正确的类型且不为空
        if let stringContent = content as? String {
            // 确保字符串不为空
            if !stringContent.isEmpty {
                apiMessage["content"] = stringContent
            } else {
                // 如果文本为空但有附件，使用占位符
                apiMessage["content"] = message.attachments.isEmpty ? " " : "[附件]"
            }
        } else if let arrayContent = content as? [[String: Any]] {
            // 确保数组不为空
            if !arrayContent.isEmpty {
                apiMessage["content"] = arrayContent
            } else {
                // 如果数组为空，降级为文本
                apiMessage["content"] = message.content.isEmpty ? " " : message.content
            }
        } else {
            // 降级为字符串，确保不为空
            apiMessage["content"] = message.content.isEmpty ? " " : message.content
        }
        
        return apiMessage
    }
    
    /// 生成聊天会话总结（使用新的配置系统）
    /// - Parameters:
    ///   - messages: 会话消息列表
    ///   - profile: AI 服务配置
    ///   - model: 模型名称（覆盖 profile 默认模型）
    ///   - timeout: 超时时间（覆盖 profile 默认超时）
    /// - Returns: 生成的总结文本
    func generateSummary(
        messages: [ChatMessage],
        profile: AIServiceProfile,
        model: String? = nil,
        timeout: Double? = nil
    ) async throws -> String {
        let effectiveModel = model ?? profile.defaultModel
        let effectiveTimeout = timeout ?? profile.timeout
        
        return try await generateSummaryLegacy(
            messages: messages,
            endpoint: profile.effectiveEndpoint,
            model: effectiveModel,
            apiToken: profile.apiKey.isEmpty ? nil : profile.apiKey,
            timeout: effectiveTimeout
        )
    }
    
    /// 生成聊天会话总结（旧版兼容方法）
    /// - Parameters:
    ///   - messages: 会话消息列表
    ///   - endpoint: API 端点
    ///   - model: 模型名称
    ///   - apiToken: API Token（可选）
    ///   - timeout: 超时时间
    /// - Returns: 生成的总结文本
    func generateSummaryLegacy(
        messages: [ChatMessage],
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 30.0
    ) async throws -> String {
        print("📝 [ChatAIService] 开始生成聊天总结，消息数量: \(messages.count)")
        
        // 只使用用户和助手消息，过滤掉系统消息
        let conversationMessages = messages.filter { $0.role == .user || $0.role == .assistant }
        
        guard !conversationMessages.isEmpty else {
            throw ChatAIError.invalidResponse
        }
        
        // 构建对话内容（限制长度，避免token过多）
        var conversationText = ""
        let maxMessages = min(conversationMessages.count, 10)  // 最多使用10条消息
        let recentMessages = Array(conversationMessages.suffix(maxMessages))
        
        for message in recentMessages {
            let role = message.role == .user ? "用户" : "助手"
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                conversationText += "\(role): \(content)\n\n"
            }
        }
        
        // 构建总结提示词
        let summaryPrompt = """
请为以下对话生成一个简洁的总结（不超过50字），概括对话的主要内容和主题：

\(conversationText)

总结：
"""
        
        // 构建 URL
        let url = try AITodoAIService.buildAPIURL(endpoint: endpoint)
        
        // 检测 API 类型
        let apiType = AITodoAIService.detectAPIType(endpoint: endpoint)
        
        // 构建请求体
        let requestBody: [String: Any]
        
        if apiType == .openAI {
            requestBody = [
                "model": model,
                "messages": [
                    [
                        "role": "user",
                        "content": summaryPrompt
                    ]
                ],
                "temperature": 0.3,
                "top_p": 0.9,
                "max_tokens": 100  // 限制输出长度
            ]
        } else {
            requestBody = [
                "model": model,
                "prompt": summaryPrompt,
                "stream": false,
                "options": [
                    "temperature": 0.3,
                    "top_p": 0.9,
                    "num_predict": 100  // Ollama 限制输出长度
                ]
            ]
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
        
        print("📝 [ChatAIService] 发送总结生成请求...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [ChatAIService] 总结生成失败: \(errorMessage)")
            throw ChatAIError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatAIError.invalidResponse
        }
        
        let summaryText: String
        
        if apiType == .openAI {
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                summaryText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                throw ChatAIError.invalidResponse
            }
        } else {
            guard let responseText = json["response"] as? String else {
                throw ChatAIError.invalidResponse
            }
            summaryText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        print("✅ [ChatAIService] 总结生成成功: \(summaryText)")
        return summaryText
    }
    
    /// 生成聊天会话标题（使用新的配置系统）
    /// - Parameters:
    ///   - messages: 会话消息列表
    ///   - profile: AI 服务配置
    ///   - model: 模型名称（覆盖 profile 默认模型）
    ///   - timeout: 超时时间（覆盖 profile 默认超时）
    /// - Returns: 生成的标题文本
    func generateTitle(
        messages: [ChatMessage],
        profile: AIServiceProfile,
        model: String? = nil,
        timeout: Double? = nil
    ) async throws -> String {
        let effectiveModel = model ?? profile.defaultModel
        let effectiveTimeout = timeout ?? profile.timeout
        
        return try await generateTitleLegacy(
            messages: messages,
            endpoint: profile.effectiveEndpoint,
            model: effectiveModel,
            apiToken: profile.apiKey.isEmpty ? nil : profile.apiKey,
            timeout: effectiveTimeout
        )
    }
    
    /// 生成聊天会话标题（旧版兼容方法）
    /// - Parameters:
    ///   - messages: 会话消息列表
    ///   - endpoint: API 端点
    ///   - model: 模型名称
    ///   - apiToken: API Token（可选）
    ///   - timeout: 超时时间
    /// - Returns: 生成的标题文本
    func generateTitleLegacy(
        messages: [ChatMessage],
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 30.0
    ) async throws -> String {
        print("📝 [ChatAIService] 开始生成聊天标题，消息数量: \(messages.count)")
        
        // 只使用用户和助手消息，过滤掉系统消息
        let conversationMessages = messages.filter { $0.role == .user || $0.role == .assistant }
        
        guard !conversationMessages.isEmpty else {
            throw ChatAIError.invalidResponse
        }
        
        // 构建对话内容（限制长度，避免token过多）
        var conversationText = ""
        let maxMessages = min(conversationMessages.count, 10)  // 最多使用10条消息
        let recentMessages = Array(conversationMessages.suffix(maxMessages))
        
        for message in recentMessages {
            let role = message.role == .user ? "用户" : "助手"
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                conversationText += "\(role): \(content)\n\n"
            }
        }
        
        // 构建标题生成提示词
        let titlePrompt = """
请为以下对话生成一个简洁的标题（10-30个字符），准确概括对话的核心主题：

\(conversationText)

标题（只返回标题，不要添加任何说明或引号）：
"""
        
        // 构建 URL
        let url = try AITodoAIService.buildAPIURL(endpoint: endpoint)
        
        // 检测 API 类型
        let apiType = AITodoAIService.detectAPIType(endpoint: endpoint)
        
        // 构建请求体
        let requestBody: [String: Any]
        
        if apiType == .openAI {
            requestBody = [
                "model": model,
                "messages": [
                    [
                        "role": "user",
                        "content": titlePrompt
                    ]
                ],
                "temperature": 0.3,
                "top_p": 0.9,
                "max_tokens": 50  // 限制输出长度
            ]
        } else {
            requestBody = [
                "model": model,
                "prompt": titlePrompt,
                "stream": false,
                "options": [
                    "temperature": 0.3,
                    "top_p": 0.9,
                    "num_predict": 50  // Ollama 限制输出长度
                ]
            ]
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
        
        print("📝 [ChatAIService] 发送标题生成请求...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [ChatAIService] 标题生成失败: \(errorMessage)")
            throw ChatAIError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatAIError.invalidResponse
        }
        
        let titleText: String
        
        if apiType == .openAI {
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                titleText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                throw ChatAIError.invalidResponse
            }
        } else {
            guard let responseText = json["response"] as? String else {
                throw ChatAIError.invalidResponse
            }
            titleText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 清理标题：移除可能的引号、换行等
        let cleanedTitle = titleText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        
        // 限制标题长度（最多30个字符）
        let finalTitle = String(cleanedTitle.prefix(30))
        
        print("✅ [ChatAIService] 标题生成成功: \(finalTitle)")
        return finalTitle
    }
}


