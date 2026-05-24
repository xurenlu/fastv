//
//  TextInsertionService.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AppKit
import ApplicationServices

/// 文本插入服务
/// 
/// 重要说明：
/// 此服务使用剪贴板 + Cmd+V 的方式将文本插入到当前激活的输入框。
/// 为了避免插入错误的内容，我们：
/// 1. 先清空剪贴板
/// 2. 设置新内容并验证
/// 3. 等待足够时间确保剪贴板稳定
/// 4. 发送 Cmd+V 粘贴命令
class TextInsertionService {
    static let shared = TextInsertionService()
    
    private init() {}
    
    // 记录最后一次插入的文本，用于调试
    private var lastInsertedText: String?
    private var insertionCount = 0
    // 用于防止重入 - 使用 os_unfair_lock 替代 NSLock，性能更好
    private var isInserting = false
    private var lock = os_unfair_lock()
    
    /// 将文本插入到当前激活的输入框
    /// - Parameter text: 要插入的文本
    func insertText(_ text: String) {
        // 确保文本不为空
        guard !text.isEmpty else {
            print("⚠️ [TextInsertionService] 文本为空，跳过插入")
            return
        }
        
        // 防止重入
        os_unfair_lock_lock(&lock)
        if isInserting {
            os_unfair_lock_unlock(&lock)
            print("⚠️ [TextInsertionService] 正在插入中，跳过本次请求")
            return
        }
        isInserting = true
        insertionCount += 1
        let currentCount = insertionCount
        os_unfair_lock_unlock(&lock)
        
        print("═══════════════════════════════════════════════════════")
        print("📝 [TextInsertionService] 开始插入操作 #\(currentCount)")
        print("📝 [TextInsertionService] 文本长度: \(text.count) 字符")
        print("═══════════════════════════════════════════════════════")
        
        // 直接在当前线程执行（避免死锁）
        // 如果不在主线程，切换到主线程
        if Thread.isMainThread {
            performTextInsertionSafely(text, operationId: currentCount)
            finishInsertion(text: text, operationId: currentCount)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performTextInsertionSafely(text, operationId: currentCount)
                self?.finishInsertion(text: text, operationId: currentCount)
            }
        }
    }
    
    private func finishInsertion(text: String, operationId: Int) {
        // 延迟重置状态，确保粘贴完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            os_unfair_lock_lock(&self.lock)
            self.lastInsertedText = text
            self.isInserting = false
            os_unfair_lock_unlock(&self.lock)
            print("✅ [TextInsertionService] 插入操作 #\(operationId) 完成")
            print("═══════════════════════════════════════════════════════")
        }
    }
    
    /// 安全地执行文本插入（必须在主线程调用）
    private func performTextInsertionSafely(_ text: String, operationId: Int) {
        let pasteboard = NSPasteboard.general
        
        // 记录操作前的剪贴板状态
        let oldContentLength = pasteboard.string(forType: .string)?.count ?? 0
        let changeCountBefore = pasteboard.changeCount
        print("📋 [#\(operationId)] 操作前剪贴板: changeCount=\(changeCountBefore), 文本长度=\(oldContentLength)")
        
        // ========== 第一步：清空剪贴板 ==========
        pasteboard.clearContents()
        Thread.sleep(forTimeInterval: 0.05) // 50ms
        
        let afterClear = pasteboard.string(forType: .string)
        print("📋 [#\(operationId)] 清空后剪贴板状态: \(afterClear == nil ? "nil (正确)" : "仍有文本，长度=\(afterClear?.count ?? 0)")")
        
        // ========== 第二步：设置新内容 ==========
        let success = pasteboard.setString(text, forType: .string)
        if !success {
            print("❌ [#\(operationId)] setString 返回 false!")
        }
        
        Thread.sleep(forTimeInterval: 0.05) // 50ms
        
        // ========== 第三步：验证剪贴板内容 ==========
        let changeCountAfter = pasteboard.changeCount
        guard let currentContent = pasteboard.string(forType: .string) else {
            print("❌ [#\(operationId)] 无法读取剪贴板内容!")
            return
        }
        
        print("📋 [#\(operationId)] 设置后剪贴板: changeCount=\(changeCountAfter), 文本长度=\(currentContent.count)")
        
        if currentContent != text {
            print("❌ [#\(operationId)] 剪贴板内容不匹配!")
            print("   预期长度: \(text.count)")
            print("   实际长度: \(currentContent.count)")
            print("   这可能是因为其他程序修改了剪贴板!")
            
            // 强制重试
            for retry in 1...3 {
                print("🔄 [#\(operationId)] 重试 \(retry)/3...")
                pasteboard.clearContents()
                Thread.sleep(forTimeInterval: 0.03)
                pasteboard.setString(text, forType: .string)
                Thread.sleep(forTimeInterval: 0.03)
                
                if let retryContent = pasteboard.string(forType: .string), retryContent == text {
                    print("✅ [#\(operationId)] 重试 \(retry) 成功")
                    break
                }
            }
        } else {
            print("✅ [#\(operationId)] 剪贴板内容验证通过")
        }
        
        // ========== 第四步：最终等待 ==========
        Thread.sleep(forTimeInterval: 0.05) // 50ms
        
        // 最终验证
        if let finalContent = pasteboard.string(forType: .string) {
            print("📋 [#\(operationId)] 发送粘贴前最终验证: 文本长度=\(finalContent.count)")
            if finalContent != text {
                print("⚠️ [#\(operationId)] 警告: 剪贴板在最终验证时内容不匹配!")
            }
        }
        
        // ========== 第五步：发送粘贴快捷键 ==========
        print("⌨️ [#\(operationId)] 发送 Cmd+V...")
        sendPasteCommand()
        print("⌨️ [#\(operationId)] Cmd+V 已发送")
    }
    
    /// 发送粘贴命令 (Cmd+V)
    private func sendPasteCommand() {
        // 使用 hidSystemState 而不是 combinedSessionState
        // hidSystemState 更底层，更可靠
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("❌ [TextInsertionService] 无法创建事件源")
            return
        }
        
        // 创建按键事件
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            print("❌ [TextInsertionService] 无法创建按键事件")
            return
        }
        
        // 设置 Command 修饰键标志
        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = [] // 释放时清除所有修饰键
        
        // 使用 cghidEventTap 发送事件（最底层的方式）
        // 按顺序发送：Command按下 -> V按下 -> V释放 -> Command释放
        cmdDown.post(tap: .cghidEventTap)
        usleep(10000) // 10ms
        
        vDown.post(tap: .cghidEventTap)
        usleep(10000) // 10ms
        
        vUp.post(tap: .cghidEventTap)
        usleep(10000) // 10ms
        
        cmdUp.post(tap: .cghidEventTap)
    }
    
    /// 获取最后插入的文本（用于调试）
    func getLastInsertedText() -> String? {
        return lastInsertedText
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
