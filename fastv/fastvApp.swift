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

// 自定义通知名称
extension Notification.Name {
    static let shortcutConfigDidChange = Notification.Name("shortcutConfigDidChange")
}

// 语音输入时长阈值（秒）
private enum VoiceInputDurationThreshold {
    /// 最短推荐录音时长，低于此时长提示用户「建议说长一点」
    static let minimumRecommended: TimeInterval = 0.5
    /// 智能分段：单段最短时长，低于此时长跳过转写
    static let minimumIncrementalSegment: TimeInterval = 1.0
    /// 智能分段：剩余段落最短时长（已有缓存时更严格）
    static let minimumRemainingWhenHasCache: TimeInterval = 1.5
}

// 全局变量：记录语音输入开始时间
private var voiceInputStartTime: Date?
// 記錄當前語音輸入是否需要 AI 校正
private var currentVoiceInputNeedsAI: Bool = false
// 本次錄音會話是否啟用智能分段
private var currentSessionUsesIncremental: Bool = false
// 本次錄音會話的靜音檢測器（智能分段時使用）
private var currentSessionSilenceDetector: SilenceDetector?
// 智能分段轉寫串行隊列：確保按時間順序插入，避免並發導致順序錯亂
private var incrementalTranscriptionTask: Task<Void, Never>?
/// 智能分段單條結果：含音頻與轉寫文本，用於二次拼接轉寫（長音頻準確率更高）
private struct IncrementalSegmentInfo {
    let audio: VoiceRecording
    let transcript: String
}

// 智能分段轉寫結果緩存：邊說邊轉但不插入，鬆鍵時一次性合併輸出（利於 AI 優化整段）
private var incrementalTranscriptionResults: [IncrementalSegmentInfo] = []
// 智能分段本輪累計：語音時長、識別耗時（用於統計）
private var currentSessionIncrementalAudioSeconds: TimeInterval = 0
private var currentSessionIncrementalTranscriptionSeconds: TimeInterval = 0

/// 二次拼接轉寫：動態規劃分批，每批至少3段、至少3秒，避免過短片段。鬆鍵時若某批已完成則替換該批零碎結果。
private var incrementalBatchRefinementTasks: [Task<Void, Never>] = []
private var incrementalBatchPartition: [Range<Int>] = []       // 動態規劃分批方案，如 [0..<4, 4..<7]
private var incrementalBatchRefinedTexts: [String?] = []       // 每批的轉寫結果，nil 表示未完成
private let incrementalBatchMinSegments = 3  // 至少 3 段才觸發（2 段拼接效果提升有限）
private let incrementalBatchMinDuration: TimeInterval = 3.0     // 每批至少 3 秒，避免過短
private let incrementalBatchMaxDuration: TimeInterval = 6.0     // 每批最多 6 秒，避免過度合併導致效率下降

/// 智能分段：靜音觸發時提取當前段落、轉寫並緩存（串行執行，不插入，鬆鍵時一次性輸出）
/// 同時啟動二次拼接轉寫：多段音頻合併後再轉寫，準確率更高；鬆鍵時若已完成則替換零碎結果
@MainActor
private func performIncrementalSegmentTranscription() async {
    let voiceService = VoiceInputService.shared
    let waveformManager = WaveformWindowManager.shared
    let language = TranscriptLanguage(rawValue: UserPreferences.shared.voiceInputLanguage) ?? .zh

    guard let result = try? await voiceService.extractCurrentSegmentWithTiming() else { return }
    guard result.duration >= VoiceInputDurationThreshold.minimumIncrementalSegment else {
        print("⚠️ [fastvApp] 智能分段：段落過短(\(String(format: "%.1f", result.duration))s)，跳過")
        return
    }

    currentSessionIncrementalAudioSeconds += result.duration

    // 檢測到停頓、開始轉寫時，立即切換為轉文字中的轉圈樣式
    waveformManager.setTranscribing()

    let transcribeStart = CFAbsoluteTimeGetCurrent()
    do {
        var text = try await SpeechTranscriber.transcribe(recording: result.recording, language: language, enableCTCDeduplication: nil)
        currentSessionIncrementalTranscriptionSeconds += CFAbsoluteTimeGetCurrent() - transcribeStart
        if CommonMistakeManager.shared.enableAutoCorrection {
            text = TextCorrectionService.shared.correctText(text)
        }
        guard !text.isEmpty else { return }

        let segmentInfo = IncrementalSegmentInfo(audio: result.recording, transcript: text)
        incrementalTranscriptionResults.append(segmentInfo)
        print("✅ [fastvApp] 智能分段轉寫緩存: \(text.prefix(30))... (共\(incrementalTranscriptionResults.count)段)")

        // 二次拼接轉寫：動態規劃分批，每批至少3段、至少2秒
        if incrementalTranscriptionResults.count >= incrementalBatchMinSegments {
            scheduleBatchRefinementTranscription(language: language)
        }
    } catch {
        print("❌ [fastvApp] 智能分段轉寫失敗: \(error)")
    }

    // 轉寫完成，恢復錄音狀態（用戶可繼續說話）
    waveformManager.setRecording()
}

