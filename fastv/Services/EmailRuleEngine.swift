//
//  EmailRuleEngine.swift
//  fastv
//
//  Created for Email Rule Engine
//

import Foundation
import Combine

/// 邮件规则引擎
/// 使用 Lua 脚本引擎处理邮件规则
@MainActor
class EmailRuleEngine: ObservableObject {
    static let shared = EmailRuleEngine()
    
    private let luaEngine = LuaEngine.shared
    private var rulesLoaded = false
    private let rulesDirectory: URL
    private let defaultRulesFile: URL
    
    private init() {
        // 规则脚本存储目录
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rulesDirectory = appSupport.appendingPathComponent("fastv/Rules")
        
        // 默认规则文件
        defaultRulesFile = rulesDirectory.appendingPathComponent("default_rules.lua")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: rulesDirectory, withIntermediateDirectories: true)
        
        // 初始化时加载规则
        Task {
            await loadRules()
        }
    }
    
    /// 加载规则脚本
    func loadRules() async {
        // 如果 Lua 引擎未初始化，跳过
        guard luaEngine.initialized else {
            print("⚠️ [EmailRuleEngine] Lua 引擎未初始化，跳过规则加载")
            return
        }
        
        // 检查默认规则文件是否存在，如果不存在则从模板创建
        if !FileManager.default.fileExists(atPath: defaultRulesFile.path) {
            await createDefaultRulesFile()
        }
        
        // 加载默认规则文件 - 使用 Result 类型避免崩溃
        let result = await luaEngine.loadScript(from: defaultRulesFile.path)
        switch result {
        case .success:
            rulesLoaded = true
            print("✅ [EmailRuleEngine] 规则脚本加载成功")
        case .failure(let error):
            print("❌ [EmailRuleEngine] 加载规则脚本失败: \(error.message)")
            rulesLoaded = false
        }
        
        // 加载其他规则文件
        await loadAdditionalRules()
    }
    
    /// 从模板创建默认规则文件
    private func createDefaultRulesFile() async {
        // 从 Resources 目录读取模板
        guard let templatePath = Bundle.main.path(forResource: "rule_template", ofType: "lua") else {
            print("⚠️ [EmailRuleEngine] 未找到规则模板文件")
            return
        }
        
        do {
            let templateContent = try String(contentsOfFile: templatePath, encoding: .utf8)
            try templateContent.write(to: defaultRulesFile, atomically: true, encoding: .utf8)
            print("✅ [EmailRuleEngine] 已创建默认规则文件")
        } catch {
            // 使用 NSError 的描述，避免类型转换问题
            let nsError = error as NSError
            print("❌ [EmailRuleEngine] 创建默认规则文件失败: \(nsError.localizedDescription)")
        }
    }
    
    /// 加载额外的规则文件
    private func loadAdditionalRules() async {
        guard let files = try? FileManager.default.contentsOfDirectory(at: rulesDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for file in files where file.pathExtension == "lua" && file != defaultRulesFile {
            let result = await luaEngine.loadScript(from: file.path)
            switch result {
            case .success:
                print("✅ [EmailRuleEngine] 加载规则文件: \(file.lastPathComponent)")
            case .failure(let error):
                print("⚠️ [EmailRuleEngine] 加载规则文件失败 \(file.lastPathComponent): \(error.message)")
            }
        }
    }
    
    /// 处理邮件，应用规则
    /// - Parameter message: 要处理的邮件
    /// - Returns: 处理后的邮件（已应用规则结果）
    func processMessage(_ message: EmailMessage) async -> EmailMessage {
        guard rulesLoaded else {
            print("⚠️ [EmailRuleEngine] 规则未加载，跳过处理")
            return message
        }
        
        // 将邮件转换为 Lua 表
        let emailTable = convertMessageToLuaTable(message)
        
        // 调用 Lua 规则处理函数 - 使用 Result 类型
        let result = await luaEngine.callFunction("processEmail", arguments: [emailTable])
        switch result {
        case .success(let value):
            // 解析结果并更新邮件
            if let resultDict = value as? [String: Any] {
                return applyRuleResult(to: message, result: resultDict)
            }
        case .failure(let error):
            print("❌ [EmailRuleEngine] 执行规则失败: \(error.message)")
        }
        
        return message
    }
    
    /// 将 EmailMessage 转换为 Lua 表（Swift Dictionary）
    private func convertMessageToLuaTable(_ message: EmailMessage) -> [String: Any] {
        var table: [String: Any] = [:]
        
        table["id"] = message.id.uuidString
        table["accountId"] = message.accountId.uuidString
        table["folderId"] = message.folderId?.uuidString
        table["subject"] = message.subject
        table["from"] = [
            "name": message.from.name ?? "",
            "email": message.from.email
        ]
        table["to"] = message.to.map { ["name": $0.name ?? "", "email": $0.email] }
        table["cc"] = message.cc.map { ["name": $0.name ?? "", "email": $0.email] }
        table["textBody"] = message.textBody ?? ""
        table["htmlBody"] = message.htmlBody ?? ""
        table["preview"] = message.preview
        table["date"] = message.date.timeIntervalSince1970
        table["isRead"] = message.isRead
        table["hasAttachments"] = message.hasAttachments
        table["tags"] = message.tags
        
        return table
    }
    
    /// 应用规则结果到邮件
    private func applyRuleResult(to message: EmailMessage, result: [String: Any]) -> EmailMessage {
        var updatedMessage = message
        
        // 更新重要标记
        if let isImportant = result["isImportant"] as? Bool {
            updatedMessage.isImportant = isImportant
        }
        
        // 更新垃圾邮件标记
        if let isSpam = result["isSpam"] as? Bool {
            updatedMessage.isSpam = isSpam
        }
        
        // 更新订阅邮件标记（可以通过标签实现）
        if let isSubscription = result["isSubscription"] as? Bool, isSubscription {
            if !updatedMessage.tags.contains("订阅") {
                updatedMessage.tags.append("订阅")
            }
        }
        
        // 更新标签
        if let tags = result["tags"] as? [String] {
            // 合并标签，避免重复
            for tag in tags {
                if !updatedMessage.tags.contains(tag) {
                    updatedMessage.tags.append(tag)
                }
            }
        }
        
        // 更新优先级
        if let priorityString = result["priority"] as? String {
            if let priority = EmailPriority(rawValue: priorityString) {
                updatedMessage.aiPriority = priority
            }
        }
        
        return updatedMessage
    }
    
    /// 测试规则（用于规则管理界面）
    func testRule(_ ruleCode: String, with message: EmailMessage) async throws -> [String: Any] {
        // 临时加载规则代码
        let loadResult = await luaEngine.loadScript(ruleCode)
        if case .failure(let error) = loadResult {
            throw EmailRuleEngineError.loadFailed(error.message)
        }
        
        // 转换邮件
        let emailTable = convertMessageToLuaTable(message)
        
        // 执行规则
        let callResult = await luaEngine.callFunction("processEmail", arguments: [emailTable])
        
        // 重新加载正常规则
        await loadRules()
        
        switch callResult {
        case .success(let value):
            if let resultDict = value as? [String: Any] {
                return resultDict
            }
            return [:]
        case .failure(let error):
            throw EmailRuleEngineError.executionFailed(error.message)
        }
    }
    
    /// 获取规则文件路径
    func getRulesDirectory() -> URL {
        return rulesDirectory
    }
    
    /// 保存规则文件
    func saveRuleFile(_ filename: String, content: String) async throws {
        let fileURL = rulesDirectory.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        
        // 重新加载规则
        await loadRules()
    }
    
    /// 列出所有规则文件
    func listRuleFiles() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: rulesDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return files.filter { $0.pathExtension == "lua" }.map { $0.lastPathComponent }
    }
}

/// 邮件规则引擎错误
enum EmailRuleEngineError: LocalizedError {
    case rulesNotLoaded
    case loadFailed(String)
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .rulesNotLoaded:
            return "规则未加载"
        case .loadFailed(let message):
            return "加载规则失败: \(message)"
        case .executionFailed(let message):
            return "执行规则失败: \(message)"
        }
    }
}
