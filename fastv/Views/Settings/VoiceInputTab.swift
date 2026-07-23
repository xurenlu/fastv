//
//  QuickSettingsTab.swift
//  fastv
//
//  Created by rocky on 2025/11/29.
//

import SwiftUI
import AVFoundation
import AppKit

// MARK: - 主窗皮肤调色板环境（从原 VoiceInputView 迁移，供测试框/统计/历史卡片使用）

private struct MainWindowPaletteKey: EnvironmentKey {
    static let defaultValue = MainWindowSkinPalette.systemDefault
}

private extension EnvironmentValues {
    var mainWindowPalette: MainWindowSkinPalette {
        get { self[MainWindowPaletteKey.self] }
        set { self[MainWindowPaletteKey.self] = newValue }
    }
}

/// 设置 - 语音输入：快捷键、触发方式、识别语言、智能分段、悬浮工具条、文本插入、权限测试，
/// 以及测试输入框、语音输入统计、语音输入历史（原主窗口内容并入此 tab）。
struct VoiceInputTab: View {
    @ObservedObject var preferences = UserPreferences.shared
    @ObservedObject private var historyManager = VoiceInputHistoryManager.shared
    @ObservedObject private var contextProfileManager = ContextProfileManager.shared
    @State private var testInputText: String = ""
    @FocusState private var isTestInputFocused: Bool
    @State private var showClearHistoryConfirm = false
    @State private var copiedRecordId: UUID?
    @State private var subtab: VoiceSubtab = .general

    /// 语音输入的二级子 tab
    enum VoiceSubtab: String, CaseIterable, Identifiable {
        case general    // 杂项设置 + 测试框
        case stats      // 统计与历史
        case powerMode  // Power Mode 场景感知
        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .general: return "voice.subtab.general"
            case .stats: return "voice.subtab.stats"
            case .powerMode: return "voice.subtab.powerMode"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $subtab) {
                ForEach(VoiceSubtab.allCases) { tab in
                    Text(NSLocalizedString(tab.titleKey, comment: "")).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            switch subtab {
            case .general: generalForm
            case .stats: statsForm
            case .powerMode: powerModeForm
            }
        }
    }

    // MARK: - 子 tab：杂项设置 + 测试框

    private var generalForm: some View {
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

            // 默认语言（仅作用于语音输入识别的默认语言）
            Section {
                Picker(NSLocalizedString("default.language", comment: ""), selection: Binding(
                    get: { preferences.defaultLanguage },
                    set: { newValue in
                        preferences.defaultLanguage = newValue
                        LocalizationManager.shared.currentLanguage = newValue
                    }
                )) {
                    ForEach(SupportedLanguage.allCases, id: \.self) { language in
                        Text(language.nativeName).tag(language.rawValue)
                    }
                }
            } header: {
                Text(NSLocalizedString("language", comment: ""))
            } footer: {
                Text(NSLocalizedString("language.description", comment: ""))
            }

            // 测试输入框（原主窗口内容并入）
            Section {
                TestInputSection(
                    testInputText: $testInputText,
                    isTestInputFocused: $isTestInputFocused
                )
                .environment(\.mainWindowPalette, MainWindowSkinPalette.systemDefault)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 子 tab：统计与历史

    private var statsForm: some View {
        Form {
            // 语音输入统计
            Section {
                StatsSection(historyManager: historyManager)
                    .environment(\.mainWindowPalette, MainWindowSkinPalette.systemDefault)
            }

            // 语音输入历史
            Section {
                HistorySection(
                    historyManager: historyManager,
                    copiedRecordId: $copiedRecordId,
                    showClearHistoryConfirm: $showClearHistoryConfirm,
                    onCopyRecord: copyRecord
                )
                .environment(\.mainWindowPalette, MainWindowSkinPalette.systemDefault)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(NSLocalizedString("clear.all.confirm.title", comment: ""), isPresented: $showClearHistoryConfirm) {
            Button(NSLocalizedString("clear.all", comment: ""), role: .destructive) {
                historyManager.clear()
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("clear.all.confirm.message", comment: ""))
        }
    }

    // MARK: - 子 tab：Power Mode（场景感知 prompt 模板）

    private var powerModeForm: some View {
        Form {
            Section {
                Toggle(
                    NSLocalizedString("context.profile.enable.power.mode", comment: ""),
                    isOn: $contextProfileManager.enablePowerMode
                )

                NavigationLink {
                    ContextProfileEditorView()
                        .navigationTitle(NSLocalizedString("context.profile.title", comment: ""))
                        .frame(minWidth: 780, minHeight: 580)
                } label: {
                    HStack {
                        Image(systemName: "rectangle.and.text.magnifyingglass")
                        Text(NSLocalizedString("context.profile.title", comment: ""))
                        Spacer()
                        Text("\(contextProfileManager.profiles.count) " + NSLocalizedString("context.profile.count.suffix", comment: ""))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .disabled(!contextProfileManager.enablePowerMode)
            } header: {
                Text(NSLocalizedString("context.profile.section.header", comment: ""))
            } footer: {
                Text(NSLocalizedString("context.profile.section.footer", comment: ""))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 历史记录复制

    private func copyRecord(_ record: VoiceInputHistoryRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.text, forType: .string)
        copiedRecordId = record.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copiedRecordId = nil
        }
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

// MARK: - 测试输入区（原 VoiceInputView 迁移）
private struct TestInputSection: View {
    @Binding var testInputText: String
    @FocusState.Binding var isTestInputFocused: Bool
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 提示：简洁、不喧宾夺主
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryTextColor)
                    .symbolRenderingMode(.hierarchical)
                Text(NSLocalizedString("main.usage.hint", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryTextColor)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.elevatedSurfaceColor)
            )

            // 输入框
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("test.input.label", comment: ""))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.secondaryTextColor)

                TextField(NSLocalizedString("test.input.placeholder", comment: ""), text: $testInputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .focused($isTestInputFocused)
                    .foregroundStyle(palette.primaryTextColor)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.fieldColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(isTestInputFocused ? palette.accentColor.opacity(0.62) : palette.borderColor, lineWidth: isTestInputFocused ? 1.5 : 1)
                            )
                    )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.surfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.borderColor, lineWidth: 1)
                )
        )
    }
}

