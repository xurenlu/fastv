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
class TextInsertionService {
    static let shared = TextInsertionService()
    
    private init() {}
    
    /// 将文本插入到当前激活的输入框
    /// - Parameter text: 要插入的文本
    func insertText(_ text: String) {
        // 方法1: 使用剪贴板 + Cmd+V（最可靠的方法）
        // 先保存当前剪贴板内容
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        
        // 将文本复制到剪贴板（在主线程执行，但应该很快）
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 模拟 Cmd+V 粘贴（这些操作应该很快）
        let source = CGEventSource(stateID: .hidSystemState)
        
        // 按下 Command
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) // Command键
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        
        // 按下 V
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V键
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        
        // 释放 V
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)
        
        // 释放 Command
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        cmdUp?.flags = .maskCommand
        cmdUp?.post(tap: .cghidEventTap)
        
        // 恢复剪贴板内容（延迟执行，确保粘贴完成，不阻塞）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let previousContents = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previousContents, forType: .string)
            }
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

