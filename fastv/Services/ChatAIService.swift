//
//  ChatAIService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import OSLog

/// 用于 AI 网络日志的 Logger（生产构建里 .private/.sensitive 字段不会被记录）
private let chatAILogger = Logger(subsystem: "com.fastv.ai", category: "ChatAI")

/// 把响应体截断 + 抹掉常见敏感字段，用于日志输出（仅 DEBUG 才会调用）
fileprivate func sanitizeResponseBody(_ raw: String, limit: Int = 500) -> String {
    var s = raw
    let patterns = [
        #""(?:api[_-]?key|authorization|token|access[_-]?token|bearer|cookie|set-cookie)"\s*:\s*"[^"]*""#,
        #"sk-[A-Za-z0-9_\-]{8,}"#,
        #"Bearer\s+[A-Za-z0-9_\-\.]+"#,
    ]
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "\"<redacted>\"")
        }
    }
    if s.count > limit {
        s = String(s.prefix(limit)) + "…(+\(s.count - limit) chars)"
    }
    return s
}

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
        
        chatAILogger.log("发送请求到 AI（超时: \(effectiveTimeout, privacy: .public)秒），协议: \(profile.protocolType.displayName, privacy: .public)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAIError.invalidResponse
        }

        chatAILogger.log("收到响应，状态码: \(httpResponse.statusCode, privacy: .public)，长度: \(data.count, privacy: .public)")

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            #if DEBUG
            chatAILogger.error("请求失败 (\(httpResponse.statusCode, privacy: .public)): \(sanitizeResponseBody(errorMessage), privacy: .public)")
            #else
            chatAILogger.error("请求失败 (\(httpResponse.statusCode, privacy: .public))")
            #endif
            throw ChatAIError.requestFailed(httpResponse.statusCode, errorMessage)
        }

        return try adapter.parseResponse(data: data, for: profile)
    }
    
    /// 流式发送聊天消息（SSE）
    /// - Parameters:
    ///   - messages: OpenAI 风格的 messages 数组（method 内部会按协议自动转换）
    ///   - profile: AI 服务配置
    ///   - model: 模型名称
    ///   - timeout: 超时（用于 URLRequest.timeoutInterval）
    ///   - systemPrompt: 仅 Ollama 等需要 system 字段的协议会用到
    /// - Returns: 文本增量的异步流。每次 yield 都是「相对上次的新增片段」。
    ///   失败会抛 ChatAIError；如果远端不支持流式，请改用 sendMessage(...)。
    func sendMessageStream(
        messages: [[String: Any]],
        profile: AIServiceProfile,
        model: String? = nil,
        timeout: Double? = nil,
        systemPrompt: String? = nil,
        preferences: UserPreferences? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let effectiveModel = model ?? profile.defaultModel
        let effectiveTimeout = timeout ?? profile.timeout

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    let adapter = AIServiceAdapter.shared

                    // DashScope 原生模式要把 messages 里的 String content 拍成 [{text: ...}]
                    let endpoint = profile.effectiveEndpoint.lowercased()
                    let usesDashScopeCompatibleMode = endpoint.contains("compatible-mode") || endpoint.contains("/chat/completions")
                    let convertedMessages: [[String: Any]]
                    if profile.protocolType == .dashScope && !usesDashScopeCompatibleMode {
                        convertedMessages = messages.map { msg in
                            var m = msg
                            if let content = msg["content"] as? String {
                                m["content"] = [["text": content]]
                            }
                            return m
                        }
                    } else {
                        convertedMessages = messages
                    }

                    let baseBody = adapter.buildRequestBody(
                        for: profile,
                        messages: convertedMessages,
                        model: effectiveModel,
                        systemPrompt: systemPrompt,
                        temperature: preferences?.chatTemperature,
                        topP: preferences?.chatTopP,
                        maxTokens: preferences?.chatMaxTokens,
                        additionalParams: buildAdditionalParams(for: profile, preferences: preferences)
                    )
                    let body = adapter.enableStreaming(in: baseBody, for: profile)

                    let url = try adapter.buildStreamURL(for: profile, model: effectiveModel)
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = effectiveTimeout
                    for (k, v) in adapter.buildStreamHeaders(for: profile) {
                        request.setValue(v, forHTTPHeaderField: k)
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ChatAIError.invalidResponse
                    }
                    guard http.statusCode == 200 else {
                        // 错误响应是普通 JSON / 文本，攒一下吐出去
                        var errorBuffer = Data()
                        for try await byte in bytes {
                            errorBuffer.append(byte)
                            if errorBuffer.count > 4096 { break }
                        }
                        let errMsg = String(data: errorBuffer, encoding: .utf8) ?? "未知错误"
                        throw ChatAIError.requestFailed(http.statusCode, errMsg)
                    }

                    var pendingEvent = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.isEmpty {
                            // 事件结束
                            if !pendingEvent.isEmpty {
                                let chunk = adapter.parseStreamChunk(pendingEvent, for: profile)
                                if !chunk.isEmpty { continuation.yield(chunk) }
                                pendingEvent = ""
                            }
                            continue
                        }
                        // SSE 形式："data: {...}"；Ollama / Gemini(alt=sse) 也是这个模式
                        if line.hasPrefix("data:") {
                            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                            if payload == "[DONE]" { break }
                            pendingEvent = payload
                        } else if line.hasPrefix(":") || line.hasPrefix("event:") || line.hasPrefix("id:") {
                            // SSE 注释 / 事件名 / id，忽略
                            continue
                        } else {
                            // 没前缀：Ollama 直接吐 JSONL；按一整行解析
                            let chunk = adapter.parseStreamChunk(line, for: profile)
                            if !chunk.isEmpty { continuation.yield(chunk) }
                        }
                    }
                    // 收尾，处理没空行结束的最后一段
                    if !pendingEvent.isEmpty {
                        let chunk = adapter.parseStreamChunk(pendingEvent, for: profile)
                        if !chunk.isEmpty { continuation.yield(chunk) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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
        chatAILogger.log("开始生成聊天总结，消息数量: \(messages.count, privacy: .public)")
        
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
        
        chatAILogger.log("发送总结生成请求")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            #if DEBUG
            chatAILogger.error("总结生成失败: \(sanitizeResponseBody(errorMessage), privacy: .public)")
            #else
            chatAILogger.error("总结生成失败 (\(httpResponse.statusCode, privacy: .public))")
            #endif
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
        
        chatAILogger.log("总结生成成功，长度: \(summaryText.count, privacy: .public)（内容已脱敏不入日志）")
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
        chatAILogger.log("开始生成聊天标题，消息数量: \(messages.count, privacy: .public)")
        
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
        
        chatAILogger.log("发送标题生成请求")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            #if DEBUG
            chatAILogger.error("标题生成失败: \(sanitizeResponseBody(errorMessage), privacy: .public)")
            #else
            chatAILogger.error("标题生成失败 (\(httpResponse.statusCode, privacy: .public))")
            #endif
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
        
        chatAILogger.log("标题生成成功，长度: \(finalTitle.count, privacy: .public)")
        return finalTitle
    }
}


