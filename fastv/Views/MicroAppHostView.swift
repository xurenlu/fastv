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
                MicroAppWebView(appId: appId)
            }
        }
    }
}

/// WKWebView 包装器
struct MicroAppWebView: NSViewRepresentable {
    let appId: String
    @StateObject private var manager = MicroAppManager.shared
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // JavaScript 默认启用，无需设置
        
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // 存储 bridge 引用到 context
        context.coordinator.webView = webView
        
        // 加载应用
        Task { @MainActor in
            do {
                let manifest = try manager.getManifest(for: appId)
                let entryURL = try manager.getEntryURL(for: appId)
                
                // 创建 Bridge
                let bridge = MicroAppBridge(webView: webView, appId: appId, manifest: manifest)
                context.coordinator.bridge = bridge
                
                // 加载入口文件
                webView.loadFileURL(entryURL, allowingReadAccessTo: entryURL.deletingLastPathComponent())
            } catch {
                print("❌ [MicroAppWebView] 加载失败: \(error.localizedDescription)")
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
    
    class Coordinator {
        var webView: WKWebView?
        var bridge: MicroAppBridge?
        
        deinit {
            // 在 deinit 中异步清理
            if let bridge = bridge {
                Task { @MainActor in
                    bridge.cleanup()
                }
            }
        }
    }
}

