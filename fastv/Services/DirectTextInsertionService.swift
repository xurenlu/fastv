//
//  DirectTextInsertionService.swift
//  fastv
//
//  Created on 2025/12/07.
//

import Foundation
import AppKit
import ApplicationServices

/// 直接文本插入服务
/// 
/// 使用 CGEvent 直接模拟键盘输入，不依赖剪贴板
/// 优点：
/// 1. 不会干扰用户的剪贴板内容
/// 2. 不会出现剪贴板竞争导致的错误内容
/// 3. 更接近真实的键盘输入行为
///
/// 实现原理：
/// 使用 CGEventKeyboardSetUnicodeString 将文本作为 Unicode 字符序列发送
/// 每次最多发送 20 个字符（macOS 限制），对于长文本分批发送
class DirectTextInsertionService {
    static let shared = DirectTextInsertionService()
    
    private init() {}
    
    // 用于防止重入
    private var isInserting = false
    private let lock = NSLock()
    private var insertionCount = 0
    
    // 每批发送的最大字符数（macOS CGEvent 限制）
    private let maxCharsPerEvent = 20
    
    // 字符间延迟（毫秒）
    private let charDelay: UInt32 = 1000 // 1ms
    
    // 批次间延迟（毫秒）
    private let batchDelay: UInt32 = 5000 // 5ms
    
    /// 将文本直接插入到当前激活的输入框
    /// - Parameter text: 要插入的文本
    func insertText(_ text: String) {
        // 确保文本不为空
        guard !text.isEmpty else {
            print("⚠️ [DirectTextInsertionService] 文本为空，跳过插入")
            return
        }
        
        // 防止重入
        lock.lock()
        if isInserting {
            lock.unlock()
            print("⚠️ [DirectTextInsertionService] 正在插入中，跳过本次请求")
            return
        }
        isInserting = true
        insertionCount += 1
        let currentCount = insertionCount
        lock.unlock()
        
        print("═══════════════════════════════════════════════════════")
        print("📝 [DirectTextInsertionService] 开始插入操作 #\(currentCount)")
        print("📝 [DirectTextInsertionService] 要插入的文本: \"\(text.prefix(100))...\"")
        print("📝 [DirectTextInsertionService] 文本长度: \(text.count) 字符")
        print("═══════════════════════════════════════════════════════")
        
        // 在主线程执行
        if Thread.isMainThread {
            performDirectInsertion(text, operationId: currentCount)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performDirectInsertion(text, operationId: currentCount)
            }
        }
    }
    
    /// 执行直接文本插入
    private func performDirectInsertion(_ text: String, operationId: Int) {
        let startTime = Date()
        
        // 创建事件源
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("❌ [DirectTextInsertionService] 无法创建事件源")
            finishInsertion(operationId: operationId)
            return
        }
        
        // 将文本转换为 Unicode 字符数组
        let characters = Array(text.utf16)
        let totalChars = characters.count
        var insertedChars = 0
        
        print("⌨️ [#\(operationId)] 开始发送 \(totalChars) 个字符...")
        
        // 分批发送字符
        var offset = 0
        while offset < totalChars {
            let endIndex = min(offset + maxCharsPerEvent, totalChars)
            let batch = Array(characters[offset..<endIndex])
            
            // 发送这一批字符
            if !sendCharacterBatch(batch, source: source, operationId: operationId) {
                print("❌ [#\(operationId)] 发送字符批次失败，已发送 \(insertedChars)/\(totalChars) 字符")
                break
            }
            
            insertedChars += batch.count
            offset = endIndex
            
            // 批次间延迟
            if offset < totalChars {
                usleep(batchDelay)
            }
        }
        
        let duration = Date().timeIntervalSince(startTime) * 1000 // 转换为毫秒
        print("✅ [#\(operationId)] 完成发送 \(insertedChars)/\(totalChars) 字符，耗时 \(String(format: "%.2f", duration))ms")
        
        finishInsertion(operationId: operationId)
    }
    
    /// 发送一批字符
    private func sendCharacterBatch(_ chars: [UInt16], source: CGEventSource, operationId: Int) -> Bool {
        // 创建键盘事件
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            print("❌ [#\(operationId)] 无法创建键盘事件")
            return false
        }
        
        // 设置 Unicode 字符串
        var buffer = chars
        keyDown.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &buffer)
        keyUp.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &buffer)
        
        // 发送事件
        keyDown.post(tap: .cghidEventTap)
        usleep(charDelay)
        keyUp.post(tap: .cghidEventTap)
        usleep(charDelay)
        
        return true
    }
    
    /// 完成插入操作
    private func finishInsertion(operationId: Int) {
        // 延迟重置状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.lock.lock()
            self?.isInserting = false
            self?.lock.unlock()
            print("✅ [DirectTextInsertionService] 插入操作 #\(operationId) 完成")
            print("═══════════════════════════════════════════════════════")
        }
    }
    
    /// 检查是否有辅助功能权限
    static func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// 请求辅助功能权限
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

