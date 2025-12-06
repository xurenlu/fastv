//
//  MicroAppHostView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI
import WebKit

/// Micro-App 宿主视图（WKWebView 容器）
struct MicroAppHostView: View {
    let appId: String
    @StateObject private var manager = MicroAppManager.shared
    @State private var errorMessage: String?
    @State private var showDebugConsole = false
    @State private var debugMessages: [DebugMessage] = []
    @StateObject private var cpuMonitor = MicroAppCPUMonitor()
    
    var body: some View {
        Group {
            if let errorMessage = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("加载失败")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    MicroAppWebView(
                        appId: appId,
                        debugMessages: $debugMessages,
                        cpuMonitor: cpuMonitor,
                        onTerminate: { reason in
                            errorMessage = reason
                        }
                    )
                    
                    // 调试控制台按钮（仅在 Debug 模式下显示）
                    #if DEBUG
                    HStack {
                        Button(action: { showDebugConsole.toggle() }) {
                            Label("调试控制台", systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)
                        .padding(8)
                        
                        Spacer()
                        
                        if !debugMessages.isEmpty {
                            Text("\(debugMessages.count) 条消息")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 8)
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    #endif
                }
            }
        }
        .sheet(isPresented: $showDebugConsole) {
            DebugConsoleView(messages: $debugMessages)
        }
        .onDisappear {
            // 视图消失时停止 CPU 监控
            cpuMonitor.stopMonitoring()
        }
    }
}

/// 调试消息
struct DebugMessage: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: Level
    let message: String
    let source: String?
    
    enum Level {
        case log
        case warning
        case error
        
        var color: Color {
            switch self {
            case .log: return .primary
            case .warning: return .orange
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .log: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            }
        }
    }
}

/// WKWebView 包装器
struct MicroAppWebView: NSViewRepresentable {
    let appId: String
    @Binding var debugMessages: [DebugMessage]
    let cpuMonitor: MicroAppCPUMonitor
    let onTerminate: (String) -> Void
    @StateObject private var manager = MicroAppManager.shared
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // 🔒 进程隔离：为每个 microAPP 使用独立的进程池
        // 这样即使某个 microAPP 崩溃，也不会影响其他 microAPP 或主进程
        let processPoolManager = MicroAppProcessPoolManager.shared
        config.processPool = processPoolManager.getProcessPool(for: appId)
        context.coordinator.appId = appId
        
        // JavaScript 默认启用，无需设置
        
        // 🔒 安全策略：限制资源访问
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.javaScriptEnabled = true
        
