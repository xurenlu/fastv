//
//  RichTextView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import WebKit
import AppKit

struct RichTextView: View {
    let text: String
    let isTransparentBackground: Bool

    var body: some View {
        let segments = parseInlineFormats(text)
        
        let hasOnlySimpleFormats = segments.allSatisfy { segment in
            switch segment.type {
            case .bold, .italic, .code, .link:
                return true
            case .inlineLatex:
                return false
            }
        }
        
        if segments.isEmpty || hasOnlySimpleFormats {
            RichTextSwiftUIView(
                text: text,
                segments: segments,
                isTransparentBackground: isTransparentBackground
            )
        } else {
            RichTextWebView(
                text: text,
                segments: segments,
                isTransparentBackground: isTransparentBackground
            )
        }
    }
}

// 使用SwiftUI处理简单内联格式
struct RichTextSwiftUIView: View {
    let text: String
    let segments: [InlineFormatSegment]
    let isTransparentBackground: Bool
    
    var body: some View {
        let components = buildTextComponents(from: text, with: segments)
        
        Text(buildAttributedString(from: components))
            .font(.system(size: 14))
            .lineSpacing(2)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }
    
    private func buildAttributedString(from components: [TextComponent]) -> AttributedString {
        var result = AttributedString()
        let baseColor = isTransparentBackground ? Color.white : Color.primary
        
        for component in components {
            var part = AttributedString()
            
            switch component.type {
            case .text(let text):
                part = AttributedString(text)
                part.foregroundColor = baseColor
                part.font = .system(size: 14)
            case .bold(let text):
                part = AttributedString(text)
                part.font = .system(size: 14, weight: .bold)
                part.foregroundColor = baseColor
            case .italic(let text):
                part = AttributedString(text)
                part.font = .system(size: 14).italic()
                part.foregroundColor = baseColor
            case .code(let text):
                part = AttributedString("⌜\(text)⌝")
                part.font = .system(size: 14, design: .monospaced)
                part.foregroundColor = .purple
            case .link(let text, let url):
                part = AttributedString(text)
                part.font = .system(size: 14)
                part.foregroundColor = .blue
                part.underlineStyle = .single
                if let linkURL = URL(string: url) {
                    part.link = linkURL
                }
            }
            
            result.append(part)
        }
        
        return result
    }
    
    private func buildTextComponents(from text: String, with segments: [InlineFormatSegment]) -> [TextComponent] {
        var components: [TextComponent] = []
        let sorted = segments.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var cursor = text.startIndex
        
        for segment in sorted {
            let before = String(text[cursor..<segment.range.lowerBound])
            if !before.isEmpty {
                components.append(TextComponent(type: .text(before)))
            }
            
            switch segment.type {
            case .bold:
                components.append(TextComponent(type: .bold(segment.text)))
            case .italic:
                components.append(TextComponent(type: .italic(segment.text)))
            case .code:
                components.append(TextComponent(type: .code(segment.text)))
            case .link(let linkText, let url):
                components.append(TextComponent(type: .link(linkText, url)))
            case .inlineLatex:
                components.append(TextComponent(type: .text(segment.text)))
            }
            
            cursor = segment.range.upperBound
        }
        
        if cursor < text.endIndex {
            let after = String(text[cursor...])
            if !after.isEmpty {
                components.append(TextComponent(type: .text(after)))
            }
        }
        
        return components
    }
}

// 文本组件类型
struct TextComponent {
    let type: TextComponentType
}

enum TextComponentType {
    case text(String)
    case bold(String)
    case italic(String)
    case code(String)
    case link(String, String)
}

// 使用WebKit处理包含LaTeX的文本
struct RichTextWebView: View {
    let text: String
    let segments: [InlineFormatSegment]
    let isTransparentBackground: Bool
    
    @State private var webViewHeight: CGFloat = 30
    
    var body: some View {
        RichTextWebViewRepresentable(
            text: text,
            segments: segments,
            isTransparentBackground: isTransparentBackground,
            onHeightChange: { height in
                webViewHeight = height
            }
        )
        .frame(height: webViewHeight)
    }
}

// 实际的NSViewRepresentable实现
struct RichTextWebViewRepresentable: NSViewRepresentable {
    let text: String
    let segments: [InlineFormatSegment]
    let isTransparentBackground: Bool
    let onHeightChange: (CGFloat) -> Void
    
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
        
