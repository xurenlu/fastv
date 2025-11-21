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
    private var fnKeyReleaseTimer: Timer?
    private var lastFNKeyEventTime: Date?
    
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
        fnKeyReleaseTimer?.invalidate()
        fnKeyReleaseTimer = nil
        lastFNKeyEventTime = nil
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
        // FN键在macOS上的行为比较复杂，可能通过flagsChanged或keyDown/keyUp触发
        // 我们同时监听这两种事件类型，并改进检测逻辑
        
        let eventModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        
        if event.type == .flagsChanged {
            // FN键通常通过flagsChanged事件触发
            // 检查keyCode是否为0x3F（FN键的标准keyCode）或0（某些键盘）
            let isFNKeyCandidate = event.keyCode == 0x3F || 
                                   (event.keyCode == 0 && eventModifiers.isEmpty)
            
            if isFNKeyCandidate {
                print("🔑 [GlobalShortcutMonitor] FN键 flagsChanged: keyCode=\(event.keyCode), modifiers=\(eventModifiers.rawValue), 目标modifiers=\(targetModifiers.rawValue), isKeyPressed=\(isKeyPressed), 所有flags=\(event.modifierFlags.rawValue)")
                
                // FN键通常没有标准修饰键（或只有FN键本身的标志）
                // 检查修饰键是否匹配（FN键通常没有标准修饰键）
                if eventModifiers == targetModifiers {
                    if !isKeyPressed {
                        print("✅ [GlobalShortcutMonitor] FN键按下匹配！触发 onShortcutPressed")
                        isKeyPressed = true
                        lastFNKeyEventTime = Date()
                        
                        // 启动定时器检测FN键释放
                        // 使用更短的超时时间（50ms），更快响应释放事件
                        fnKeyReleaseTimer?.invalidate()
                        fnKeyReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] timer in
                            guard let self = self, self.isKeyPressed else {
                                timer.invalidate()
                                return
                            }
                            
                            // 检查是否长时间没有FN键事件（可能是已释放）
                            // 缩短超时时间到50ms，让释放检测更快
                            if let lastTime = self.lastFNKeyEventTime,
                               Date().timeIntervalSince(lastTime) > 0.05 {
                                print("🔑 [GlobalShortcutMonitor] FN键已释放（超时检测），触发释放事件")
                                self.isKeyPressed = false
                                timer.invalidate()
                                self.fnKeyReleaseTimer = nil
                                self.lastFNKeyEventTime = nil
                                DispatchQueue.main.async {
                                    self.onShortcutReleased?()
                                }
                            }
                        }
                        
                        DispatchQueue.main.async {
                            self.onShortcutPressed?()
                        }
                    } else {
                        // 更新最后事件时间（FN键仍然按下）
                        lastFNKeyEventTime = Date()
                    }
                }
            } else if isKeyPressed {
                // 如果FN键已按下，但现在检测到的不是FN键事件，且修饰键为空
                // 可能是FN键已释放（某些键盘在释放FN键时会发送一个空的flagsChanged事件）
                if eventModifiers.isEmpty && event.keyCode == 0 {
                    print("🔑 [GlobalShortcutMonitor] 检测到FN键可能已释放（flagsChanged，修饰键为空）")
                    // 立即触发释放事件，不再延迟
                            print("✅ [GlobalShortcutMonitor] 确认FN键已释放，触发 onShortcutReleased")
                            self.isKeyPressed = false
                            self.fnKeyReleaseTimer?.invalidate()
                            self.fnKeyReleaseTimer = nil
                            self.lastFNKeyEventTime = nil
                    DispatchQueue.main.async {
                            self.onShortcutReleased?()
                    }
                }
            }
        } else if event.type == .keyDown {
            // 某些键盘的FN键也可能通过keyDown触发
            if event.keyCode == 0x3F {
                print("🔑 [GlobalShortcutMonitor] FN键 keyDown: modifiers=\(eventModifiers.rawValue), 目标modifiers=\(targetModifiers.rawValue)")
                if eventModifiers == targetModifiers && !isKeyPressed {
                    print("✅ [GlobalShortcutMonitor] FN键按下匹配！触发 onShortcutPressed")
                    isKeyPressed = true
                    lastFNKeyEventTime = Date()
                    
                    // 启动定时器检测FN键释放
                    fnKeyReleaseTimer?.invalidate()
                    fnKeyReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] timer in
                        guard let self = self, self.isKeyPressed else {
                            timer.invalidate()
                            return
                        }
                        
                        if let lastTime = self.lastFNKeyEventTime,
                           Date().timeIntervalSince(lastTime) > 0.05 {
                            print("🔑 [GlobalShortcutMonitor] FN键已释放（超时检测），触发释放事件")
                            self.isKeyPressed = false
                            timer.invalidate()
                            self.fnKeyReleaseTimer = nil
                            self.lastFNKeyEventTime = nil
                            DispatchQueue.main.async {
                                self.onShortcutReleased?()
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.onShortcutPressed?()
                    }
                } else if isKeyPressed {
                    // 更新最后事件时间
                    lastFNKeyEventTime = Date()
                }
            }
        } else if event.type == .keyUp {
            // FN键释放（最可靠的检测方式）
            if event.keyCode == 0x3F && isKeyPressed {
                print("✅ [GlobalShortcutMonitor] FN键释放匹配（keyUp）！触发 onShortcutReleased")
                isKeyPressed = false
                fnKeyReleaseTimer?.invalidate()
                fnKeyReleaseTimer = nil
                lastFNKeyEventTime = nil
                DispatchQueue.main.async {
                    self.onShortcutReleased?()
                }
            }
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

