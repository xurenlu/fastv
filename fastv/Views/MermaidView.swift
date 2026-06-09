//
//  MermaidView.swift
//  fastv
//
//  Created by rocky on 2026/06/03.
//

import SwiftUI
import WebKit

/// 用 WKWebView + mermaid.js 渲染思维导图 / 流程图 / 时序图等。
struct MermaidBlockView: View {
    let source: String
    let isTransparentBackground: Bool

    @State private var isLoading = true
    @State private var renderError: String?
    @State private var contentHeight: CGFloat = 220

    private var viewBackground: Color {
        isTransparentBackground ? Color.black.opacity(0.1) : Color(NSColor.textBackgroundColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "scribble.variable")
                    .font(.caption)
                    .foregroundColor(.purple)
                Text("Mermaid 图")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(source, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(isTransparentBackground ? .white.opacity(0.7) : .secondary)
                }
                .buttonStyle(.plain)
                .help("复制源码")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.purple.opacity(0.08))

            ZStack {
                if let error = renderError {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("Mermaid 渲染失败")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(source)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(8)
                            .background(viewBackground)
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MermaidWebView(
                        source: source,
                        isTransparentBackground: isTransparentBackground,
                        onRenderComplete: { ok, errMsg, height in
                            DispatchQueue.main.async {
                                isLoading = false
                                if ok, let h = height {
                                    contentHeight = max(h, 120)
                                    renderError = nil
                                } else {
                                    renderError = errMsg ?? "未知错误"
                                }
                            }
                        }
                    )
                    .frame(height: contentHeight)
                    .background(viewBackground)
                }

                if isLoading {
                    VStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("正在渲染 Mermaid…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(viewBackground.opacity(0.85))
                }
            }
        }
        .background(viewBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.25), lineWidth: 1)
        )
    }
}

struct MermaidWebView: NSViewRepresentable {
    let source: String
    let isTransparentBackground: Bool
    let onRenderComplete: (Bool, String?, CGFloat?) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if #available(macOS 11.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
            config.preferences.javaScriptEnabled = true
        }
        config.userContentController.add(context.coordinator, name: "mermaidDone")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        if isTransparentBackground {
            webView.setValue(true, forKey: "drawsTransparentBackground")
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.handler = onRenderComplete
        webView.loadHTMLString(buildHTML(), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mermaidDone")
        coordinator.handler = nil
    }

    private func buildHTML() -> String {
        let bg = isTransparentBackground ? "transparent" : "#ffffff"
        let textColor = isTransparentBackground ? "#ffffff" : "#1c1c1e"
        // 用 jsDelivr CDN，失败会通过 onerror 回调
        let mermaidCDN = "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"
        let escapedSource = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
          body { margin: 0; padding: 12px; background: \(bg); color: \(textColor);
                 font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
          #diagram { width: 100%; overflow: auto; }
          .mermaid svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
        </style>
        </head>
        <body>
          <div id="diagram"><pre class="mermaid">\(source.replacingOccurrences(of: "<", with: "&lt;"))</pre></div>
          <script src="\(mermaidCDN)" onerror="window.webkit.messageHandlers.mermaidDone.postMessage({status:'error',message:'无法加载 Mermaid CDN，请检查网络'});"></script>
          <script>
            (async function() {
              try {
                if (typeof mermaid === 'undefined') {
                  throw new Error('mermaid 未加载');
                }
                mermaid.initialize({ startOnLoad: false, theme: '\(isTransparentBackground ? "dark" : "default")', securityLevel: 'loose' });
                await mermaid.run({ querySelector: '.mermaid' });
                setTimeout(() => {
                  const h = document.documentElement.scrollHeight;
                  window.webkit.messageHandlers.mermaidDone.postMessage({status:'success', height: h});
                }, 80);
              } catch (e) {
                window.webkit.messageHandlers.mermaidDone.postMessage({status:'error', message: String(e && e.message || e)});
              }
            })();
          </script>
        </body></html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var handler: ((Bool, String?, CGFloat?) -> Void)?

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handler?(false, "WebView 加载失败: \(error.localizedDescription)", nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mermaidDone",
                  let body = message.body as? [String: Any],
                  let status = body["status"] as? String else { return }
            if status == "success" {
                handler?(true, nil, body["height"] as? CGFloat)
            } else {
                handler?(false, body["message"] as? String ?? "未知错误", nil)
            }
        }
    }
}