/// 動態規劃分批：每批至少 minSegments 段、至少 minDuration 秒、最多 maxDuration 秒
/// 例如 7 段可拆成 4+3 或 7（一整批），9 段可拆成 6+3 或 9，優先讓每批盡長但不超过最大時長
/// 避免過度合併（如先合併成10秒、後續再合併成16秒）導致轉寫效率大幅下降
private func partitionSegmentsForBatchRefinement(_ segments: [IncrementalSegmentInfo]) -> [Range<Int>] {
    let n = segments.count
    guard n >= incrementalBatchMinSegments else { return [] }
    var result: [Range<Int>] = []
    var start = 0
    while start < n {
        let remaining = n - start
        if remaining < incrementalBatchMinSegments {
            if !result.isEmpty {
                let last = result.removeLast()
                result.append(last.lowerBound..<n)
            } else {
                result.append(start..<n)
            }
            break
        }
        var bestEnd = start + incrementalBatchMinSegments
        var bestDuration = segments[start..<bestEnd].reduce(0.0) { $0 + $1.audio.durationSeconds }
        // 若不足最小時長，繼續加段（但不超过最大時長）
        while bestDuration < incrementalBatchMinDuration && bestEnd < n && bestDuration < incrementalBatchMaxDuration {
            bestEnd += 1
            bestDuration += segments[bestEnd - 1].audio.durationSeconds
        }
        let tailCount = n - bestEnd
        if tailCount > 0 && tailCount < incrementalBatchMinSegments {
            bestEnd = n
        } else if bestEnd < n {
            // 嘗試擴展當前批次，但同時滿足：最小時長、剩余可成批、不超过最大時長
            for end in (bestEnd + 1)...n {
                let duration = segments[start..<end].reduce(0.0) { $0 + $1.audio.durationSeconds }
                let tail = n - end
                // 超過最大時長時停止擴展
                if duration > incrementalBatchMaxDuration {
                    break
                }
                if duration >= incrementalBatchMinDuration && (tail == 0 || tail >= incrementalBatchMinSegments) {
                    bestEnd = end
                }
            }
        }
        result.append(start..<bestEnd)
        start = bestEnd
    }
    return result
}

/// 調度二次拼接轉寫：按動態規劃分批，並行轉寫各批
@MainActor
private func scheduleBatchRefinementTranscription(language: TranscriptLanguage) {
    incrementalBatchRefinementTasks.forEach { $0.cancel() }
    incrementalBatchRefinementTasks = []
    let segments = incrementalTranscriptionResults
    let partition = partitionSegmentsForBatchRefinement(segments)
    guard !partition.isEmpty else { return }
    incrementalBatchPartition = partition
    incrementalBatchRefinedTexts = [String?](repeating: nil, count: partition.count)
    let partDesc = partition.map { "\($0.count)段" }.joined(separator: "+")
    print("📐 [fastvApp] 動態規劃分批: \(partDesc)")
    for (index, range) in partition.enumerated() {
        let batchSegments = Array(segments[range])
        let task = Task { @MainActor in
            let refined = await runBatchRefinementTranscription(segments: batchSegments, language: language)
            guard !Task.isCancelled, let r = refined else { return }
            if index < incrementalBatchRefinedTexts.count {
                incrementalBatchRefinedTexts[index] = r
                let duration = batchSegments.reduce(0.0) { $0 + $1.audio.durationSeconds }
                print("✅ [fastvApp] 批次\(index+1)/\(partition.count) 二次轉寫完成(\(range.count)段, \(String(format: "%.1f", duration))s)")
            }
        }
        incrementalBatchRefinementTasks.append(task)
    }
}

/// 將多段音頻拼接後進行二次轉寫，長音頻準確率通常更高
@MainActor
private func runBatchRefinementTranscription(segments: [IncrementalSegmentInfo], language: TranscriptLanguage) async -> String? {
    guard segments.count >= incrementalBatchMinSegments else { return nil }
    let combinedPCM = segments.map { $0.audio.pcmData }.reduce(Data(), +)
    guard !combinedPCM.isEmpty else { return nil }
    let first = segments[0].audio
    let combined = VoiceRecording(pcmData: combinedPCM, sampleRate: first.sampleRate, channelCount: first.channelCount)
    do {
        var text = try await SpeechTranscriber.transcribe(
            recording: combined,
            language: language,
            enableCTCDeduplication: nil,
            cancellationCheck: { Task.isCancelled }
        )
        if CommonMistakeManager.shared.enableAutoCorrection {
            text = TextCorrectionService.shared.correctText(text)
        }
        guard !text.isEmpty else { return nil }
        print("✅ [fastvApp] 二次拼接轉寫完成(\(segments.count)段合併): \(text.prefix(40))...")
        return text
    } catch {
        print("⚠️ [fastvApp] 二次拼接轉寫失敗: \(error)")
        return nil
    }
}

