//
//  fastvApp.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AVFoundation
import Combine

// 全局变量：记录语音输入开始时间
private var voiceInputStartTime: Date?

@main
struct fastvApp: App {
    @StateObject private var appState = AppStateManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    // 延迟初始化，确保窗口已显示
                    Task { @MainActor in
                        // 延迟一下，确保应用完全启动
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                        setupVoiceInput()
                    }
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 800, height: 600)
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
            if !TextInsertionService.checkAccessibilityPermission() {
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
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                // 权限请求完成
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
        } catch {
            print("❌ [fastvApp] 开始录音失败: \(error)")
            // 即使录音失败，也保持窗口显示，让用户知道快捷键已触发
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
        
        // 隐藏波形窗口
        print("📊 [fastvApp] 隐藏波形窗口...")
        waveformManager.hide()
        print("✅ [fastvApp] 波形窗口已隐藏")
        
        // 停止录音
        print("🎤 [fastvApp] 停止录音...")
        guard let audioURL = try? await voiceService.stopRecording() else {
            print("❌ [fastvApp] 停止录音失败或返回空URL")
            return
        }
        print("✅ [fastvApp] 录音已停止，音频文件: \(audioURL.path)")
        
        // 语音转文字
        print("🔊 [fastvApp] 开始语音转文字...")
        do {
            let text = try await SpeechTranscriber.transcribe(audioURL: audioURL)
            print("✅ [fastvApp] 语音转文字成功: \(text.prefix(50))...")
            
            // 保存到历史记录（包含时长）
            history.add(text, duration: duration)
            print("✅ [fastvApp] 已保存到历史记录（时长: \(String(format: "%.2f", duration))秒）")
            
            // 插入到当前输入框
            print("📝 [fastvApp] 插入文本到当前输入框...")
            textInsertion.insertText(text)
            print("✅ [fastvApp] 文本已插入")
            
            // 清理临时文件
            try? FileManager.default.removeItem(at: audioURL)
            print("✅ [fastvApp] 临时文件已清理")
        } catch {
            print("❌ [fastvApp] 语音转文字失败: \(error)")
        }
    }
}

/// 应用状态管理器
class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    private init() {}
}

