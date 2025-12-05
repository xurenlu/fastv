//
//  EmailBodyWebView.swift
//  fastv
//
//  Created by rocky on 2025/12/01.
//

import SwiftUI
import WebKit
import AppKit
import CoreGraphics

/// 使用 WKWebView 渲染邮件 HTML 内容，提供完整的 HTML/CSS 支持
struct EmailBodyWebView: View {
    let htmlBody: String
    let textBody: String?
    let showImages: Bool
    @State private var webViewHeight: CGFloat = 100
    
    init(htmlBody: String, textBody: String?, showImages: Bool = false) {
        self.htmlBody = htmlBody
        self.textBody = textBody
        self.showImages = showImages
    }
    
    var body: some View {
        Group {
            if !htmlBody.isEmpty {
                EmailBodyWebViewRepresentable(
                    htmlBody: htmlBody,
                    showImages: showImages,
                    onHeightChange: { height in
                        webViewHeight = height
                    }
                )
                .frame(height: webViewHeight)
            } else if let textBody = textBody, !textBody.isEmpty {
                // 纯文本邮件使用 SwiftUI Text
                Text(textBody)
                    .font(.system(size: 16))
                    .lineSpacing(6)
                    .foregroundStyle(Color(red: 29/255, green: 29/255, blue: 31/255))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
    }
}

// MARK: - WKWebView 实现
struct EmailBodyWebViewRepresentable: NSViewRepresentable {
    let htmlBody: String
    let showImages: Bool
    let onHeightChange: (CGFloat) -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if #available(macOS 11.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true // 需要 JS 来处理图片加载失败
        } else {
            config.preferences.javaScriptEnabled = true
        }
        
        config.userContentController.add(context.coordinator, name: "renderComplete")
        
        let webView = NonScrollingWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        
        // 启用文本选择
        webView.configuration.preferences.isTextInteractionEnabled = true
        
        // 设置透明背景，让 SwiftUI 的白色背景显示
        webView.setValue(true, forKey: "drawsTransparentBackground")
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // 生成内容标识符，避免重复加载相同内容
        let contentHash = "\(htmlBody.hashValue)_\(showImages)"
        
        // 如果内容没有变化，跳过加载
        if context.coordinator.lastContentHash == contentHash {
            return
        }
        context.coordinator.lastContentHash = contentHash
        
        context.coordinator.setRenderCompleteHandler { success, errorMessage, height, width in
            if success, let h = height {
                DispatchQueue.main.async {
                    self.onHeightChange(max(h, 100))
                }
            }
        }
        
        // 在后台线程处理 HTML 样式注入，避免阻塞主线程
        let html = htmlBody
        let showImg = showImages
        Task.detached(priority: .userInitiated) {
            let styledHTML = await MainActor.run {
                Self.injectEmailStylesStatic(into: html, showImages: showImg)
            }
            await MainActor.run {
                webView.loadHTMLString(styledHTML, baseURL: nil)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "renderComplete")
        coordinator.renderCompleteHandler = nil
        coordinator.lastContentHash = nil
    }
    
    // 静态方法用于后台线程调用
    private static func injectEmailStylesStatic(into html: String, showImages: Bool) -> String {
        // 调用实例方法的逻辑（复制一份以便静态调用）
        return EmailBodyWebViewRepresentable(htmlBody: "", showImages: false, onHeightChange: { _ in })
            .injectEmailStyles(into: html, showImages: showImages)
    }
    
    // MARK: - HTML 样式注入
    private func injectEmailStyles(into html: String, showImages: Bool) -> String {
        // 现代化的邮件样式，参考 Apple Mail 和 Gmail
        let css = """
        <style>
        /* 基础重置 - Apple 设计风格 */
        * {
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, "PingFang SC", "Helvetica Neue", Helvetica, Arial, sans-serif;
            font-size: 16px;
            line-height: 1.6;
            color: #1d1d1f;
            background-color: #ffffff;
            margin: 0;
            padding: 16px 20px !important;
            word-wrap: break-word;
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
        }
        
        /* 移除所有不必要的边框 */
        table, td, th {
            border: none !important;
            outline: none !important;
        }
        
        /* 强制覆盖邮件中的内联样式 */
        p, div, span, font, td, th, li {
            font-family: inherit !important;
            line-height: inherit !important;
            color: inherit !important;
        }
        
        /* 移除邮件布局表格的边框和内边距 */
        table[role="presentation"],
        table[cellpadding],
        table[cellspacing],
        table {
            border: none !important;
            border-collapse: collapse !important;
            border-spacing: 0 !important;
            margin: 0 !important;
        }
        
        table[role="presentation"] td,
        table[cellpadding] td,
        table[cellspacing] td,
        td {
            border: none !important;
            padding: 0 !important;
            margin: 0 !important;
        }
        
        /* 确保最外层 table 不添加额外间距 */
        body > table:first-child {
            width: 100% !important;
            margin: 0 !important;
        }
        
        body > table:first-child > tbody > tr > td:first-child {
            padding: 0 !important;
        }
        
        /* 段落优化 */
        p {
            margin-top: 0.8em !important;
            margin-bottom: 0.8em !important;
        }
        
        p:first-child {
            margin-top: 0 !important;
        }
        
        p:last-child {
            margin-bottom: 0 !important;
        }
        
        /* 移除 div 的默认 margin/padding，但保留内容区域的合理间距 */
        div {
            margin: 0 !important;
        }
        
        /* 移除邮件中常见的布局 div 的 padding */
        div[style*="padding"],
        div[style*="margin"] {
            padding: 0 !important;
            margin: 0 !important;
        }
        
        /* 标题优化 */
        h1, h2, h3, h4, h5, h6 {
            font-family: -apple-system, "PingFang SC", sans-serif;
            font-weight: 600;
            color: #000000;
            margin-top: 1.4em;
            margin-bottom: 0.6em;
            line-height: 1.3;
        }
        
        h1 {
            font-size: 24px;
            letter-spacing: -0.5px;
        }
        
        h2 {
            font-size: 20px;
            letter-spacing: -0.3px;
        }
        
        h3 {
            font-size: 18px;
        }
        
        h1:first-child, h2:first-child, h3:first-child {
            margin-top: 0;
        }
        
        /* 链接样式 */
        a {
            color: #007AFF !important;
            text-decoration: none;
        }
        
        a:hover {
            text-decoration: underline;
        }
        
        /* 列表样式 */
        ul, ol {
            margin: 12px 0;
            padding-left: 24px;
        }
        
        li {
            margin-bottom: 6px;
            padding-left: 4px;
        }
        
        /* 引用块 */
        blockquote {
            margin: 16px 0;
            padding: 12px 16px;
            border-left: 4px solid #d1d1d6;
            background-color: #f5f5f7;
            color: #636366;
            font-style: normal;
            border-radius: 0 6px 6px 0;
            word-wrap: break-word;
            overflow-wrap: break-word;
            white-space: normal;
            overflow: visible;
            text-overflow: clip;
            max-width: 100%;
            width: 100%;
        }
        
        /* 确保 blockquote 内的所有元素都能正常换行 */
        blockquote * {
            word-wrap: break-word;
            overflow-wrap: break-word;
            white-space: normal;
            overflow: visible;
            text-overflow: clip;
            max-width: 100%;
        }
        
        /* 图片优化 */
        img {
            max-width: 100% !important;
            height: auto !important;
            border-radius: 8px;
            margin: 12px 0;
            display: block;
            position: relative;
        }
        
        /* 根据 showImages 控制图片显示 */
        \(showImages ? "" : """
        img {
            display: none !important;
        }
        """)
        
        /* 图片加载失败的占位符样式 */
        img.image-error {
            background-color: #f5f5f7;
            border: 1px solid #e5e5e5;
            min-height: 100px;
            display: flex;
            align-items: center;
            justify-content: center;
            position: relative;
        }
        
        img.image-error::before {
            content: "📷";
            font-size: 32px;
            opacity: 0.3;
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
        }
        
        img.image-error::after {
            content: "图片无法加载";
            font-size: 12px;
            color: #8e8e93;
            position: absolute;
            bottom: 12px;
            left: 50%;
            transform: translateX(-50%);
            white-space: nowrap;
        }
        
        /* 代码块 */
        pre, code {
            font-family: "SF Mono", Menlo, Monaco, "Courier New", monospace;
            font-size: 14px;
        }
        
        code {
            background-color: #f5f5f7;
            color: #1d1d1f;
            padding: 2px 6px;
            border-radius: 4px;
        }
        
        pre {
            background-color: #f5f5f7;
            color: #1d1d1f;
            padding: 16px;
            border-radius: 8px;
            overflow-x: auto;
            line-height: 1.5;
            border: 1px solid #e5e5e5;
        }
        
        pre code {
            background-color: transparent;
            padding: 0;
        }
        
        /* 数据表格样式（如果有实际数据表格） */
        table:not([role="presentation"]):not([cellpadding]):not([cellspacing]) {
            border-collapse: collapse;
            width: 100%;
            margin: 16px 0;
            font-size: 14px;
        }
        
        table:not([role="presentation"]):not([cellpadding]):not([cellspacing]) th,
        table:not([role="presentation"]):not([cellpadding]):not([cellspacing]) td {
            border: 1px solid #e5e5e5;
            padding: 8px 12px;
            text-align: left;
            vertical-align: top;
        }
        
        table:not([role="presentation"]):not([cellpadding]):not([cellspacing]) th {
            background-color: #f5f5f7;
            font-weight: 600;
        }
        
        /* 分割线 */
        hr {
            border: none;
            border-top: 1px solid #e5e5e5;
            margin: 24px 0;
        }
        
        /* 按钮样式优化 */
        a[href^="mailto:"],
        a.button,
        .button,
        input[type="button"],
        input[type="submit"],
        button {
            display: inline-block;
            padding: 10px 20px;
            background-color: #007AFF;
            color: #ffffff !important;
            text-decoration: none;
            border-radius: 8px;
            font-weight: 500;
            margin: 8px 4px;
            border: none;
            cursor: pointer;
        }
        
        a.button:hover,
        .button:hover,
        input[type="button"]:hover,
        input[type="submit"]:hover,
        button:hover {
            background-color: #0051D5;
            text-decoration: none;
        }
        
        /* 响应式设计 */
        @media (max-width: 600px) {
            body {
                padding: 12px 16px !important;
                font-size: 15px;
            }
            
            h1 { font-size: 22px; }
            h2 { font-size: 19px; }
            h3 { font-size: 17px; }
        }
        
        /* 移除邮件客户端添加的额外样式 */
        .moz-text-html,
        .gmail_quote,
        .yahoo_quoted {
            display: none;
        }
        
        /* 确保文本可选中 */
        * {
            -webkit-user-select: text;
            user-select: text;
        }
        </style>
        """
        
        // 预处理 HTML
        var processedHTML = html
        
        // 移除可能干扰的 body 标签属性
        if let bodyRange = processedHTML.range(of: "<body[^>]*>", options: .regularExpression) {
            processedHTML.replaceSubrange(bodyRange, with: "<body>")
        }
        
        // 注入 CSS
        if let headRange = processedHTML.range(of: "<head>", options: .caseInsensitive) {
            processedHTML.insert(contentsOf: css, at: headRange.upperBound)
        } else if let htmlRange = processedHTML.range(of: "<html>", options: .caseInsensitive) {
            processedHTML.insert(contentsOf: "<head>\(css)</head>", at: htmlRange.upperBound)
        } else {
            // 如果没有 HTML 结构，创建一个完整的 HTML 文档
            processedHTML = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \(css)
            </head>
            <body>
            \(processedHTML)
            </body>
            </html>
            """
        }
        
        return processedHTML
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var renderCompleteHandler: ((Bool, String?, CGFloat?, CGFloat?) -> Void)?
        var lastContentHash: String?
        
        func setRenderCompleteHandler(_ handler: @escaping (Bool, String?, CGFloat?, CGFloat?) -> Void) {
            self.renderCompleteHandler = handler
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 外部链接在默认浏览器打开
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 页面加载完成后，设置图片加载失败处理并计算内容高度
            webView.evaluateJavaScript("""
                (function() {
                    // 处理图片加载失败
                    function handleImageError(img) {
                        if (!img.classList.contains('image-error')) {
                            img.classList.add('image-error');
                            img.src = 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cmVjdCB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgZmlsbD0iI2Y1ZjVmNyIvPjx0ZXh0IHg9IjUwIiB5PSI1MCIgZm9udC1zaXplPSIxNCIgZmlsbD0iIzhlOGU5MyIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZHk9Ii4zZW0iPuaXoOazleWKoOi9veWbvueJhzwvdGV4dD48L3N2Zz4=';
                            img.alt = '图片无法加载';
                        }
                    }
                    
                    // 为所有现有图片添加错误处理
                    document.querySelectorAll('img').forEach(function(img) {
                        if (img.complete && img.naturalHeight === 0) {
                            handleImageError(img);
                        } else {
                            img.addEventListener('error', function() {
                                handleImageError(this);
                            });
                        }
                    });
                    
                    // 监听新添加的图片
                    const observer = new MutationObserver(function(mutations) {
                        mutations.forEach(function(mutation) {
                            mutation.addedNodes.forEach(function(node) {
                                if (node.nodeName === 'IMG') {
                                    node.addEventListener('error', function() {
                                        handleImageError(this);
                                    });
                                } else if (node.querySelectorAll) {
                                    node.querySelectorAll('img').forEach(function(img) {
                                        img.addEventListener('error', function() {
                                            handleImageError(this);
                                        });
                                    });
                                }
                            });
                        });
                    });
                    
                    observer.observe(document.body, {
                        childList: true,
                        subtree: true
                    });
                    
                    // 计算内容高度
                    const body = document.body;
                    const html = document.documentElement;
                    const height = Math.max(
                        body.scrollHeight,
                        body.offsetHeight,
                        html.clientHeight,
                        html.scrollHeight,
                        html.offsetHeight
                    );
                    const width = Math.max(
                        body.scrollWidth,
                        body.offsetWidth,
                        html.clientWidth,
                        html.scrollWidth,
                        html.offsetWidth
                    );
                    window.webkit.messageHandlers.renderComplete.postMessage({
                        status: "success",
                        height: height,
                        width: width
                    });
                })();
            """) { result, error in
                if let error = error {
                    self.renderCompleteHandler?(false, error.localizedDescription, nil, nil)
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            renderCompleteHandler?(false, "WebView failed to load: \(error.localizedDescription)", nil, nil)
        }
        
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            renderCompleteHandler?(false, "Web content process terminated", nil, nil)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "renderComplete", let body = message.body as? [String: Any] {
                if let status = body["status"] as? String {
                    if status == "success" {
                        let height: CGFloat?
                        let width: CGFloat?
                        
                        if let h = body["height"] as? CGFloat {
                            height = h
                        } else if let h = body["height"] as? Double {
                            height = CGFloat(h)
                        } else {
                            height = nil
                        }
                        
                        if let w = body["width"] as? CGFloat {
                            width = w
                        } else if let w = body["width"] as? Double {
                            width = CGFloat(w)
                        } else {
                            width = nil
                        }
                        
                        renderCompleteHandler?(true, nil, height, width)
                    } else {
                        let errorMessage = body["message"] as? String ?? "Unknown error"
                        renderCompleteHandler?(false, errorMessage, nil, nil)
                    }
                }
            }
        }
    }
}

