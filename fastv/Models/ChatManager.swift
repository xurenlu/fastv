//
//  ChatManager.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 聊天管理器
@MainActor
class ChatManager: ObservableObject {
    static let shared = ChatManager()
    
    @Published private(set) var sessions: [ChatSession] = []
    @Published private(set) var messages: [UUID: [ChatMessage]] = [:]  // sessionId -> messages
    
    private let maxSessions = 1000  // 最多保存1000个会话
    private let maxMessagesPerSession = 1000  // 每个会话最多1000条消息
    private let sessionsStorageKey = "chatSessions"
    private let messagesStorageKey = "chatMessages"
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 2.0  // 延迟2秒保存，避免频繁写入
    
    private init() {
        // 异步加载，避免阻塞启动
        Task { @MainActor in
            await loadSessions()
            await loadMessages()
        }
    }
    
    // MARK: - Session Management
    
    /// 创建新会话
    func createSession(title: String? = nil, model: String = "") -> ChatSession {
        let session = ChatSession(
            title: title ?? ChatSession.generateDefaultTitle(),
            model: model
        )
        sessions.insert(session, at: 0)
        messages[session.id] = []
        
        // 限制会话数量
        if sessions.count > maxSessions {
            let removedSessions = Array(sessions.suffix(sessions.count - maxSessions))
            sessions.removeSubrange(maxSessions..<sessions.count)
            // 删除被移除会话的消息
            for removedSession in removedSessions {
                messages.removeValue(forKey: removedSession.id)
            }
        }
        
        scheduleSave()
        return session
    }
    
    /// 更新会话
    func updateSession(_ session: ChatSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
            return
        }
        
        var updatedSession = session
        updatedSession.updatedAt = Date()
        sessions[index] = updatedSession
        scheduleSave()
    }
    
    /// 删除会话
    func deleteSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        messages.removeValue(forKey: session.id)
        scheduleSave()
    }
    
    /// 获取会话
    func getSession(id: UUID) -> ChatSession? {
        sessions.first { $0.id == id }
    }
    
    // MARK: - Message Management
    
    /// 添加消息
    func addMessage(_ message: ChatMessage) {
        var sessionMessages = messages[message.sessionId] ?? []
        sessionMessages.append(message)
        
        // 限制消息数量
        if sessionMessages.count > maxMessagesPerSession {
            sessionMessages.removeFirst(sessionMessages.count - maxMessagesPerSession)
        }
        
        messages[message.sessionId] = sessionMessages
        
        // 更新会话的最后消息预览和更新时间
        if let index = sessions.firstIndex(where: { $0.id == message.sessionId }) {
            var updatedSession = sessions[index]
            updatedSession.updatedAt = Date()
            updatedSession.messageCount = sessionMessages.count
            if message.role == .user || message.role == .assistant {
                updatedSession.lastMessagePreview = message.content.isEmpty ? nil : String(message.content.prefix(50))
            }
            sessions[index] = updatedSession
        }
        
        scheduleSave()
    }
    
    /// 更新消息
    func updateMessage(_ message: ChatMessage) {
        guard var sessionMessages = messages[message.sessionId] else {
            return
        }
        
        guard let index = sessionMessages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        
        var updatedMessage = message
        updatedMessage.updatedAt = Date()
        sessionMessages[index] = updatedMessage
        messages[message.sessionId] = sessionMessages
        scheduleSave()
    }
    
    /// 删除消息
    func deleteMessage(_ message: ChatMessage) {
        guard var sessionMessages = messages[message.sessionId] else {
            return
        }
        
        sessionMessages.removeAll { $0.id == message.id }
        messages[message.sessionId] = sessionMessages
        
        // 更新会话的消息数量
        if let index = sessions.firstIndex(where: { $0.id == message.sessionId }) {
            var updatedSession = sessions[index]
            updatedSession.messageCount = sessionMessages.count
            updatedSession.lastMessagePreview = sessionMessages.last?.content.isEmpty == false ? String(sessionMessages.last!.content.prefix(50)) : nil
            sessions[index] = updatedSession
        }
        
        scheduleSave()
    }
    
    /// 获取会话的消息列表
    func getMessages(for sessionId: UUID) -> [ChatMessage] {
        messages[sessionId] ?? []
    }
    
    /// 更新会话总结
    func updateSessionSummary(_ sessionId: UUID, summary: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            return
        }
        
        var updatedSession = sessions[index]
        updatedSession.summary = summary
        updatedSession.updatedAt = Date()
        sessions[index] = updatedSession
        scheduleSave()
    }
    
    /// 清空会话的所有消息
    func clearMessages(for sessionId: UUID) {
        messages[sessionId] = []
        
        // 更新会话
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            var updatedSession = sessions[index]
            updatedSession.messageCount = 0
            updatedSession.lastMessagePreview = nil
            updatedSession.summary = nil
            updatedSession.updatedAt = Date()
            sessions[index] = updatedSession
        }
        
        scheduleSave()
    }
    
    // MARK: - Persistence
    
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveAll()
            }
        }
    }
    
    private func saveAll() {
        let sessionsToSave = sessions
        let messagesToSave = messages
        
        Task.detached(priority: .background) {
            // 保存会话
            if let encoded = try? JSONEncoder().encode(sessionsToSave) {
                UserDefaults.standard.set(encoded, forKey: self.sessionsStorageKey)
            }
            
            // 保存消息（需要转换为可编码格式）
            let messagesDict: [String: [ChatMessage]] = Dictionary(uniqueKeysWithValues: messagesToSave.map { (key, value) in
                (key.uuidString, value)
            })
            if let encoded = try? JSONEncoder().encode(messagesDict) {
                UserDefaults.standard.set(encoded, forKey: self.messagesStorageKey)
            }
        }
    }
    
    private func loadSessions() async {
        let data = UserDefaults.standard.data(forKey: sessionsStorageKey)
        
        guard let data = data else {
            await MainActor.run {
                sessions = []
            }
            return
        }
        
        let decoded = await Task.detached(priority: .userInitiated) {
            try? JSONDecoder().decode([ChatSession].self, from: data)
        }.value
        
        await MainActor.run {
            sessions = decoded ?? []
        }
    }
    
    private func loadMessages() async {
        let data = UserDefaults.standard.data(forKey: messagesStorageKey)
        
        guard let data = data else {
            await MainActor.run {
                messages = [:]
            }
            return
        }
        
        let decoded = await Task.detached(priority: .userInitiated) {
            try? JSONDecoder().decode([String: [ChatMessage]].self, from: data)
        }.value
        
        await MainActor.run {
            if let decoded = decoded {
                messages = Dictionary(uniqueKeysWithValues: decoded.map { (key, value) in
                    (UUID(uuidString: key)!, value)
                })
            } else {
                messages = [:]
            }
        }
    }
}

