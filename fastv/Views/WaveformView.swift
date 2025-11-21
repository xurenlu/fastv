//
//  WaveformView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AppKit
import Combine

/// 波形窗口状态
enum WaveformWindowState {
    case recording      // 录音中
    case transcribing   // 转文字中
}

/// 波形显示器窗口管理器
class WaveformWindowManager: ObservableObject {
    static let shared = WaveformWindowManager()
    
    private var window: NSWindow?
    private var hostingView: NSHostingView<WaveformView>?
    private var cleanupTask: DispatchWorkItem?
    
    @Published var audioLevel: Float = 0.0
    @Published var isVisible = false
    @Published var state: WaveformWindowState = .recording
    
    private init() {}
    
    /// 显示波形窗口
    func show() {
        print("📊 [WaveformWindowManager] show() 被调用")
        
        // 取消之前的清理任务
        cleanupTask?.cancel()
        cleanupTask = nil
        
        // 如果窗口已存在，先关闭它
        if let existingWindow = window {
            print("ℹ️ [WaveformWindowManager] 窗口已存在，先关闭旧窗口")
            existingWindow.contentView = nil
            existingWindow.close()
            window = nil
            hostingView = nil
        }
        
        print("📊 [WaveformWindowManager] 创建波形窗口...")
        
        // 重置状态为录音中
        state = .recording
        audioLevel = 0.0
        
        // 使用 weak self 避免循环引用
        let contentView = WaveformView(
            audioLevel: Binding(
                get: { [weak self] in self?.audioLevel ?? 0.0 },
                set: { [weak self] newValue in self?.audioLevel = newValue }
            ),
            state: Binding(
                get: { [weak self] in self?.state ?? .recording },
                set: { [weak self] newValue in self?.state = newValue }
            )
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 120, height: 40)
        
        let windowFrame = calculateWindowFrame()
        print("📊 [WaveformWindowManager] 窗口位置: x=\(windowFrame.origin.x), y=\(windowFrame.origin.y), width=\(windowFrame.width), height=\(windowFrame.height)")
        
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .statusBar  // 改为statusBar级别，比floating更高
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]  // 添加fullScreenAuxiliary
        window.ignoresMouseEvents = true
        window.hasShadow = true
        window.isReleasedWhenClosed = false  // 重要：防止窗口被自动释放
        window.hidesOnDeactivate = false  // 防止失去焦点时隐藏
        
        // 设置窗口委托，监听窗口关闭事件
        let delegate = WindowDelegate(manager: self)
        window.delegate = delegate
        
        self.window = window
        self.hostingView = hostingView
        
        print("📊 [WaveformWindowManager] 显示窗口...")
        print("📊 [WaveformWindowManager] 窗口层级: \(window.level.rawValue)")
        print("📊 [WaveformWindowManager] 窗口alpha: \(window.alphaValue)")
        
        // 立即显示窗口（同步）
        window.orderFrontRegardless()  // 强制显示在最前面
        window.makeKeyAndOrderFront(nil)
        
        // 立即检查状态
        print("📊 [WaveformWindowManager] 窗口显示后状态:")
        print("   - isVisible: \(window.isVisible)")
        print("   - isOnActiveSpace: \(window.isOnActiveSpace)")
        print("   - orderedIndex: \(window.orderedIndex)")
        print("   - screen: \(window.screen?.localizedName ?? "nil")")
        
        isVisible = true
        
