//
//  AIChatViewModel.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

/// AI聊天ViewModel
@MainActor
class AIChatViewModel: ObservableObject {
    @Published var currentSessionId: UUID?
    @Published var inputText: String = ""
    @Published var isRecording: Bool = false
    @Published var isSending: Bool = false
    @Published var errorMessage: String?
    @Published var selectedModel: String = ""
    @Published var availableModels: [String] = []
    
    private let chatManager = ChatManager.shared
    private let chatService = ChatAIService.shared
    private let voiceService = VoiceInputService.shared
    
    var currentSession: ChatSession? {
        guard let sessionId = currentSessionId else { return nil }
        return chatManager.getSession(id: sessionId)
    }
    
    var currentMessages: [ChatMessage] {
        guard let sessionId = currentSessionId else { return [] }
        return chatManager.getMessages(for: sessionId)
    }
    
    init() {
        loadAvailableModels()
    }
    
    // MARK: - Session Management
    
    /// 创建新会话
    func createNewSession() {
        let model = selectedModel.isEmpty ? getDefaultModel() : selectedModel
        let session = chatManager.createSession(model: model)
        currentSessionId = session.id
        selectedModel = session.model
        errorMessage = nil
    }
    
    /// 选择会话
    func selectSession(_ session: ChatSession) {
        currentSessionId = session.id
        selectedModel = session.model.isEmpty ? getDefaultModel() : session.model
        errorMessage = nil
    }
    
    /// 删除会话
    func deleteSession(_ session: ChatSession) {
        if currentSessionId == session.id {
            currentSessionId = nil
        }
        chatManager.deleteSession(session)
    }
    
    /// 更新会话标题
    func updateSessionTitle(_ session: ChatSession, title: String) {
        var updated = session
        updated.title = title
        chatManager.updateSession(updated)
    }
    
    // MARK: - Model Management
    
    /// 加载可用模型列表
    private func loadAvailableModels() {
        let preferences = UserPreferences.shared
        var models: [String] = []
        
        // 从设置中获取模型
        if !preferences.aiModel.isEmpty {
            models.append(preferences.aiModel)
        }
        if !preferences.aiTodoModel.isEmpty && !models.contains(preferences.aiTodoModel) {
            models.append(preferences.aiTodoModel)
        }
        
        // 添加常用模型列表（只包含聊天类模型）
        let defaultModels = [
            "qwen-turbo",                    // 文本模型
            "qwen-plus",                     // 文本模型（增强版）
            "qwen-max",                      // 文本模型（最强版）
            "qwen-max-longcontext",          // 长文本模型
            "qwen2.5",                       // Qwen2.5 模型
            "qwen2.5-7b-instruct",           // Qwen2.5 7B 指令模型
            "qwen2.5-14b-instruct",          // Qwen2.5 14B 指令模型
            "qwen2.5-32b-instruct",          // Qwen2.5 32B 指令模型
            "qwen2.5-72b-instruct",          // Qwen2.5 72B 指令模型
            "qwen3",                         // Qwen3 模型（支持 thinking）
            "qwen3-7b-instruct",             // Qwen3 7B 指令模型（支持 thinking）
            "qwen3-14b-instruct",            // Qwen3 14B 指令模型（支持 thinking）
            "qwen3-32b-instruct",            // Qwen3 32B 指令模型（支持 thinking）
            "qwen3-vl",                      // Qwen3 视觉理解模型（支持 thinking）
            "qwen3-vl-plus",                 // Qwen3 视觉理解模型增强版（支持 thinking）
            "qwen-vl-plus",                  // 视觉理解模型
            "qwen-vl-max",                   // 视觉理解模型（最强版）
            "qwen2-audio-instruct"           // 音频理解模型
        ]
        
        // 添加默认模型（如果还没有）
        for model in defaultModels {
            if !models.contains(model) {
                models.append(model)
            }
        }
        
        // 如果没有配置，添加默认模型
        if models.isEmpty {
            models.append("qwen-turbo")  // 阿里云通义默认模型
        }
        
        availableModels = models
        selectedModel = getDefaultModel()
    }
    
    /// 获取默认模型
    private func getDefaultModel() -> String {
        let preferences = UserPreferences.shared
        if !preferences.aiModel.isEmpty {
            return preferences.aiModel
        }
        if !preferences.aiTodoModel.isEmpty {
            return preferences.aiTodoModel
        }
        return "qwen-turbo"
    }
    
    /// 切换模型
    func changeModel(_ model: String) {
        selectedModel = model
        if var session = currentSession {
            session.model = model
            chatManager.updateSession(session)
        }
    }
    
    // MARK: - Message Sending
    
