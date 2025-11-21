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
    @State private var isTranscribing = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // 快捷键说明区域
            VStack(spacing: 16) {
                // 按着说模式
                HStack(spacing: 12) {
                    Text("按着说:")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        // 显示快捷键按钮
                        ForEach(shortcutKeys, id: \.self) { key in
                            Text(key)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.gray.opacity(0.2))
                                }
                        }
                    }
                    
                    Text("按住开始说话,松开后结束")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                
                if !preferences.enableVoiceInput {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        
                        Text("请在设置中启用语音输入法功能")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .background {
                Rectangle()
                    .fill(.regularMaterial)
            }
            
            Divider()
            
            // 统计信息栏
            HStack(spacing: 32) {
                // 总时长
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    
                    Text(formatDuration(history.totalDuration()))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }
                
                // 总字数
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    
                    Text(formatCharacterCount(history.totalCharacters()))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }
                
                // 每分钟字数
                HStack(spacing: 8) {
                    Image(systemName: "bolt")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    
                    Text("\(history.charactersPerMinute()) 字/分")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                Rectangle()
                    .fill(Color.secondary.opacity(0.05))
            }
            
            Divider()
            
            // 历史记录区域
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Text("History")
                        .font(.system(size: 17, weight: .semibold))
                    
                    Spacer()
                    
                    if !history.items.isEmpty {
                        Button(action: {
                            history.clear()
                        }) {
                            Text("清空所有")
                                .font(.system(size: 13))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                Divider()
                
                // 历史记录列表
                if history.items.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("暂无记录")
                                .font(.system(size: 20, weight: .semibold))
                        } icon: {
                            Image(systemName: "waveform")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                    } description: {
                        Text("按下快捷键开始语音输入")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(history.items) { item in
                            VoiceInputHistoryRow(item: item)
                                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("语音输入")
        .alert("错误", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {
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
            return ["未设置"]
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
        
        return keys.isEmpty ? ["未设置"] : keys
    }
    
    // 格式化时长显示（分钟）
    private func formatDuration(_ minutes: Double) -> String {
        if minutes < 1 {
            return "0分"
        } else if minutes < 60 {
            return "\(Int(minutes))分"
        } else {
            let hours = Int(minutes / 60)
            let mins = Int(minutes.truncatingRemainder(dividingBy: 60))
            return "\(hours)小时\(mins)分"
        }
    }
    
    // 格式化字数显示（带千分位）
    private func formatCharacterCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return "\(formatter.string(from: NSNumber(value: count)) ?? "\(count)")字"
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        // 常见按键映射
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

/// 历史记录行视图
struct VoiceInputHistoryRow: View {
    let item: VoiceInputHistoryItem
    @ObservedObject private var history = VoiceInputHistory.shared
    @State private var isHovered = false
    @State private var showMenu = false
    @State private var copySuccess = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // 时间戳
            VStack(alignment: .trailing, spacing: 4) {
                Text(timeString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .trailing)
            
            // 文本内容
            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(2)
            }
            
            // 操作按钮（悬停时显示）
            if isHovered {
                HStack(spacing: 8) {
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
                            .font(.system(size: 13))
                            .foregroundStyle(copySuccess ? .green : .blue)
                            .animation(.easeInOut(duration: 0.2), value: copySuccess)
                    }
                    .buttonStyle(.plain)
                    .help(copySuccess ? "已复制" : "复制")
                    
                    // 删除按钮
                    Button(action: {
                        withAnimation {
                            history.remove(item)
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                    
                    // 更多选项按钮
                    Menu {
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
                            Label("复制", systemImage: copySuccess ? "checkmark.circle.fill" : "doc.on.doc")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: {
                            withAnimation {
                                history.remove(item)
                            }
                        }) {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("更多选项")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 20)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
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

