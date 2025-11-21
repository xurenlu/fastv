//
//  GlobalShortcutMonitor.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AppKit

/// 全局快捷键监听器
class GlobalShortcutMonitor {
    static let shared = GlobalShortcutMonitor()
    
    private var eventMonitor: Any?
    
    var onShortcutPressed: (() -> Void)?
    var onShortcutReleased: (() -> Void)?
    
    private var isKeyPressed = false
    private var targetKeyCode: UInt16?
    private var targetModifiers: NSEvent.ModifierFlags?
    
    // Control键相关状态
    private var controlKeyReleaseTimer: Timer?
    private var lastControlKeyEventTime: Date?
    private var hasOtherKeyPressed = false // 标记是否按下了其他键
    
    private init() {}
    
    /// 开始监听快捷键
    func startMonitoring(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        print("🔧 [GlobalShortcutMonitor] 开始监听快捷键: keyCode=\(keyCode), modifiers=\(modifiers.rawValue)")
        
        stopMonitoring()
        
        targetKeyCode = keyCode
        targetModifiers = modifiers
        
        // 检查辅助功能权限
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("🔧 [GlobalShortcutMonitor] 辅助功能权限状态: \(isTrusted ? "已授权" : "未授权")")
        
        if !isTrusted {
            print("⚠️ [GlobalShortcutMonitor] 警告：未获得辅助功能权限，全局快捷键监听可能无法工作")
            print("💡 [GlobalShortcutMonitor] 提示：请在'系统设置 > 隐私与安全性 > 辅助功能'中找到 fastv 并勾选")
        }
        
        // 使用 NSEvent 全局监听
        // 注意：需要辅助功能权限才能监听全局事件
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self else { return }
            
            self.handleEvent(event)
        }
        
