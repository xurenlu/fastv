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
    /// - Parameters:
    ///   - message: 邮件消息
    ///   - config: AI配置元组（可选，如果为nil则从preferences获取）
    ///   - preferences: 用户偏好设置（可选，如果为nil则从MainActor获取）
    func generateSmartTags(for message: EmailMessage, config: (profile: AIServiceProfile, model: String, timeout: Double)? = nil, preferences: UserPreferences? = nil) async throws -> [String] {
        // 在后台线程一次性获取配置，避免多次切换到主线程
        let effectiveConfig: (profile: AIServiceProfile, model: String, timeout: Double)
        let effectivePrefs: UserPreferences
        
        if let config = config, let prefs = preferences {
            effectiveConfig = config
            effectivePrefs = prefs
        } else {
            // 如果未提供配置，则一次性从主线程获取
            let (configResult, prefs) = await MainActor.run {
                (self.preferences.getConfig(for: .aiChat), self.preferences)
            }
            effectiveConfig = configResult
            effectivePrefs = prefs
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
        
        let result = try await chatAIService.sendMessage(
            messages: messages,
            profile: effectiveConfig.profile,
            model: effectiveConfig.model,
            timeout: effectiveConfig.timeout,
            preferences: effectivePrefs
        )
        
        // 解析标签
        let tags = result.content
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return tags
    }
    
    // MARK: - Priority Detection
    
    /// 识别邮件优先级
    /// - Parameters:
    ///   - message: 邮件消息
    ///   - config: AI配置元组（可选，如果为nil则从preferences获取）
    ///   - preferences: 用户偏好设置（可选，如果为nil则从MainActor获取）
    func detectPriority(for message: EmailMessage, config: (profile: AIServiceProfile, model: String, timeout: Double)? = nil, preferences: UserPreferences? = nil) async throws -> EmailPriority {
        // 在后台线程一次性获取配置，避免多次切换到主线程
        let effectiveConfig: (profile: AIServiceProfile, model: String, timeout: Double)
        let effectivePrefs: UserPreferences
        
        if let config = config, let prefs = preferences {
            effectiveConfig = config
            effectivePrefs = prefs
        } else {
            // 如果未提供配置，则一次性从主线程获取
            let (configResult, prefs) = await MainActor.run {
                (self.preferences.getConfig(for: .aiChat), self.preferences)
            }
            effectiveConfig = configResult
            effectivePrefs = prefs
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
        
        let result = try await chatAIService.sendMessage(
            messages: messages,
            profile: effectiveConfig.profile,
            model: effectiveConfig.model,
            timeout: effectiveConfig.timeout,
            preferences: effectivePrefs
        )
        
        let priorityString = result.content.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
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
    /// - Parameters:
    ///   - message: 邮件消息
    ///   - config: AI配置元组（可选，如果为nil则从preferences获取）
    ///   - preferences: 用户偏好设置（可选，如果为nil则从MainActor获取）
    func generateSummary(for message: EmailMessage, config: (profile: AIServiceProfile, model: String, timeout: Double)? = nil, preferences: UserPreferences? = nil) async throws -> String {
        // 在后台线程一次性获取配置，避免多次切换到主线程
        let effectiveConfig: (profile: AIServiceProfile, model: String, timeout: Double)
        let effectivePrefs: UserPreferences
        
        if let config = config, let prefs = preferences {
            effectiveConfig = config
            effectivePrefs = prefs
        } else {
            // 如果未提供配置，则一次性从主线程获取
            let (configResult, prefs) = await MainActor.run {
                (self.preferences.getConfig(for: .aiChat), self.preferences)
            }
            effectiveConfig = configResult
            effectivePrefs = prefs
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
        
        let result = try await chatAIService.sendMessage(
            messages: messages,
            profile: effectiveConfig.profile,
            model: effectiveConfig.model,
            timeout: effectiveConfig.timeout,
            preferences: effectivePrefs
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
    
    // MARK: - Translate (纯翻译，保留原结构，不做改写/润色)

    /// 把邮件正文按段翻译成中文（或英文）；保持换行/段落，不增删信息、不做"商务化润色"。
    /// - Parameters:
    ///   - text: 原始正文文本（已剥过 HTML）
    ///   - targetLanguage: "中文" 或 "英文" 等自然语言名
    /// - Returns: 翻译后的纯文本
    func translate(text: String, targetLanguage: String = "中文") async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "EmailAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "正文内容为空"])
        }

        // 翻译走独立的「邮件翻译」场景：用户可在「AI 场景映射」里单独指定服务/模型，
        // 未绑定时 getConfig 会回退到默认 Profile，再回退到旧版兼容配置。
        let config = await MainActor.run { preferences.getConfig(for: .emailTranslate) }
        let prefs = await MainActor.run { preferences }

        let systemPrompt = """
        你是一名专业的邮件翻译助手。请把用户提供的邮件正文翻译成「\(targetLanguage)」。

        【严格要求】
        1. **只做翻译，不改写、不润色、不增删任何内容**；不要加问候/落款等原文没有的内容
        2. 保留原文的换行、空行、列表符号（如 - / 1. / •）、缩进等结构
        3. 链接 URL、邮箱地址、代码片段、专有名词（公司/产品/人名）原样保留不翻译
        4. 引用符号「>」开头的引用行翻译其内容，符号本身保留
        5. 输出**只包含翻译后的正文本身**，不要任何前后说明、不要写"以下是翻译"等
        6. 不要用 Markdown 代码块包裹结果
        """

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": trimmed],
        ]

        let result = try await chatAIService.sendMessage(
            messages: messages,
            profile: config.profile,
            model: config.model,
            timeout: config.timeout,
            preferences: prefs
        )

        var translated = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        // 兜底：偶尔模型会用 ```...``` 包裹
        if translated.hasPrefix("```") {
            if let firstNewline = translated.firstIndex(of: "\n") {
                translated = String(translated[translated.index(after: firstNewline)...])
            }
            if translated.hasSuffix("```") {
                translated = String(translated.dropLast(3))
            }
            translated = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return translated
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
    
    // MARK: - HTML Layout Optimization
    
    /// AI智能优化邮件HTML排版
    /// - Parameters:
    ///   - htmlBody: 原始HTML正文
    ///   - textBody: 纯文本正文（作为备用）
    ///   - existingStyles: 已应用的CSS样式信息
    /// - Returns: 优化后的HTML正文
    func optimizeHTMLLayout(htmlBody: String, textBody: String?, existingStyles: String? = nil) async throws -> String {
        // 检查输入是否有效
        let trimmedHTML = htmlBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHTML.isEmpty else {
            throw NSError(domain: "EmailAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "邮件正文为空"])
        }
        
        let config = await MainActor.run {
            preferences.getConfig(for: .aiChat)
        }
        
        // 从HTML中提取纯文本内容
        let textContent = htmlBody.strippingHTML()
        
        let styleInfo = existingStyles ?? """
        软件内置浏览器会自动添加以下CSS样式：
        - 使用 -apple-system, PingFang SC 等系统字体
        - 基础字号 16px，行高 1.6
        - 主要文字颜色 #1d1d1f
        - 链接颜色 #007AFF
        - 标题使用 600 字重
        - 图片圆角 8px
        - 代码块背景色 #f5f5f7
        - 表格边框颜色 #e5e5e5
        """
        
        let prompt = """
        请优化以下邮件HTML的排版布局，使其更加美观易读。要求：

        1. **保持内容完整**：不要改变原文意思、不要删除任何信息
        2. **优化HTML结构**：
           - 使用语义化标签（如 <h1>-<h6>、<p>、<ul>、<ol>、<blockquote> 等）
           - 合理分段，每个段落用 <p> 标签包裹
           - 列表内容用 <ul> 或 <ol> 标签
           - 重要信息可用 <strong> 或 <em> 强调
        3. **移除冗余**：
           - 删除多余的 <table> 布局标签（改用语义化标签）
           - 移除内联样式（style属性），因为软件会自动应用美观的CSS
           - 删除 &nbsp; 等HTML实体（用正常空格或段落间距）
        4. **格式美化**：
           - 长段落合理断句
           - 引用内容用 <blockquote>
           - 代码用 <code> 或 <pre><code>
           - 链接保留 <a> 标签
        5. **考虑现有样式**：
        \(styleInfo)

        原始HTML：
        \(trimmedHTML)
        
        纯文本内容（供参考）：
        \(textContent)
        
        请直接返回优化后的HTML代码，只需要 <body> 标签内的内容，不要包含 <!DOCTYPE>、<html>、<head> 等标签。
        不要添加任何解释说明，直接返回HTML代码。
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
        
        // 清理返回结果
        var optimizedHTML = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 移除可能的代码块标记
        if optimizedHTML.hasPrefix("```html") {
            optimizedHTML = optimizedHTML.replacingOccurrences(of: "```html", with: "")
            optimizedHTML = optimizedHTML.replacingOccurrences(of: "```", with: "")
            optimizedHTML = optimizedHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if optimizedHTML.hasPrefix("```") {
            optimizedHTML = optimizedHTML.replacingOccurrences(of: "```", with: "")
            optimizedHTML = optimizedHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 移除可能的 <!DOCTYPE>、<html>、<head>、<body> 标签
        let patterns = [
            "<!DOCTYPE[^>]*>",
            "<html[^>]*>",
            "</html>",
            "<head[^>]*>.*?</head>",
            "<body[^>]*>",
            "</body>"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(optimizedHTML.startIndex..., in: optimizedHTML)
                optimizedHTML = regex.stringByReplacingMatches(in: optimizedHTML, options: [], range: range, withTemplate: "")
            }
        }
        
        return optimizedHTML.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

