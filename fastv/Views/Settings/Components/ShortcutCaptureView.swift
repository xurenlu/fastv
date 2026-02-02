//
//  ShortcutCaptureView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AppKit

// MARK: - 快捷键捕获器

struct ShortcutCaptureView: View {
    @Binding var keyCode: UInt16
    @Binding var modifiers: NSEvent.ModifierFlags
    
    // 默認值（用於恢復默認）
    var defaultKeyCode: UInt16 = 0x3F  // 默認 FN
    var defaultModifiers: NSEvent.ModifierFlags = []
    
    @State private var isCapturing = false
    @State private var capturedKeyCode: UInt16?
    @State private var capturedModifiers: NSEvent.ModifierFlags = []
    @State private var eventMonitor: Any?
    
    // 用於組合鍵捕獲：記錄當前按住的修飾鍵
    @State private var currentHeldModifiers: NSEvent.ModifierFlags = []
    @State private var waitingForMainKey = false
    @State private var captureTimer: Timer?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 当前快捷键显示
            HStack {
                Text(NSLocalizedString("current.shortcut", comment: ""))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if keyCode == 0 {
                    Text(NSLocalizedString("not.set", comment: ""))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.quaternary)
                        }
                } else {
                    HStack(spacing: 4) {
                        // 显示修饰键
                        if modifiers.contains(.command) {
                            KeyBadge(symbol: "⌘")
                        }
                        if modifiers.contains(.shift) {
                            KeyBadge(symbol: "⇧")
                        }
                        if modifiers.contains(.option) {
                            KeyBadge(symbol: "⌥")
                        }
                        if modifiers.contains(.control) {
                            KeyBadge(symbol: "⌃")
                        }
                        
                        // 显示主键
                        KeyBadge(symbol: keyCodeToString(keyCode))
                    }
                }
            }
            
            // 按鈕區域
            HStack(spacing: 8) {
                // 捕获按钮
                Button(action: {
                    if isCapturing {
                        stopCapturing()
                    } else {
                        startCapturing()
                    }
                }) {
                    HStack {
                        Image(systemName: isCapturing ? "stop.circle.fill" : "keyboard")
                            .font(.system(size: 13))
                        
                        Text(isCapturing ? NSLocalizedString("shortcut.capture.stop", comment: "") : NSLocalizedString("shortcut.capture.click", comment: ""))
                            .font(.system(size: 13))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isCapturing ? 
                                  Color.red.opacity(0.1) : 
                                  Color.accentColor.opacity(0.1))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        isCapturing ? Color.red.opacity(0.3) : Color.accentColor.opacity(0.3),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .foregroundStyle(isCapturing ? .red : .accentColor)
                }
                .buttonStyle(.plain)
                
                // 恢復默認按鈕
                Button(action: {
                    resetToDefault()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.1))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                                }
                        }
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("恢復默認快捷鍵")
                .disabled(isCapturing)
            }
            
            if isCapturing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        
                        Text("請按下快捷鍵組合...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    
                    // 顯示當前按住的修飾鍵
                    if !currentHeldModifiers.isEmpty || waitingForMainKey {
                        HStack(spacing: 4) {
                            Text("當前：")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            
                            if currentHeldModifiers.contains(.control) {
                                KeyBadge(symbol: "⌃")
                            }
                            if currentHeldModifiers.contains(.option) {
                                KeyBadge(symbol: "⌥")
                            }
                            if currentHeldModifiers.contains(.shift) {
                                KeyBadge(symbol: "⇧")
                            }
                            if currentHeldModifiers.contains(.command) {
                                KeyBadge(symbol: "⌘")
                            }
                            
                            if waitingForMainKey {
                                Text("+ ?")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    
                    Text("支持：FN、Control+FN、Option+V 等組合")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
    
    /// 恢復默認快捷鍵
    private func resetToDefault() {
        keyCode = defaultKeyCode
        modifiers = defaultModifiers
        print("🔄 [ShortcutCapture] 已恢復默認快捷鍵: keyCode=\(defaultKeyCode), modifiers=\(defaultModifiers.rawValue)")
    }
    
    private func startCapturing() {
        isCapturing = true
        capturedKeyCode = nil
        capturedModifiers = []
        currentHeldModifiers = []
        waitingForMainKey = false
        
        // 取消之前的定時器
        captureTimer?.invalidate()
        captureTimer = nil
        
        // 监听键盘事件
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            if self.isCapturing {
                return self.handleCaptureEvent(event)
            }
            return event
        }
    }
    
    private func stopCapturing() {
        isCapturing = false
        waitingForMainKey = false
        currentHeldModifiers = []
        
        // 取消定時器
        captureTimer?.invalidate()
        captureTimer = nil
        
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        // 如果捕获到了按键，更新设置
        if let capturedKeyCode = capturedKeyCode {
            keyCode = capturedKeyCode
            modifiers = capturedModifiers
            print("✅ [ShortcutCapture] 設置快捷鍵: keyCode=\(capturedKeyCode), modifiers=\(capturedModifiers.rawValue)")
        }
    }
    
    private func handleCaptureEvent(_ event: NSEvent) -> NSEvent? {
        let monitoredModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        
        // 處理修飾鍵變化（通過 flagsChanged 事件）
        if event.type == .flagsChanged {
            let newModifiers = event.modifierFlags.intersection(monitoredModifiers)
            let hasFunctionFlag = event.modifierFlags.contains(.function)
            
            // 檢測 FN 鍵
            // FN 鍵的 keyCode 是 0x3F，且有 .function 標誌
            if event.keyCode == 0x3F && hasFunctionFlag {
                print("🔑 [ShortcutCapture] 檢測到 FN 鍵，當前修飾鍵: \(currentHeldModifiers.rawValue)")
                
                // FN 鍵作為主鍵，當前按住的修飾鍵作為修飾鍵
                capturedKeyCode = 0x3F
                capturedModifiers = currentHeldModifiers
                
                // 取消之前的定時器
                captureTimer?.invalidate()
                
                // 延遲停止捕獲，給用戶反饋
                captureTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [self] _ in
                    DispatchQueue.main.async {
                        self.stopCapturing()
                    }
                }
                return nil
            }
            
            // 更新當前按住的修飾鍵
            currentHeldModifiers = newModifiers
            
            // 如果有修飾鍵被按下，標記為等待主鍵
            if !newModifiers.isEmpty {
                waitingForMainKey = true
                print("🔑 [ShortcutCapture] 修飾鍵按下: \(newModifiers.rawValue)，等待主鍵...")
                
                // 取消之前的定時器
                captureTimer?.invalidate()
                
                // 設置一個較長的超時（2秒），如果用戶只按了修飾鍵沒有按主鍵
                // 則視為單獨的修飾鍵（僅對 Control 鍵有效）
                captureTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [self] _ in
                    DispatchQueue.main.async {
                        if self.isCapturing && self.waitingForMainKey {
                            // 超時，檢查是否是單獨的 Control 鍵
                            if self.currentHeldModifiers == .control {
                                print("🔑 [ShortcutCapture] 超時，設置為單獨的 Control 鍵")
                                self.capturedKeyCode = 0xFFFF
                                self.capturedModifiers = []
                                self.stopCapturing()
                            } else {
                                // 其他修飾鍵組合，取消捕獲
                                print("⚠️ [ShortcutCapture] 超時，未檢測到主鍵，取消捕獲")
                                self.capturedKeyCode = nil
                                self.stopCapturing()
                            }
                        }
                    }
                }
            } else {
                // 所有修飾鍵都釋放了
                if waitingForMainKey && capturedKeyCode == nil {
                    // 如果之前在等待主鍵但沒有捕獲到，取消捕獲
                    print("⚠️ [ShortcutCapture] 修飾鍵釋放，未檢測到主鍵")
                }
                waitingForMainKey = false
                
                // 取消定時器
                captureTimer?.invalidate()
                captureTimer = nil
            }
            
            return nil
        }
        
        // 處理普通按鍵
        if event.type == .keyDown {
            let eventModifiers = event.modifierFlags.intersection(monitoredModifiers)
            
            // 忽略功能鍵（F1-F12 等），但允許 FN 鍵（0x3F）
            if event.keyCode >= 0x7A && event.keyCode <= 0x7F && event.keyCode != 0x3F {
                return event
            }
            
            // 取消定時器
            captureTimer?.invalidate()
            captureTimer = nil
            
            // 如果 keyCode 是 0x3F，認為是 FN 鍵
            if event.keyCode == 0x3F {
                capturedKeyCode = 0x3F
                capturedModifiers = eventModifiers
                print("🔑 [ShortcutCapture] 捕獲到 FN 鍵 + 修飾鍵: \(eventModifiers.rawValue)")
            } else {
                capturedKeyCode = event.keyCode
                capturedModifiers = eventModifiers
                print("🔑 [ShortcutCapture] 捕獲到按鍵: keyCode=\(event.keyCode), modifiers=\(eventModifiers.rawValue)")
            }
            
            waitingForMainKey = false
            
            // 延遲停止捕獲，給用戶反饋
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.stopCapturing()
            }
            
            return nil // 消費事件，防止觸發其他操作
        }
        
        return event
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0xFFFF: return "左Control"
        case 0x3F: return "FN"
        case 0x09: return "V"
        case 0x00: return "A"
        case 0x0B: return "B"
        case 0x08: return "C"
        case 0x02: return "D"
        case 0x0E: return "E"
        case 0x03: return "F"
        case 0x05: return "G"
        case 0x04: return "H"
        case 0x22: return "I"
        case 0x26: return "J"
        case 0x28: return "K"
        case 0x25: return "L"
        case 0x2E: return "M"
        case 0x2D: return "N"
        case 0x1F: return "O"
        case 0x23: return "P"
        case 0x0C: return "Q"
        case 0x0F: return "R"
        case 0x01: return "S"
        case 0x11: return "T"
        case 0x20: return "U"
        case 0x31: return "Space"
        case 0x24: return "Return"
        case 0x35: return "Esc"
        default: return "键\(keyCode)"
        }
    }
}

