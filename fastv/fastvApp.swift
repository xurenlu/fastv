//
//  fastvApp.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AVFoundation
import Combine
import AppKit

// 全局变量：记录语音输入开始时间
private var voiceInputStartTime: Date?

private struct ShortcutConfig: Equatable {
    var isEnabled: Bool
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
}

private var lastShortcutConfig: ShortcutConfig?

/// 应用代理，用于监听应用退出事件
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 应用启动完成后，初始化状态栏
        print("📱 [AppDelegate] 应用启动完成，初始化状态栏")
        StatusBarManager.shared.show()
        
        // 设置应用不自动退出（关闭窗口时保留在后台）
        NSApplication.shared.setActivationPolicy(.regular)
        
        // 设置窗口标题为多语言的 APP 名称
        DispatchQueue.main.async {
            self.setWindowTitle()
        }
    }
    
    /// 设置窗口标题为多语言的 APP 名称
    private func setWindowTitle() {
        // 获取多语言的 APP 名称（使用本地化字符串）
        let appName = NSLocalizedString("app.name", comment: "应用名称")
        
        // 设置所有窗口的标题
        for window in NSApplication.shared.windows {
            window.title = appName
        }
        
        // 监听新窗口创建，自动设置标题
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                window.title = NSLocalizedString("app.name", comment: "应用名称")
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("🧹 [AppDelegate] 应用即将退出，清理资源")
        WaveformWindowManager.shared.cleanup()
        StatusBarManager.shared.cleanup()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 当最后一个窗口关闭时，不退出应用，而是隐藏窗口并保留在系统托盘
        print("📱 [AppDelegate] 最后一个窗口关闭，隐藏窗口并保留在系统托盘")
        // 隐藏所有窗口
        NSApplication.shared.windows.forEach { window in
            window.orderOut(nil)
        }
        // 不退出应用
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 当用户点击 Dock 图标时，显示主窗口
        if !flag {
            // 如果没有可见窗口，显示主窗口
            if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        return true
    }
}

