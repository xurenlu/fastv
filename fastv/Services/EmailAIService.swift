//
//  EmailAIService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 邮件AI服务
class EmailAIService {
    static let shared = EmailAIService()
    
    private let chatAIService = ChatAIService.shared
    private let preferences = UserPreferences.shared
    
    private init() {}
    
    /// 获取邮件的文本内容（优先使用 textBody，否则从 htmlBody 提取）
    private func getTextContent(from message: EmailMessage) -> String {
        // 优先使用 textBody
        if let textBody = message.textBody, !textBody.isEmpty {
            return textBody
        }
        
        // 如果 textBody 为空，从 htmlBody 提取纯文本
        if let htmlBody = message.htmlBody, !htmlBody.isEmpty {
            return htmlBody.strippingHTML()
        }
        
        // 最后使用 preview
        return message.preview
    }
    
    // MARK: - Auto Reply
    
    /// 生成自动回复
    func generateAutoReply(for message: EmailMessage, template: String? = nil) async throws -> String {
        let config = await MainActor.run {
            preferences.getConfig(for: .aiChat)
        }
        let templateText = await MainActor.run {
            template ?? preferences.emailAutoReplyTemplate
        }
        
        let textContent = getTextContent(from: message)
        
        let prompt = """
        请为以下邮件生成一封礼貌、专业的自动回复。
        
        原邮件主题：\(message.subject)
        发件人：\(message.from.displayName)
        邮件内容：
        \(textContent)
        
        回复模板（如果适用）：
        \(templateText.isEmpty ? "标准自动回复" : templateText)
        
        请生成一封简洁、专业的自动回复邮件正文。
        """
        
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        
        let prefs = await MainActor.run {
            preferences
        }
        
        let result = try await chatAIService.sendMessage(
            messages: messages,
            profile: config.profile,
            model: config.model,
            timeout: config.timeout,
            preferences: prefs
        )
        
        return result.content
    }
    
    // MARK: - Smart Tagging
    
    /// 生成智能标签
    func generateSmartTags(for message: EmailMessage) async throws -> [String] {
        let config = await MainActor.run {
            preferences.getConfig(for: .aiChat)
        }
        
        let textContent = getTextContent(from: message)
        
        let prompt = """
        分析以下邮件内容，为其生成3-5个标签。标签应该简洁、有意义，能够帮助分类和检索。
        
        邮件主题：\(message.subject)
        发件人：\(message.from.displayName)
        邮件内容：\(textContent)
        
        请只返回标签，用逗号分隔，不要其他解释。
        例如：工作,紧急,发票,待处理
        """
        
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        
        let prefs = await MainActor.run {
            preferences
        }
        
        let result = try await chatAIService.sendMessage(
            messages: messages,
            profile: config.profile,
            model: config.model,
            timeout: config.timeout,
            preferences: prefs
        )
        
        // 解析标签
        let tags = result.content
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return tags
    }
    
    // MARK: - Priority Detection
    
    /// 识别邮件优先级
    func detectPriority(for message: EmailMessage) async throws -> EmailPriority {
        let config = await MainActor.run {
            preferences.getConfig(for: .aiChat)
        }
        
        let textContent = getTextContent(from: message)
        
        let prompt = """
        分析以下邮件，判断其优先级（low/normal/high/urgent）。
        
        邮件主题：\(message.subject)
        发件人：\(message.from.displayName)
        邮件内容：\(textContent)
        
        请只返回优先级（low/normal/high/urgent），不要其他解释。
        """
        
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        
        let prefs = await MainActor.run {
            preferences
        }
        
        let result = try await chatAIService.sendMessage(
            messages: messages,
            profile: config.profile,
            model: config.model,
            timeout: config.timeout,
            preferences: prefs
        )
        
        let priorityString = result.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if priorityString.contains("urgent") {
            return .urgent
        } else if priorityString.contains("high") {
            return .high
        } else if priorityString.contains("low") {
            return .low
        } else {
            return .normal
        }
    }
    
    // MARK: - Summary Generation
    
    /// 生成邮件摘要
    func generateSummary(for message: EmailMessage) async throws -> String {
        let config = await MainActor.run {
            preferences.getConfig(for: .aiChat)
        }
        
        let textContent = getTextContent(from: message)
        
        let prompt = """
        为以下邮件生成一个简洁的摘要（50-100字）。
        
        邮件主题：\(message.subject)
        发件人：\(message.from.displayName)
        邮件内容：
        \(textContent)
        
        请生成摘要，突出关键信息和行动项。
        """
        
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        
        let prefs = await MainActor.run {
            preferences
        }
        
        let result = try await chatAIService.sendMessage(
            messages: messages,
            profile: config.profile,
            model: config.model,
            timeout: config.timeout,
            preferences: prefs
        )
        
        return result.content
    }
    
    // MARK: - Duplicate Detection
    
