//
//  GlobalShortcutMonitor.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AppKit

/// 快捷鍵類型
enum ShortcutType {
    case voiceInput       // 純語音輸入
    case voiceInputWithAI // 語音輸入 + AI 校正
}

/// 全局快捷键监听器
class GlobalShortcutMonitor {
    static let shared = GlobalShortcutMonitor()
    
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    
    var onShortcutPressed: (() -> Void)?
    var onShortcutReleased: (() -> Void)?
    
    // 带Ctrl键状态的回调（舊版，保留兼容）
    var onShortcutPressedWithCtrl: ((Bool) -> Void)?
    var onShortcutReleasedWithCtrl: ((Bool) -> Void)?
    
    // 新版回調：帶快捷鍵類型
    var onShortcutPressedWithType: ((ShortcutType) -> Void)?
    var onShortcutReleasedWithType: ((ShortcutType) -> Void)?
    
    private var isKeyPressed = false
    private var targetKeyCode: UInt16?
    private var targetModifiers: NSEvent.ModifierFlags?
    
    // 第二個快捷鍵（語音輸入+AI校正）
    private var secondaryKeyCode: UInt16?
    private var secondaryModifiers: NSEvent.ModifierFlags?
    
    // 記錄當前觸發的是哪種快捷鍵
    private var currentShortcutType: ShortcutType = .voiceInput
    
    // Control键相关状态
    private var controlKeyReleaseTimer: Timer?
    private var lastControlKeyEventTime: Date?
    private var hasOtherKeyPressed = false // 标记是否按下了其他键
    
    // FN键相关状态
    private var fnKeyReleaseTimer: Timer?
    private var fnKeySafetyTimer: Timer? // 安全定时器：防止释放检测失败导致录音无限继续
    private var lastFNKeyEventTime: Date?
    private var hasOtherKeyPressedWithFN = false // 标记FN键按下时是否按下了其他键
    private var isCtrlPressedWithFN = false // 标记FN键按下时是否同时按下了Ctrl键

    // FN键安全超时时间（秒）：如果在此时间内没有检测到释放，自动触发释放
    // 设置为 5 分钟，避免正常录音被中断，同时防止无限录音
    private let fnKeySafetyTimeout: TimeInterval = 300.0
    
    private init() {}
    
    /// 開始監聽快捷鍵（雙快捷鍵版本）
    /// - Parameters:
    ///   - keyCode: 主快捷鍵鍵碼（純語音輸入）
    ///   - modifiers: 主快捷鍵修飾鍵
    ///   - secondaryKeyCode: 次快捷鍵鍵碼（語音輸入+AI校正），nil 表示不啟用
    ///   - secondaryModifiers: 次快捷鍵修飾鍵
    func startMonitoring(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        secondaryKeyCode: UInt16? = nil,
        secondaryModifiers: NSEvent.ModifierFlags? = nil
    ) {
        print("🔧 [GlobalShortcutMonitor] 開始監聽快捷鍵:")
        print("  - 主快捷鍵: keyCode=\(keyCode), modifiers=\(modifiers.rawValue)")
        if let secKey = secondaryKeyCode, let secMod = secondaryModifiers {
            print("  - AI校正快捷鍵: keyCode=\(secKey), modifiers=\(secMod.rawValue)")
        }
        
        stopMonitoring()
        
        targetKeyCode = keyCode
        targetModifiers = modifiers
        self.secondaryKeyCode = secondaryKeyCode
        self.secondaryModifiers = secondaryModifiers
        
        // 检查辅助功能权限
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("🔧 [GlobalShortcutMonitor] 辅助功能权限状态: \(isTrusted ? "已授权" : "未授权")")
        
        if !isTrusted {
            print("⚠️ [GlobalShortcutMonitor] 警告：未获得辅助功能权限，全局快捷键监听可能无法工作")
            print("💡 [GlobalShortcutMonitor] 提示：请在'系统设置 > 隐私与安全性 > 辅助功能'中找到 fastv 并勾选")
        }
        
        // 使用 NSEvent 全局监听（捕获其他应用的按键事件）
        // 注意：需要辅助功能权限才能监听全局事件
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self else { return }
            
            self.handleEvent(event)
        }
        