        if isTransparentBackground {
            webView.setValue(true, forKey: "drawsTransparentBackground")
        }
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.setRenderCompleteHandler { success, errorMessage, height, width in
            if success, let h = height {
                DispatchQueue.main.async {
                    self.onHeightChange(max(h, 30))
                }
            }
        }

        let htmlContent = generateRichTextHTML(text: text, segments: segments, isTransparent: isTransparentBackground)
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
    
    private func generateRichTextHTML(text: String, segments: [InlineFormatSegment], isTransparent: Bool) -> String {
        let backgroundColor: String = isTransparent ? "transparent" : "#ffffff"
        let textColor: String = isTransparent ? "#ffffff" : "#000000"

        func escapeHTML(_ s: String) -> String {
            var r = s
            r = r.replacingOccurrences(of: "&", with: "&amp;")
            r = r.replacingOccurrences(of: "<", with: "&lt;")
            r = r.replacingOccurrences(of: ">", with: "&gt;")
            r = r.replacingOccurrences(of: "\"", with: "&quot;")
            r = r.replacingOccurrences(of: "'", with: "&#39;")
            return r
        }

        let sorted = segments.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var htmlContent = ""
        var cursor = text.startIndex

        for seg in sorted {
            let before = String(text[cursor..<seg.range.lowerBound])
            htmlContent += escapeHTML(before)

            switch seg.type {
            case .inlineLatex:
                htmlContent += "$" + seg.text + "$"
            case .link(let linkText, let url):
                let safeText = escapeHTML(linkText)
                let safeURL = escapeHTML(url)
                htmlContent += "<a href=\"\(safeURL)\" target=\"_blank\" rel=\"noopener noreferrer\">\(safeText)</a>"
            case .bold, .italic, .code:
                let original = String(text[seg.range])
                htmlContent += escapeHTML(original)
            }

            cursor = seg.range.upperBound
        }

        if cursor < text.endIndex {
            htmlContent += escapeHTML(String(text[cursor...]))
        }

        let katexCSS = CDNManager.shared.getKaTeXCSS()
        let katexJS = CDNManager.shared.getKaTeXJS()
        let katexAutoRender = CDNManager.shared.getKaTeXAutoRender()
        
        let katexCssList = katexCSS.content != nil ? "" : CDNManager.shared.getAllKaTeXCSSCDNs().map { "\"\($0)\"" }.joined(separator: ",")
        let katexJsList = katexJS.content != nil ? "" : CDNManager.shared.getAllKaTeXJSCDNs().map { "\"\($0)\"" }.joined(separator: ",")
        let katexAutoList = katexAutoRender.content != nil ? "" : CDNManager.shared.getAllKaTeXAutoRenderCDNs().map { "\"\($0)\"" }.joined(separator: ",")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset=\"utf-8\">
            \(katexCSS.content != nil ? "<style>\(katexCSS.content!)</style>" : "")
            \(katexJS.content != nil ? "<script>\(katexJS.content!)</script>" : "")
            \(katexAutoRender.content != nil ? "<script>\(katexAutoRender.content!)</script>" : "")
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

                    window.__loadKatexPromise = loadCSSSequentially(0)
                        .then(() => loadJSSequentially(jsList, 0))
                        .then(() => loadJSSequentially(autoList, 0))
                        .catch(() => {});
                })();
            </script>
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    background-color: \(backgroundColor);
                    color: \(textColor);
                    font-size: 18px;
                    line-height: 1.4;
                    font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif;
                    overflow: visible;
                }
                #content {
                    text-align: left;
                    white-space: normal;
                    word-wrap: break-word;
                }
                a { color: #1a73e8; text-decoration: underline; }
                .katex { font-size: 1em; line-height: 1.2; display: inline; }
                .katex-html { display: inline; }
            </style>
        </head>
        <body>
            <div id=\"content\">\(htmlContent)</div>
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
                            throwOnError: false,
                            errorColor: '#cc0000'
                        });

                        setTimeout(() => {
                            const content = document.getElementById("content");
                            const height = content.scrollHeight;
                            const width = content.scrollWidth;
                            const message = { status: "success", height: height, width: width };
                            window.webkit.messageHandlers.renderComplete.postMessage(message);
                        }, 100);
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

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            renderCompleteHandler?(false, "Web content process terminated", nil, nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            renderCompleteHandler?(false, "WebView failed to load: \(error.localizedDescription)", nil, nil)
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

