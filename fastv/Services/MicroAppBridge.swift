//
//  MicroAppBridge.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import WebKit
import AppKit
import UniformTypeIdentifiers

/// Micro-App JS Bridge
@MainActor
class MicroAppBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    private var appId: String?
    private var manifest: MicroAppManifest?
    
    init(webView: WKWebView, appId: String, manifest: MicroAppManifest) {
        self.webView = webView
        self.appId = appId
        self.manifest = manifest
        super.init()
        setupBridge()
    }
    
    /// 清理 Bridge（应在视图销毁时调用）
    func cleanup() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "row1Bridge")
    }
    
    /// 设置 JS Bridge
    private func setupBridge() {
        guard let webView = webView else { return }
        
        let contentController = webView.configuration.userContentController
        
        // 注入 JS Bridge 代码
        let bridgeScript = """
        (function() {
            if (window.row1) return;
            
            window.row1 = {
                _callbacks: {},
                _callbackId: 0,
                
                chat: function(options) {
                    return this._call('chat', options);
                },
                
                vision: function(options) {
                    return this._call('vision', options);
                },
                
                pickImage: function() {
                    return this._call('pickImage', {});
                },
                
                showToast: function(message) {
                    return this._call('showToast', { message: message });
                },
                
                _call: function(method, params) {
                    const callbackId = this._callbackId++;
                    return new Promise((resolve, reject) => {
                        this._callbacks[callbackId] = { resolve, reject };
                        window.webkit.messageHandlers.row1Bridge.postMessage({
                            method: method,
                            params: params,
                            callbackId: callbackId
                        });
                    });
                }
            };
        })();
        """
        
        let script = WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(script)
        
        // 注册消息处理器
        contentController.add(self, name: "row1Bridge")
    }
    
    /// 处理来自 JS 的消息
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "row1Bridge",
              let body = message.body as? [String: Any],
              let method = body["method"] as? String,
              let callbackId = body["callbackId"] as? Int,
              let params = body["params"] as? [String: Any] else {
            return
        }
        
        Task {
            do {
                let result: Any
                switch method {
                case "chat":
                    result = try await handleChat(params: params)
                case "vision":
                    result = try await handleVision(params: params)
                case "pickImage":
                    result = try await handlePickImage()
                case "showToast":
                    result = try await handleShowToast(params: params)
                default:
                    throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "未知方法: \(method)"])
                }
                
                // 返回结果给 JS
                let resultString: String
                if let stringResult = result as? String {
                    resultString = stringResult
                } else if let boolResult = result as? Bool {
                    resultString = boolResult ? "true" : "false"
                } else {
                    resultString = String(describing: result)
                }
                let resultJson = escapeJSONString(resultString)
                let js = "window.row1._callbacks[\(callbackId)].resolve(\(resultJson)); delete window.row1._callbacks[\(callbackId)];"
                webView?.evaluateJavaScript(js, completionHandler: nil)
            } catch {
                // 返回错误给 JS
                let errorCode = (error as NSError).code
                let errorMessage = escapeJSONString(error.localizedDescription)
                let js = "window.row1._callbacks[\(callbackId)].reject({code: \(errorCode), message: \"\(errorMessage)\"}); delete window.row1._callbacks[\(callbackId)];"
                webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }
    
    /// 处理聊天请求
    private func handleChat(params: [String: Any]) async throws -> String {
        guard let manifest = manifest,
              manifest.hasPermission("chat") else {
            throw MicroAppError.permissionDenied("chat")
        }
        
        guard let messages = params["messages"] as? [[String: Any]] else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "缺少 messages 参数"])
        }
        
        let preferences = UserPreferences.shared
        let config = preferences.getConfig(for: .voiceInputOptimization)
        let profile = config.profile
        
        // 参数暂未使用，保留用于未来扩展
        _ = params["temperature"] as? Double ?? 0.7
        _ = params["maxTokens"] as? Int ?? 1024
        
        // 转换消息格式
        var apiMessages: [[String: Any]] = []
        for msg in messages {
            guard let role = msg["role"] as? String,
                  let content = msg["content"] as? String else {
                continue
            }
            apiMessages.append([
                "role": role,
                "content": content
            ])
        }
        
        let (content, _) = try await ChatAIService.shared.sendMessage(
            messages: apiMessages,
            profile: profile,
            model: nil,
            timeout: nil,
            preferences: preferences
        )
        
        return content
    }
    
    /// 处理视觉识别请求
    private func handleVision(params: [String: Any]) async throws -> String {
        guard let manifest = manifest,
              manifest.hasPermission("vision") else {
            throw MicroAppError.permissionDenied("vision")
        }
        
        guard let imageBase64 = params["imageBase64"] as? String,
              let prompt = params["prompt"] as? String else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "缺少 imageBase64 或 prompt 参数"])
        }
        
        // 解析 base64 图片
        let base64String = imageBase64.replacingOccurrences(of: "data:image/[^;]+;base64,", with: "", options: .regularExpression)
        guard let imageData = Data(base64Encoded: base64String),
              let image = NSImage(data: imageData) else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的图片数据"])
        }
        
        let preferences = UserPreferences.shared
        let config = preferences.getConfig(for: .voiceInputOptimization)
        let profile = config.profile
        
        // 使用 OllamaService 的图片分析功能
        let result = try await OllamaService.shared.analyzeImageLegacy(
            image: image,
            prompt: prompt,
            endpoint: profile.effectiveEndpoint,
            model: profile.defaultModel,
            apiToken: profile.apiKey.isEmpty ? nil : profile.apiKey,
            timeout: 60.0
        )
        
        return result
    }
    
    /// 处理选择图片请求
    private func handlePickImage() async throws -> String {
        guard let manifest = manifest,
              manifest.hasPermission("file") else {
            throw MicroAppError.permissionDenied("file")
        }
        
        return await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            
            panel.begin { response in
                if response == .OK, let url = panel.url,
                   let imageData = try? Data(contentsOf: url) {
                    let base64 = imageData.base64EncodedString()
                    let mimeType = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
                    continuation.resume(returning: "data:\(mimeType);base64,\(base64)")
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }
    
    /// 处理显示 Toast 请求
    private func handleShowToast(params: [String: Any]) async throws -> Bool {
        guard let message = params["message"] as? String else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "缺少 message 参数"])
        }
        
        // 在主线程显示 Toast（简化实现，使用 Alert）
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
        
        return true
    }
    
    /// 转义 JSON 字符串
    private func escapeJSONString(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
    
    deinit {
        // 注意：deinit 中不能使用 Task，因为 self 可能已经被释放
        // 在实际使用中，应该在视图销毁时手动清理
        // 这里保留空实现，避免编译错误
    }
}