    /// 发送文本消息
    func sendTextMessage(_ text: String? = nil) async {
        let messageText = text ?? inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else {
            errorMessage = "请输入消息内容"
            return
        }
        
        guard let sessionId = currentSessionId else {
            // 如果没有会话，创建一个新的
            createNewSession()
            guard let newSessionId = currentSessionId else {
                errorMessage = "无法创建会话"
                return
            }
            await sendMessage(text: messageText, sessionId: newSessionId)
            return
        }
        
        await sendMessage(text: messageText, sessionId: sessionId)
    }
    
    /// 发送消息（内部方法）
    private func sendMessage(text: String, sessionId: UUID, attachments: [ChatAttachment] = []) async {
        isSending = true
        errorMessage = nil
        
        // 创建用户消息
        let userMessage = ChatMessage(
            sessionId: sessionId,
            role: .user,
            content: text,
            contentType: attachments.isEmpty ? .text : .mixed,
            attachments: attachments,
            isSending: true
        )
        chatManager.addMessage(userMessage)
        
        // 清空输入框
        inputText = ""
        
        // 获取历史消息
        let historyMessages = chatManager.getMessages(for: sessionId)
        
        // 构建API消息列表
        var apiMessages: [[String: Any]] = []
        
        // 添加历史消息（限制数量，避免token过多）
        let recentMessages = Array(historyMessages.suffix(20))  // 只保留最近20条
        for msg in recentMessages {
            apiMessages.append(chatService.convertToAPIMessage(msg))
        }
        
        // 获取API配置
        let preferences = UserPreferences.shared
        let endpoint = preferences.aiAPIEndpoint
        let model = selectedModel.isEmpty ? getDefaultModel() : selectedModel
        let apiToken = preferences.aiAPIToken.isEmpty ? nil : preferences.aiAPIToken
        let timeout = preferences.aiTimeout > 0 ? preferences.aiTimeout : 30.0
        
        do {
            // 调用AI服务
            let result = try await chatService.sendMessage(
                messages: apiMessages,
                endpoint: endpoint,
                model: model,
                apiToken: apiToken,
                timeout: timeout,
                preferences: preferences
            )
            
            // 更新用户消息状态
            var updatedUserMessage = userMessage
            updatedUserMessage.isSending = false
            chatManager.updateMessage(updatedUserMessage)
            
            // 创建AI回复消息（包含 thinking）
            let aiMessage = ChatMessage(
                sessionId: sessionId,
                role: .assistant,
                content: result.content,
                contentType: .text,
                thinking: result.thinking
            )
            chatManager.addMessage(aiMessage)
            
            // 自动生成总结（当消息数量达到3条时）
            let allMessages = chatManager.getMessages(for: sessionId)
            let conversationMessages = allMessages.filter { $0.role == .user || $0.role == .assistant }
            if conversationMessages.count >= 3 {
                // 异步生成总结，不阻塞UI
                Task {
                    await generateSessionSummary(sessionId: sessionId)
                }
            }
            
        } catch {
            // 更新用户消息状态为失败
            var failedMessage = userMessage
            failedMessage.isSending = false
            failedMessage.sendError = error.localizedDescription
            chatManager.updateMessage(failedMessage)
            
            errorMessage = "发送失败: \(error.localizedDescription)"
            print("❌ [AIChatViewModel] 发送消息失败: \(error)")
        }
        
        isSending = false
    }
    
    // MARK: - Voice Input
    
    /// 开始语音录制
    func startVoiceRecording() {
        guard !isRecording else { return }
        
        do {
            try voiceService.startRecording()
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            isRecording = false
        }
    }
    
    /// 停止语音录制并发送
    func stopVoiceRecording() async {
        guard isRecording else { return }
        
        isRecording = false
        
        do {
            guard let recording = try await voiceService.stopRecording() else {
                errorMessage = "录音失败，未获取到音频数据"
                return
            }
            
            // 转文字
            let language = UserPreferences.shared.transcriptLanguage
            let transcribedText = try await SpeechTranscriber.transcribe(recording: recording, language: language)
            
            // 确保有会话
            if currentSessionId == nil {
                createNewSession()
            }
            
            guard let sessionId = currentSessionId else {
                errorMessage = "无法创建会话"
                return
            }
            
            // 构建音频附件（base64编码，使用PCM数据）
            let pcmData = recording.pcmData
            let base64Data = pcmData.base64EncodedString()
            
            let audioAttachment = ChatAttachment(
                type: .audio,
                base64Data: base64Data,
                fileName: "recording.pcm",
                mimeType: "audio/pcm"
            )
            
            // 发送消息（同时包含文字和音频）
            await sendMessage(
                text: transcribedText,
                sessionId: sessionId,
                attachments: [audioAttachment]
            )
            
        } catch {
            errorMessage = "语音转文字失败: \(error.localizedDescription)"
        }
    }
    
    /// 取消语音录制
    func cancelVoiceRecording() {
        voiceService.cancelRecording()
        isRecording = false
    }
    
