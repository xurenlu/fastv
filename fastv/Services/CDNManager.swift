//
//  CDNManager.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// CDN 管理器 - 根据用户地区和语言智能选择 CDN，优先使用本地资源
class CDNManager: ObservableObject {
    static let shared = CDNManager()
    
    private init() {}
    
    /// 本地资源管理器
    private let localResourceManager = LocalWebResourceManager.shared
    
    /// 是否优先使用本地资源（默认启用）
    @Published var preferLocalResources: Bool = true
    
    /// 获取当前用户的地区代码
    var currentRegion: String {
        return Locale.current.region?.identifier ?? "US"
    }
    
    /// 获取当前用户的主要语言代码
    var currentLanguage: String {
        return Locale.preferredLanguages.first?.prefix(2).description ?? "en"
    }
    
    /// 判断是否为中文用户
    var isChineseUser: Bool {
        return currentLanguage == "zh" || 
               currentLanguage == "zh-Hans" || 
               currentLanguage == "zh-Hant" ||
               currentLanguage.hasPrefix("zh")
    }
    
    /// 判断是否为中国地区用户
    var isChineseRegion: Bool {
        return currentRegion == "CN" || 
               currentRegion == "HK" || 
               currentRegion == "TW" ||
               currentRegion == "MO"
    }
    
    /// 判断是否应该使用国内 CDN
    var shouldUseChineseCDN: Bool {
        return isChineseUser || isChineseRegion
    }
    
    /// 获取 KaTeX CSS 内容或 CDN URL
    func getKaTeXCSS() -> (content: String?, cdnURL: String?) {
        // 优先使用本地资源
        if preferLocalResources, let localContent = localResourceManager.getKaTeXCSS() {
            return (content: localContent, cdnURL: nil)
        }
        
        // 降级到 CDN
        return (content: nil, cdnURL: getKaTeXCSSCDN())
    }
    
    /// 获取 KaTeX CSS 的 CDN URL（内部方法）
    private func getKaTeXCSSCDN() -> String {
        if shouldUseChineseCDN {
            let chineseCDNs = [
                "https://lf26-cdn-tos.bytecdntp.com/cdn/expire-1-M/KaTeX/0.16.0/katex.min.css",
                "https://cdn.staticfile.org/KaTeX/0.16.0/katex.min.css",
                "https://unpkg.zhimg.com/katex@0.16.0/dist/katex.min.css",
                "https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/katex.min.css"
            ]
            return chineseCDNs[0]
        } else {
            return "https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/katex.min.css"
        }
    }
    
    /// 获取 KaTeX JS 内容或 CDN URL
    func getKaTeXJS() -> (content: String?, cdnURL: String?) {
        // 优先使用本地资源
        if preferLocalResources, let localContent = localResourceManager.getKaTeXJS() {
            return (content: localContent, cdnURL: nil)
        }
        
        // 降级到 CDN
        return (content: nil, cdnURL: getKaTeXJSCDN())
    }
    
    /// 获取 KaTeX JS 的 CDN URL（内部方法）
    private func getKaTeXJSCDN() -> String {
        if shouldUseChineseCDN {
            let chineseCDNs = [
                "https://lf26-cdn-tos.bytecdntp.com/cdn/expire-1-M/KaTeX/0.16.0/katex.min.js",
                "https://cdn.staticfile.org/KaTeX/0.16.0/katex.min.js",
                "https://unpkg.zhimg.com/katex@0.16.0/dist/katex.min.js",
                "https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/katex.min.js"
            ]
            return chineseCDNs[0]
        } else {
            return "https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/katex.min.js"
        }
    }
    
    /// 获取 KaTeX AutoRender 内容或 CDN URL
    func getKaTeXAutoRender() -> (content: String?, cdnURL: String?) {
        // 优先使用本地资源
        if preferLocalResources, let localContent = localResourceManager.getKaTeXAutoRenderJS() {
            return (content: localContent, cdnURL: nil)
        }
        
        // 降级到 CDN
        return (content: nil, cdnURL: getKaTeXAutoRenderCDN())
    }
    
