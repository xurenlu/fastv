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
    case recording           // 录音中
    case transcribing       // 转文字中
    case aiCorrecting       // AI修正中
    case aiCorrected        // AI修正成功
    case aiCorrectionFailed // AI修正失败
    case aiCorrectionDisabled // AI修正未启用
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
        
        let contentView = WaveformView(manager: self)
        let hostingView = NSHostingView(rootView: contentView)
        
        // 根据用户设置的样式调整窗口大小
        let windowSize = UserPreferences.shared.waveformWindowStyle.size
        hostingView.frame = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        
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
        window.hasShadow = false  // 去掉窗口阴影，避免黑框效果
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
        // 立即切换状态，不使用动画延迟，确保用户感觉不到停顿
        state = .transcribing
        audioLevel = 0.0
    }
    
    /// 设置AI修正状态
    func setAICorrecting() {
        print("📊 [WaveformWindowManager] 设置AI修正中状态")
        state = .aiCorrecting
        audioLevel = 0.0
    }
    
    /// 设置AI修正成功状态（会自动在1秒后隐藏）
    func setAICorrected() {
        print("📊 [WaveformWindowManager] 设置AI修正成功状态")
        state = .aiCorrected
        audioLevel = 0.0
        
        // 1秒后自动隐藏窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.hide()
        }
    }
    
    /// 设置AI修正失败状态（会自动在0.8秒后隐藏）
    func setAICorrectionFailed() {
        print("📊 [WaveformWindowManager] 设置AI修正失败状态")
        state = .aiCorrectionFailed
        audioLevel = 0.0
        
        // 0.8秒后自动隐藏窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.hide()
        }
    }
    
    /// 设置AI修正未启用状态（会自动在0.8秒后隐藏）
    func setAICorrectionDisabled() {
        print("📊 [WaveformWindowManager] 设置AI修正未启用状态")
        state = .aiCorrectionDisabled
        audioLevel = 0.0
        
        // 0.8秒后自动隐藏窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.hide()
        }
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
            let size = UserPreferences.shared.waveformWindowStyle.size
            return NSRect(x: 0, y: 0, width: size.width, height: size.height)
        }
        
        let screenFrame = screen.visibleFrame
        let windowSize = UserPreferences.shared.waveformWindowStyle.size
        let windowWidth: CGFloat = windowSize.width
        let windowHeight: CGFloat = windowSize.height
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
    
    @objc(windowDidClose:)
    func windowDidClose(_ notification: Notification) {
        print("📊 [WindowDelegate] 窗口已关闭")
    }
}

/// 波形视图
struct WaveformView: View {
    @ObservedObject var manager: WaveformWindowManager
    @State private var rotationAngle: Double = 0
    @State private var bars: [CGFloat] = [0.3, 0.5, 0.7, 0.5, 0.3]
    @State private var containerScale: CGFloat = 1.0
    @State private var containerOpacity: Double = 1.0
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let style = UserPreferences.shared.waveformWindowStyle
        let colorStyle = UserPreferences.shared.waveformWindowColorStyle
        let size = style.size
        let colorConfig = colorStyle.colorConfig(for: colorScheme)
        let barColor = colorConfig.barColor
        let state = manager.state
        