        if eventMonitor != nil {
            print("✅ [GlobalShortcutMonitor] 快捷键监听已启动")
        } else {
            print("❌ [GlobalShortcutMonitor] 快捷键监听启动失败（可能需要辅助功能权限）")
        }
    }
    
    /// 停止监听
    func stopMonitoring() {
        print("🔧 [GlobalShortcutMonitor] 停止监听快捷键")
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
            print("✅ [GlobalShortcutMonitor] 已移除事件监听器")
        } else {
            print("ℹ️ [GlobalShortcutMonitor] 没有活动的监听器需要停止")
        }
        targetKeyCode = nil
        targetModifiers = nil
        isKeyPressed = false
        controlKeyReleaseTimer?.invalidate()
        controlKeyReleaseTimer = nil
        lastControlKeyEventTime = nil
        hasOtherKeyPressed = false
    }
    
    private func handleEvent(_ event: NSEvent) {
        guard let targetKeyCode = targetKeyCode,
              let targetModifiers = targetModifiers else {
            return
        }
        
        // 检查按键是否匹配
        let eventModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let targetModifiersFiltered = targetModifiers.intersection([.command, .shift, .option, .control])
        
        // 调试日志：记录所有按键事件（仅在调试模式下）
        #if DEBUG
        if event.type == .keyDown || event.type == .keyUp || event.type == .flagsChanged {
            print("⌨️ [GlobalShortcutMonitor] 捕获到按键事件: type=\(event.type.rawValue), keyCode=\(event.keyCode), modifiers=\(eventModifiers.rawValue), 目标keyCode=\(targetKeyCode), 目标modifiers=\(targetModifiersFiltered.rawValue)")
        }
        #endif
        
        // 特殊处理FN键（keyCode = 0x3F）
        if targetKeyCode == 0x3F {
            handleFNKeyEvent(event, targetModifiers: targetModifiersFiltered)
            return
        }
        
        // 特殊处理单独的Control键（左Control键码：0x3B，右Control键码：0x3E）
        // 注意：这里我们使用特殊的keyCode 0xFFFF 来表示"单独的Control键"
        if targetKeyCode == 0xFFFF {
            handleControlKeyEvent(event, targetModifiers: targetModifiersFiltered)
            return
        }
        
        // 处理普通按键事件
        if event.type == .keyDown {
            if event.keyCode == targetKeyCode && eventModifiers == targetModifiersFiltered && !isKeyPressed {
                print("✅ [GlobalShortcutMonitor] 快捷键按下匹配！触发 onShortcutPressed")
                isKeyPressed = true
                DispatchQueue.main.async {
                    self.onShortcutPressed?()
                }
            }
        } else if event.type == .keyUp {
            if event.keyCode == targetKeyCode && isKeyPressed {
                print("✅ [GlobalShortcutMonitor] 快捷键释放匹配！触发 onShortcutReleased")
                isKeyPressed = false
                DispatchQueue.main.async {
                    self.onShortcutReleased?()
                }
            }
        }
    }
    
    /// 处理FN键事件（FN键通过flagsChanged事件触发）
    private func handleFNKeyEvent(_ event: NSEvent, targetModifiers: NSEvent.ModifierFlags) {
        // FN键是修饰键，通过flagsChanged或个别键盘的keyDown/keyUp触发
        let monitoredModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let eventModifiers = event.modifierFlags.intersection(monitoredModifiers)
        let isFNKey = event.keyCode == 0x3F || event.keyCode == 0
        let hasFunctionFlag = event.modifierFlags.contains(.function)
        
        switch event.type {
        case .flagsChanged:
            guard isFNKey else {
                // 如果之前按下FN，但现在function标志消失，也认为是释放
                if isKeyPressed && !hasFunctionFlag {
                    print("🔑 [GlobalShortcutMonitor] FN键function标志消失，触发释放")
                    triggerFNRelease()
                }
                return
            }
            
            print("🔑 [GlobalShortcutMonitor] FN键 flagsChanged: keyCode=\(event.keyCode), hasFunctionFlag=\(hasFunctionFlag), modifiers=\(eventModifiers.rawValue), 目标modifiers=\(targetModifiers.rawValue), isKeyPressed=\(isKeyPressed)")
            
            if hasFunctionFlag {
                guard eventModifiers == targetModifiers else {
                    // 搭配的其他修饰键不一致，忽略
                    return
                }
                
                if !isKeyPressed {
                    print("✅ [GlobalShortcutMonitor] FN键按下匹配！触发 onShortcutPressed")
                    isKeyPressed = true
                    DispatchQueue.main.async {
                        self.onShortcutPressed?()
                    }
                }
            } else if isKeyPressed {
                print("✅ [GlobalShortcutMonitor] FN键释放（flagsChanged）！触发 onShortcutReleased")
                triggerFNRelease()
            }
            
        case .keyDown:
            guard isFNKey else { return }
            print("🔑 [GlobalShortcutMonitor] FN键 keyDown: modifiers=\(eventModifiers.rawValue), 目标modifiers=\(targetModifiers.rawValue)")
            if eventModifiers == targetModifiers && !isKeyPressed {
                print("✅ [GlobalShortcutMonitor] FN键按下匹配！触发 onShortcutPressed")
                isKeyPressed = true
                DispatchQueue.main.async {
                    self.onShortcutPressed?()
                }
            }
            
        case .keyUp:
            guard isFNKey else { return }
            if isKeyPressed {
                print("✅ [GlobalShortcutMonitor] FN键释放（keyUp）！触发 onShortcutReleased")
                triggerFNRelease()
            }
            
        default:
            break
        }
    }
    
    private func triggerFNRelease() {
        isKeyPressed = false
        DispatchQueue.main.async {
            self.onShortcutReleased?()
        }
    }
    
    /// 处理单独的Control键事件
    private func handleControlKeyEvent(_ event: NSEvent, targetModifiers: NSEvent.ModifierFlags) {
        // Control键是修饰键，通过flagsChanged事件触发
        // 我们需要确保：只有单独按下Control键才触发，如果同时按了其他键就不触发
        
        let eventModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        
        if event.type == .flagsChanged {
            // 检查是否是Control键的变化
            let hasControl = event.modifierFlags.contains(.control)
            
            print("🔑 [GlobalShortcutMonitor] Control键 flagsChanged: hasControl=\(hasControl), modifiers=\(eventModifiers.rawValue), isKeyPressed=\(isKeyPressed), hasOtherKeyPressed=\(hasOtherKeyPressed)")
            
            if hasControl && eventModifiers == .control {
                // Control键按下，且没有其他修饰键
                if !isKeyPressed {
                    print("✅ [GlobalShortcutMonitor] Control键按下（单独），等待确认没有其他键...")
                    isKeyPressed = true
                    hasOtherKeyPressed = false
                    lastControlKeyEventTime = Date()
                    
                    // 延迟一小段时间触发，确保没有其他键按下
                    controlKeyReleaseTimer?.invalidate()
                    controlKeyReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                        guard let self = self, self.isKeyPressed, !self.hasOtherKeyPressed else { return }
                        
                        print("✅ [GlobalShortcutMonitor] 确认Control键单独按下，触发 onShortcutPressed")
                        DispatchQueue.main.async {
                            self.onShortcutPressed?()
                        }
                    }
                } else {
                    // 更新最后事件时间
                    lastControlKeyEventTime = Date()
                }
            } else if !hasControl && isKeyPressed {
                // Control键释放
                print("🔑 [GlobalShortcutMonitor] Control键释放")
                
                // 取消定时器
                controlKeyReleaseTimer?.invalidate()
                controlKeyReleaseTimer = nil
                
                // 只有在没有按其他键的情况下才触发释放事件
                if !hasOtherKeyPressed {
                    print("✅ [GlobalShortcutMonitor] Control键释放（单独），触发 onShortcutReleased")
                    isKeyPressed = false
                    lastControlKeyEventTime = nil
                    DispatchQueue.main.async {
                        self.onShortcutReleased?()
                    }
                } else {
                    print("ℹ️ [GlobalShortcutMonitor] Control键释放，但之前按了其他键，不触发释放事件")
                    isKeyPressed = false
                    hasOtherKeyPressed = false
                    lastControlKeyEventTime = nil
                }
            }
        } else if event.type == .keyDown {
            // 如果Control键按下后，又按了其他键，标记为"按了其他键"
            if isKeyPressed && event.keyCode != 0x3B && event.keyCode != 0x3E {
                print("⚠️ [GlobalShortcutMonitor] Control键按下时检测到其他键按下（keyCode=\(event.keyCode)），取消录音")
                hasOtherKeyPressed = true
                
                // 取消定时器
                controlKeyReleaseTimer?.invalidate()
                controlKeyReleaseTimer = nil
                
                // 如果已经触发了录音，需要取消
                // 这里我们不直接取消，而是标记状态，等Control键释放时不触发onShortcutReleased
            }
        }
    }
}