    /// 获取 KaTeX AutoRender 的 CDN URL（内部方法）
    private func getKaTeXAutoRenderCDN() -> String {
        if shouldUseChineseCDN {
            let chineseCDNs = [
                "https://lf26-cdn-tos.bytecdntp.com/cdn/expire-1-M/KaTeX/0.16.0/contrib/auto-render.min.js",
                "https://cdn.staticfile.org/KaTeX/0.16.0/contrib/auto-render.min.js",
                "https://unpkg.zhimg.com/katex@0.16.0/dist/contrib/auto-render.min.js",
                "https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/contrib/auto-render.min.js"
            ]
            return chineseCDNs[0]
        } else {
            return "https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/contrib/auto-render.min.js"
        }
    }

    /// 获取所有 KaTeX CSS 的 CDN 列表（按优先顺序）
    func getAllKaTeXCSSCDNs() -> [String] {
        if shouldUseChineseCDN {
            return [
                "https://lf26-cdn-tos.bytecdntp.com/cdn/expire-1-M/KaTeX/0.16.0/katex.min.css",
                "https://cdn.staticfile.org/KaTeX/0.16.0/katex.min.css",
                "https://unpkg.zhimg.com/katex@0.16.0/dist/katex.min.css",
                "https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.0/katex.min.css",
                "https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/katex.min.css",
                "https://unpkg.com/katex@0.16.0/dist/katex.min.css"
            ]
        } else {
            return [
                "https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/katex.min.css",
                "https://unpkg.com/katex@0.16.0/dist/katex.min.css",
                "https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.0/katex.min.css",
                "https://unpkg.zhimg.com/katex@0.16.0/dist/katex.min.css",
                "https://cdn.staticfile.org/KaTeX/0.16.0/katex.min.css",
                "https://lf26-cdn-tos.bytecdntp.com/cdn/expire-1-M/KaTeX/0.16.0/katex.min.css"
            ]
        }
    }

    /// 获取所有 KaTeX JS 的 CDN 列表（按优先顺序）
    func getAllKaTeXJSCDNs() -> [String] {
        if shouldUseChineseCDN {
            return [
                "https://lf26-cdn-tos.bytecdntp.com/cdn/expire-1-M/KaTeX/0.16.0/katex.min.js",
                "https://cdn.staticfile.org/KaTeX/0.16.0/katex.min.js",
                "https://unpkg.zhimg.com/katex@0.16.0/dist/katex.min.js",
                "https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.0/katex.min.js",
                "https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/katex.min.js",
                "https://unpkg.com/katex@0.16.0/dist/katex.min.js"
            ]
        } else {
            return [
                "https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/katex.min.js",
                "https://unpkg.com/katex@0.16.0/dist/katex.min.js",
                "https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.0/katex.min.js",
                "https://unpkg.zhimg.com/katex@0.16.0/dist/katex.min.js",
                "https://cdn.staticfile.org/KaTeX/0.16.0/katex.min.js",
                "https://lf26-cdn-tos.bytecdntp.com/cdn/expire-1-M/KaTeX/0.16.0/katex.min.js"
            ]
        }
    }

    /// 获取所有 KaTeX AutoRender 的 CDN 列表（按优先顺序）
    func getAllKaTeXAutoRenderCDNs() -> [String] {
        if shouldUseChineseCDN {
            return [
                "https://lf26-cdn-tos.bytecdntp.com/cdn/expire-1-M/KaTeX/0.16.0/contrib/auto-render.min.js",
                "https://cdn.staticfile.org/KaTeX/0.16.0/contrib/auto-render.min.js",
                "https://unpkg.zhimg.com/katex@0.16.0/dist/contrib/auto-render.min.js",
                "https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.0/contrib/auto-render.min.js",
                "https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/contrib/auto-render.min.js",
                "https://unpkg.com/katex@0.16.0/dist/contrib/auto-render.min.js"
            ]
        } else {
            return [
                "https://cdn.jsdelivr.net/npm/katex@0.16.0/dist/contrib/auto-render.min.js",
                "https://unpkg.com/katex@0.16.0/dist/contrib/auto-render.min.js",
                "https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.0/contrib/auto-render.min.js",
                "https://unpkg.zhimg.com/katex@0.16.0/dist/contrib/auto-render.min.js",
                "https://cdn.staticfile.org/KaTeX/0.16.0/contrib/auto-render.min.js",
                "https://lf26-cdn-tos.bytecdntp.com/cdn/expire-1-M/KaTeX/0.16.0/contrib/auto-render.min.js"
            ]
        }
    }
}