struct KeyBadge: View {
    let symbol: String
    
    var body: some View {
        Text(symbol)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.quaternary)
            }
    }
}

/// 快捷键显示视图
struct ShortcutDisplayView: View {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    var showCtrl: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            // 显示修饰键
            if modifiers.contains(.command) {
                KeyBadge(symbol: "⌘")
            }
            if modifiers.contains(.shift) {
                KeyBadge(symbol: "⇧")
            }
            if modifiers.contains(.option) {
                KeyBadge(symbol: "⌥")
            }
            if modifiers.contains(.control) {
                KeyBadge(symbol: "⌃")
            }
            
            // 如果 showCtrl 为 true，额外显示 Ctrl 键
            if showCtrl && !modifiers.contains(.control) {
                KeyBadge(symbol: "⌃")
            }
            
            // 显示主键
            KeyBadge(symbol: keyCodeToString(keyCode))
        }
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0xFFFF: return NSLocalizedString("key.left.control", comment: "")
        case 0x3F: return NSLocalizedString("key.fn", comment: "")
        case 0x09: return "V"
        case 0x00: return "A"
        case 0x0B: return "B"
        case 0x08: return "C"
        case 0x02: return "D"
        case 0x0E: return "E"
        case 0x03: return "F"
        case 0x05: return "G"
        case 0x04: return "H"
        case 0x22: return "I"
        case 0x26: return "J"
        case 0x28: return "K"
        case 0x25: return "L"
        case 0x2E: return "M"
        case 0x2D: return "N"
        case 0x1F: return "O"
        case 0x23: return "P"
        case 0x0C: return "Q"
        case 0x0F: return "R"
        case 0x01: return "S"
        case 0x11: return "T"
        case 0x20: return "U"
        case 0x31: return NSLocalizedString("key.space", comment: "")
        case 0x24: return NSLocalizedString("key.return", comment: "")
        case 0x35: return NSLocalizedString("key.esc", comment: "")
        default: return "\(NSLocalizedString("key", comment: ""))\(keyCode)"
        }
    }
}