        ZStack {
            // 背景 - 根据配置使用毛玻璃效果或纯色
            if colorConfig.useMaterial {
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background {
                        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                            .fill(colorConfig.backgroundColor.opacity(colorConfig.backgroundOpacity))
                    }
            } else {
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(colorConfig.backgroundColor.opacity(colorConfig.backgroundOpacity))
            }
            
            // 根据状态显示不同内容 - 使用动画过渡
            Group {
                switch state {
                case .recording:
                    // 录音中：显示音量波形动画 - 更协调的波形
                    HStack(spacing: style.barSpacing) {
                        ForEach(0..<bars.count, id: \.self) { index in
                            RoundedRectangle(cornerRadius: style.barWidth / 2, style: .continuous)
                                .fill(
                                    // 更丰富的渐变层次
                                    LinearGradient(
                                        colors: [
                                            barColor.opacity(0.9),
                                            barColor.opacity(0.7),
                                            barColor.opacity(0.5)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: style.barWidth, height: bars[index] * style.maxBarHeight)
                                // 添加微妙的发光效果
                                .shadow(color: barColor.opacity(0.3), radius: 2, x: 0, y: 0)
                        }
                    }
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
                    .onAppear {
                        animateBars()
                    }
                    .onChange(of: manager.audioLevel) { _, newLevel in
                        updateBars(with: newLevel)
                    }
                    // 更自然的过渡效果
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9),
                        removal: .scale(scale: 1.05).combined(with: .opacity)
                    ))
                    
                case .transcribing, .aiCorrecting:
                    // 转文字中或AI修正中：显示旋转加载动画 - 更流畅的动画
                    VStack(spacing: 6) {
                        ZStack {
                            // 背景圆环 - 更细腻
                            Circle()
                                .stroke(barColor.opacity(0.25), lineWidth: 2.5)
                                .frame(width: style.spinnerSize, height: style.spinnerSize)
                            
                            // 旋转的渐变圆环 - 更丰富的渐变
                            Circle()
                                .trim(from: 0.0, to: 0.75)
                                .stroke(
                                    AngularGradient(
                                        gradient: Gradient(colors: [
                                            barColor.opacity(1.0),
                                            barColor.opacity(0.85),
                                            barColor.opacity(0.6),
                                            barColor.opacity(0.35),
                                            barColor.opacity(0.15)
                                        ]),
                                        center: .center,
                                        startAngle: .degrees(0),
                                        endAngle: .degrees(360)
                                    ),
                                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
                                )
                                .frame(width: style.spinnerSize, height: style.spinnerSize)
                                .rotationEffect(.degrees(rotationAngle))
                                // 添加微妙的发光效果
                                .shadow(color: barColor.opacity(0.45), radius: 4, x: 0, y: 0)
                            
                            // 额外的高光层，增强存在感
                            Circle()
                                .trim(from: 0.0, to: 0.35)
                                .stroke(barColor.opacity(0.5), lineWidth: 1.2)
                                .frame(width: style.spinnerSize + 4, height: style.spinnerSize + 4)
                                .blur(radius: 1.5)
                                .opacity(0.8)
                        }
                        .onAppear {
                            // 立即启动转圈动画，不等待
                            startTranscribingAnimation()
                        }
                        .onChange(of: state) { _, newState in
                            // 当状态切换到转文字或AI修正时，立即启动动画
                            if newState == .transcribing || newState == .aiCorrecting {
                                startTranscribingAnimation()
                            }
                        }
                    }
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
                    // 更自然的过渡效果
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.05),
                        removal: .scale(scale: 0.85).combined(with: .opacity)
                    ))
                    
                case .aiCorrected:
                    // AI修正成功：显示成功图标和提示
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.green)
                        
                        if style != .compact {
                            Text("AI已优化")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .scale(scale: 1.1).combined(with: .opacity)
                    ))
                    
                case .aiCorrectionFailed:
                    // AI修正失败：显示失败图标
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.orange)
                        
                        if style != .compact {
                            Text("AI优化失败")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .scale(scale: 1.1).combined(with: .opacity)
                    ))
                    
                case .aiCorrectionDisabled:
                    // AI修正未启用：显示禁用图标
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles.slash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                        if style != .compact {
                            Text("AI未启用")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .scale(scale: 1.1).combined(with: .opacity)
                    ))
                }
            }
            // 不使用动画延迟，确保状态切换立即生效
            .id(state) // 强制在状态改变时重新创建视图，确保动画立即切换
        }
        .frame(width: size.width, height: size.height)
        // 容器本身的缩放动画 - 增加微交互
        .scaleEffect(containerScale)
        .opacity(containerOpacity)
        .onAppear {
            // 出现时的弹性动画
            containerScale = 0.8
            containerOpacity = 0
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                containerScale = 1.0
                containerOpacity = 1.0
            }
        }
    }
    
    private func animateBars() {
        // 更协调的波形动画 - 中间高两边低的自然形态
        let baseHeights: [CGFloat] = [0.35, 0.55, 0.75, 0.55, 0.35]
        
        for i in 0..<bars.count {
            let delay = Double(i) * 0.08 // 轻微的延迟创造波浪效果
            let duration = 0.4 + Double(i) * 0.05 // 不同的持续时间增加变化
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // 使用缓入缓出动画，更自然
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                ) {
                    // 在基础高度上下波动，而不是完全随机
                    let variation: CGFloat = 0.15
                    bars[i] = baseHeights[i] + CGFloat.random(in: -variation...variation)
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
        // 立即重置角度并启动动画，不等待
        rotationAngle = 0
        
        // 使用线性动画确保连续旋转，立即开始
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                self.rotationAngle = 360
            }
        }
    }
}