        print("✅ [WaveformWindowManager] 波形窗口已显示，isVisible=\(isVisible)")
    }
    
    /// 隐藏波形窗口
    func hide() {
        print("📊 [WaveformWindowManager] hide() 被调用")
        
        // 取消之前的清理任务
        cleanupTask?.cancel()
        cleanupTask = nil
        
        guard let window = window else {
            print("ℹ️ [WaveformWindowManager] 窗口不存在，无需关闭")
            isVisible = false
            return
        }
        
        print("📊 [WaveformWindowManager] 关闭窗口...")
        
        // 先移除 contentView，避免在窗口关闭时出现问题
        window.contentView = nil
        
        // 保存窗口引用的弱引用，用于延迟清理
        let windowToClose = window
        
        // 关闭窗口（这会触发窗口的关闭动画）
        windowToClose.close()
        
        // 延迟释放窗口引用，等待窗口关闭动画完成
        // macOS 窗口关闭动画通常很快，但我们需要确保在动画完成后才释放
        // 使用 weak self 避免循环引用，并且不直接访问 window 属性
        cleanupTask = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            print("📊 [WaveformWindowManager] 延迟清理窗口引用")
            // 检查窗口是否仍然是我们之前关闭的那个
            if self.window === windowToClose {
                self.window = nil
                self.hostingView = nil
            }
            self.isVisible = false
            self.cleanupTask = nil
            print("✅ [WaveformWindowManager] 波形窗口已隐藏，isVisible=\(self.isVisible)")
        }
        
        if let task = cleanupTask {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
        }
        
        // 立即更新状态，但保留窗口引用直到动画完成
        isVisible = false
    }
    
    /// 更新音频电平
    func updateAudioLevel(_ level: Float) {
        guard state == .recording else { return }
        audioLevel = level
    }
    
    /// 切换到转文字状态
    func setTranscribing() {
        print("📊 [WaveformWindowManager] 切换到转文字状态")
        state = .transcribing
        audioLevel = 0.0
    }
    
    /// 强制清理窗口（用于应用退出时的兜底方案）
    func cleanup() {
        print("🧹 [WaveformWindowManager] cleanup() 被调用，强制清理窗口")
        
        // 取消所有延迟任务
        cleanupTask?.cancel()
        cleanupTask = nil
        
        guard let window = window else {
            print("ℹ️ [WaveformWindowManager] 窗口不存在，无需清理")
            isVisible = false
            return
        }
        
        print("🧹 [WaveformWindowManager] 强制关闭窗口...")
        
        // 立即移除 contentView，避免窗口关闭时的任何问题
        window.contentView = nil
        
        // 立即关闭窗口（不使用延迟，同步执行）
        window.close()
        
        // 立即清理引用（不使用延迟）
        self.window = nil
        self.hostingView = nil
        self.isVisible = false
        
        print("✅ [WaveformWindowManager] 窗口已强制清理")
    }
    
    /// 计算窗口位置
    private func calculateWindowFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 120, height: 40)
        }
        
        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = 120
        let windowHeight: CGFloat = 40
        let margin: CGFloat = 20
        
        // 获取用户设置的位置
        let position = UserPreferences.shared.waveformWindowPosition
        
        let x: CGFloat
        let y: CGFloat
        
        switch position {
        case .topLeft:
            x = screenFrame.minX + margin
            y = screenFrame.maxY - windowHeight - margin
        case .topRight:
            x = screenFrame.maxX - windowWidth - margin
            y = screenFrame.maxY - windowHeight - margin
        case .bottomLeft:
            x = screenFrame.minX + margin
            y = screenFrame.minY + margin
        case .bottomRight:
            x = screenFrame.maxX - windowWidth - margin
            y = screenFrame.minY + margin
        case .bottomCenter:
            x = screenFrame.midX - windowWidth / 2
            y = screenFrame.minY + margin
        }
        
        return NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
    }
}

/// 窗口委托，用于监听窗口关闭事件
class WindowDelegate: NSObject, NSWindowDelegate {
    weak var manager: WaveformWindowManager?
    
    init(manager: WaveformWindowManager) {
        self.manager = manager
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        print("📊 [WindowDelegate] 窗口即将关闭")
    }
    
    func windowDidClose(_ notification: Notification) {
        print("📊 [WindowDelegate] 窗口已关闭")
    }
}

/// 波形视图
struct WaveformView: View {
    @Binding var audioLevel: Float
    @Binding var state: WaveformWindowState
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var bars: [CGFloat] = [0.3, 0.5, 0.7, 0.5, 0.3]
    
    var body: some View {
        ZStack {
            // 更明显的背景，确保可见
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            
            // 根据状态显示不同内容
            switch state {
            case .recording:
                // 录音中：显示简单的音量动画
                HStack(spacing: 4) {
                    // 简单的音量条动画
                    ForEach(0..<bars.count, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.accentColor.opacity(0.8))
                            .frame(width: 4, height: bars[index] * 20)
                            .animation(
                                .easeInOut(duration: 0.3)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.1),
                                value: bars[index]
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .onAppear {
                    animateBars()
                }
                .onChange(of: audioLevel) { newLevel in
                    updateBars(with: newLevel)
                }
                
            case .transcribing:
                VStack(spacing: 6) {
                    Circle()
                        .trim(from: 0.0, to: 0.85)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [Color.accentColor, Color.accentColor.opacity(0.2)]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(rotationAngle))
                        .onAppear {
                            startTranscribingAnimation()
                        }
                        .onChange(of: state) { newState in
                            if newState == .transcribing {
                                startTranscribingAnimation()
                            }
                        }
                    
                    Text("转文字中…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 120, height: 40)
    }
    
    private func animateBars() {
        // 创建持续的动画效果
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            for i in 0..<bars.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                    withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                        bars[i] = Double.random(in: 0.3...1.0)
                    }
                }
            }
        }
    }
    
    private func updateBars(with level: Float) {
        // 根据实际音频电平更新音量条
        let normalizedLevel = min(max(level, 0.0), 1.0)
        
        // 更新中间的音量条（更明显）
        if bars.count >= 3 {
            bars[2] = CGFloat(normalizedLevel * 0.7 + 0.3) // 0.3 到 1.0
            bars[1] = CGFloat(normalizedLevel * 0.5 + 0.3) // 0.3 到 0.8
            bars[3] = CGFloat(normalizedLevel * 0.5 + 0.3) // 0.3 到 0.8
        }
        
        // 边缘的音量条稍微小一点
        if bars.count >= 5 {
            bars[0] = CGFloat(normalizedLevel * 0.4 + 0.2) // 0.2 到 0.6
            bars[4] = CGFloat(normalizedLevel * 0.4 + 0.2) // 0.2 到 0.6
        }
    }
    
    private func startTranscribingAnimation() {
        rotationAngle = 0
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }
}