// MARK: - 统计区（卡片式，Apple 风格）
private struct StatsSection: View {
    @ObservedObject var historyManager: VoiceInputHistoryManager
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 区块标题：明确这些数据来自语音输入
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.subheadline)
                    .foregroundStyle(palette.accentColor)
                Text(NSLocalizedString("stats.voice.section", comment: ""))
                    .font(.headline)
                    .foregroundStyle(palette.primaryTextColor)
            }

            // 今日 / 累计 双卡片
            HStack(spacing: 16) {
                VoiceInputStatCard(
                    title: NSLocalizedString("stats.today", comment: ""),
                    characterCount: historyManager.todayCharacterCount,
                    charactersPerMinute: historyManager.todayCharactersPerMinute,
                    audioSeconds: historyManager.todayAudioSeconds,
                    transcriptionSeconds: historyManager.todayTranscriptionSeconds,
                    realtimeFactor: historyManager.todayRealtimeFactor
                )
                VoiceInputStatCard(
                    title: NSLocalizedString("stats.all", comment: ""),
                    characterCount: historyManager.totalCharacterCount,
                    charactersPerMinute: historyManager.totalCharactersPerMinute,
                    audioSeconds: historyManager.totalAudioSeconds,
                    transcriptionSeconds: historyManager.totalTranscriptionSeconds,
                    realtimeFactor: historyManager.totalRealtimeFactor
                )
            }

            // 平均每条
            HStack(spacing: 8) {
                Text(NSLocalizedString("avg.characters.per.record", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryTextColor)
                Text(String(format: "%.0f", historyManager.averageCharactersPerRecord))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.elevatedSurfaceColor)
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.surfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.borderColor, lineWidth: 1)
                )
        )
    }
}

