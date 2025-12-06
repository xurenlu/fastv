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
                
                showToast: function(message) {
                    return this._call('showToast', { message: message });
                },
                
                uploadFile: function(file) {
                    return new Promise((resolve, reject) => {
                        const reader = new FileReader();
                        reader.onload = function(e) {
                            const base64 = e.target.result.split(',')[1]; // 移除 data:image/png;base64, 前缀
                            const fileName = file.name || 'file';
                            const fileType = file.type || 'application/octet-stream';
                            this._call('uploadFile', {
                                data: base64,
                                fileName: fileName,
                                fileType: fileType
                            }).then(resolve).catch(reject);
                        }.bind(this);
                        reader.onerror = reject;
                        reader.readAsDataURL(file);
                    });
                },
                
                downloadFile: function(data, fileName, fileType) {
                    return this._call('downloadFile', {
                        data: data,
                        fileName: fileName || 'file',
                        fileType: fileType || 'application/octet-stream'
                    });
                },
                
                selectFolder: function() {
                    return this._call('selectFolder', {});
                },
                
                saveFileToFolder: function(data, fileName, folderPath, fileType) {
                    return this._call('saveFileToFolder', {
                        data: data,
                        fileName: fileName || 'file',
                        folderPath: folderPath,
                        fileType: fileType || 'application/octet-stream'
                    });
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
                case "showToast":
                    result = try await handleShowToast(params: params)
                case "uploadFile":
                    result = try await handleUploadFile(params: params)
                case "downloadFile":
                    result = try await handleDownloadFile(params: params)
                case "selectFolder":
                    result = try await handleSelectFolder(params: params)
                case "saveFileToFolder":
                    result = try await handleSaveFileToFolder(params: params)
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
    /// 注意：应用需要先自行上传图片到云存储，然后提供图片 URL
    private func handleVision(params: [String: Any]) async throws -> String {
        guard let manifest = manifest,
              manifest.hasPermission("vision") else {
            throw MicroAppError.permissionDenied("vision")
        }
        
        guard let imageUrl = params["imageUrl"] as? String,
              let prompt = params["prompt"] as? String else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "缺少 imageUrl 或 prompt 参数。请先上传图片并获取 URL"])
        }
        
        // 验证 URL 格式
        guard URL(string: imageUrl) != nil else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的图片 URL"])
        }
        
        let preferences = UserPreferences.shared
        let config = preferences.getConfig(for: .voiceInputOptimization)
        let profile = config.profile
        
        // 检查是否是 DashScope 兼容模式
        let endpoint = profile.effectiveEndpoint.lowercased()
        let usesDashScopeCompatibleMode = endpoint.contains("compatible-mode") || endpoint.contains("/chat/completions")
        
        // 构建消息内容数组
        var contentArray: [[String: Any]] = []
        
        if profile.protocolType == .dashScope && usesDashScopeCompatibleMode {
            // DashScope 兼容模式：使用 OpenAI 格式（需要 type 字段）
            contentArray.append([
                "type": "image_url",
                "image_url": [
                    "url": imageUrl
                ]
            ])
            contentArray.append([
                "type": "text",
                "text": prompt
            ])
        } else if profile.protocolType == .dashScope {
            // DashScope 原生模式：使用原生格式
            contentArray.append(["image": imageUrl])
            contentArray.append(["text": prompt])
        } else if profile.protocolType == .openAI || profile.protocolType == .azureOpenAI {
            // OpenAI/Azure OpenAI：使用 OpenAI 格式
            contentArray.append([
                "type": "image_url",
                "image_url": [
                    "url": imageUrl
                ]
            ])
            contentArray.append([
                "type": "text",
                "text": prompt
            ])
        } else {
            // Ollama 等其他协议：需要下载图片后转换为 base64
            // 这里暂时不支持，建议使用 DashScope/OpenAI
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "当前协议不支持 URL 格式的图片，请使用 DashScope 或 OpenAI 协议"])
        }
        
        // 构建消息
        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": contentArray
            ]
        ]
        
        // 使用 ChatAIService 发送请求
        let (content, _) = try await ChatAIService.shared.sendMessage(
            messages: messages,
            profile: profile,
            model: nil,
            timeout: 60.0,
            preferences: UserPreferences.shared
        )
        
        return content
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
    
    /// 处理文件上传请求
    private func handleUploadFile(params: [String: Any]) async throws -> String {
        guard let base64Data = params["data"] as? String,
              let fileName = params["fileName"] as? String else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "缺少 data 或 fileName 参数"])
        }
        
        let fileType = params["fileType"] as? String ?? "application/octet-stream"
        
        // 解码 base64 数据
        guard let data = Data(base64Encoded: base64Data) else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 base64 数据"])
        }
        
        // 生成文件路径
        let prefix = String((0..<5).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".randomElement()! })
        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let timestamp = Int(now.timeIntervalSince1970)
        let ext = (fileName as NSString).pathExtension.isEmpty ? "png" : (fileName as NSString).pathExtension
        let targetPath = "upload/\(String(format: "%04d%02d", year, month))/\(timestamp)-\(prefix).\(ext)"
        
        // Cloudflare Worker 上传配置
        let uploadURL = "https://cfworker.xurenlu9959.workers.dev/\(targetPath)"
        let authKey = "baby9527"
        
        // 创建上传请求
        var request = URLRequest(url: URL(string: uploadURL)!)
        request.httpMethod = "PUT"
        request.setValue(authKey, forHTTPHeaderField: "X-Custom-Auth-Key")
        request.setValue(fileType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        // 执行上传
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "上传失败，HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"])
        }
        
        // 返回 CDN URL
        let imageUrl = "https://cdn.facev.app/\(targetPath)"
        return imageUrl
    }
    
    /// 处理文件下载请求（保存到本地）
    private func handleDownloadFile(params: [String: Any]) async throws -> Bool {
        guard let base64Data = params["data"] as? String,
              let fileName = params["fileName"] as? String else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "缺少 data 或 fileName 参数"])
        }
        
        let fileType = params["fileType"] as? String ?? "application/octet-stream"
        
        // 解码 base64 数据
        guard let data = Data(base64Encoded: base64Data) else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 base64 数据"])
        }
        
        // 在主线程显示保存对话框
        return await MainActor.run {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType(filenameExtension: (fileName as NSString).pathExtension) ?? .png]
            savePanel.nameFieldStringValue = fileName
            savePanel.canCreateDirectories = true
            
            let response = savePanel.runModal()
            
            if response == .OK, let url = savePanel.url {
                do {
                    try data.write(to: url)
                    return true
                } catch {
                    print("❌ [MicroAppBridge] 保存文件失败: \(error.localizedDescription)")
                    return false
                }
            }
            
            return false
        }
    }
    
    /// 处理选择文件夹请求
    private func handleSelectFolder(params: [String: Any]) async throws -> String {
        return await MainActor.run {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = false
            openPanel.canChooseDirectories = true
            openPanel.allowsMultipleSelection = false
            openPanel.canCreateDirectories = true
            openPanel.message = "选择保存文件夹"
            
            let response = openPanel.runModal()
            
            if response == .OK, let url = openPanel.url {
                return url.path
            }
            
            return ""
        }
    }
    
    /// 处理保存文件到指定文件夹请求
    private func handleSaveFileToFolder(params: [String: Any]) async throws -> Bool {
        guard let base64Data = params["data"] as? String,
              let fileName = params["fileName"] as? String,
              let folderPath = params["folderPath"] as? String else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "缺少 data、fileName 或 folderPath 参数"])
        }
        
        // 解码 base64 数据
        guard let data = Data(base64Encoded: base64Data) else {
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 base64 数据"])
        }
        
        // 构建文件路径
        let folderURL = URL(fileURLWithPath: folderPath)
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            return true
        } catch {
            print("❌ [MicroAppBridge] 保存文件失败: \(error.localizedDescription)")
            throw NSError(domain: "MicroAppBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "保存文件失败: \(error.localizedDescription)"])
        }
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

