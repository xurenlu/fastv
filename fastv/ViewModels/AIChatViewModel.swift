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
    @Published var selectedProfileId: UUID?  // 选中的 Provider
    @Published var selectedModel: String = ""
    @Published var availableProfiles: [AIServiceProfile] = []  // 可用于聊天的 Provider 列表
    @Published var availableModels: [String] = []
    @Published var pendingAttachments: [ChatAttachment] = []  // 待发送的附件列表
    @Published var currentMessages: [ChatMessage] = []  // 当前会话的消息列表
    
    private let chatManager = ChatManager.shared
    private let chatService = ChatAIService.shared
    private let voiceService = VoiceInputService.shared
    private var cancellables = Set<AnyCancellable>()
    
    var currentSession: ChatSession? {
        guard let sessionId = currentSessionId else { return nil }
        return chatManager.getSession(id: sessionId)
    }
    
    init() {
        loadAvailableProfiles()
        loadAvailableModels()
        
        // 监听 ChatManager 的消息变化
        chatManager.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messagesDict in
                guard let self = self else { return }
                // 只在当前会话的消息变化时更新
                if let sessionId = self.currentSessionId {
                    let newMessages = messagesDict[sessionId] ?? []
                    // 只在消息列表真正变化时更新（比较数量和ID列表，避免不必要的UI刷新）
                    if newMessages.count != self.currentMessages.count ||
                       newMessages.map({ $0.id }) != self.currentMessages.map({ $0.id }) {
                        self.currentMessages = newMessages
                    }
                } else {
                    self.currentMessages = []
                }
            }
            .store(in: &cancellables)
        
        // 监听会话ID的变化
        $currentSessionId
            .sink { [weak self] sessionId in
                guard let self = self else { return }
                if let sessionId = sessionId {
                    self.currentMessages = self.chatManager.getMessages(for: sessionId)
                } else {
                    self.currentMessages = []
                }
            }
            .store(in: &cancellables)
        
        // 初始化消息列表
        updateCurrentMessages()
    }
    
    /// 更新当前消息列表
    private func updateCurrentMessages() {
        guard let sessionId = currentSessionId else {
            currentMessages = []
            return
        }
        currentMessages = chatManager.getMessages(for: sessionId)
    }
    
    // MARK: - Session Management
    
    /// 创建新会话
    func createNewSession() {
        let model = selectedModel.isEmpty ? getDefaultModel() : selectedModel
        let session = chatManager.createSession(model: model)
        currentSessionId = session.id
        selectedModel = session.model
        errorMessage = nil
        loadAvailableProfiles()
        loadAvailableModels()
    }
    
    /// 选择会话
    func selectSession(_ session: ChatSession) {
        currentSessionId = session.id
        selectedModel = session.model.isEmpty ? getDefaultModel() : session.model
        errorMessage = nil
        loadAvailableProfiles()
        loadAvailableModels()
        updateCurrentMessages()
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
    
    // MARK: - Provider & Model Management
    
    /// 当前选中的 Profile（用于发送消息）
    var selectedProfile: AIServiceProfile? {
        if let pid = selectedProfileId, let p = UserPreferences.shared.getProfile(id: pid) {
            return p
        }
        let config = UserPreferences.shared.getConfig(for: .aiChat)
        return config.profile
    }
    
    /// 加载可用于聊天的 Provider 列表（已配置 API Key 或 Ollama 无需 Key）
    private func loadAvailableProfiles() {
        let prefs = UserPreferences.shared
        var profiles = prefs.aiServiceProfiles.filter { p in
            !p.protocolType.requiresAPIKey || !p.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if profiles.isEmpty {
            profiles = prefs.aiServiceProfiles
        }
        availableProfiles = profiles
        
        // 若当前选中的 Provider 不在列表中，重置为默认或第一个
        if let pid = selectedProfileId, !profiles.contains(where: { $0.id == pid }) {
            selectedProfileId = prefs.getConfig(for: .aiChat).profile.id
            if !availableProfiles.contains(where: { $0.id == selectedProfileId }) {
                selectedProfileId = availableProfiles.first?.id
            }
        }
        if selectedProfileId == nil {
            selectedProfileId = prefs.getConfig(for: .aiChat).profile.id
            if !availableProfiles.contains(where: { $0.id == selectedProfileId }) {
                selectedProfileId = availableProfiles.first?.id
            }
        }
    }
    
    /// 加载可用模型列表（根据选中的 Provider 动态加载）
    private func loadAvailableModels() {
        guard let profile = selectedProfile else {
            let config = UserPreferences.shared.getConfig(for: .aiChat)
            var models = config.profile.protocolType.recommendedModels
            if models.isEmpty { models = ["qwen-flash", "qwen-max"] }
            availableModels = models
            if selectedModel.isEmpty { selectedModel = getDefaultModel() }
            return
        }
        var models = profile.protocolType.recommendedModels
        if models.isEmpty {
            models = ["qwen-flash", "qwen-max", "qwen-vl-plus", "qwen-vl-max"]
        }
        if !selectedModel.isEmpty && !models.contains(selectedModel) {
            models.insert(selectedModel, at: 0)
        }
        availableModels = models
        if selectedModel.isEmpty {
            selectedModel = getDefaultModel()
        }
    }
    
    /// 获取默认模型
    private func getDefaultModel() -> String {
        let preferences = UserPreferences.shared
        if !preferences.aiModel.isEmpty && availableModels.contains(preferences.aiModel) {
            return preferences.aiModel
        }
        return "qwen-flash"
    }
    
    /// 判断当前 Provider + 模型是否支持图片/多模态
    func supportsImage() -> Bool {
        guard let profile = selectedProfile else { return false }
        return profile.protocolType.supportsVision(model: selectedModel)
    }
    
    /// 判断模型是否支持附件
    func supportsAttachment() -> Bool {
        return supportsImage()  // 目前只有支持图片的模型支持附件
    }
    
    /// 判断模型是否支持语音
    func supportsVoice() -> Bool {
        return false  // 目前都不支持语音，留待将来
    }
    
    /// 切换 Provider
    func changeProfile(_ profileId: UUID) {
        selectedProfileId = profileId
        loadAvailableModels()
        if !supportsAttachment() {
            pendingAttachments.removeAll()
        }
    }
    
    /// 切换模型
    func changeModel(_ model: String) {
        selectedModel = model
        if !supportsAttachment() {
            pendingAttachments.removeAll()
        }
        if var session = currentSession {
            session.model = model
            chatManager.updateSession(session)
        }
    }
    
    // MARK: - Message Sending
    
    /// 发送文本消息
    func sendTextMessage(_ text: String? = nil) async {
        let messageText = text ?? inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果没有文本且没有待发送的附件，提示用户
        guard !messageText.isEmpty || !pendingAttachments.isEmpty else {
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
            await sendMessage(text: messageText.isEmpty ? " " : messageText, sessionId: newSessionId, attachments: pendingAttachments)
            pendingAttachments.removeAll()  // 清空待发送的附件
            return
        }
        
        await sendMessage(text: messageText.isEmpty ? " " : messageText, sessionId: sessionId, attachments: pendingAttachments)
        pendingAttachments.removeAll()  // 清空待发送的附件
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
        
        // 清空输入框（附件已在 sendTextMessage 中清空）
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
        
        // 获取 API 配置：优先使用选中的 Provider
        let preferences = UserPreferences.shared
        let profile = selectedProfile ?? preferences.getConfig(for: .aiChat).profile
        let config = preferences.getConfig(for: .aiChat)
        let model = selectedModel.isEmpty ? config.model : selectedModel
        let timeout = config.timeout
        
        do {
            let startTime = Date()
            let result = try await chatService.sendMessage(
                messages: apiMessages,
                profile: profile,
                model: model,
                timeout: timeout,
                preferences: preferences
            )
            let responseTime = Date().timeIntervalSince(startTime)

            // 更新用户消息状态
            var updatedUserMessage = userMessage
            updatedUserMessage.isSending = false
            chatManager.updateMessage(updatedUserMessage)

            // 创建AI回复消息（包含 thinking 和响应耗时）
            let aiMessage = ChatMessage(
                sessionId: sessionId,
                role: .assistant,
                content: result.content,
                contentType: .text,
                thinking: result.thinking,
                responseTimeSeconds: responseTime
            )
            chatManager.addMessage(aiMessage)
            
            // 自动生成总结和标题
            let allMessages = chatManager.getMessages(for: sessionId)
            let conversationMessages = allMessages.filter { $0.role == .user || $0.role == .assistant }
            
            // 计算聊天内容总长度
            let totalLength = conversationMessages.reduce(0) { $0 + $1.content.count }
            
            // 检查是否需要生成标题（内容超过100字且标题还是默认的）
            if let session = chatManager.getSession(id: sessionId),
               session.title.hasPrefix("新对话") && totalLength >= 100 {
                // 异步生成标题，不阻塞UI
                Task {
                    await generateSessionTitle(sessionId: sessionId)
                }
            }
            
            // 当消息数量达到3条时生成总结
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
        guard supportsVoice() else {
            errorMessage = "当前模型不支持语音功能"
            return
        }
        
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
            let transcribedText = try await SpeechTranscriber.transcribe(recording: recording, language: language, enableCTCDeduplication: nil)
            
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
        guard supportsAttachment() else {
            errorMessage = NSLocalizedString("chat.attachment.not.supported", comment: "")
            return
        }
        
        let panel = NSOpenPanel()
        // 只允许图片类型
        panel.allowedContentTypes = [
            .image, .jpeg, .png, .gif, .webP
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "选择图片"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await addImageAttachment(url: url)
            }
        }
    }
    
    /// 添加图片附件（不立即发送）
    private func addImageAttachment(url: URL) async {
        // 确保有会话
        if currentSessionId == nil {
            createNewSession()
        }
        
        guard currentSessionId != nil else {
            errorMessage = "无法创建会话"
            return
        }
        
        // 读取文件数据
        guard let fileData = try? Data(contentsOf: url) else {
            errorMessage = "无法读取文件"
            return
        }
        
        // 判断文件类型
        let mimeType: String
        let ext = url.pathExtension.lowercased()
        
        // 只支持图片类型
        if ext == "jpg" || ext == "jpeg" {
            mimeType = "image/jpeg"
        } else if ext == "png" {
            mimeType = "image/png"
        } else if ext == "gif" {
            mimeType = "image/gif"
        } else if ext == "webp" {
            mimeType = "image/webp"
        } else {
            errorMessage = "不支持的文件类型，仅支持图片"
            return
        }
        
        // Base64编码
        let base64Data = fileData.base64EncodedString()
        
        // 创建附件并添加到待发送列表
        let attachment = ChatAttachment(
            type: .image,
            base64Data: base64Data,
            fileName: url.lastPathComponent,
            mimeType: mimeType,
            fileSize: Int64(fileData.count)
        )
        
        pendingAttachments.append(attachment)
        errorMessage = nil  // 清除错误信息
    }
    
    /// 删除待发送的附件
    func removePendingAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }
    
    // MARK: - Message Management
    
    /// 删除消息
    func deleteMessage(_ message: ChatMessage) {
        chatManager.deleteMessage(message)
    }
    
    /// 重试发送失败的消息（先删除失败消息，再重新发送，避免重复）
    func retryMessage(_ message: ChatMessage) async {
        guard message.isUserMessage && message.sendError != nil else {
            return
        }
        
        let text = message.content
        let sessionId = message.sessionId
        let attachments = message.attachments
        
        // 先删除失败的用户消息，避免重复
        chatManager.deleteMessage(message)
        
        // 重新发送
        await sendMessage(text: text, sessionId: sessionId, attachments: attachments)
    }
    
    /// 重新生成 AI 回复（删除当前 AI 回复，基于原用户消息重新请求）
    func regenerateResponse(for aiMessage: ChatMessage) async {
        guard aiMessage.isAIMessage else { return }
        guard let sessionId = currentSessionId, sessionId == aiMessage.sessionId else { return }
        
        let messages = chatManager.getMessages(for: sessionId)
        guard let aiIndex = messages.firstIndex(where: { $0.id == aiMessage.id }) else { return }
        
        // 找到该 AI 消息之前的最后一条用户消息
        let messagesBeforeAI = Array(messages.prefix(aiIndex))
        guard let lastUserMessage = messagesBeforeAI.last(where: { $0.role == .user }) else {
            return
        }
        
        // 删除当前 AI 回复
        chatManager.deleteMessage(aiMessage)
        
        // 使用原用户消息重新请求 AI（不创建新的用户消息）
        isSending = true
        errorMessage = nil
        
        let historyMessages = chatManager.getMessages(for: sessionId)
        var apiMessages: [[String: Any]] = []
        let recentMessages = Array(historyMessages.suffix(20))
        for msg in recentMessages {
            apiMessages.append(chatService.convertToAPIMessage(msg))
        }
        
        let preferences = UserPreferences.shared
        let profile = selectedProfile ?? preferences.getConfig(for: .aiChat).profile
        let config = preferences.getConfig(for: .aiChat)
        let model = selectedModel.isEmpty ? config.model : selectedModel
        
        do {
            let startTime = Date()
            let result = try await chatService.sendMessage(
                messages: apiMessages,
                profile: profile,
                model: model,
                timeout: config.timeout,
                preferences: preferences
            )
            let responseTime = Date().timeIntervalSince(startTime)

            let newAIMessage = ChatMessage(
                sessionId: sessionId,
                role: .assistant,
                content: result.content,
                contentType: .text,
                thinking: result.thinking,
                responseTimeSeconds: responseTime
            )
            chatManager.addMessage(newAIMessage)
            
            // 异步生成标题和总结（如需要）
            let allMessages = chatManager.getMessages(for: sessionId)
            let conversationMessages = allMessages.filter { $0.role == .user || $0.role == .assistant }
            let totalLength = conversationMessages.reduce(0) { $0 + $1.content.count }
            
            if let session = chatManager.getSession(id: sessionId),
               session.title.hasPrefix("新对话") && totalLength >= 100 {
                Task { await generateSessionTitle(sessionId: sessionId) }
            }
            if conversationMessages.count >= 3 {
                Task { await generateSessionSummary(sessionId: sessionId) }
            }
        } catch {
            errorMessage = "重新生成失败: \(error.localizedDescription)"
            print("❌ [AIChatViewModel] 重新生成失败: \(error)")
        }
        
        isSending = false
    }
    
    // MARK: - Summary Generation
    
    /// 生成会话标题
    /// 注意：标题使用的模型与聊天使用的模型相同（selectedModel 或默认的 aiModel）
    private func generateSessionTitle(sessionId: UUID) async {
        let messages = chatManager.getMessages(for: sessionId)
        guard !messages.isEmpty else { return }
        
        let preferences = UserPreferences.shared
        let profile = selectedProfile ?? preferences.getConfig(for: .aiChat).profile
        let config = preferences.getConfig(for: .aiChat)
        let model = selectedModel.isEmpty ? config.model : selectedModel
        
        do {
            let title = try await chatService.generateTitle(
                messages: messages,
                profile: profile,
                model: model,
                timeout: config.timeout
            )
            
            // 更新会话标题
            chatManager.updateSessionTitle(sessionId, title: title)
            print("✅ [AIChatViewModel] 会话标题生成成功: \(title)")
        } catch {
            print("❌ [AIChatViewModel] 生成会话标题失败: \(error.localizedDescription)")
            // 标题生成失败不影响正常使用，静默处理
        }
    }
    
    /// 生成会话总结
    /// 注意：总结使用的模型与聊天使用的模型相同（selectedModel 或默认的 aiModel）
    private func generateSessionSummary(sessionId: UUID) async {
        let messages = chatManager.getMessages(for: sessionId)
        guard !messages.isEmpty else { return }

        let preferences = UserPreferences.shared
        let profile = selectedProfile ?? preferences.getConfig(for: .aiChat).profile
        let config = preferences.getConfig(for: .aiChat)
        let model = selectedModel.isEmpty ? config.model : selectedModel

        do {
            let summary = try await chatService.generateSummary(
                messages: messages,
                profile: profile,
                model: model,
                timeout: config.timeout
            )

            // 更新会话总结
            chatManager.updateSessionSummary(sessionId, summary: summary)
            print("✅ [AIChatViewModel] 会话总结生成成功")
        } catch {
            print("❌ [AIChatViewModel] 生成会话总结失败: \(error.localizedDescription)")
            // 总结生成失败不影响正常使用，静默处理
        }
    }

    /// 清理资源（在视图销毁时调用）
    /// 由于 @MainActor 类的 deinit 可能在主线程上执行，这里提供一个显式的清理方法
    func cleanup() {
        cancellables.removeAll()
        #if DEBUG
        print("🧹 [AIChatViewModel] 已清理 Combine 订阅")
        #endif
    }

    deinit {
        cancellables.removeAll()
        #if DEBUG
        print("🧹 [AIChatViewModel] deinit - 已清理所有订阅")
        #endif
    }
}