@main
struct fastvApp: App {
    @StateObject private var appState = AppStateManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    // 应用启动时，先清理可能遗留的工具条窗口（兜底方案）
                    Task { @MainActor in
                        print("🧹 [fastvApp] 应用启动，清理可能遗留的工具条窗口")
                        WaveformWindowManager.shared.cleanup()
                        
                        // 确保状态栏已初始化
                        StatusBarManager.shared.show()
                        
                        // 设置窗口标题为多语言的 APP 名称
                        if let window = NSApplication.shared.windows.first {
                            window.title = NSLocalizedString("app.name", comment: "应用名称")
                        }
                        
                        // 延迟初始化，确保窗口已显示
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                        setupVoiceInput()
                    }
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 800, height: 600)
    }
    
    /// 清理波形窗口（兜底方案）
    private func cleanupWaveformWindow() {
        print("🧹 [fastvApp] 清理波形窗口（兜底方案）")
        WaveformWindowManager.shared.cleanup()
    }
    
    private func setupVoiceInput() {
        // 确保在主线程执行
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.setupVoiceInput()
            }
            return
        }
        
        // 请求麦克风权限（异步，不阻塞）
        Task { @MainActor in
            requestMicrophonePermission()
        }
        
        // 请求辅助功能权限（异步，不阻塞）
        Task { @MainActor in
            let hasAccessibility = TextInsertionService.checkAccessibilityPermission()
            if hasAccessibility {
                print("✅ [fastvApp] 辅助功能权限已授权")
            } else {
                print("⚠️ [fastvApp] 辅助功能权限未授权，请求权限...")
                print("💡 [fastvApp] 提示：系统将弹出权限请求对话框，请点击'打开系统偏好设置'")
                let appName = NSLocalizedString("app.name", comment: "")
                print("💡 [fastvApp] 然后在'系统设置 > 隐私与安全性 > 辅助功能'中找到 \(appName) 并勾选")
                TextInsertionService.requestAccessibilityPermission()
            }
        }
        
        // 设置全局快捷键监听（延迟执行，确保应用已完全启动）
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒延迟
            setupGlobalShortcut()
        }
        
        // 监听设置变化
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            // 延迟一下，确保 UserPreferences 已经更新
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Task { @MainActor in
                    applyShortcutConfigIfNeeded(reason: "UserDefaults.didChangeNotification")
                }
            }
        }
    }
    
    private func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎤 [fastvApp] 当前麦克风权限状态: \(status.rawValue) - \(microphoneStatusDescription(status))")
        
        // 添加 Bundle ID 诊断信息
        if let bundleId = Bundle.main.bundleIdentifier {
            print("🔍 [fastvApp] Bundle ID: \(bundleId)")
        }
        
        switch status {
        case .notDetermined:
            print("🎤 [fastvApp] 权限未确定，请求麦克风权限...")
            print("💡 [fastvApp] 提示：系统将弹出权限请求对话框，请点击'允许'授权")
            print("⏳ [fastvApp] 等待用户响应权限请求...")
            
            // 请求权限（这是异步的，会弹出系统对话框）
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                if granted {
                        print("✅ [fastvApp] 用户已授权麦克风权限")
                        print("💡 [fastvApp] 现在可以使用语音输入功能了")
                } else {
                        print("❌ [fastvApp] 用户拒绝了麦克风权限")
                        print("💡 [fastvApp] 如需使用语音输入，请在'系统设置 > 隐私与安全性 > 麦克风'中手动授权应用")
                        if let bundleId = Bundle.main.bundleIdentifier {
                            print("💡 [fastvApp] 请确保系统设置中授权的是 Bundle ID: \(bundleId)")
                        }
                        
                        // 显示提示对话框
                        self.showMicrophonePermissionDeniedAlert()
                    }
                }
            }
        case .authorized:
            print("✅ [fastvApp] 麦克风权限已授权")
            // 权限已授权，不需要再次请求
        case .denied, .restricted:
            print("⚠️ [fastvApp] 麦克风权限被拒绝或受限")
            print("💡 [fastvApp] 提示：请在'系统设置 > 隐私与安全性 > 麦克风'中找到应用并勾选")
            if let bundleId = Bundle.main.bundleIdentifier {
                print("💡 [fastvApp] 请确保系统设置中授权的是 Bundle ID: \(bundleId)")
                print("💡 [fastvApp] 如果系统设置中显示的是不同的应用名称，可能是 Bundle ID 不匹配")
            }
            
            // 显示提示对话框
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.showMicrophonePermissionDeniedAlert()
            }
        @unknown default:
            print("⚠️ [fastvApp] 未知的权限状态: \(status.rawValue)")
        }
    }
    
    private func microphoneStatusDescription(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "未确定（系统将请求权限）"
        case .restricted:
            return "受限制（可能被家长控制或企业策略限制）"
        case .denied:
            return "已拒绝（需要在系统设置中手动授权）"
        case .authorized:
            return "已授权"
        @unknown default:
            return "未知状态"
        }
    }
    
    @MainActor
    private func showMicrophonePermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("microphone.permission.required", comment: "")
        alert.informativeText = NSLocalizedString("microphone.permission.description", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("open.system.settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("later", comment: ""))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 打开系统设置的麦克风权限页面
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func setupGlobalShortcut() {
        // 确保在主线程执行
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.setupGlobalShortcut()
            }
            return
        }
        
        print("🔧 [fastvApp] 开始设置全局快捷键")
        
        let preferences = UserPreferences.shared
        
        print("🔧 [fastvApp] 语音输入设置: enableVoiceInput=\(preferences.enableVoiceInput), keyCode=\(preferences.voiceInputShortcutKeyCode), modifiers=\(preferences.voiceInputShortcutModifiers.rawValue)")
        
        // 设置快捷键监听回调（使用带Ctrl状态的回调）
        print("🔧 [fastvApp] 设置快捷键回调函数")
        GlobalShortcutMonitor.shared.onShortcutPressedWithCtrl = { hasCtrl in
            print("🎯 [fastvApp] onShortcutPressed 回调被触发（Ctrl: \(hasCtrl)）")
            Task { @MainActor in
                await handleShortcutPressed(hasCtrl: hasCtrl)
            }
        }
        
        GlobalShortcutMonitor.shared.onShortcutReleasedWithCtrl = { hasCtrl in
            print("🎯 [fastvApp] onShortcutReleased 回调被触发（Ctrl: \(hasCtrl)）")
            Task { @MainActor in
                await handleShortcutReleased(hasCtrl: hasCtrl)
            }
        }
        
        applyShortcutConfigIfNeeded(reason: "initial setup")
    }
    
    @MainActor
    private func applyShortcutConfigIfNeeded(reason: String) {
        let preferences = UserPreferences.shared
        let newConfig = ShortcutConfig(
            isEnabled: preferences.enableVoiceInput,
            keyCode: preferences.voiceInputShortcutKeyCode,
            modifiers: preferences.voiceInputShortcutModifiers
        )
        
        if newConfig == lastShortcutConfig {
            print("ℹ️ [fastvApp] 快捷键配置未变化（原因: \(reason)），跳过重新注册")
            return
        }
        
        lastShortcutConfig = newConfig
        
        if newConfig.isEnabled {
            print("🔧 [fastvApp] 快捷键配置已更新（原因: \(reason)），重新注册监听")
            GlobalShortcutMonitor.shared.startMonitoring(
                keyCode: newConfig.keyCode,
                modifiers: newConfig.modifiers
            )
        } else {
            print("ℹ️ [fastvApp] 语音输入已禁用（原因: \(reason)），停止快捷键监听")
            GlobalShortcutMonitor.shared.stopMonitoring()
        }
    }
    
    @MainActor
    private func handleShortcutPressed(hasCtrl: Bool = false) async {
        print("🎤 [fastvApp] handleShortcutPressed: 开始处理快捷键按下事件")
        
        // 记录开始时间
        voiceInputStartTime = Date()
        
        let voiceService = VoiceInputService.shared
        let waveformManager = WaveformWindowManager.shared
        
        // 先显示波形窗口（即使录音失败也要显示）
        print("📊 [fastvApp] 显示波形窗口...")
        waveformManager.show()
        print("✅ [fastvApp] 波形窗口已显示")
        
        // 开始录音
        do {
            print("🎤 [fastvApp] 尝试开始录音...")
            try voiceService.startRecording()
            print("✅ [fastvApp] 录音已开始")
            
            // 连接音频数据回调
            voiceService.onAudioData = { level in
                waveformManager.updateAudioLevel(level)
            }
            print("✅ [fastvApp] 音频数据回调已连接")
        } catch VoiceInputError.microphoneInUse {
            print("❌ [fastvApp] 麦克风被占用（可能是闪电说或其他应用）")
            // 显示错误提示
            waveformManager.hide()
            showMicrophoneInUseAlert()
        } catch VoiceInputError.microphonePermissionDenied {
            print("❌ [fastvApp] 麦克风权限被拒绝")
            // 隐藏窗口并显示权限提示
            waveformManager.hide()
            showMicrophonePermissionAlert()
        } catch {
            print("❌ [fastvApp] 开始录音失败: \(error)")
            // 即使录音失败，也保持窗口显示，让用户知道快捷键已触发
            // 但如果是权限问题，应该隐藏窗口并提示
            waveformManager.hide()
        }
    }
    
    /// 显示麦克风被占用的提示
    @MainActor
    private func showMicrophoneInUseAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("microphone.in.use", comment: "")
        alert.informativeText = NSLocalizedString("microphone.in.use.description", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("got.it", comment: ""))
        alert.runModal()
    }
    
    /// 显示麦克风权限被拒绝的提示
    @MainActor
    private func showMicrophonePermissionAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("microphone.permission.required", comment: "")
        alert.informativeText = NSLocalizedString("microphone.permission.description", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("open.system.settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("later", comment: ""))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 打开系统设置的麦克风权限页面
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @MainActor
    private func handleShortcutReleased(hasCtrl: Bool = false) async {
        print("🎤 [fastvApp] handleShortcutReleased: 开始处理快捷键释放事件")
        
        // 计算持续时间
        let duration: Double
        if let startTime = voiceInputStartTime {
            duration = Date().timeIntervalSince(startTime)
            print("⏱️ [fastvApp] 输入时长: \(String(format: "%.2f", duration))秒")
        } else {
            duration = 0
            print("⚠️ [fastvApp] 未找到开始时间，使用默认时长 0")
        }
        voiceInputStartTime = nil
        
        let voiceService = VoiceInputService.shared
        let waveformManager = WaveformWindowManager.shared
        let textInsertion = TextInsertionService.shared
        let history = VoiceInputHistory.shared
        
        // 立即切换到转文字状态（在停止录音之前），不使用延迟
        print("📊 [fastvApp] 立即切换到转文字状态...")
        waveformManager.setTranscribing()
        print("✅ [fastvApp] 已切换到转文字状态")
        
        // 停止录音
        print("🎤 [fastvApp] 停止录音...")
        guard let recording = try? await voiceService.stopRecording() else {
            print("❌ [fastvApp] 停止录音失败或返回空录音数据")
            // 如果停止录音失败，也要隐藏窗口
            waveformManager.hide()
            return
        }
        print("✅ [fastvApp] 录音已停止，PCM字节数: \(recording.pcmData.count)")
        
        // 语音转文字
        print("🔊 [fastvApp] 开始语音转文字...")
        do {
            // 获取用户设置的识别语言
            let preferences = UserPreferences.shared
            let languageString = preferences.voiceInputLanguage
            let language = TranscriptLanguage(rawValue: languageString) ?? .zh // 如果无效，默认使用中文
            print("🌐 [fastvApp] 使用识别语言: \(languageString) (languageID: \(language.languageID))")
            
            var text = try await SpeechTranscriber.transcribe(recording: recording, language: language)
            print("✅ [fastvApp] 语音转文字成功: \(text.prefix(50))...")
            
            // 快速纠错（如果启用，毫秒级，非常快）
            if preferences.enableFastCorrection {
                let correctionStartTime = Date()
                text = TextCorrectionService.shared.correctText(text)
                let correctionDuration = Date().timeIntervalSince(correctionStartTime) * 1000 // 转换为毫秒
                print("✅ [fastvApp] 快速纠错完成，耗时: \(String(format: "%.2f", correctionDuration))毫秒")
            }
            
            // 常错词自动修正（在AI优化之前）
            let mistakeManager = CommonMistakeManager.shared
            if mistakeManager.enableAutoCorrection {
                let mistakeStartTime = Date()
                let originalText = text
                text = mistakeManager.applyCorrections(to: text)
                if text != originalText {
                    let mistakeDuration = Date().timeIntervalSince(mistakeStartTime) * 1000
                    print("✅ [fastvApp] 常错词修正完成，耗时: \(String(format: "%.2f", mistakeDuration))毫秒")
                    print("📝 [fastvApp] 修正前: \(originalText.prefix(50))...")
                    print("📝 [fastvApp] 修正后: \(text.prefix(50))...")
                }
            }
            
            // AI 优化（如果启用）
            // 注意：已移除Control键检测，现在只根据设置决定是否启用AI优化
            if preferences.enableAIOptimization {
                print("🤖 [fastvApp] AI 优化已启用，开始优化文本（超时: \(preferences.aiTimeout)秒）...")
                // 设置AI修正中状态
                waveformManager.setAICorrecting()
                
                let aiStartTime = Date()
                do {
                    let optimizedText = try await OllamaService.shared.optimizeTranscript(
                        text: text,
                        scenario: .voiceInputOptimization,
                        systemPrompt: preferences.aiSystemPrompt,
                        useMistakes: true,
                        useHighFrequencyWords: true
                    )
                    let aiDuration = Date().timeIntervalSince(aiStartTime)
                    print("✅ [fastvApp] AI 优化完成，耗时: \(String(format: "%.2f", aiDuration))秒")
                    print("📝 [fastvApp] 原文: \(text.prefix(50))...")
                    print("📝 [fastvApp] 优化后: \(optimizedText.prefix(50))...")
                    text = optimizedText
                    
                    // AI修正成功：设置成功状态（会自动在1秒后隐藏窗口）
                    waveformManager.setAICorrected()
                } catch {
                    print("⚠️ [fastvApp] AI 优化失败，使用原始文本: \(error.localizedDescription)")
                    // AI 优化失败不影响主流程，继续使用原始文本
                    // AI修正失败：设置失败状态（会自动在0.8秒后隐藏窗口）
                    waveformManager.setAICorrectionFailed()
                }
            } else {
                print("ℹ️ [fastvApp] AI 优化未启用（设置中已关闭），使用原始文本")
                // AI修正未启用：设置未启用状态（会自动在0.8秒后隐藏窗口）
                waveformManager.setAICorrectionDisabled()
            }
            
            // 先插入文本（优先保证用户体验）
            if !text.isEmpty {
                print("📝 [fastvApp] 插入文本到当前输入框...")
                textInsertion.insertText(text)
                print("✅ [fastvApp] 文本已插入")
            } else {
                print("ℹ️ [fastvApp] 识别结果为空，跳过文本插入")
            }
            
            // 注意：波形窗口的隐藏由AI修正状态方法自动处理
            // - AI修正成功：setAICorrected() 会在1秒后自动隐藏
            // - AI修正失败：setAICorrectionFailed() 会在0.8秒后自动隐藏
            // - AI修正未启用：setAICorrectionDisabled() 会在0.8秒后自动隐藏
            // 如果AI优化未启用，窗口会在显示未启用状态后自动隐藏
            // 如果AI优化启用但失败，窗口会在显示失败状态后自动隐藏
            // 如果AI优化成功，窗口会在显示成功状态1秒后自动隐藏
            
            // 最后保存到历史记录（延迟保存，不阻塞文本插入）
            history.add(text, duration: duration)
            print("✅ [fastvApp] 已保存到历史记录（时长: \(String(format: "%.2f", duration))秒）")
        } catch {
            print("❌ [fastvApp] 语音转文字失败: \(error)")
            // 转文字失败时也要隐藏窗口
            waveformManager.hide()
        }
    }
}

/// 应用状态管理器
class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    private init() {}
}