        // 禁用媒体自动播放（减少资源消耗）
        if #available(macOS 10.12.2, *) {
            config.mediaTypesRequiringUserActionForPlayback = .all
        }
        
        // 限制网站数据存储
        // 使用非持久化存储：应用关闭后数据自动清除，提供更好的隔离
        let dataStore = WKWebsiteDataStore.nonPersistent()
        config.websiteDataStore = dataStore
        
        // 启用调试（仅在 Debug 模式下）
        #if DEBUG
        if #available(macOS 13.3, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        #endif
        
        // 设置用户代理（可选：标识这是 microAPP 环境）
        config.applicationNameForUserAgent = "MicroAPP/1.0"
        
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // 存储 bridge 引用到 context
        context.coordinator.webView = webView
        context.coordinator.debugMessages = $debugMessages
        
        // 设置导航代理以捕获错误
        webView.navigationDelegate = context.coordinator
        
        // 加载应用
        Task { @MainActor in
            do {
                let manifest = try manager.getManifest(for: appId)
                let entryURL = try manager.getEntryURL(for: appId)
                
                // 创建 Bridge
                let bridge = MicroAppBridge(webView: webView, appId: appId, manifest: manifest)
                context.coordinator.bridge = bridge
                
                // 注入控制台日志捕获脚本
                injectConsoleLogger(webView: webView, coordinator: context.coordinator)
                
                // 设置进程终止回调
                context.coordinator.onProcessTerminated = {
                    Task { @MainActor in
                        onTerminate("应用进程意外终止。这可能是由于应用代码错误导致的，但不会影响主程序或其他应用。")
                    }
                }
                
                // 启动 CPU 监控
                cpuMonitor.startMonitoring(webView: webView, appId: appId) {
                    // 当 CPU 过高需要终止时，停止加载并调用终止回调
                    Task { @MainActor in
                        webView.stopLoading()
                        // 停止所有 JavaScript 执行
                        webView.evaluateJavaScript("window.stop();", completionHandler: nil)
                        // 调用终止回调，这会更新 errorMessage 并显示错误界面
                        onTerminate("应用因 CPU 使用率过高（超过 \(Int(cpuMonitor.cpuThreshold))%）已被自动终止")
                    }
                }
                
                // 加载入口文件
                webView.loadFileURL(entryURL, allowingReadAccessTo: entryURL.deletingLastPathComponent())
            } catch {
                print("❌ [MicroAppWebView] 加载失败: \(error.localizedDescription)")
                addDebugMessage(level: .error, message: error.localizedDescription, source: "加载", to: &debugMessages)
            }
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // 更新逻辑（如果需要）
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    /// 注入控制台日志捕获脚本
    private func injectConsoleLogger(webView: WKWebView, coordinator: Coordinator) {
        let script = """
        (function() {
            const originalLog = console.log;
            const originalWarn = console.warn;
            const originalError = console.error;
            
            function sendToNative(level, args) {
                const message = Array.from(args).map(arg => {
                    if (typeof arg === 'object') {
                        try {
                            return JSON.stringify(arg, null, 2);
                        } catch (e) {
                            return String(arg);
                        }
                    }
                    return String(arg);
                }).join(' ');
                
                window.webkit.messageHandlers.consoleLog.postMessage({
                    level: level,
                    message: message,
                    timestamp: new Date().toISOString()
                });
            }
            
            console.log = function(...args) {
                originalLog.apply(console, args);
                sendToNative('log', args);
            };
            
            console.warn = function(...args) {
                originalWarn.apply(console, args);
                sendToNative('warning', args);
            };
            
            console.error = function(...args) {
                originalError.apply(console, args);
                sendToNative('error', args);
            };
            
            // 捕获未处理的错误
            window.addEventListener('error', function(event) {
                sendToNative('error', [`${event.message} at ${event.filename}:${event.lineno}:${event.colno}`]);
            });
            
            // 捕获 Promise 未处理的拒绝
            window.addEventListener('unhandledrejection', function(event) {
                sendToNative('error', [`Unhandled Promise Rejection: ${event.reason}`]);
            });
        })();
        """
        
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(userScript)
        
        // 注册消息处理器
        webView.configuration.userContentController.add(coordinator, name: "consoleLog")
    }
    
    /// 添加调试消息
    private func addDebugMessage(level: DebugMessage.Level, message: String, source: String?, to messages: inout [DebugMessage]) {
        let debugMsg = DebugMessage(
            timestamp: Date(),
            level: level,
            message: message,
            source: source
        )
        messages.append(debugMsg)
        // 限制消息数量，避免内存占用过大
        if messages.count > 1000 {
            messages.removeFirst(100)
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var bridge: MicroAppBridge?
        var debugMessages: Binding<[DebugMessage]>?
        var appId: String?
        var onProcessTerminated: (() -> Void)?
        
        // MARK: - WKNavigationDelegate
        
        /// 进程崩溃处理：当 WebContent 进程意外终止时调用
        /// 这是进程隔离的关键：进程崩溃不会影响主进程
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            let appId = self.appId ?? "unknown"
            print("💥 [MicroAppWebView] WebContent 进程崩溃: \(appId)")
            
            addDebugMessage(
                level: .error,
                message: "WebContent 进程意外终止。这可能是由于应用代码错误导致的，但不会影响主程序或其他应用。",
                source: "Process"
            )
            
            // 清理进程池
            MicroAppProcessPoolManager.shared.forceCleanupProcessPool(for: appId)
            
            // 停止 CPU 监控（如果正在运行）
            // 注意：cpuMonitor 在 MicroAppWebView 中，需要通过回调通知
            
            // 通知上层处理（这会设置 errorMessage 并显示错误界面）
            onProcessTerminated?()
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            addDebugMessage(level: .error, message: "加载失败: \(error.localizedDescription)", source: "Navigation")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            addDebugMessage(level: .error, message: "导航失败: \(error.localizedDescription)", source: "Navigation")
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let httpResponse = navigationResponse.response as? HTTPURLResponse {
                if httpResponse.statusCode >= 400 {
                    addDebugMessage(level: .error, message: "HTTP \(httpResponse.statusCode): \(navigationResponse.response.url?.absoluteString ?? "未知URL")", source: "HTTP")
                }
            }
            decisionHandler(.allow)
        }
        
        /// 导航策略：限制外部链接和危险操作
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 允许同源导航和文件加载
            if let url = navigationAction.request.url {
                // 检查是否是 file:// 协议（本地文件）
                if url.scheme == "file" {
                    decisionHandler(.allow)
                    return
                }
                
                // 检查是否是 http/https（microAPP 不应该访问外部网络）
                // 如果需要访问外部网络，应该通过 Bridge API
                if url.scheme == "http" || url.scheme == "https" {
                    addDebugMessage(
                        level: .warning,
                        message: "阻止外部网络请求: \(url.absoluteString)。microAPP 应使用 Bridge API 访问网络资源。",
                        source: "Security"
                    )
                    decisionHandler(.cancel)
                    return
                }
            }
            
            decisionHandler(.allow)
        }
        
        // MARK: - WKScriptMessageHandler
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "consoleLog",
                  let body = message.body as? [String: Any],
                  let levelStr = body["level"] as? String,
                  let messageText = body["message"] as? String else {
                return
            }
            
            let level: DebugMessage.Level
            switch levelStr {
            case "warning": level = .warning
            case "error": level = .error
            default: level = .log
            }
            
            addDebugMessage(level: level, message: messageText, source: "JS Console")
        }
        
        private func addDebugMessage(level: DebugMessage.Level, message: String, source: String) {
            guard let binding = debugMessages else { return }
            
            Task { @MainActor in
                let debugMsg = DebugMessage(
                    timestamp: Date(),
                    level: level,
                    message: message,
                    source: source
                )
                binding.wrappedValue.append(debugMsg)
                
                // 限制消息数量
                if binding.wrappedValue.count > 1000 {
                    binding.wrappedValue.removeFirst(100)
                }
            }
        }
        
        deinit {
            // 在 deinit 中异步清理（deinit 是非隔离上下文）
            let appIdToRelease = appId
            let bridgeToCleanup = bridge
            
            Task { @MainActor in
                // 清理进程池引用
                if let appId = appIdToRelease {
                    MicroAppProcessPoolManager.shared.releaseProcessPool(for: appId)
                }
                
                // 清理 bridge
                bridgeToCleanup?.cleanup()
            }
        }
    }
}

