//
//  QuickSettingsTab.swift
//  fastv
//
//  Created by rocky on 2025/11/29.
//

import SwiftUI
import AVFoundation

/// 设置 - 语音输入：快捷键、触发方式、识别语言、智能分段、悬浮工具条、文本插入、权限测试。
struct VoiceInputTab: View {
    @ObservedObject var preferences = UserPreferences.shared

    var body: some View {
        Form {
            // 语音输入配置
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // 主快捷鍵設置區域（純語音輸入）
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("語音輸入快捷鍵")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Text("純語音輸入")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        
                        Text("當前快捷鍵：")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // 主快捷鍵捕獲器
                        ShortcutCaptureView(
                            keyCode: Binding(
                                get: { preferences.voiceInputShortcutKeyCode },
                                set: { preferences.voiceInputShortcutKeyCode = $0 }
                            ),
                            modifiers: Binding(
                                get: { preferences.voiceInputShortcutModifiers },
                                set: { preferences.voiceInputShortcutModifiers = $0 }
                            ),
                            defaultKeyCode: 0x3F,  // 默認 FN
                            defaultModifiers: []
                        )
                    }
                    
                    Divider()
                    
                    // AI 校正快捷鍵設置區域（語音輸入 + AI 校正）
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("AI 校正快捷鍵")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Text("語音輸入 + AI 校正")
                                .font(.caption)
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        
                        Text("當前快捷鍵：")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // AI 校正快捷鍵捕獲器
                        ShortcutCaptureView(
                            keyCode: Binding(
                                get: { preferences.voiceInputWithAIShortcutKeyCode },
                                set: { preferences.voiceInputWithAIShortcutKeyCode = $0 }
                            ),
                            modifiers: Binding(
                                get: { preferences.voiceInputWithAIShortcutModifiers },
                                set: { preferences.voiceInputWithAIShortcutModifiers = $0 }
                            ),
                            defaultKeyCode: 0x3F,  // 默認 FN
                            defaultModifiers: .control  // 默認 Control 修飾鍵
                        )
                        
                        // AI 校正說明
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.purple)
                            Text("使用此快捷鍵時，語音識別完成後會自動進行 AI 文本優化。需要先在「AI與模型」中配置 AI 服務。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()

                    // 触发方式：按住 / 切换 / 混合
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(NSLocalizedString("hotkey.trigger.mode.title", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        Picker("", selection: $preferences.hotkeyTriggerMode) {
                            Text(NSLocalizedString("hotkey.trigger.mode.push.to.talk", comment: ""))
                                .tag(HotkeyTriggerMode.pushToTalk)
                            Text(NSLocalizedString("hotkey.trigger.mode.toggle", comment: ""))
                                .tag(HotkeyTriggerMode.toggle)
                            Text(NSLocalizedString("hotkey.trigger.mode.hybrid", comment: ""))
                                .tag(HotkeyTriggerMode.hybrid)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text(triggerModeDescription(preferences.hotkeyTriggerMode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // 识别语言设置
                    Picker(NSLocalizedString("recognition.language", comment: ""), selection: $preferences.voiceInputLanguage) {
                        Text(NSLocalizedString("auto.detect", comment: "")).tag("auto")
                        Text(NSLocalizedString("chinese", comment: "")).tag("zh")
                        Text(NSLocalizedString("english", comment: "")).tag("en")
                        Text(NSLocalizedString("cantonese", comment: "")).tag("yue")
                        Text(NSLocalizedString("japanese", comment: "")).tag("ja")
                        Text(NSLocalizedString("korean", comment: "")).tag("ko")
                    }
                    
                    // 自动检测提示
                    if preferences.voiceInputLanguage == "auto" {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text(NSLocalizedString("auto.detect.hint", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 20)
                    }
                        
                        Divider()
                        
                        // 智能分段转文字
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(NSLocalizedString("enable.incremental.transcription", comment: ""), isOn: $preferences.enableIncrementalTranscription)
                            
                            if preferences.enableIncrementalTranscription {
                                HStack(spacing: 8) {
                                    Text(NSLocalizedString("silence.detection.duration", comment: ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Slider(value: $preferences.silenceDetectionDuration, in: 0.5...2.0, step: 0.1)
                                    Text("\(String(format: "%.1f", preferences.silenceDetectionDuration))s")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, alignment: .trailing)
                                }
                            }
                            
                            Text(NSLocalizedString("incremental.transcription.description", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        
                        // 松开后尾缓冲：减少末尾内容丢失
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(NSLocalizedString("voice.input.release.tail.buffer", comment: ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Slider(value: $preferences.voiceInputReleaseTailBufferSeconds, in: 0...1.0, step: 0.1)
                                Text("\(String(format: "%.1f", preferences.voiceInputReleaseTailBufferSeconds))s")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                            }
                            Text(NSLocalizedString("voice.input.release.tail.buffer.description", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        
                        // 悬浮工具条位置设置
                        Picker(NSLocalizedString("waveform.window.position", comment: ""), selection: $preferences.waveformWindowPosition) {
                            ForEach(WaveformWindowPosition.allCases, id: \.self) { position in
                                Text(position.displayName).tag(position)
                            }
                        }

                        if preferences.waveformWindowPosition.isFollowingCursor {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                Text(NSLocalizedString("waveform.position.followCursor.hint", comment: ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 20)
                        }

                        // 悬浮工具条样式设置
                        Picker(NSLocalizedString("waveform.window.size", comment: ""), selection: $preferences.waveformWindowStyle) {
                            ForEach(WaveformWindowStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        
                        // 悬浮工具条颜色设置
                        Picker(NSLocalizedString("waveform.window.color", comment: ""), selection: $preferences.waveformWindowColorStyle) {
                            ForEach(WaveformWindowColorStyle.allCases, id: \.self) { colorStyle in
                                let colorConfig = colorStyle.colorConfig(for: .dark)
                                HStack(spacing: 8) {
                                    // 显示背景色和音量条颜色的组合预览
                                    ZStack {
                                        // 背景色
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(colorConfig.backgroundColor.opacity(colorConfig.backgroundOpacity))
                                            .frame(width: 24, height: 16)
                                        
                                        // 音量条颜色（小竖条）
                                        HStack(spacing: 2) {
                                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                                .fill(colorConfig.barColor)
                                                .frame(width: 2, height: 8)
                                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                                .fill(colorConfig.barColor)
                                                .frame(width: 2, height: 12)
                                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                                .fill(colorConfig.barColor)
                                                .frame(width: 2, height: 10)
                                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                                .fill(colorConfig.barColor)
                                                .frame(width: 2, height: 8)
                                        }
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                                    }
                                    
                                    Text(colorStyle.displayName)
                                        .font(.body)
                                }
                                .tag(colorStyle)
                            }
                        }
                        
                        Divider()
                        
                        // 文本插入方式设置
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(NSLocalizedString("direct.text.insertion", comment: ""), isOn: $preferences.useDirectTextInsertion)
                            
                            Text(preferences.useDirectTextInsertion
                                ? NSLocalizedString("direct.text.insertion.description", comment: "")
                                : NSLocalizedString("clipboard.text.insertion.description", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Toggle(NSLocalizedString("ai.contextual.rewrite", comment: ""), isOn: $preferences.enableAIContextualRewrite)

                            Text(NSLocalizedString("ai.contextual.rewrite.description", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        
                        // 测试按钮区域
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("permission.test", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    testMicrophonePermission()
                                }) {
                                    HStack {
                                        Image(systemName: "mic.circle.fill")
                                        Text(NSLocalizedString("test.microphone.permission", comment: ""))
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .help(NSLocalizedString("test.microphone.permission", comment: ""))
                                
                                Button(action: {
                                    print("🧪 [QuickSettingsTab] 测试显示波形窗口")
                                    WaveformWindowManager.shared.show()
                                    
                                    // 3秒后自动隐藏
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        print("🧪 [QuickSettingsTab] 测试结束，隐藏窗口")
                                        WaveformWindowManager.shared.hide()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "play.circle.fill")
                                        Text(NSLocalizedString("test.show.toolbar", comment: ""))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help(NSLocalizedString("test.show.toolbar", comment: ""))
                            }
                            
                            Button(action: {
                                WaveformWindowManager.shared.cleanup()
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                    Text(NSLocalizedString("cleanup.toolbar.window", comment: ""))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(NSLocalizedString("cleanup.toolbar.window", comment: ""))
                        }
                    }
            } header: {
                Text(NSLocalizedString("voice.input.section", comment: ""))
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("voice.input.description", comment: ""))
                    
                    // 权限状态显示
                    PermissionStatusView()
                    
                    // FN键提示
                    if preferences.voiceInputShortcutKeyCode == 0x3F || preferences.voiceInputWithAIShortcutKeyCode == 0x3F {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text(NSLocalizedString("fn.key.hint", comment: ""))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    // 双快捷键使用说明
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text("使用說明：")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        
                        let voiceShortcut = formatShortcut(
                            keyCode: preferences.voiceInputShortcutKeyCode,
                            modifiers: preferences.voiceInputShortcutModifiers
                        )
                        let aiShortcut = formatShortcut(
                            keyCode: preferences.voiceInputWithAIShortcutKeyCode,
                            modifiers: preferences.voiceInputWithAIShortcutModifiers
                        )
                        
                        Text("• \(voiceShortcut)：按住開始錄音，鬆開後直接輸入文字")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        
                        Text("• \(aiShortcut)：按住開始錄音，鬆開後進行 AI 校正再輸入")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }

        }
        .formStyle(.grouped)
    }
    
    // MARK: - Helper Methods
    
    /// 测试麦克风权限
    private func testMicrophonePermission() {
        print("🧪 [QuickSettingsTab] 测试麦克风权限")
        
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎤 [QuickSettingsTab] 当前麦克风权限状态: \(status.rawValue)")
        
        switch status {
        case .notDetermined:
            print("🎤 [QuickSettingsTab] 权限未确定，请求麦克风权限...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        print("✅ [QuickSettingsTab] 用户已授权麦克风权限")
                        showPermissionGrantedAlert()
                    } else {
                        print("❌ [QuickSettingsTab] 用户拒绝了麦克风权限")
                        showPermissionDeniedAlert()
                    }
                }
            }
            
        case .authorized:
            print("✅ [QuickSettingsTab] 麦克风权限已授权")
            showPermissionAlreadyGrantedAlert()
            
        case .denied, .restricted:
            print("⚠️ [QuickSettingsTab] 麦克风权限被拒绝或受限")
            showPermissionDeniedAlert()
            
        @unknown default:
            print("⚠️ [QuickSettingsTab] 未知的权限状态")
        }
    }
    
    private func showPermissionGrantedAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("permission.granted.title", comment: "")
        alert.informativeText = NSLocalizedString("permission.granted.description", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("great", comment: ""))
        alert.runModal()
    }
    
    private func showPermissionAlreadyGrantedAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("permission.already.granted.title", comment: "")
        alert.informativeText = NSLocalizedString("permission.already.granted.description", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("got.it", comment: ""))
        alert.runModal()
    }
    
    private func showPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("permission.denied.title", comment: "")
        alert.informativeText = NSLocalizedString("permission.denied.description", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("open.system.settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("later", comment: ""))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func formatShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        
        if modifiers.contains(.command) {
            parts.append("⌘")
        }
        if modifiers.contains(.shift) {
            parts.append("⇧")
        }
        if modifiers.contains(.option) {
            parts.append("⌥")
        }
        if modifiers.contains(.control) {
            parts.append("⌃")
        }
        
        let keyName: String
        switch keyCode {
        case 0xFFFF: keyName = "左Control"
        case 0x3F: keyName = "FN"
        case 0x09: keyName = "V"
        case 0x00: keyName = "A"
        case 0x0B: keyName = "B"
        case 0x08: keyName = "C"
        case 0x02: keyName = "D"
        case 0x0E: keyName = "E"
        case 0x03: keyName = "F"
        case 0x05: keyName = "G"
        case 0x04: keyName = "H"
        case 0x22: keyName = "I"
        case 0x26: keyName = "J"
        case 0x28: keyName = "K"
        case 0x25: keyName = "L"
        case 0x2E: keyName = "M"
        case 0x2D: keyName = "N"
        case 0x1F: keyName = "O"
        case 0x23: keyName = "P"
        case 0x0C: keyName = "Q"
        case 0x0F: keyName = "R"
        case 0x01: keyName = "S"
        case 0x11: keyName = "T"
        case 0x20: keyName = "U"
        case 0x31: keyName = "Space"
        case 0x24: keyName = "Return"
        case 0x35: keyName = "Esc"
        default: keyName = "键\(keyCode)"
        }
        
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    private func triggerModeDescription(_ mode: HotkeyTriggerMode) -> String {
        switch mode {
        case .pushToTalk:
            return NSLocalizedString("hotkey.trigger.mode.push.to.talk.description", comment: "")
        case .toggle:
            return NSLocalizedString("hotkey.trigger.mode.toggle.description", comment: "")
        case .hybrid:
            return NSLocalizedString("hotkey.trigger.mode.hybrid.description", comment: "")
        }
    }
}

#Preview {
    VoiceInputTab()
}