        // 同时添加本地监听器（捕获本应用窗口内的按键事件）
        // 本地监听器不需要辅助功能权限，但只能捕获窗口内的按键
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            
            // 先处理事件
            self.handleEvent(event)
            
            // 如果匹配快捷键，消费事件（不传递给其他处理者）
            // 否则返回事件，让系统正常处理
            if self.shouldConsumeEvent(event) {
                return nil
            }
            
            return event
        }
        
        if globalEventMonitor != nil || localEventMonitor != nil {
            print("✅ [GlobalShortcutMonitor] 快捷键监听已启动（全局: \(globalEventMonitor != nil), 本地: \(localEventMonitor != nil)）")
        } else {
            print("❌ [GlobalShortcutMonitor] 快捷键监听启动失败（可能需要辅助功能权限）")
        }
    }
    
    /// 停止监听
    func stopMonitoring() {
        print("🔧 [GlobalShortcutMonitor] 停止监听快捷键")
        
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
            print("✅ [GlobalShortcutMonitor] 已移除全局事件监听器")
        }
        
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
            print("✅ [GlobalShortcutMonitor] 已移除本地事件监听器")
        }
        
        if globalEventMonitor == nil && localEventMonitor == nil {
            print("ℹ️ [GlobalShortcutMonitor] 没有活动的监听器需要停止")
        }
        
        targetKeyCode = nil
        targetModifiers = nil
        secondaryKeyCode = nil
        secondaryModifiers = nil
        isKeyPressed = false
        currentShortcutType = .voiceInput
        controlKeyReleaseTimer?.invalidate()
        controlKeyReleaseTimer = nil
        lastControlKeyEventTime = nil
        hasOtherKeyPressed = false
        fnKeyReleaseTimer?.invalidate()
        fnKeyReleaseTimer = nil
        fnKeySafetyTimer?.invalidate()
        fnKeySafetyTimer = nil
        lastFNKeyEventTime = nil
        hasOtherKeyPressedWithFN = false
    }
    
    /// 判断是否应该消费事件（阻止事件传递给其他处理者）
    /// 注意：我们只在按下时消费事件，释放时不消费，这样不会影响其他功能
    private func shouldConsumeEvent(_ event: NSEvent) -> Bool {
        guard let targetKeyCode = targetKeyCode,
              let targetModifiers = targetModifiers else {
            return false
        }
        
        let eventModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let targetModifiersFiltered = targetModifiers.intersection([.command, .shift, .option, .control])
        
        // 特殊处理FN键
        if targetKeyCode == 0x3F {
            let hasFunctionFlag = event.modifierFlags.contains(.function)
            let isFNKey = event.keyCode == 0x3F && hasFunctionFlag
            
            // 只在按下时消费，释放时不消费
            if event.type == .flagsChanged && hasFunctionFlag && !isKeyPressed {
                return true // 消费FN键的按下事件
            }
            if event.type == .keyDown && isFNKey {
                return true // 消费FN键的keyDown事件
            }
            return false
        }
        
        // 特殊处理Control键
        if targetKeyCode == 0xFFFF {
            // 只在按下时消费，释放时不消费
            if event.type == .flagsChanged && event.modifierFlags.contains(.control) && !isKeyPressed {
                return true // 消费Control键的按下事件
            }
            return false
        }
        
        // 处理普通按键
        // 只在按下时消费，释放时不消费
        if event.type == .keyDown {
            if event.keyCode == targetKeyCode && eventModifiers == targetModifiersFiltered {
                return true // 消费匹配的按键按下事件
            }
        }
        
        return false
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
        // 已注释：语音输入法功能已稳定，不再需要此日志
        // #if DEBUG
        // if event.type == .keyDown || event.type == .keyUp || event.type == .flagsChanged {
        //     print("⌨️ [GlobalShortcutMonitor] 捕获到按键事件: type=\(event.type.rawValue), keyCode=\(event.keyCode), modifiers=\(eventModifiers.rawValue), 目标keyCode=\(targetKeyCode), 目标modifiers=\(targetModifiersFiltered.rawValue)")
        // }
        // #endif
        
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
            // 检查基本快捷键是否匹配（不考虑额外的 Ctrl 键）
            // 先检查是否匹配基本快捷键（排除 Ctrl 键）
            let eventModifiersWithoutCtrl = eventModifiers.intersection([.command, .shift, .option])
            let targetModifiersWithoutCtrl = targetModifiersFiltered.intersection([.command, .shift, .option])
            
            if event.keyCode == targetKeyCode && eventModifiersWithoutCtrl == targetModifiersWithoutCtrl && !isKeyPressed {
                // 检查是否额外按下了 Ctrl 键（即使 Ctrl 不在目标修饰键中）
                let hasCtrl = event.modifierFlags.contains(.control)
                print("✅ [GlobalShortcutMonitor] 快捷键按下匹配！触发 onShortcutPressed（Ctrl: \(hasCtrl), 事件modifiers: \(eventModifiers.rawValue), 目标modifiers: \(targetModifiersFiltered.rawValue)）")
                isKeyPressed = true
                // 同步调用回调，减少延迟（防止首字丢失）
                // 回调内部会使用 MainActor 确保线程安全
                if let callback = onShortcutPressedWithCtrl {
                    callback(hasCtrl)
                } else {
                    onShortcutPressed?()
                }
            }
        } else if event.type == .keyUp {
            if event.keyCode == targetKeyCode && isKeyPressed {
                // 检查是否同时按下了 Ctrl 键
                let hasCtrl = event.modifierFlags.contains(.control)
                print("✅ [GlobalShortcutMonitor] 快捷键释放匹配！触发 onShortcutReleased（Ctrl: \(hasCtrl)）")
                isKeyPressed = false
                // 同步调用回调，减少延迟
                if let callback = onShortcutReleasedWithCtrl {
                    callback(hasCtrl)
                } else {
                    onShortcutReleased?()
                }
            }
        }
    }
    
    /// 处理FN键事件（FN键通过flagsChanged事件触发）
    /// 支持區分 FN（純語音輸入）和 FN+Control（語音輸入+AI校正）
    private func handleFNKeyEvent(_ event: NSEvent, targetModifiers: NSEvent.ModifierFlags) {
        // FN键是修饰键，通过flagsChanged或个别键盘的keyDown/keyUp触发
        let monitoredModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let eventModifiers = event.modifierFlags.intersection(monitoredModifiers)
        let hasFunctionFlag = event.modifierFlags.contains(.function)

        // 严格检查FN键：必须同时满足keyCode匹配和function标志位
        let isFNKeyByCode = event.keyCode == 0x3F
        let isFNKey = isFNKeyByCode && hasFunctionFlag

        switch event.type {
        case .flagsChanged:
            // 对于flagsChanged事件，主要依赖function标志位的变化
            // 如果之前按下FN，但现在function标志消失，认为是释放
            if isKeyPressed && !hasFunctionFlag {
                print("🔑 [GlobalShortcutMonitor] FN键function标志消失，触发释放")
                triggerFNRelease()
                return
            }

            // 只有当function标志位存在时才处理
            guard hasFunctionFlag else {
                return
            }

            // 检查是否按下了Ctrl键
            let hasCtrl = eventModifiers.contains(.control)
            isCtrlPressedWithFN = hasCtrl

            // 判斷觸發的是哪種快捷鍵
            // 1. 如果主快捷鍵是 FN（無修飾鍵），次快捷鍵是 FN+Control
            // 2. 根據當前的 Ctrl 狀態決定類型
            let detectedType: ShortcutType
            if hasCtrl && secondaryKeyCode == 0x3F && secondaryModifiers?.contains(.control) == true {
                // FN+Control → 語音輸入+AI校正
                detectedType = .voiceInputWithAI
            } else if !hasCtrl && targetModifiers.isEmpty {
                // 純 FN → 純語音輸入
                detectedType = .voiceInput
            } else if eventModifiers == targetModifiers {
                // 其他情況：檢查是否匹配主快捷鍵
                detectedType = .voiceInput
            } else if hasCtrl {
                // 有 Ctrl 但沒有配置次快捷鍵，仍視為語音輸入+AI（向後兼容）
                detectedType = .voiceInputWithAI
            } else {
                // 不匹配任何快捷鍵
                return
            }

            print("🔑 [GlobalShortcutMonitor] FN鍵 flagsChanged: keyCode=\(event.keyCode), Ctrl=\(hasCtrl), 類型=\(detectedType)")

            if !isKeyPressed {
                print("✅ [GlobalShortcutMonitor] FN鍵按下檢測到（類型: \(detectedType)），立即觸發錄音")
                isKeyPressed = true
                hasOtherKeyPressedWithFN = false
                currentShortcutType = detectedType
                lastFNKeyEventTime = Date()

                // 启动安全定时器：防止释放检测失败导致录音无限继续
                // 如果在超时时间内没有检测到释放，自动触发释放
                fnKeySafetyTimer?.invalidate()
                fnKeySafetyTimer = Timer.scheduledTimer(withTimeInterval: fnKeySafetyTimeout, repeats: false) { [weak self] _ in
                    guard let self = self, self.isKeyPressed else { return }
                    print("⏰ [GlobalShortcutMonitor] FN键安全超时（\(self.fnKeySafetyTimeout)秒），自动触发释放")
                    self.triggerFNRelease()
                }

                // 立即触发回调，减少延迟（防止首字丢失）
                // 设置取消定时器：如果在50ms内检测到其他按键，标记为误触
                fnKeyReleaseTimer?.invalidate()
                fnKeyReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                    // 定时器仅用于取消误触，不影响正常触发
                    // 如果 hasOtherKeyPressedWithFN 为 true，说明是误触，调用方应取消录音
                }

                let shortcutType = detectedType
                // 同步调用回调，立即开始录音
                if let callback = onShortcutPressedWithType {
                    callback(shortcutType)
                } else if let callback = onShortcutPressedWithCtrl {
                    callback(shortcutType == .voiceInputWithAI)
                } else {
                    onShortcutPressed?()
                }
            } else {
                // 更新 Ctrl 鍵狀態和類型
                isCtrlPressedWithFN = hasCtrl
                // 如果在按住 FN 期間按下了 Ctrl，更新類型為 AI 校正
                if hasCtrl && currentShortcutType == .voiceInput {
                    currentShortcutType = .voiceInputWithAI
                    print("🔄 [GlobalShortcutMonitor] 檢測到 Ctrl 鍵按下，切換為語音輸入+AI校正模式")
                }
                lastFNKeyEventTime = Date()
            }

        case .keyDown:
            // 如果FN键按下后，又按了其他键，标记为"按了其他键"
            if isKeyPressed && !isFNKey {
                print("⚠️ [GlobalShortcutMonitor] FN键按下时检测到其他键按下（keyCode=\(event.keyCode)），取消触发")
                hasOtherKeyPressedWithFN = true

                // 取消定时器
                fnKeyReleaseTimer?.invalidate()
                fnKeyReleaseTimer = nil
            }

            // 对于keyDown事件，必须同时满足keyCode和function标志位
            guard isFNKey else { return }
            print("🔑 [GlobalShortcutMonitor] FN键 keyDown: modifiers=\(eventModifiers.rawValue), 目标modifiers=\(targetModifiers.rawValue)")
            if eventModifiers == targetModifiers && !isKeyPressed {
                print("✅ [GlobalShortcutMonitor] FN键按下匹配！立即触发 onShortcutPressed")
                isKeyPressed = true
                hasOtherKeyPressedWithFN = false
                currentShortcutType = .voiceInput

                // 启动安全定时器
                fnKeySafetyTimer?.invalidate()
                fnKeySafetyTimer = Timer.scheduledTimer(withTimeInterval: fnKeySafetyTimeout, repeats: false) { [weak self] _ in
                    guard let self = self, self.isKeyPressed else { return }
                    print("⏰ [GlobalShortcutMonitor] FN键安全超时（\(self.fnKeySafetyTimeout)秒），自动触发释放")
                    self.triggerFNRelease()
                }

                // 同步调用回调，减少延迟
                if let callback = onShortcutPressedWithType {
                    callback(.voiceInput)
                } else {
                    onShortcutPressed?()
                }
            }

        case .keyUp:
            // 备用释放检测：放宽 keyUp 检测条件
            // 某些键盘驱动在松开 FN 键时可能不发送 function 标志，只匹配 keyCode
            let isFNKeyByCodeOnly = event.keyCode == 0x3F

            // 优先使用严格检查（带 function 标志），如果失败则使用备用检查（仅 keyCode）
            let shouldTriggerRelease = (isFNKey && isKeyPressed) || (isFNKeyByCodeOnly && isKeyPressed && !hasFunctionFlag)

            if shouldTriggerRelease {
                print("✅ [GlobalShortcutMonitor] FN键释放（keyUp，isFNKey=\(isFNKey), isFNKeyByCodeOnly=\(isFNKeyByCodeOnly), hasFunctionFlag=\(hasFunctionFlag)）！触发 onShortcutReleased")
                triggerFNRelease()
            }

        default:
            break
        }
    }
    
    private func triggerFNRelease() {
        // 取消所有定时器（包括误触检测定时器和安全定时器）
        fnKeyReleaseTimer?.invalidate()
        fnKeyReleaseTimer = nil
        fnKeySafetyTimer?.invalidate()
        fnKeySafetyTimer = nil

        // 只有在没有按其他键的情况下才触发释放事件
        if !hasOtherKeyPressedWithFN {
            let shortcutType = currentShortcutType
            print("✅ [GlobalShortcutMonitor] FN鍵釋放（類型: \(shortcutType)），觸發 onShortcutReleased")
            isKeyPressed = false
            lastFNKeyEventTime = nil
            hasOtherKeyPressedWithFN = false
            // 同步调用回调，减少延迟
            if let callback = onShortcutReleasedWithType {
                callback(shortcutType)
            } else if let callback = onShortcutReleasedWithCtrl {
                callback(shortcutType == .voiceInputWithAI)
            } else {
                onShortcutReleased?()
            }
            // 重置狀態
            isCtrlPressedWithFN = false
            currentShortcutType = .voiceInput
        } else {
            print("ℹ️ [GlobalShortcutMonitor] FN键释放，但之前按了其他键，不触发释放事件")
            isKeyPressed = false
            hasOtherKeyPressedWithFN = false
            lastFNKeyEventTime = nil
            isCtrlPressedWithFN = false
            currentShortcutType = .voiceInput
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
                    print("✅ [GlobalShortcutMonitor] Control键按下（单独），立即触发录音")
                    isKeyPressed = true
                    hasOtherKeyPressed = false
                    lastControlKeyEventTime = Date()

                    // 立即触发回调，减少延迟（防止首字丢失）
                    // 设置取消定时器：如果在50ms内检测到其他按键，标记为误触
                    controlKeyReleaseTimer?.invalidate()
                    controlKeyReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                        // 定时器仅用于取消误触，不影响正常触发
                    }

                    // 同步调用回调，立即开始录音
                    onShortcutPressed?()
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
                    // 同步调用回调，减少延迟
                    onShortcutReleased?()
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

