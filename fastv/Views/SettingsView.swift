//
//  SettingsView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AVFoundation
import AppKit

struct SettingsView: View {
    @ObservedObject var preferences = UserPreferences.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("提取第一帧", isOn: $preferences.extractFirstFrame)
                    Toggle("提取最后一帧", isOn: $preferences.extractLastFrame)
                    Toggle("提取音频", isOn: $preferences.extractAudio)
                    
                    Picker("音频格式", selection: $preferences.audioFormat) {
                        ForEach(AudioFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                } header: {
                    Text("默认处理选项")
                } footer: {
                    Text("这些选项将作为下次处理视频时的默认设置")
                }
                
                Section {
                    Picker("图片格式", selection: $preferences.imageFormat) {
                        ForEach(ImageFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    
                    HStack {
                        Text("最大宽度")
                        Spacer()
                        TextField("", value: $preferences.imageMaxWidth, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                        Text("像素")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("最大高度")
                        Spacer()
                        TextField("", value: $preferences.imageMaxHeight, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                        Text("像素")
                            .foregroundStyle(.secondary)
                    }
                    
                    Toggle("启用图片压缩", isOn: $preferences.imageCompressionEnabled)
                    
                    if preferences.imageCompressionEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("压缩质量")
                                Spacer()
                                Text("\(Int(preferences.imageCompressionQuality * 100))%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $preferences.imageCompressionQuality, in: 0.1...1.0)
                        }
                        .padding(.leading, 20)
                    }
                } header: {
                    Text("图片设置")
                } footer: {
                    Text("设置图片的最大尺寸和压缩选项")
                }
                
                Section {
                    Toggle("启用语音输入法", isOn: $preferences.enableVoiceInput)
                    
                    if preferences.enableVoiceInput {
                        VStack(alignment: .leading, spacing: 16) {
                            // 快捷键设置区域
                            VStack(alignment: .leading, spacing: 8) {
                                Text("全局快捷键")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                // 快捷键捕获器
                                ShortcutCaptureView(
                                    keyCode: Binding(
                                        get: { preferences.voiceInputShortcutKeyCode },
                                        set: { preferences.voiceInputShortcutKeyCode = $0 }
                                    ),
                                    modifiers: Binding(
                                        get: { preferences.voiceInputShortcutModifiers },
                                        set: { preferences.voiceInputShortcutModifiers = $0 }
                                    )
                                )
                            }
                            
                            Divider()
                            
                            // 识别语言设置
                            Picker("识别语言", selection: $preferences.voiceInputLanguage) {
                                Text("自动检测").tag("auto")
                                Text("中文").tag("zh")
                                Text("英文").tag("en")
                                Text("日语").tag("ja")
                                Text("韩语").tag("ko")
                            }
                            
                            Divider()
                            
                            // 悬浮工具条位置设置
                            Picker("悬浮工具条位置", selection: $preferences.waveformWindowPosition) {
                                ForEach(WaveformWindowPosition.allCases, id: \.self) { position in
                                    Text(position.displayName).tag(position)
                                }
                            }
                            
                            Divider()
                            
                            // 麦克风权限测试按钮
                            VStack(alignment: .leading, spacing: 12) {
                                Text("权限测试")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                HStack(spacing: 12) {
                                    Button(action: {
                                        testMicrophonePermission()
                                    }) {
                                        HStack {
                                            Image(systemName: "mic.circle.fill")
                                            Text("测试麦克风权限")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .help("测试麦克风权限，如果未授权会弹出权限请求对话框")
                                    
                                    Button(action: {
                                        print("🧪 [SettingsView] 测试显示波形窗口")
                                        WaveformWindowManager.shared.show()
                                        
                                        // 3秒后自动隐藏
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                            print("🧪 [SettingsView] 测试结束，隐藏窗口")
                                            WaveformWindowManager.shared.hide()
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "play.circle.fill")
                                            Text("测试显示工具条")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("测试显示波形工具条（3秒后自动消失）")
                                }
                                
                            Button(action: {
                                WaveformWindowManager.shared.cleanup()
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("清理工具条窗口")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("如果工具条窗口没有正常关闭，可以点击此按钮强制清理")
                            }
                        }
                        .padding(.leading, 20)
                    }
                } header: {
                    Text("语音输入法")
                } footer: {
                    if preferences.enableVoiceInput {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("按下快捷键开始语音输入，松开时自动识别并插入文本。需要麦克风和辅助功能权限。")
                            
                            // 权限状态显示
                            PermissionStatusView()
                            
                            // FN键提示
                            if preferences.voiceInputShortcutKeyCode == 0x3F {
                                VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    Text("提示：FN键在macOS上可能被其他应用占用，如果无法正常工作，建议使用其他快捷键组合（如 ⌥V 或 ⌘⇧V）。")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    }
                                    
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                        Text("冲突警告：如果闪电说等其他语音输入应用也使用FN键，可能会导致麦克风资源冲突。建议：\n• 关闭其他语音输入应用\n• 或使用不同的快捷键\n• 或错开使用时间")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            
                            // Control键提示
                            if preferences.voiceInputShortcutKeyCode == 0xFFFF {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                        Text("推荐：单独按左Control键是一个很好的选择，不容易与其他应用冲突。")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    HStack(spacing: 6) {
                                        Image(systemName: "info.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                        Text("使用说明：\n• 单独按下左Control键开始录音\n• 如果同时按了其他键（如Ctrl+C），不会触发录音\n• 松开Control键后自动识别并插入文本")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            
                            // 显示当前快捷键说明
                            if preferences.enableVoiceInput {
                                let currentShortcut = formatShortcut(
                                    keyCode: preferences.voiceInputShortcutKeyCode,
                                    modifiers: preferences.voiceInputShortcutModifiers
                                )
                                Text("当前快捷键：\(currentShortcut)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                    } else {
                        Text("启用后可通过快捷键进行语音输入")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(minWidth: 520, minHeight: 480)
        }
    }
    
    /// 测试麦克风权限
    private func testMicrophonePermission() {
        print("🧪 [SettingsView] 测试麦克风权限")
        
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎤 [SettingsView] 当前麦克风权限状态: \(status.rawValue) - \(microphoneStatusDescription(status))")
        
        switch status {
        case .notDetermined:
            print("🎤 [SettingsView] 权限未确定，请求麦克风权限...")
            print("💡 [SettingsView] 即将弹出系统权限对话框，请稍候...")
            
            // 直接请求权限，不先显示提示
            // 这样系统对话框会立即弹出
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        print("✅ [SettingsView] 用户已授权麦克风权限")
                        self.showPermissionGrantedAlert()
                    } else {
                        print("❌ [SettingsView] 用户拒绝了麦克风权限")
                        self.showPermissionDeniedAlert()
                    }
                }
            }
            
        case .authorized:
            print("✅ [SettingsView] 麦克风权限已授权")
            showPermissionAlreadyGrantedAlert()
            
        case .denied, .restricted:
            print("⚠️ [SettingsView] 麦克风权限被拒绝或受限")
            print("💡 [SettingsView] 尝试使用其他方法触发权限请求...")
            // 尝试通过实际使用麦克风来触发权限请求
            tryToTriggerPermissionDialog()
            
        @unknown default:
            print("⚠️ [SettingsView] 未知的权限状态")
        }
    }
    
    /// 尝试通过实际使用麦克风来触发权限对话框
    private func tryToTriggerPermissionDialog() {
        print("🎤 [SettingsView] 尝试通过AVAudioEngine触发权限请求...")
        
        let alert = NSAlert()
        alert.messageText = "尝试触发权限请求"
        alert.informativeText = "即将尝试访问麦克风以触发系统权限对话框。\n\n如果弹出权限对话框，请点击\"允许\"。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 尝试创建音频引擎来触发权限
            let audioEngine = AVAudioEngine()
            let inputNode = audioEngine.inputNode
            
            // 安装tap会触发权限请求
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.inputFormat(forBus: 0)) { _, _ in
                // 不做任何处理
            }
            
            do {
                try audioEngine.start()
                print("✅ [SettingsView] 音频引擎已启动，应该触发了权限请求")
                
                // 等待一会儿，然后停止
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    
                    // 重新检查权限状态
                    let newStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                    if newStatus == .authorized {
                        self.showPermissionGrantedAlert()
                    } else {
                        self.showPermissionDeniedAlert()
                    }
                }
            } catch {
                print("❌ [SettingsView] 启动音频引擎失败: \(error)")
                self.showPermissionDeniedAlert()
            }
        }
    }
    
    private func microphoneStatusDescription(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "未确定"
        case .restricted:
            return "受限制"
        case .denied:
            return "已拒绝"
        case .authorized:
            return "已授权"
        @unknown default:
            return "未知"
        }
    }
    
    private func showPermissionRequestAlert() {
        let alert = NSAlert()
        alert.messageText = "请求麦克风权限"
        alert.informativeText = "系统将弹出权限请求对话框。\n\n请点击\"允许\"以授权 fastv 访问麦克风。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
    
    private func showPermissionGrantedAlert() {
        let alert = NSAlert()
        alert.messageText = "✅ 麦克风权限已授权"
        alert.informativeText = "您已成功授权麦克风权限！\n\n现在可以使用语音输入功能了。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "太好了")
        alert.runModal()
    }
    
    private func showPermissionAlreadyGrantedAlert() {
        let alert = NSAlert()
        alert.messageText = "✅ 麦克风权限已授权"
        alert.informativeText = "您已经授权了麦克风权限。\n\n可以直接使用语音输入功能。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
    
    private func showPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "⚠️ 麦克风权限被拒绝"
        alert.informativeText = "语音输入功能需要麦克风权限。\n\n请按以下步骤手动授权：\n1. 打开\"系统设置\"\n2. 进入\"隐私与安全性\" > \"麦克风\"\n3. 找到 fastv 并勾选"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        
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
}

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
                Text("当前快捷键:")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if keyCode == 0 {
                    Text("未设置")
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
                    
                    Text(isCapturing ? "停止捕获（按下要设置的快捷键）" : "点击设置快捷键")
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
                    
                    Text("请按下要设置的快捷键（支持FN键）")
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

struct ShortcutModifiersPicker: View {
    @Binding var modifiers: NSEvent.ModifierFlags
    
    var body: some View {
        HStack(spacing: 6) {
            ModifierKeyButton(
                symbol: "⌘",
                isSelected: modifiers.contains(.command),
                action: {
                    if modifiers.contains(.command) {
                        modifiers.remove(.command)
                    } else {
                        modifiers.insert(.command)
                    }
                }
            )
            
            ModifierKeyButton(
                symbol: "⇧",
                isSelected: modifiers.contains(.shift),
                action: {
                    if modifiers.contains(.shift) {
                        modifiers.remove(.shift)
                    } else {
                        modifiers.insert(.shift)
                    }
                }
            )
            
            ModifierKeyButton(
                symbol: "⌥",
                isSelected: modifiers.contains(.option),
                action: {
                    if modifiers.contains(.option) {
                        modifiers.remove(.option)
                    } else {
                        modifiers.insert(.option)
                    }
                }
            )
            
            ModifierKeyButton(
                symbol: "⌃",
                isSelected: modifiers.contains(.control),
                action: {
                    if modifiers.contains(.control) {
                        modifiers.remove(.control)
                    } else {
                        modifiers.insert(.control)
                    }
                }
            )
        }
    }
}

struct ModifierKeyButton: View {
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 32, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? 
                              Color.accentColor.opacity(0.15) : 
                              (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                                    lineWidth: 1
                                )
                        }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// 权限状态视图
struct PermissionStatusView: View {
    @State private var microphoneStatus: AVAuthorizationStatus = .notDetermined
    @State private var accessibilityStatus: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 麦克风权限状态
            HStack(spacing: 8) {
                Image(systemName: microphoneStatus == .authorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(microphoneStatus == .authorized ? .green : .red)
                
                Text("麦克风权限")
                    .font(.system(size: 12))
                
                Spacer()
                
                Text(statusText(for: microphoneStatus))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                if microphoneStatus != .authorized {
                    HStack(spacing: 8) {
                        Button("申请权限") {
                            requestMicrophonePermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .font(.system(size: 11))
                        
                        Button("打开设置") {
                            openSystemSettings(for: .microphone)
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    }
                }
            }
            
            // 辅助功能权限状态
            HStack(spacing: 8) {
                Image(systemName: accessibilityStatus ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(accessibilityStatus ? .green : .red)
                
                Text("辅助功能权限")
                    .font(.system(size: 12))
                
                Spacer()
                
                Text(accessibilityStatus ? "已授权" : "未授权")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                if !accessibilityStatus {
                    Button("打开设置") {
                        openSystemSettings(for: .accessibility)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        // 检查麦克风权限
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        // 检查辅助功能权限
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        accessibilityStatus = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .notDetermined:
            // 请求权限
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.checkPermissions()
                }
            }
        case .denied, .restricted:
            // 权限被拒绝，打开系统设置
            openSystemSettings(for: .microphone)
        case .authorized:
            // 已授权，无需操作
            break
        @unknown default:
            break
        }
    }
    
    private func statusText(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "已授权"
        case .notDetermined:
            return "未请求"
        case .denied:
            return "已拒绝"
        case .restricted:
            return "受限"
        @unknown default:
            return "未知"
        }
    }
    
    private func openSystemSettings(for permission: PermissionType) {
        switch permission {
        case .microphone:
            // 打开系统设置中的麦克风权限页面
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        case .accessibility:
            // 打开系统设置中的辅助功能权限页面
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    enum PermissionType {
        case microphone
        case accessibility
    }
}

#Preview {
    SettingsView()
}