    // MARK: - File Upload
    
    /// 选择并上传文件
    func selectAndUploadFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .image, .jpeg, .png, .gif, .webP,
            .audio, .mp3, .mpeg4Audio, .wav,
            .movie, .mpeg4Movie, .quickTimeMovie, .avi
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "选择文件"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await uploadFile(url: url)
            }
        }
    }
    
    /// 上传文件
    private func uploadFile(url: URL) async {
        guard let sessionId = currentSessionId ?? {
            createNewSession()
            return currentSessionId
        }() else {
            errorMessage = "无法创建会话"
            return
        }
        
        // 读取文件数据
        guard let fileData = try? Data(contentsOf: url) else {
            errorMessage = "无法读取文件"
            return
        }
        
        // 判断文件类型
        let contentType: ChatMessageContentType
        let mimeType: String
        let ext = url.pathExtension.lowercased()
        
        // 图片类型
        if ext == "jpg" || ext == "jpeg" {
            contentType = .image
            mimeType = "image/jpeg"
        } else if ext == "png" {
            contentType = .image
            mimeType = "image/png"
        } else if ext == "gif" {
            contentType = .image
            mimeType = "image/gif"
        } else if ext == "webp" {
            contentType = .image
            mimeType = "image/webp"
        }
        // 音频类型
        else if ext == "mp3" {
            contentType = .audio
            mimeType = "audio/mpeg"
        } else if ext == "wav" {
            contentType = .audio
            mimeType = "audio/wav"
        } else if ext == "m4a" {
            contentType = .audio
            mimeType = "audio/m4a"
        }
        // 视频类型
        else if ext == "mp4" || ext == "m4v" {
            contentType = .video
            mimeType = "video/mp4"
        } else if ext == "mov" {
            contentType = .video
            mimeType = "video/quicktime"
        } else if ext == "avi" {
            contentType = .video
            mimeType = "video/x-msvideo"
        } else if ext == "mkv" {
            contentType = .video
            mimeType = "video/x-matroska"
        } else if ext == "webm" {
            contentType = .video
            mimeType = "video/webm"
        } else {
            errorMessage = "不支持的文件类型"
            return
        }
        
        // Base64编码
        let base64Data = fileData.base64EncodedString()
        
        // 创建附件
        let attachment = ChatAttachment(
            type: contentType,
            base64Data: base64Data,
            fileName: url.lastPathComponent,
            mimeType: mimeType,
            fileSize: Int64(fileData.count)
        )
        
        // 发送消息（如果用户有输入文本，一起发送）
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultText: String
        switch contentType {
        case .image:
            defaultText = "[图片]"
        case .audio:
            defaultText = "[音频]"
        case .video:
            defaultText = "[视频]"
        default:
            defaultText = "[文件]"
        }
        await sendMessage(
            text: text.isEmpty ? defaultText : text,
            sessionId: sessionId,
            attachments: [attachment]
        )
    }
    
    // MARK: - Message Management
    
    /// 删除消息
    func deleteMessage(_ message: ChatMessage) {
        chatManager.deleteMessage(message)
    }
    
    /// 重试发送失败的消息
    func retryMessage(_ message: ChatMessage) async {
        guard message.isUserMessage && message.sendError != nil else {
            return
        }
        
        // 重新发送
        await sendMessage(
            text: message.content,
            sessionId: message.sessionId,
            attachments: message.attachments
        )
    }
    
    // MARK: - Summary Generation
    
    /// 生成会话总结
    /// 注意：总结使用的模型与聊天使用的模型相同（selectedModel 或默认的 aiModel）
    private func generateSessionSummary(sessionId: UUID) async {
        let messages = chatManager.getMessages(for: sessionId)
        guard !messages.isEmpty else { return }
        
        // 获取API配置
        let preferences = UserPreferences.shared
        let endpoint = preferences.aiAPIEndpoint
        // 使用当前选择的模型，如果没有选择则使用默认模型（preferences.aiModel）
        let model = selectedModel.isEmpty ? getDefaultModel() : selectedModel
        let apiToken = preferences.aiAPIToken.isEmpty ? nil : preferences.aiAPIToken
        let timeout = preferences.aiTimeout > 0 ? preferences.aiTimeout : 30.0
        
        do {
            let summary = try await chatService.generateSummary(
                messages: messages,
                endpoint: endpoint,
                model: model,
                apiToken: apiToken,
                timeout: timeout
            )
            
            // 更新会话总结
            chatManager.updateSessionSummary(sessionId, summary: summary)
            print("✅ [AIChatViewModel] 会话总结生成成功")
        } catch {
            print("❌ [AIChatViewModel] 生成会话总结失败: \(error.localizedDescription)")
            // 总结生成失败不影响正常使用，静默处理
        }
    }
}

