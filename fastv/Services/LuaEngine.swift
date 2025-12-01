//
//  LuaEngine.swift
//  fastv
//
//  Created for Email Rule Engine
//

import Foundation

/// 简单的字符串错误类型
struct LuaError: Error, LocalizedError, Sendable {
    let message: String
    
    var errorDescription: String? {
        return message
    }
}

/// Lua 引擎封装
/// 提供 Swift 与 Lua 脚本引擎的桥接
/// 注意：当前 Lua 功能未集成，所有方法返回未初始化错误
final class LuaEngine: @unchecked Sendable {
    static let shared = LuaEngine()
    
    // Lua 功能当前未启用
    private var isInitialized = false
    
    private init() {
        // Lua 功能当前未集成
        print("⚠️ [LuaEngine] Lua 功能当前未启用")
    }
    
    /// 加载 Lua 脚本文件
    func loadScript(from filePath: String) async -> Result<Void, LuaError> {
        // Lua 功能未启用
        return .failure(LuaError(message: "Lua 功能未启用"))
    }
    
    /// 加载 Lua 代码字符串
    func loadScript(_ code: String) async -> Result<Void, LuaError> {
        // Lua 功能未启用
        return .failure(LuaError(message: "Lua 功能未启用"))
    }
    
    /// 调用 Lua 函数
    func callFunction(_ functionName: String, arguments: [Any] = []) async -> Result<Any?, LuaError> {
        // Lua 功能未启用
        return .failure(LuaError(message: "Lua 功能未启用"))
    }
    
    /// 设置全局变量
    func setGlobal(_ name: String, value: Any) async -> Result<Void, LuaError> {
        // Lua 功能未启用
        return .failure(LuaError(message: "Lua 功能未启用"))
    }
    
    /// 获取全局变量
    func getGlobal(_ name: String) async -> Result<Any?, LuaError> {
        // Lua 功能未启用
        return .failure(LuaError(message: "Lua 功能未启用"))
    }
    
    /// 注册 Swift 函数到 Lua
    func registerFunction(_ name: String, block: @escaping ([Any]) -> Any?) {
        // Lua 功能未启用
        print("⚠️ [LuaEngine] 无法注册函数，Lua 功能未启用")
    }
    
    /// 检查是否已初始化
    var initialized: Bool {
        return isInitialized
    }
}

/// Lua 引擎错误 - 保留用于兼容性
enum LuaEngineError: LocalizedError {
    case notInitialized
    case loadFailed(String)
    case executionFailed(String)
    case setGlobalFailed(String)
    case functionNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Lua 引擎未初始化，请确保 Lua 库已正确集成"
        case .loadFailed(let message):
            return "加载 Lua 脚本失败: \(message)"
        case .executionFailed(let message):
            return "执行 Lua 脚本失败: \(message)"
        case .setGlobalFailed(let message):
            return "设置全局变量失败: \(message)"
        case .functionNotFound(let name):
            return "Lua 函数 '\(name)' 未找到"
        }
    }
}