    /// 检测是否为重复邮件
    func isDuplicate(_ message: EmailMessage, comparedTo messages: [EmailMessage]) async throws -> Bool {
        // 简单的重复检测：比较主题和发件人
        let similarMessages = messages.filter { other in
            other.id != message.id &&
            other.from.email == message.from.email &&
            other.subject.lowercased() == message.subject.lowercased()
        }
        
        if !similarMessages.isEmpty {
            return true
        }
        
        // 使用AI进行更智能的重复检测
        let config = await MainActor.run {
            preferences.getConfig(for: .aiChat)
        }
        
        let recentSubjects = messages.prefix(10).map { $0.subject }.joined(separator: "\n")
        let textContent = getTextContent(from: message)
        
        let prompt = """
        判断以下邮件是否与最近收到的邮件重复或高度相似。
        
        当前邮件：
        主题：\(message.subject)
        发件人：\(message.from.displayName)
        内容：\(textContent)
        
        最近邮件主题列表：
        \(recentSubjects)
        
        请只返回"是"或"否"，不要其他解释。
        """
        
        let aiMessages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        
        let prefs = await MainActor.run {
            preferences
        }
        
        let result = try await chatAIService.sendMessage(
            messages: aiMessages,
            profile: config.profile,
            model: config.model,
            timeout: config.timeout,
            preferences: prefs
        )
        
        return result.content.lowercased().contains("是")
    }
    
    // MARK: - Email Body Polish
    
    /// 邮件正文润色模式
    enum PolishMode {
        case chineseFormal      // 中文商务润色
        case englishEmail       // 英文邮件格式
        case translateToChinese // 翻译成中文并美化
        case translateToEnglish // 翻译成英文并美化
    }
    
    /// 润色邮件正文
    /// - Parameters:
    ///   - text: 原始正文文本
    ///   - mode: 润色模式（中文商务、英文邮件或翻译并美化）
    /// - Returns: 润色后的正文文本
    func polishEmailBody(text: String, mode: PolishMode) async throws -> String {
        // 检查输入文本是否有效
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw NSError(domain: "EmailAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "正文内容为空"])
        }
        
        let config = await MainActor.run {
            preferences.getConfig(for: .aiChat)
        }
        
        let prompt: String
        switch mode {
        case .chineseFormal:
            prompt = """
            请将以下邮件正文改写为更正式、商务化的中文邮件格式。要求：
            1. 保持原意不变
            2. 使用得体的商务用语和礼貌措辞
            3. 结构清晰，段落分明
            4. 符合常见商务邮件规范
            5. 如果原文较短，请添加适当的商务礼貌用语（如"顺祝商祺"、"此致敬礼"等）
            6. 确保格式美观，段落分明
            
            原始正文：
            \(trimmedText)
            
            请直接返回改写后的正文，不要添加任何解释或说明。
            """
        case .englishEmail:
            prompt = """
            Please rewrite the following email body into a professional, native English email format. Requirements:
            1. Keep the original meaning unchanged
            2. Use appropriate business English expressions and polite language
            3. Include proper greeting (e.g., "Dear", "Hello") and closing (e.g., "Best regards", "Sincerely")
            4. Structure clearly with well-organized paragraphs
            5. Follow common English email conventions
            6. If the original text is short, add appropriate professional closing phrases
            
            Original text:
            \(trimmedText)
            
            Please return only the rewritten email body, without any explanations or notes.
            """
        case .translateToChinese:
            prompt = """
            请将以下邮件正文翻译成中文，并改写为正式、商务化的中文邮件格式。要求：
            1. 准确翻译原意
            2. 使用得体的商务用语和礼貌措辞
            3. 结构清晰，段落分明
            4. 符合常见商务邮件规范
            5. 添加适当的商务礼貌用语（如"顺祝商祺"、"此致敬礼"等）
            6. 确保格式美观，段落分明
            
            原始正文：
            \(trimmedText)
            
            请直接返回翻译并改写后的正文，不要添加任何解释或说明。
            """
        case .translateToEnglish:
            prompt = """
            Please translate the following email body into English and rewrite it into a professional, native English email format. Requirements:
            1. Accurately translate the original meaning
            2. Use appropriate business English expressions and polite language
            3. Include proper greeting (e.g., "Dear", "Hello") and closing (e.g., "Best regards", "Sincerely")
            4. Structure clearly with well-organized paragraphs
            5. Follow common English email conventions
            
            Original text:
            \(trimmedText)
            
            Please return only the translated and rewritten email body, without any explanations or notes.
            """
        }
        
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        
        let prefs = await MainActor.run {
            preferences
        }
        
        let result = try await chatAIService.sendMessage(
            messages: messages,
            profile: config.profile,
            model: config.model,
            timeout: config.timeout,
            preferences: prefs
        )
        
        // 清理返回结果，移除可能的引号或多余格式
        var polishedText = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果 AI 返回的内容被引号包裹，移除引号
        if polishedText.hasPrefix("\"") && polishedText.hasSuffix("\"") {
            polishedText = String(polishedText.dropFirst().dropLast())
        }
        if polishedText.hasPrefix("'") && polishedText.hasSuffix("'") {
            polishedText = String(polishedText.dropFirst().dropLast())
        }
        
        return polishedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Action Suggestions
    
    /// 生成行动建议
    func generateActionSuggestions(for message: EmailMessage) async throws -> [String] {
        let config = await MainActor.run {
            preferences.getConfig(for: .aiChat)
        }
        
        let textContent = getTextContent(from: message)
        
        let prompt = """
        分析以下邮件，生成2-3个建议的行动项。
        
        邮件主题：\(message.subject)
        发件人：\(message.from.displayName)
        邮件内容：\(textContent)
        
        请生成简洁的行动建议，每行一个。
        """
        
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        
        let prefs = await MainActor.run {
            preferences
        }
        
        let result = try await chatAIService.sendMessage(
            messages: messages,
            profile: config.profile,
            model: config.model,
            timeout: config.timeout,
            preferences: prefs
        )
        
        let suggestions = result.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasPrefix("•") }
            .prefix(3)
        
        return Array(suggestions)
    }
}