private struct ShortcutConfig: Equatable {
    var isEnabled: Bool
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
}

private var lastShortcutConfig: ShortcutConfig?

/// 应用代理，用于监听应用退出事件
class AppDelegate: NSObject, NSApplicationDelegate {
    // 保存观察者引用，用于清理
    private var windowObserver: NSObjectProtocol?
    private var userDefaultsObserver: NSObjectProtocol?
    private var settingsShortcutObserver: Any?
    private var appIsActiveObserver: NSObjectProtocol?

    // AppleScript 支持
    private var scriptingAppInstance: FastVScriptingApplication?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 一次性清除已保存的窗口状态，解决「侧边栏被持久化为折叠」导致看不到菜单的问题
        flushSavedSidebarStateIfNeeded()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 应用启动完成后，初始化状态栏
        print("📱 [AppDelegate] 应用启动完成，初始化状态栏")
        StatusBarManager.shared.show()

        // 初始化 AppleScript 支持
        setupAppleScriptSupport()

        // 设置应用不自动退出（关闭窗口时保留在后台）
        NSApplication.shared.setActivationPolicy(.regular)

        // 设置 Cmd+, 快捷键打开设置窗口
        setupSettingsShortcut()

        // 设置窗口标题为多语言的 APP 名称
        DispatchQueue.main.async {
            self.setWindowTitle()
        }

