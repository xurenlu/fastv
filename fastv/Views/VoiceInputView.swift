//
//  VoiceInputView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

struct VoiceInputView: View {
    @ObservedObject private var history = VoiceInputHistory.shared
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var inputText: String = ""
    @State private var isTranscribing = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部文本输入区域
            VStack(spacing: 0) {
                // 文本输入框
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $inputText)
                        .font(.system(size: 15, design: .default))
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 60, maxHeight: 120)
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(NSColor.textBackgroundColor))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            isInputFocused ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                                            lineWidth: isInputFocused ? 2 : 1
                                        )
                                }
                        }
                        .focused($isInputFocused)
                        .onChange(of: history.items.first?.id) { _ in
                            // 当历史记录更新时，更新输入框内容
                            if let latestItem = history.items.first, !latestItem.text.isEmpty {
                                inputText = latestItem.text
                            }
                        }
                    
                    // 输入框底部工具栏
                    HStack(spacing: 16) {
                        // 快捷键提示
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            
                            Text("press.shortcut.to.speak")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            
                            if preferences.enableVoiceInput {
                                HStack(spacing: 3) {
                                    ForEach(shortcutKeys, id: \.self) { key in
                                        Text(key)
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background {
                                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                    .fill(Color.secondary.opacity(0.15))
                                            }
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // 字数统计
                        if !inputText.isEmpty {
                            Text("\(inputText.count) \(NSLocalizedString("characters", comment: ""))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        
                        // 操作按钮
                        HStack(spacing: 8) {
                            // 清空按钮
                            if !inputText.isEmpty {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        inputText = ""
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(NSLocalizedString("clear", comment: ""))
                            }
                            
                            // 复制按钮
                            if !inputText.isEmpty {
                                Button(action: {
                                    history.copyToPasteboard(inputText)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                .help(NSLocalizedString("copy", comment: ""))
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(20)
                .background {
                    Rectangle()
                        .fill(.regularMaterial)
                }
                
                Divider()
            }
            
            // 历史记录区域
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("history")
                            .font(.system(size: 17, weight: .semibold))
                        
                        if !history.items.isEmpty {
                            Text("\(history.items.count) \(NSLocalizedString("records", comment: ""))")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // 统计信息
                    if !history.items.isEmpty {
                        HStack(spacing: 20) {
                            // 总时长
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                
                                Text(formatDuration(history.totalDuration()))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                            
                            // 总字数
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                
                                Text(formatCharacterCount(history.totalCharacters()))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                            
                            // 每分钟字数
                            HStack(spacing: 6) {
                                Image(systemName: "bolt")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                
                                Text("\(history.charactersPerMinute()) \(NSLocalizedString("characters.per.minute", comment: ""))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    
                    // 清空按钮
                    if !history.items.isEmpty {
                        Button(action: {
                            history.clear()
                            inputText = ""
                        }) {
                            Text("clear.all")
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                Divider()
                
                // 历史记录列表
                if history.items.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("no.records")
                                .font(.system(size: 20, weight: .semibold))
                        } icon: {
                            Image(systemName: "waveform")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                    } description: {
                        VStack(spacing: 8) {
                            Text("press.shortcut.to.start")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            
                            if preferences.enableVoiceInput {
                                HStack(spacing: 3) {
                                    Text("press")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                    
                                    ForEach(shortcutKeys, id: \.self) { key in
                                        Text(key)
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background {
                                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                    .fill(Color.secondary.opacity(0.2))
                                            }
                                    }
                                    
                                    Text("to.speak")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(history.items) { item in
                                VoiceInputHistoryRow(item: item)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 4)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("voice.input", comment: ""))
        .onAppear {
            // 初始化时，如果有最新记录，显示在输入框中
            if let latestItem = history.items.first {
                inputText = latestItem.text
            }
        }
        .alert(NSLocalizedString("error", comment: ""), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(NSLocalizedString("ok", comment: ""), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    // 格式化快捷键显示
    private var shortcutKeys: [String] {
        guard preferences.enableVoiceInput else {
            return []
        }
        
        var keys: [String] = []
        let modifiers = preferences.voiceInputShortcutModifiers
        
        if modifiers.contains(.command) {
            keys.append("⌘")
        }
        if modifiers.contains(.shift) {
            keys.append("⇧")
        }
        if modifiers.contains(.option) {
            keys.append("⌥")
        }
        if modifiers.contains(.control) {
            keys.append("⌃")
        }
        
        let keyName = keyCodeToString(preferences.voiceInputShortcutKeyCode)
        keys.append(keyName)
        
        return keys.isEmpty ? [] : keys
    }
    
    // 格式化时长显示（分钟）
    private func formatDuration(_ minutes: Double) -> String {
        if minutes < 1 {
            return "0\(NSLocalizedString("minutes", comment: ""))"
        } else if minutes < 60 {
            return "\(Int(minutes))\(NSLocalizedString("minutes", comment: ""))"
        } else {
            let hours = Int(minutes / 60)
            let mins = Int(minutes.truncatingRemainder(dividingBy: 60))
            return "\(hours)\(NSLocalizedString("hours", comment: ""))\(mins)\(NSLocalizedString("minutes", comment: ""))"
        }
    }
    
    // 格式化字数显示（带千分位）
    private func formatCharacterCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return "\(formatter.string(from: NSNumber(value: count)) ?? "\(count)")\(NSLocalizedString("characters", comment: ""))"
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        // 常见按键映射
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

/// 历史记录行视图
struct VoiceInputHistoryRow: View {
    let item: VoiceInputHistoryItem
    @ObservedObject private var history = VoiceInputHistory.shared
    @State private var isHovered = false
    @State private var copySuccess = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 时间戳
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                if item.duration > 0 {
                    Text(String(format: "%.1fs", item.duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 65, alignment: .trailing)
            
            // 文本内容
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // 操作按钮（固定在右侧，使用透明度控制显示）
            HStack(spacing: 6) {
                // 复制按钮
                Button(action: {
                    history.copyToPasteboard(item.text)
                    copySuccess = true
                    // 1.5秒后恢复图标
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            copySuccess = false
                        }
                    }
                }) {
                    Image(systemName: copySuccess ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(copySuccess ? .green : .blue)
                        .frame(width: 20, height: 20)
                        .animation(.easeInOut(duration: 0.2), value: copySuccess)
                }
                .buttonStyle(.plain)
                .help(copySuccess ? NSLocalizedString("copied", comment: "") : NSLocalizedString("copy", comment: ""))
                .opacity(isHovered ? 1.0 : 0.0)
                .allowsHitTesting(isHovered)
                
                // 删除按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        history.remove(item)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("delete", comment: ""))
                .opacity(isHovered ? 1.0 : 0.0)
                .allowsHitTesting(isHovered)
            }
            .frame(width: 52) // 固定宽度，避免布局抖动
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: item.timestamp)
    }
}

#Preview {
    VoiceInputView()
}