// MARK: - 统计卡片（语音输入专用，与 EmailDashboardView.StatCard 区分）
private struct VoiceInputStatCard: View {
    let title: String
    let characterCount: Int
    let charactersPerMinute: Double?
    let audioSeconds: TimeInterval
    let transcriptionSeconds: TimeInterval
    let realtimeFactor: Double?
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.secondaryTextColor)

            HStack(spacing: 16) {
                StatItemView(
                    title: NSLocalizedString("stats.characters", comment: ""),
                    value: "\(characterCount)"
                )
                StatItemView(
                    title: NSLocalizedString("stats.chars.per.min", comment: ""),
                    value: charsPerMinDisplay
                )
                StatItemView(
                    title: NSLocalizedString("stats.audio.seconds", comment: ""),
                    value: formatSeconds(audioSeconds)
                )
                StatItemView(
                    title: NSLocalizedString("stats.transcription.seconds", comment: ""),
                    value: formatSeconds(transcriptionSeconds)
                )
                StatItemView(
                    title: NSLocalizedString("stats.realtime.factor", comment: ""),
                    value: realtimeFactorDisplay
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.elevatedSurfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(palette.borderColor.opacity(0.7), lineWidth: 1)
                )
        )
    }

    private var charsPerMinDisplay: String {
        if let cpm = charactersPerMinute, cpm > 0 {
            return String(format: "%.0f", cpm)
        }
        return "—"
    }

    private var realtimeFactorDisplay: String {
        if let rtf = realtimeFactor, rtf > 0 {
            let unit = NSLocalizedString("stats.realtime.factor.unit", comment: "")
            return String(format: "%.2f%@", rtf, unit)
        }
        return "—"
    }

    private func formatSeconds(_ s: TimeInterval) -> String {
        guard s > 0 else { return "—" }
        if s >= 60 {
            let m = Int(s) / 60
            let sec = Int(s) % 60
            let minStr = NSLocalizedString("minute", comment: "")
            let secStr = NSLocalizedString("seconds.short", comment: "")
            return "\(m)\(minStr)\(sec)\(secStr)"
        }
        let secStr = NSLocalizedString("seconds.short", comment: "")
        return String(format: "%.1f", s) + secStr
    }
}

// MARK: - 统计项
private struct StatItemView: View {
    let title: String
    let value: String
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(palette.tertiaryTextColor)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.primaryTextColor)
        }
    }
}

// MARK: - 历史记录区
private struct HistorySection: View {
    @ObservedObject var historyManager: VoiceInputHistoryManager
    @Binding var copiedRecordId: UUID?
    @Binding var showClearHistoryConfirm: Bool
    let onCopyRecord: (VoiceInputHistoryRecord) -> Void
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题行
            HStack {
                Text(NSLocalizedString("voice.input.history", comment: ""))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.primaryTextColor)
                Text("(\(historyManager.totalCount) \(NSLocalizedString("records", comment: "")))")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryTextColor)
                Spacer()
                if !historyManager.records.isEmpty {
                    Button(action: { showClearHistoryConfirm = true }) {
                        Text(NSLocalizedString("clear.all", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if historyManager.records.isEmpty {
                ContentUnavailableView {
                    Label(NSLocalizedString("no.records", comment: ""), systemImage: "text.badge.plus")
                }
                .foregroundStyle(palette.secondaryTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                VStack(spacing: 0) {
                    ForEach(historyManager.records) { record in
                        HistoryRecordRow(
                            record: record,
                            isCopied: copiedRecordId == record.id,
                            onCopy: { onCopyRecord(record) },
                            onDelete: { historyManager.remove(record) }
                        )
                        if record.id != historyManager.records.last?.id {
                            Rectangle()
                                .fill(palette.borderColor)
                                .frame(height: 1)
                                .padding(.leading, 20)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.elevatedSurfaceColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(palette.borderColor, lineWidth: 1)
                        )
                )
            }
        }
    }
}

// MARK: - 历史记录行（Apple 风格：清晰、可操作）
private struct HistoryRecordRow: View {
    let record: VoiceInputHistoryRecord
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @Environment(\.mainWindowPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.text)
                    .font(.body)
                    .lineLimit(5)
                    .textSelection(.enabled)
                    .foregroundStyle(palette.primaryTextColor)
                Text(record.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryTextColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.leading, 20)

            Button(action: onCopy) {
                if isCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .symbolRenderingMode(.hierarchical)
                        Text(NSLocalizedString("copy.success", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .foregroundStyle(isHovered ? palette.primaryTextColor : palette.secondaryTextColor)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 20)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(action: onCopy) {
                Label(NSLocalizedString("copy", comment: ""), systemImage: "doc.on.doc")
            }
            Button(role: .destructive, action: onDelete) {
                Label(NSLocalizedString("delete", comment: ""), systemImage: "trash")
            }
        }
    }
}

#Preview {
    VoiceInputTab()
}
