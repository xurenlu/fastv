//
//  LatexView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import WebKit

// MARK: - LaTeX Rendering Components

struct LatexBlockView: View {
    let latexCode: String
    let isTransparentBackground: Bool
    
    @State private var isLoading = true
    @State private var renderError: String?
    @State private var webViewHeight: CGFloat = 300
    @State private var lastRenderedCode: String = ""
    @State private var isSuccessfullyRendered = false
    
    private var viewBackground: Color {
        isTransparentBackground ? Color.black.opacity(0.1) : Color(NSColor.textBackgroundColor)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let error = renderError {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("LaTeX 渲染失败")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                        
                        Text(error)
                            .font(.caption)
                            .foregroundColor(isTransparentBackground ? .white.opacity(0.7) : Color.primary.opacity(0.7))
                        
                        Text("原始代码")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(isTransparentBackground ? .white.opacity(0.8) : Color.primary.opacity(0.8))
                        
                        Text(latexCode)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(isTransparentBackground ? .white : Color.primary)
                            .padding()
                            .background(viewBackground)
                            .cornerRadius(6)
                    }
                    .padding()
                } else {
                    LatexWebView(
                        latexCode: latexCode,
                        isTransparentBackground: isTransparentBackground,
                        isInline: false,
                        onRenderComplete: { success, errorMessage, height, width in
                            DispatchQueue.main.async {
                                isLoading = false
                                if success, let h = height {
                                    webViewHeight = max(h, 120)
                                    renderError = nil
                                    isSuccessfullyRendered = true
                                } else {
                                    renderError = errorMessage ?? "Unknown rendering error"
                                    isSuccessfullyRendered = false
                                }
                            }
                        }
                    )
                    .frame(height: webViewHeight)
                    .background(viewBackground)
                    .cornerRadius(8)
                    
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("正在渲染 LaTeX...")
                                .font(.caption)
                                .foregroundColor(isTransparentBackground ? .white.opacity(0.7) : Color.primary.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(viewBackground.opacity(0.8))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(viewBackground)
        .cornerRadius(12)
        .onAppear {
            if latexCode == lastRenderedCode && isSuccessfullyRendered {
                isLoading = false
                return
            }
            
            if latexCode != lastRenderedCode {
                lastRenderedCode = latexCode
                isSuccessfullyRendered = false
                isLoading = true
                renderError = nil
            }
        }
    }
}

// LaTeX WebView Component
struct LatexWebView: NSViewRepresentable {
    let latexCode: String
    let isTransparentBackground: Bool
    let isInline: Bool
    let onRenderComplete: (Bool, String?, CGFloat?, CGFloat?) -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if #available(macOS 11.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
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
        