        // 延迟设置，确保 fastvApp 已初始化
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupNotificationObservers()
        }
    }

    /// 设置 Cmd+, 快捷键打开设置窗口
    private func setupSettingsShortcut() {
        // 监听按键事件
        settingsShortcutObserver = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // 检查是否是 Cmd+, (Command + ,)
            if event.modifierFlags.contains(.command) && event.characters == "," {
                self.openSettingsWindow()
                return nil // 消费事件，防止继续传递
            }
            return event
        }
        print("⌨️ [AppDelegate] Cmd+, 快捷键已设置")
    }

    /// 一次性清除已保存的窗口状态（含侧边栏折叠状态），解决 macOS 恢复「折叠」导致看不到菜单
    private func flushSavedSidebarStateIfNeeded() {
        let key = "sidebarStateFlush_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard let libURL = try? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        let bundleId = Bundle.main.bundleIdentifier ?? "fastv"
        let windowsPlist = libURL
            .appendingPathComponent("Saved Application State", isDirectory: true)
            .appendingPathComponent("\(bundleId).savedState", isDirectory: true)
            .appendingPathComponent("windows.plist", isDirectory: false)
        if FileManager.default.fileExists(atPath: windowsPlist.path) {
            try? FileManager.default.removeItem(at: windowsPlist)
            print("🧹 [AppDelegate] 已清除窗口保存状态，解决侧边栏折叠持久化问题")
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// 打开设置窗口
    @objc private func openSettingsWindow() {
        // 发送通知打开设置窗口
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    /// 初始化 AppleScript 支持
    private func setupAppleScriptSupport() {
        print("📜 [AppDelegate] 初始化 AppleScript 支持...")

        // 创建 AppleScript 应用实例
        scriptingAppInstance = FastVScriptingApplication()

        // 设置 AppleScript 事件委托
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleAppleEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )

        print("✅ [AppDelegate] AppleScript 支持已启用")
    }

    /// 处理 AppleScript 事件
    @objc private func handleAppleEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        print("📜 [AppDelegate] 收到 AppleScript 事件")

        // 这里可以处理特定的 AppleScript 事件
        // 大部分命令将通过 .sdef 定义的接口直接处理
    }

    /// 设置通知观察者（由 AppDelegate 统一管理）
    private func setupNotificationObservers() {
        // 监听应用激活/失活状态变化（用于降低后台 CPU 占用）
        appIsActiveObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let isAppActive = NSApplication.shared.isActive
            if !isAppActive {
                print("⏸️ [AppDelegate] 应用进入后台，暂停非必要活动")
                self.pauseBackgroundActivities()
            } else {
                print("▶️ [AppDelegate] 应用进入前台，恢复活动")
                self.resumeBackgroundActivities()
            }
        }

        // 监听 UserDefaults 变化
        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // 延迟一下，确保 UserPreferences 已经更新
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Task { @MainActor in
                    self.notifyShortcutConfigChange()
                }
            }
        }
    }

    /// 通知快捷键配置已变化（通过通知中心传递给 fastvApp）
    private func notifyShortcutConfigChange() {
        NotificationCenter.default.post(name: .shortcutConfigDidChange, object: nil)
    }

    /// 暂停后台活动以降低 CPU 占用
    private func pauseBackgroundActivities() {
        // 暂停内存监控（如果正在运行）
        #if DEBUG
        MemoryMonitor.shared.stopMonitoring()
        #endif

        // 隐藏波形窗口（如果正在显示）
        WaveformWindowManager.shared.cleanup()

        // 如果正在录音，可以考虑是否要停止
        // 这里我们保持录音状态，因为用户可能在后台使用语音输入
    }

    /// 恢复后台活动
    private func resumeBackgroundActivities() {
        // 恢复内存监控（仅在 Debug 模式）
        #if DEBUG
        MemoryMonitor.shared.startMonitoring()
        #endif
    }

    /// 设置窗口标题为多语言的 APP 名称
    private func setWindowTitle() {
        // 获取多语言的 APP 名称（使用本地化字符串）
        let appName = NSLocalizedString("app.name", comment: "应用名称")

        // 设置所有窗口的标题
        for window in NSApplication.shared.windows {
            window.title = appName
        }

        // 监听新窗口创建，自动设置标题（保存引用以便清理）
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let window = notification.object as? NSWindow {
                window.title = NSLocalizedString("app.name", comment: "应用名称")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("🧹 [AppDelegate] 应用即将退出，清理资源")

        // 优先释放麦克风，避免退出后状态栏仍显示橙色录音图标
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                VoiceInputService.shared.forceReleaseMicrophone()
            }
        } else {
            DispatchQueue.main.sync {
                VoiceInputService.shared.forceReleaseMicrophone()
            }
        }

        // 移除所有通知观察者
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
        if let observer = userDefaultsObserver {
            NotificationCenter.default.removeObserver(observer)
            userDefaultsObserver = nil
        }
        if let observer = appIsActiveObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appIsActiveObserver = nil
        }

        WaveformWindowManager.shared.cleanup()
        StatusBarManager.shared.cleanup()
    }

    deinit {
        // 确保观察者被清理
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = userDefaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = appIsActiveObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
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
            ZStack {
                ContentView()
                    .environmentObject(appState)
                
                // 语音模型预加载启动屏（仅当已完成引导且有模型文件时显示）
                if UserPreferences.shared.hasCompletedOnboarding {
                    SpeechModelPreloadSplashView(preloadManager: SpeechModelPreloadManager.shared)
                }
            }
            .onAppear {
                // 应用启动时预加载语音模型（若有模型文件），首次语音输入即可直接使用
                SpeechModelPreloadManager.shared.startPreloadIfNeeded()

                // 启动内存监控（仅在 Debug 模式下）
                #if DEBUG
                MemoryMonitor.shared.startMonitoring()
                #endif

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

        // 监听设置变化（由 AppDelegate 转发）
        setupShortcutConfigObserver()
    }

    /// 监听快捷键配置变化
    private func setupShortcutConfigObserver() {
        NotificationCenter.default.publisher(for: .shortcutConfigDidChange)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { _ in
                Task { @MainActor in
                    self.applyShortcutConfigIfNeeded(reason: "shortcutConfigDidChange")
                }
            }
            .store(in: &cancellables)
    }

    // Combine cancellables 用于管理订阅
    @State private var cancellables = Set<AnyCancellable>()
    
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
        
        print("🔧 [fastvApp] 開始設置全局快捷鍵")
        
        let preferences = UserPreferences.shared
        
        print("🔧 [fastvApp] 語音輸入設置:")
        print("  - 啟用: \(preferences.enableVoiceInput)")
        print("  - 主快捷鍵: keyCode=\(preferences.voiceInputShortcutKeyCode), modifiers=\(preferences.voiceInputShortcutModifiers.rawValue)")
        print("  - AI校正快捷鍵: keyCode=\(preferences.voiceInputWithAIShortcutKeyCode), modifiers=\(preferences.voiceInputWithAIShortcutModifiers.rawValue)")
        
        // 設置快捷鍵監聽回調（使用新版帶類型的回調）
        // 注意：fastvApp 是 struct，不能使用 [weak self]，但因为是值类型，不会产生循环引用
        print("🔧 [fastvApp] 設置快捷鍵回調函數")
        GlobalShortcutMonitor.shared.onShortcutPressedWithType = { shortcutType in
            print("🎯 [fastvApp] onShortcutPressed 回調被觸發（類型: \(shortcutType)）")
            // 立即开始关键操作，不等待 Task 调度
            handleShortcutPressedImmediate(shortcutType: shortcutType)
        }

        GlobalShortcutMonitor.shared.onShortcutReleasedWithType = { shortcutType in
            print("🎯 [fastvApp] onShortcutReleased 回調被觸發（類型: \(shortcutType)）")
            Task { @MainActor in
                await handleShortcutReleased(shortcutType: shortcutType)
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
            print("ℹ️ [fastvApp] 快捷鍵配置未變化（原因: \(reason)），跳過重新註冊")
            return
        }
        
        lastShortcutConfig = newConfig
        
        if newConfig.isEnabled {
            print("🔧 [fastvApp] 快捷鍵配置已更新（原因: \(reason)），重新註冊監聽")
            // 傳遞雙快捷鍵配置
            GlobalShortcutMonitor.shared.startMonitoring(
                keyCode: newConfig.keyCode,
                modifiers: newConfig.modifiers,
                secondaryKeyCode: preferences.voiceInputWithAIShortcutKeyCode,
                secondaryModifiers: preferences.voiceInputWithAIShortcutModifiers
            )
        } else {
            print("ℹ️ [fastvApp] 語音輸入已禁用（原因: \(reason)），停止快捷鍵監聽")
            GlobalShortcutMonitor.shared.stopMonitoring()
        }
    }

    /// 快捷键按下立即响应（同步路径，最小化延迟）
    /// 执行关键操作：显示波形窗口、启动录音
    private func handleShortcutPressedImmediate(shortcutType: ShortcutType = .voiceInput) {
        // 确保在主线程执行
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.handleShortcutPressedImmediate(shortcutType: shortcutType)
            }
            return
        }

        let needsAI = shortcutType == .voiceInputWithAI
        print("🎤 [fastvApp] handleShortcutPressedImmediate: 立即响应快捷鍵（類型: \(shortcutType), 需要AI: \(needsAI)）")

        // 記錄開始時間和是否需要 AI
        voiceInputStartTime = Date()
        currentVoiceInputNeedsAI = needsAI

        let preferences = UserPreferences.shared
        currentSessionUsesIncremental = preferences.enableIncrementalTranscription
        incrementalTranscriptionResults = []
        currentSessionIncrementalAudioSeconds = 0
        currentSessionIncrementalTranscriptionSeconds = 0
        incrementalBatchRefinementTasks.forEach { $0.cancel() }
        incrementalBatchRefinementTasks = []
        incrementalBatchPartition = []
        incrementalBatchRefinedTexts = []

        let voiceService = VoiceInputService.shared
        let waveformManager = WaveformWindowManager.shared

        // 关键操作1: 立即显示波形窗口
        print("📊 [fastvApp] 顯示波形窗口...")
        waveformManager.show()
        print("✅ [fastvApp] 波形窗口已显示")

        // 关键操作2: 立即开始录音（这是最关键的操作，必须同步执行）
        do {
            print("🎤 [fastvApp] 尝试开始录音...")
            try voiceService.startRecording()
            print("✅ [fastvApp] 录音已开始")

            // 连接音频数据回调
            if currentSessionUsesIncremental {
                let silenceDetector = SilenceDetector()
                silenceDetector.silenceThreshold = preferences.silenceThreshold
                silenceDetector.relativeThreshold = preferences.silenceRelativeThreshold
                silenceDetector.minimumSilenceDuration = preferences.silenceDetectionDuration
                silenceDetector.onSilenceDetected = { _ in
                    let previousTask = incrementalTranscriptionTask
                    incrementalTranscriptionTask = Task { @MainActor in
                        await previousTask?.value
                        await performIncrementalSegmentTranscription()
                    }
                }
                currentSessionSilenceDetector = silenceDetector
                voiceService.onAudioData = { level in
                    waveformManager.updateAudioLevel(level)
                    silenceDetector.processAudioLevel(level)
                }
                print("✅ [fastvApp] 智能分段已启用，停顿阈值: \(preferences.silenceDetectionDuration)秒")
            } else {
                currentSessionSilenceDetector = nil
                voiceService.onAudioData = { level in
                    waveformManager.updateAudioLevel(level)
                }
            }
            print("✅ [fastvApp] 音频数据回调已连接")
        } catch VoiceInputError.microphoneInUse {
            print("❌ [fastvApp] 麦克风被占用（可能是闪电说或其他应用）")
            waveformManager.hide()
            Task { @MainActor in
                showMicrophoneInUseAlert()
            }
        } catch VoiceInputError.microphonePermissionDenied {
            print("❌ [fastvApp] 麦克风权限被拒绝")
            waveformManager.hide()
            Task { @MainActor in
                showMicrophonePermissionAlert()
            }
        } catch {
            print("❌ [fastvApp] 开始录音失败: \(error)")
            waveformManager.hide()
        }
    }

    @MainActor
    private func handleShortcutPressed(shortcutType: ShortcutType = .voiceInput) async {
        let needsAI = shortcutType == .voiceInputWithAI
        print("🎤 [fastvApp] handleShortcutPressed: 開始處理快捷鍵按下事件（類型: \(shortcutType), 需要AI: \(needsAI)）")
        
        // 記錄開始時間和是否需要 AI
        voiceInputStartTime = Date()
        currentVoiceInputNeedsAI = needsAI
        
        let preferences = UserPreferences.shared
        currentSessionUsesIncremental = preferences.enableIncrementalTranscription
        incrementalTranscriptionResults = []
        currentSessionIncrementalAudioSeconds = 0
        currentSessionIncrementalTranscriptionSeconds = 0
        incrementalBatchRefinementTasks.forEach { $0.cancel() }
        incrementalBatchRefinementTasks = []
        incrementalBatchPartition = []
        incrementalBatchRefinedTexts = []
        
        let voiceService = VoiceInputService.shared
        let waveformManager = WaveformWindowManager.shared
        
        // 先显示波形窗口（即使录音失败也要显示）
        print("📊 [fastvApp] 顯示波形窗口...")
        waveformManager.show()
        print("✅ [fastvApp] 波形窗口已显示")
        
        // 开始录音
        do {
            print("🎤 [fastvApp] 尝试开始录音...")
            try voiceService.startRecording()
            print("✅ [fastvApp] 录音已开始")
            
            // 连接音频数据回调
            if currentSessionUsesIncremental {
                let silenceDetector = SilenceDetector()
                silenceDetector.silenceThreshold = preferences.silenceThreshold
                silenceDetector.relativeThreshold = preferences.silenceRelativeThreshold
                silenceDetector.minimumSilenceDuration = preferences.silenceDetectionDuration
                silenceDetector.onSilenceDetected = { _ in
                    let previousTask = incrementalTranscriptionTask
                    incrementalTranscriptionTask = Task { @MainActor in
                        await previousTask?.value  // 等待上一段完成，保證按時間順序插入
                        await performIncrementalSegmentTranscription()
                    }
                }
                currentSessionSilenceDetector = silenceDetector
                voiceService.onAudioData = { level in
                    waveformManager.updateAudioLevel(level)
                    silenceDetector.processAudioLevel(level)
                }
                print("✅ [fastvApp] 智能分段已启用，停顿阈值: \(preferences.silenceDetectionDuration)秒")
            } else {
                currentSessionSilenceDetector = nil
                voiceService.onAudioData = { level in
                    waveformManager.updateAudioLevel(level)
                }
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
    private func handleShortcutReleased(shortcutType: ShortcutType = .voiceInput) async {
        let needsAI = currentVoiceInputNeedsAI || shortcutType == .voiceInputWithAI
        print("🎤 [fastvApp] handleShortcutReleased: 開始處理快捷鍵釋放事件（類型: \(shortcutType), 需要AI: \(needsAI)）")
        
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
        
        // 立即切换到转文字状态（在停止录音之前），不使用延迟
        print("📊 [fastvApp] 立即切换到转文字状态...")
        waveformManager.setTranscribing()
        print("✅ [fastvApp] 已切换到转文字状态")
        
        let preferences = UserPreferences.shared
        
        // 松开后尾缓冲：继续录音一小段时间，减少末尾内容丢失（用户可能还在说最后几个字）
        let tailBuffer = max(0, min(1.0, preferences.voiceInputReleaseTailBufferSeconds))
        if tailBuffer > 0 {
            print("⏳ [fastvApp] 尾缓冲 \(String(format: "%.2f", tailBuffer)) 秒，继续录音...")
            try? await Task.sleep(nanoseconds: UInt64(tailBuffer * 1_000_000_000))
            print("✅ [fastvApp] 尾缓冲结束")
        }
        
        // 智能分段模式：先提取剩余段落（須在 stopRecording 之前，因 extract 要求 isRecording）
        var remainingSegmentResult: VoiceInputService.SegmentResult?
        if currentSessionUsesIncremental {
            // 先等待進行中的分段轉寫完成，再提取剩餘段落，保證插入順序
            await incrementalTranscriptionTask?.value
            incrementalTranscriptionTask = nil
            remainingSegmentResult = try? await voiceService.extractCurrentSegmentWithTiming()
            currentSessionSilenceDetector?.reset()
            currentSessionSilenceDetector?.onSilenceDetected = nil
            currentSessionSilenceDetector = nil
        }
        
        // 停止录音
        print("🎤 [fastvApp] 停止录音...")
        guard let recording = try? await voiceService.stopRecording() else {
            print("❌ [fastvApp] 停止录音失败或返回空录音数据")
            waveformManager.hide()
            return
        }
        print("✅ [fastvApp] 录音已停止，PCM字节数: \(recording.pcmData.count)")
        
        // 智能分段模式：合併緩存分段 + 剩餘段落，一次性輸出（支持 AI 優化整段）
        if currentSessionUsesIncremental {
            // 按動態規劃分批：若某批二次轉寫已完成則替換該批零碎結果，否則用零碎結果
            var fullText = ""
            let segments = incrementalTranscriptionResults
            if !incrementalBatchPartition.isEmpty && incrementalBatchPartition.count == incrementalBatchRefinedTexts.count {
                for (i, range) in incrementalBatchPartition.enumerated() {
                    let lo = max(0, min(range.lowerBound, segments.count))
                    let hi = max(lo, min(range.upperBound, segments.count))
                    if let batchText = incrementalBatchRefinedTexts[i], hi > lo {
                        fullText += batchText
                    } else if hi > lo {
                        fullText += segments[lo..<hi].map { $0.transcript }.joined()
                    }
                }
                let usedBatchCount = incrementalBatchRefinedTexts.compactMap { $0 }.count
                if usedBatchCount > 0 {
                    print("✅ [fastvApp] 使用二次拼接轉寫替換 \(usedBatchCount)/\(incrementalBatchPartition.count) 批零碎結果")
                }
            } else {
                fullText = segments.map { $0.transcript }.joined()
            }
            incrementalTranscriptionResults = []
            incrementalBatchRefinementTasks.forEach { $0.cancel() }
            incrementalBatchRefinementTasks = []
            incrementalBatchPartition = []
            incrementalBatchRefinedTexts = []
            
            // 轉寫剩餘段落並合併
            let minRemainingDuration = fullText.isEmpty ? VoiceInputDurationThreshold.minimumIncrementalSegment : VoiceInputDurationThreshold.minimumRemainingWhenHasCache
            if let result = remainingSegmentResult, result.duration >= minRemainingDuration {
                currentSessionIncrementalAudioSeconds += result.duration
                let transcribeStart = CFAbsoluteTimeGetCurrent()
                do {
                    var remainingText = try await SpeechTranscriber.transcribe(recording: result.recording, language: TranscriptLanguage(rawValue: preferences.voiceInputLanguage) ?? .zh, enableCTCDeduplication: nil)
                    currentSessionIncrementalTranscriptionSeconds += CFAbsoluteTimeGetCurrent() - transcribeStart
                    if CommonMistakeManager.shared.enableAutoCorrection {
                        remainingText = TextCorrectionService.shared.correctText(remainingText)
                    }
                    if !remainingText.isEmpty {
                        fullText += remainingText
                    }
                } catch {
                    print("❌ [fastvApp] 智能分段剩餘轉寫失敗: \(error)")
                }
            }
            
            guard !fullText.isEmpty else {
                waveformManager.setAICorrectionDisabled()
                currentSessionUsesIncremental = false
                currentVoiceInputNeedsAI = false
                return
            }
            
            // 與非智能分段共用後續流程：糾錯、AI 優化、插入
            var text = fullText
            let mistakeManager = CommonMistakeManager.shared
            if mistakeManager.enableAutoCorrection {
                text = TextCorrectionService.shared.correctText(text)
            }
            
            let shouldDoAI = needsAI && isAIServiceConfigured()
            if shouldDoAI {
                waveformManager.setAICorrecting()
                do {
                    text = try await OllamaService.shared.optimizeTranscript(
                        text: text,
                        scenario: .voiceInputOptimization,
                        systemPrompt: preferences.aiSystemPrompt,
                        useMistakes: true,
                        useHighFrequencyWords: true
                    )
                    waveformManager.setAICorrected()
                } catch {
                    print("⚠️ [fastvApp] AI 優化失敗，使用原始文本: \(error.localizedDescription)")
                    waveformManager.setAICorrectionFailed()
                }
            } else {
                waveformManager.setAICorrectionDisabled()
            }
            
            if preferences.useDirectTextInsertion {
                DirectTextInsertionService.shared.insertText(text)
            } else {
                TextInsertionService.shared.insertText(text)
            }
            let audioSec = currentSessionIncrementalAudioSeconds > 0 ? currentSessionIncrementalAudioSeconds : nil
            let transSec = currentSessionIncrementalTranscriptionSeconds > 0 ? currentSessionIncrementalTranscriptionSeconds : nil
            VoiceInputHistoryManager.shared.add(text: text, audioDurationSeconds: audioSec, transcriptionDurationSeconds: transSec)
            print("✅ [fastvApp] 智能分段一次性插入: \(text.prefix(50))...")
            currentSessionUsesIncremental = false
            currentVoiceInputNeedsAI = false
            return
        }
        
        // 非智能分段：整段轉寫
        // 录音过短时提示用户，避免识别不准
        let recordingDuration = recording.durationSeconds
        if recordingDuration < VoiceInputDurationThreshold.minimumRecommended {
            waveformManager.setAICorrectionDisabled()
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("voice.recording.too.short.title", comment: "")
            alert.informativeText = NSLocalizedString("voice.recording.too.short.message", comment: "")
            alert.alertStyle = .informational
            alert.addButton(withTitle: NSLocalizedString("got.it", comment: ""))
            alert.runModal()
            waveformManager.hide()
            currentVoiceInputNeedsAI = false
            return
        }

        print("🔊 [fastvApp] 开始语音转文字...")
        do {
            let languageString = preferences.voiceInputLanguage
            let language = TranscriptLanguage(rawValue: languageString) ?? .zh // 如果无效，默认使用中文
            print("🌐 [fastvApp] 使用识别语言: \(languageString) (languageID: \(language.languageID))")

            let audioDuration = recording.durationSeconds
            let transcribeStart = CFAbsoluteTimeGetCurrent()
            var text = try await SpeechTranscriber.transcribe(recording: recording, language: language, enableCTCDeduplication: nil)
            let transcriptionDuration = CFAbsoluteTimeGetCurrent() - transcribeStart
            print("✅ [fastvApp] 语音转文字成功: \(text.prefix(50))...")
            // 转录完成后主动回收 C/ObjC 层 autorelease 对象，便于释放大块 PCM 等内存
            autoreleasepool { }
            
            // 自动纠错（包含内置规则和用户自定义规则，毫秒级，非常快）
            let mistakeManager = CommonMistakeManager.shared
            if mistakeManager.enableAutoCorrection {
                let correctionStartTime = Date()
                let originalText = text
                text = TextCorrectionService.shared.correctText(text)
                if text != originalText {
                    let correctionDuration = Date().timeIntervalSince(correctionStartTime) * 1000
                    print("✅ [fastvApp] 自动纠错完成，耗时: \(String(format: "%.2f", correctionDuration))毫秒")
                    print("📝 [fastvApp] 修正前: \(originalText.prefix(50))...")
                    print("📝 [fastvApp] 修正后: \(text.prefix(50))...")
                }
            }
            
            // AI 優化（根據快捷鍵類型決定）
            // - FN：純語音輸入，不進行 AI 校正
            // - FN+Control：語音輸入 + AI 校正
            // 注意：即使用戶按了 AI 校正快捷鍵，如果 AI 服務未配置也不會進行校正
            let shouldDoAI = needsAI && isAIServiceConfigured()
            
            if needsAI && !shouldDoAI {
                print("⚠️ [fastvApp] 用戶按下了 AI 校正快捷鍵，但 AI 服務未配置，跳過 AI 校正")
            }
            
            if shouldDoAI {
                print("🤖 [fastvApp] AI 優化已觸發（通過快捷鍵），開始優化文本（超時: \(preferences.aiTimeout)秒）...")
                // 設置AI修正中狀態
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
                    print("✅ [fastvApp] AI 優化完成，耗時: \(String(format: "%.2f", aiDuration))秒")
                    print("📝 [fastvApp] 原文: \(text.prefix(50))...")
                    print("📝 [fastvApp] 優化後: \(optimizedText.prefix(50))...")
                    text = optimizedText
                    
                    // AI修正成功：設置成功狀態（會自動在1秒後隱藏窗口）
                    waveformManager.setAICorrected()
                    // AI 優化完成後回收可能產生的臨時對象
                    autoreleasepool { }
                } catch {
                    print("⚠️ [fastvApp] AI 優化失敗，使用原始文本: \(error.localizedDescription)")
                    // AI 優化失敗不影響主流程，繼續使用原始文本
                    // AI修正失敗：設置失敗狀態（會自動在0.8秒後隱藏窗口）
                    waveformManager.setAICorrectionFailed()
                }
            } else {
                if needsAI {
                    print("ℹ️ [fastvApp] AI 服務未配置，跳過 AI 優化")
                } else {
                    print("ℹ️ [fastvApp] 使用純語音輸入模式（FN鍵），不進行 AI 優化")
                }
                // AI修正未啟用：設置未啟用狀態（會自動在0.8秒後隱藏窗口）
                waveformManager.setAICorrectionDisabled()
            }
            
            // 先插入文本（优先保证用户体验）
            if !text.isEmpty {
                // 根据设置选择文本插入方式
                if preferences.useDirectTextInsertion {
                    // 使用直接键盘输入，不依赖剪贴板，避免插入错误内容
                    print("📝 [fastvApp] 直接插入文本到当前输入框（不使用剪贴板）...")
                    DirectTextInsertionService.shared.insertText(text)
                } else {
                    // 使用剪贴板 + Cmd+V 方式（旧方式，作为备选）
                    print("📝 [fastvApp] 通过剪贴板插入文本...")
                    TextInsertionService.shared.insertText(text)
                }
                VoiceInputHistoryManager.shared.add(
                    text: text,
                    audioDurationSeconds: audioDuration > 0 ? audioDuration : nil,
                    transcriptionDurationSeconds: transcriptionDuration > 0 ? transcriptionDuration : nil
                )
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
            
        } catch {
            print("❌ [fastvApp] 语音转文字失败: \(error)")
            // 转文字失败时也要隐藏窗口
            waveformManager.hide()
        }
        
        // 重置狀態
        currentVoiceInputNeedsAI = false
    }
    
    /// 檢查 AI 服務是否已配置
    @MainActor
    private func isAIServiceConfigured() -> Bool {
        let preferences = UserPreferences.shared
        
        // 檢查是否有可用的 AI 服務配置
        // 1. 檢查是否有默認 Profile
        if let defaultProfile = preferences.getDefaultProfile() {
            // 2. 檢查 endpoint 和 model 是否已設置
            let hasEndpoint = !defaultProfile.endpoint.isEmpty
            let hasModel = !defaultProfile.defaultModel.isEmpty
            
            if hasEndpoint && hasModel {
                print("✅ [fastvApp] AI 服務已配置: \(defaultProfile.name) (\(defaultProfile.defaultModel))")
                return true
            }
        }
        
        // 3. 向後兼容：檢查舊版配置
        let hasLegacyEndpoint = !preferences.aiAPIEndpoint.isEmpty
        let hasLegacyModel = !preferences.aiModel.isEmpty
        
        if hasLegacyEndpoint && hasLegacyModel {
            print("✅ [fastvApp] AI 服務已配置（舊版配置）: \(preferences.aiAPIEndpoint) (\(preferences.aiModel))")
            return true
        }
        
        print("⚠️ [fastvApp] AI 服務未配置")
        return false
    }
}

/// 应用状态管理器
class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    private init() {}
}

