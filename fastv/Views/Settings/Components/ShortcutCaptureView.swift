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
    @State private var isCapturing = false
    @State private var capturedKeyCode: UInt16?
    @State private var capturedModifiers: NSEvent.ModifierFlags = []
    @State private var eventMonitor: Any?
    
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
            
            if isCapturing {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    
                    Text(NSLocalizedString("shortcut.capture.press.hint", comment: ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func startCapturing() {
        isCapturing = true
        capturedKeyCode = nil
        capturedModifiers = []
        
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
        
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        // 如果捕获到了按键，更新设置
        if let capturedKeyCode = capturedKeyCode {
            keyCode = capturedKeyCode
            modifiers = capturedModifiers
        }
    }
    
    private func handleCaptureEvent(_ event: NSEvent) -> NSEvent? {
        // 处理修饰键（通过flagsChanged事件）
        if event.type == .flagsChanged {
            let currentModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            
            // 检测单独的Control键
            if currentModifiers == .control {
                print("🔑 [ShortcutCapture] 检测到单独的Control键")
                capturedKeyCode = 0xFFFF // 使用特殊值表示"单独的Control键"
                capturedModifiers = []
                
                // 延迟停止捕获，给用户反馈
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    stopCapturing()
                }
                return nil // 消费事件
            }
            
            // 检测FN键
            // FN键的keyCode可能是0x3F，但也可能因键盘而异
            if event.keyCode == 0x3F || (event.keyCode == 0 && currentModifiers.isEmpty) {
                print("🔑 [ShortcutCapture] 检测到FN键")
                capturedKeyCode = 0x3F // FN键
                capturedModifiers = []
                
                // 延迟停止捕获，给用户反馈
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    stopCapturing()
                }
                return nil // 消费事件
            }
        }
        
        // 处理普通按键
        if event.type == .keyDown {
            let eventModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            
            // 忽略功能键（F1-F12等），除非用户明确想要设置
            // 但允许FN键（0x3F）
            if event.keyCode >= 0x7A && event.keyCode <= 0x7F && event.keyCode != 0x3F {
                return event
            }
            
            // 如果keyCode是0x3F，也认为是FN键
            if event.keyCode == 0x3F {
                capturedKeyCode = 0x3F
                capturedModifiers = []
            } else {
                capturedKeyCode = event.keyCode
                capturedModifiers = eventModifiers
            }
            
            // 延迟停止捕获，给用户反馈
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                stopCapturing()
            }
            
            return nil // 消费事件，防止触发其他操作
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