        if isTransparentBackground {
            webView.setValue(true, forKey: "drawsTransparentBackground")
        }
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.setRenderCompleteHandler(onRenderComplete)
        let htmlContent = generateLatexHTML(latexCode: latexCode, isTransparent: isTransparentBackground)
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "renderComplete")
        coordinator.renderCompleteHandler = nil
    }
    
    private func generateLatexHTML(latexCode: String, isTransparent: Bool) -> String {
        let backgroundColor: String = isTransparent ? "transparent" : "#ffffff"
        let textColor: String = isTransparent ? "#ffffff" : "#000000"
        
        let preparedCode = isInline ? "$\(latexCode)$" : "$$\n\(latexCode)\n$$"

        let katexCSS = CDNManager.shared.getKaTeXCSS()
        let katexJS = CDNManager.shared.getKaTeXJS()
        let katexAutoRender = CDNManager.shared.getKaTeXAutoRender()
        
        let katexCssList = katexCSS.cdnURL != nil ? CDNManager.shared.getAllKaTeXCSSCDNs().map { "\"\($0)\"" }.joined(separator: ",") : ""
        let katexJsList = katexJS.cdnURL != nil ? CDNManager.shared.getAllKaTeXJSCDNs().map { "\"\($0)\"" }.joined(separator: ",") : ""
        let katexAutoList = katexAutoRender.cdnURL != nil ? CDNManager.shared.getAllKaTeXAutoRenderCDNs().map { "\"\($0)\"" }.joined(separator: ",") : ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            \(katexCSS.content != nil ? "<style>\(katexCSS.content!)</style>" : "")
            \(katexJS.content != nil ? "<script>\(katexJS.content!)</script>" : "")
            \(katexAutoRender.content != nil ? "<script>\(katexAutoRender.content!)</script>" : "")
            \(katexCSS.content == nil || katexJS.content == nil || katexAutoRender.content == nil ? """
            <script>
                (function() {
                    const cssList = [\(katexCssList)];
                    const jsList = [\(katexJsList)];
                    const autoList = [\(katexAutoList)];
                    function loadCSSSequentially(index) {
                        if (index >= cssList.length) { return Promise.resolve(); }
                        return new Promise((resolve) => {
                            const link = document.createElement('link');
                            link.rel = 'stylesheet';
                            link.href = cssList[index];
                            link.onload = () => resolve();
                            link.onerror = () => resolve(loadCSSSequentially(index + 1));
                            document.head.appendChild(link);
                        });
                    }
                    function loadJSSequentially(list, index) {
                        if (index >= list.length) { return Promise.reject(new Error('All JS sources failed')); }
                        return new Promise((resolve) => {
                            const s = document.createElement('script');
                            s.src = list[index];
                            s.onload = () => resolve();
                            s.onerror = () => loadJSSequentially(list, index + 1).then(resolve);
                            document.head.appendChild(s);
                        });
                    }
                    window.__loadKatexPromise = \(katexCSS.content != nil ? "Promise.resolve()" : "loadCSSSequentially(0)")
                        \(katexJS.content == nil ? ".then(() => loadJSSequentially(jsList, 0))" : "")
                        \(katexAutoRender.content == nil ? ".then(() => loadJSSequentially(autoList, 0))" : "")
                        .catch(() => {});
                })();
            </script>
            """ : "")
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    background-color: \(backgroundColor);
                    color: \(textColor);
                    font-size: \(isInline ? "1.1em" : "1.2em");
                    line-height: 1.4;
                    overflow: hidden;
                    -webkit-user-select: text;
                    user-select: text;
                }
                #content {
                    text-align: left;
                    white-space: normal;
                    -webkit-user-select: text;
                    user-select: text;
                }
                .katex-display {
                    text-align: center;
                    margin: 1em 0;
                    display: block;
                }
                .katex {
                    font-size: \(isInline ? "1.1em" : "1.2em");
                    line-height: 1.4;
                    display: inline-block;
                }
                .katex-html {
                    display: inline-block;
                }
            </style>
        </head>
        <body>
            <div id="content">\(preparedCode)</div>
            <script>
                document.addEventListener("DOMContentLoaded", async function() {
                    try {
                        if (window.__loadKatexPromise) { await window.__loadKatexPromise; }
                        if (typeof renderMathInElement !== 'function') {
                            throw new Error('renderMathInElement 未加载');
                        }
                        renderMathInElement(document.getElementById("content"), {
                            delimiters: [
                                {left: "$$", right: "$$", display: true},
                                {left: "$", right: "$", display: false}
                            ],
                            throwOnError: true
                        });
                        
                        setTimeout(() => {
                            const content = document.getElementById("content");
                            const katexElement = content.querySelector('.katex');
                            
                            if (katexElement) {
                                const katexWidth = katexElement.offsetWidth;
                                const katexHeight = katexElement.offsetHeight;
                                const isInline = document.body.style.padding.includes('0px');
                                const paddedWidth = isInline ? katexWidth : katexWidth + 10;
                                const extraHeight = isInline ? 4 : 0;
                                const finalHeight = katexHeight + extraHeight;
                                
                                const message = { 
                                    status: "success", 
                                    height: finalHeight,
                                    width: paddedWidth
                                };
                                window.webkit.messageHandlers.renderComplete.postMessage(message);
                            } else {
                                const height = document.body.scrollHeight;
                                const message = { status: "success", height: height };
                                window.webkit.messageHandlers.renderComplete.postMessage(message);
                            }
                        }, 200);

                    } catch (error) {
                        const message = { status: "error", message: error.toString() };
                        window.webkit.messageHandlers.renderComplete.postMessage(message);
                    }
                });
            </script>
        </body>
        </html>
        """
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var renderCompleteHandler: ((Bool, String?, CGFloat?, CGFloat?) -> Void)?

        func setRenderCompleteHandler(_ handler: @escaping (Bool, String?, CGFloat?, CGFloat?) -> Void) {
            self.renderCompleteHandler = handler
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
                        let height = body["height"] as? CGFloat
                        let width = body["width"] as? CGFloat
                        renderCompleteHandler?(true, nil, height, width)
                    } else {
                        let errorMessage = body["message"] as? String ?? "Unknown JavaScript error"
                        renderCompleteHandler?(false, errorMessage, nil, nil)
                    }
                }
            }
        }
    }
}

