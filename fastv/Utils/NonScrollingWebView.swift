//
//  NonScrollingWebView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import WebKit
import AppKit

/// 禁用滚动的 WebView，用于内嵌渲染（LaTeX、Mermaid 等）
class NonScrollingWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // 将滚动事件传递给父视图
        nextResponder?.scrollWheel(with: event)
    }
    
    override var acceptsFirstResponder: Bool {
        return false
    }
}

