//
//  EmailRuleAIService.swift
//  fastv
//
//  Created for Email Rule Engine AI Integration
//

import Foundation
import Combine

/// 邮件规则 AI 服务
/// 使用 AI 生成和修改 Lua 规则脚本
@MainActor
class EmailRuleAIService: ObservableObject {
    static let shared = EmailRuleAIService()
    
    private let chatAIService = ChatAIService.shared
    private let preferences = UserPreferences.shared
    private let ruleEngine = EmailRuleEngine.shared
    
    private init() {}
    
    /// 根据自然语言描述生成规则脚本
    /// - Parameter description: 规则的自然语言描述
    /// - Returns: 生成的 Lua 规则代码
    func generateRule(from description: String) async throws -> String {
        let config = preferences.getConfig(for: .aiChat)
        
        // 读取现有规则模板作为参考
        let existingRules = await getExistingRules()
        
        let prompt = """
        请根据以下描述生成一个 Lua 规则函数。
        
        用户需求：\(description)
        
        现有规则模板参考：
        \(existingRules)
        
        要求：
        1. 生成的代码必须是有效的 Lua 语法
        2. 函数应该接收 email 表作为参数
        3. 函数应该返回布尔值或表
        4. 如果需要修改现有规则，请提供完整的函数代码
        5. 只返回 Lua 代码，不要包含其他解释
        
        邮件对象结构：
        - email.subject: 主题
        - email.from.email: 发件人邮箱
        - email.from.name: 发件人名称
        - email.textBody: 纯文本正文
        - email.preview: 预览文本
        - email.hasAttachments: 是否有附件
        - email.tags: 标签列表
        
        请生成符合要求的 Lua 规则代码：
        """
        
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        
        let result = try await chatAIService.sendMessage(
            messages: messages,
            profile: config.profile,
            model: config.model,
            timeout: config.timeout,
            preferences: preferences
        )
        
        return extractLuaCode(from: result.content)
    }
    
    /// 修改现有规则
    /// - Parameters:
    ///   - ruleName: 规则名称
    ///   - modification: 修改描述
    /// - Returns: 修改后的规则代码
    func modifyRule(_ ruleName: String, modification: String) async throws -> String {
        let config = preferences.getConfig(for: .aiChat)
        
        let existingRule = await getRuleFunction(ruleName)
        
        let prompt = """
        请根据以下修改要求更新 Lua 规则函数。
        
        规则名称：\(ruleName)
        
        现有规则代码：
        \(existingRule)
        
        修改要求：\(modification)
        
        要求：
        1. 保持函数名称和基本结构不变
        2. 只修改必要的部分
        3. 确保代码语法正确
        4. 只返回完整的函数代码，不要包含其他解释
        
        请生成修改后的 Lua 规则代码：
        """
        
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        
        let result = try await chatAIService.sendMessage(
            messages: messages,
            profile: config.profile,
            model: config.model,
            timeout: config.timeout,
            preferences: preferences
        )
        
        return extractLuaCode(from: result.content)
    }
    
    /// 验证规则代码语法
    /// - Parameter code: Lua 代码
    /// - Returns: 验证结果和错误信息（如果有）
    func validateRule(_ code: String) async -> (isValid: Bool, error: String?) {
        do {
            // 尝试加载规则代码
            try await ruleEngine.testRule(code, with: EmailMessage(
                accountId: UUID(),
                subject: "Test",
                from: EmailContact(email: "test@example.com"),
                preview: "Test email"
            ))
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    /// 获取现有规则内容
    private func getExistingRules() async -> String {
        guard let templatePath = Bundle.main.path(forResource: "rule_template", ofType: "lua"),
              let content = try? String(contentsOfFile: templatePath, encoding: .utf8) else {
            return "-- 未找到规则模板"
        }
        return content
    }
    
    /// 获取特定规则函数
    private func getRuleFunction(_ functionName: String) async -> String {
        // 尝试从默认规则文件读取
        let rulesDir = ruleEngine.getRulesDirectory()
        let defaultRulesFile = rulesDir.appendingPathComponent("default_rules.lua")
        
        if let content = try? String(contentsOf: defaultRulesFile, encoding: .utf8) {
            // 简单提取函数（实际应该用更智能的方式）
            if let range = content.range(of: "function \(functionName)") {
                let start = range.lowerBound
                let remaining = String(content[start...])
                // 查找函数结束（简单实现）
                if let endRange = remaining.range(of: "\nend\n") {
                    return String(remaining[..<endRange.upperBound])
                }
            }
        }
        
        return "-- 未找到规则函数"
    }
    
    /// 从 AI 响应中提取 Lua 代码
    private func extractLuaCode(from response: String) -> String {
        // 尝试提取代码块
        if let codeBlockRange = response.range(of: "```lua") {
            let start = codeBlockRange.upperBound
            let remaining = String(response[start...])
            if let endRange = remaining.range(of: "```") {
                return String(remaining[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // 如果没有代码块标记，尝试提取 function 到 end 之间的内容
        if let functionRange = response.range(of: "function") {
            let start = functionRange.lowerBound
            let remaining = String(response[start...])
            // 查找最后一个 end
            if let endRange = remaining.range(of: "end", options: .backwards) {
                return String(remaining[..<endRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // 如果都找不到，返回原始响应
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