/// 调试控制台视图
struct DebugConsoleView: View {
    @Binding var messages: [DebugMessage]
    @State private var searchText = ""
    @State private var selectedLevel: DebugMessage.Level? = nil
    @Environment(\.dismiss) var dismiss
    
    var filteredMessages: [DebugMessage] {
        var filtered = messages
        
        if let selectedLevel = selectedLevel {
            filtered = filtered.filter { $0.level == selectedLevel }
        }
        
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.message.localizedCaseInsensitiveContains(searchText) }
        }
        
        return filtered
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("调试控制台")
                    .font(.headline)
                
                Spacer()
                
                // 筛选按钮
                HStack(spacing: 8) {
                    Button(action: { selectedLevel = nil }) {
                        Text("全部")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: { selectedLevel = .error }) {
                        Label("错误", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: { selectedLevel = .warning }) {
                        Label("警告", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Button("清除") {
                    messages.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(messages.isEmpty)
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索消息", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal)
            
            // 消息列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredMessages) { msg in
                        DebugMessageRow(message: msg)
                    }
                }
                .padding()
            }
        }
        .frame(width: 800, height: 600)
    }
}

/// 调试消息行
struct DebugMessageRow: View {
    let message: DebugMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: message.level.icon)
                .foregroundStyle(message.level.color)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    
                    if let source = message.source {
                        Text("[\(source)]")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(message.message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(message.level == .error ? Color.red.opacity(0.1) : (message.level == .warning ? Color.orange.opacity(0.1) : Color.clear))
        .cornerRadius(4)
    }
}

