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

/// 应用代理，用于监听应用退出事件
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        print("🧹 [AppDelegate] 应用即将退出，清理波形窗口")
        WaveformWindowManager.shared.cleanup()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 当最后一个窗口关闭时，清理波形窗口
        print("🧹 [AppDelegate] 最后一个窗口关闭，清理波形窗口")
        WaveformWindowManager.shared.cleanup()
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
                print("💡 [fastvApp] 然后在'系统设置 > 隐私与安全性 > 辅助功能'中找到 fastv 并勾选")
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
                // 由于 fastvApp 是 struct，不需要 weak self
                // 直接调用全局函数或通过 shared 实例访问
                Task { @MainActor in
                    // 重新设置快捷键
                    let preferences = UserPreferences.shared
                    if preferences.enableVoiceInput {
                        GlobalShortcutMonitor.shared.startMonitoring(
                            keyCode: preferences.voiceInputShortcutKeyCode,
                            modifiers: preferences.voiceInputShortcutModifiers
                        )
                    } else {
                        GlobalShortcutMonitor.shared.stopMonitoring()
                    }
                }
            }
        }
    }
    
    private func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎤 [fastvApp] 当前麦克风权限状态: \(status.rawValue) - \(microphoneStatusDescription(status))")
        
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
                        print("💡 [fastvApp] 如需使用语音输入，请在'系统设置 > 隐私与安全性 > 麦克风'中手动授权 fastv")
                        
                        // 显示提示对话框
                        self.showMicrophonePermissionDeniedAlert()
                    }
                }
            }
        case .authorized:
            print("✅ [fastvApp] 麦克风权限已授权")
        case .denied, .restricted:
            print("⚠️ [fastvApp] 麦克风权限被拒绝或受限")
            print("💡 [fastvApp] 提示：请在'系统设置 > 隐私与安全性 > 麦克风'中找到 fastv 并勾选")
            
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
        alert.messageText = "需要麦克风权限"
        alert.informativeText = "语音输入功能需要访问麦克风。\n\n请按以下步骤授权：\n1. 打开\"系统设置\"\n2. 进入\"隐私与安全性\" > \"麦克风\"\n3. 找到 fastv 并勾选\n4. 重启应用"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        
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
        
        // 如果未启用语音输入，停止监听
        guard preferences.enableVoiceInput else {
            print("ℹ️ [fastvApp] 语音输入未启用，停止快捷键监听")
            GlobalShortcutMonitor.shared.stopMonitoring()
            return
        }
        
        // 设置快捷键监听回调
        print("🔧 [fastvApp] 设置快捷键回调函数")
        GlobalShortcutMonitor.shared.onShortcutPressed = {
            print("🎯 [fastvApp] onShortcutPressed 回调被触发")
            Task { @MainActor in
                await handleShortcutPressed()
            }
        }
        
        GlobalShortcutMonitor.shared.onShortcutReleased = {
            print("🎯 [fastvApp] onShortcutReleased 回调被触发")
            Task { @MainActor in
                await handleShortcutReleased()
            }
        }
        
        // 开始监听
        print("🔧 [fastvApp] 调用 startMonitoring 开始监听快捷键")
        GlobalShortcutMonitor.shared.startMonitoring(
            keyCode: preferences.voiceInputShortcutKeyCode,
            modifiers: preferences.voiceInputShortcutModifiers
        )
    }
    
    @MainActor
    private func handleShortcutPressed() async {
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
        alert.messageText = "麦克风正在使用中"
        alert.informativeText = "麦克风正被其他应用使用（如闪电说）。\n\n解决方法：\n1. 关闭其他语音输入应用\n2. 或使用不同的快捷键避免冲突\n3. 或在其他应用不录音时使用本应用"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
    
    /// 显示麦克风权限被拒绝的提示
    @MainActor
    private func showMicrophonePermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要麦克风权限"
        alert.informativeText = "语音输入功能需要访问麦克风。\n\n请按以下步骤授权：\n1. 打开\"系统设置\"\n2. 进入\"隐私与安全性\" > \"麦克风\"\n3. 找到 fastv 并勾选\n4. 重新尝试语音输入"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 打开系统设置的麦克风权限页面
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @MainActor
    private func handleShortcutReleased() async {
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
        
        // 切换到转文字状态（不隐藏窗口）
        print("📊 [fastvApp] 切换到转文字状态...")
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
            let text = try await SpeechTranscriber.transcribe(recording: recording)
            print("✅ [fastvApp] 语音转文字成功: \(text.prefix(50))...")
            
            // 保存到历史记录（包含时长）
            history.add(text, duration: duration)
            print("✅ [fastvApp] 已保存到历史记录（时长: \(String(format: "%.2f", duration))秒）")
            
            // 插入到当前输入框
            print("📝 [fastvApp] 插入文本到当前输入框...")
            textInsertion.insertText(text)
            print("✅ [fastvApp] 文本已插入")
            
            // 转文字完成后，隐藏波形窗口
            print("📊 [fastvApp] 转文字完成，隐藏波形窗口...")
            waveformManager.hide()
            print("✅ [fastvApp] 波形窗口已隐藏")
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

