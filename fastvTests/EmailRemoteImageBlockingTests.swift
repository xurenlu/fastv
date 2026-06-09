//
//  EmailRemoteImageBlockingTests.swift
//  fastvTests
//
//  覆盖 EmailBodyWebView.stripRemoteImageSources 的正则规则：
//  对每一类潜在的"远程资源加载点位"做正/反两组断言，
//  防止后续改正则时把追踪像素 / newsletter 背景图等放行回去。
//

import Foundation
import Testing
@testable import row1

struct EmailRemoteImageBlockingTests {

    private func stripped(_ html: String) -> String {
        EmailBodyWebViewRepresentable.stripRemoteImageSources(html)
    }

    /// 判断 HTML 是否还残留任何会触发远程请求的属性。
    /// 用正则在边界上找：`<tag ... attr="http"` 这种**未被改名**的形态。
    /// data-original-* 不算（前缀里已经加了 data-original-）。
    private func hasLiveRemoteRequest(_ html: String) -> Bool {
        // 寻找仍然以"src=" / "srcset=" / "poster=" / "href=" / "data="
        // 紧跟 http(s) 或 //（且前面紧贴空白或 < 或 ;）的形态。
        let patterns = [
            // 属性前面必须是空白或 < （避免匹配到 data-original-src），属性后是 http/https/// URL
            #"(?:[\s])(?:src|srcset|poster|href|data)\s*=\s*['"]?(?:https?:|//)"#,
            // CSS 形式：background[-image]:url(http...) 仍然存在
            #"background(?:-image)?\s*:\s*url\(['"]?\s*(?:https?:|//)"#,
            // 文体内 url(http...)，与 background 一起兜底
            #"@import\s+(?:url\()?(['"]?)\s*(?:https?:|//)"#
        ]
        for p in patterns {
            if html.range(of: p, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - <img src>

    @Test func blocksHttpSrcWithDoubleQuote() async throws {
        let out = stripped(#"<img src="http://t.example.com/p.gif">"#)
        #expect(!hasLiveRemoteRequest(out), "<img src=\"http\"> 应该被改成 data-original-src，输出: \(out)")
    }

    @Test func blocksHttpsSrcWithSingleQuote() async throws {
        let out = stripped(#"<img src='https://t.example.com/p.gif'>"#)
        #expect(!hasLiveRemoteRequest(out), "<img src='https'> 应该被改成 data-original-src，输出: \(out)")
    }

    @Test func blocksUppercaseSrcAttribute() async throws {
        let out = stripped(#"<IMG SRC="http://x.com/y.png">"#)
        #expect(!hasLiveRemoteRequest(out), "<IMG SRC> 大写也应该被替换，输出: \(out)")
    }

    @Test func blocksUnquotedSrc() async throws {
        let out = stripped(#"<img src=http://no-quote/x.png>"#)
        #expect(!hasLiveRemoteRequest(out), "无引号 src 也应该被替换，输出: \(out)")
    }

    @Test func blocksProtocolRelativeSrc() async throws {
        let out = stripped(#"<img src="//cdn.example.com/x.png">"#)
        #expect(!hasLiveRemoteRequest(out), "protocol-relative // 也应该被替换，输出: \(out)")
    }

    @Test func keepsCidSrc() async throws {
        let html = #"<img src="cid:image001.png@01D7...">"#
        let out = stripped(html)
        #expect(out.contains(#"src="cid:"#), "cid: 内嵌图必须保留")
        #expect(!out.contains("data-original-src"))
    }

    @Test func keepsDataUriSrc() async throws {
        let html = #"<img src="data:image/png;base64,iVBORw0KGgo=">"#
        let out = stripped(html)
        #expect(out.contains(#"src="data:image"#), "data:image 必须保留")
        #expect(!out.contains("data-original-src"))
    }

    // MARK: - <img srcset>

    @Test func blocksSrcset() async throws {
        let out = stripped(#"<img srcset="https://cdn/x.png 1x, https://cdn/x@2x.png 2x">"#)
        #expect(!hasLiveRemoteRequest(out), "srcset 应该被改名，输出: \(out)")
    }

    // MARK: - <picture><source>

    @Test func blocksPictureSource() async throws {
        let html = #"""
        <picture>
          <source srcset="https://cdn/x.webp" type="image/webp">
          <img src="https://cdn/x.png">
        </picture>
        """#
        let out = stripped(html)
        #expect(!hasLiveRemoteRequest(out), "<picture><source> 与 <img> 都应该被替换，输出: \(out)")
    }

    // MARK: - <input type=image>

    @Test func blocksInputTypeImage() async throws {
        let html = #"<input type="image" src="https://t.com/track.gif">"#
        let out = stripped(html)
        #expect(!hasLiveRemoteRequest(out), "<input type=image src> 应该被替换，输出: \(out)")
    }

    // MARK: - <video poster>

    @Test func blocksVideoPoster() async throws {
        let html = #"<video poster="https://t.com/poster.jpg"></video>"#
        let out = stripped(html)
        #expect(!hasLiveRemoteRequest(out), "<video poster> 应该被替换，输出: \(out)")
    }

    // MARK: - <iframe> / <embed> / <object>

    @Test func blocksIframeSrc() async throws {
        let html = #"<iframe src="https://t.com/x"></iframe>"#
        let out = stripped(html)
        #expect(!hasLiveRemoteRequest(out), "<iframe src> 应该被替换，输出: \(out)")
    }

    @Test func blocksObjectData() async throws {
        let html = #"<object data="https://t.com/x.pdf"></object>"#
        let out = stripped(html)
        #expect(!hasLiveRemoteRequest(out), "<object data> 应该被替换，输出: \(out)")
    }

    // MARK: - <link rel=stylesheet>

    @Test func blocksLinkHref() async throws {
        let html = #"<link rel="stylesheet" href="https://cdn/style.css">"#
        let out = stripped(html)
        #expect(!hasLiveRemoteRequest(out), "<link href> 应该被替换，输出: \(out)")
    }

    // MARK: - inline style backgrounds

    @Test func blocksBackgroundImageShorthand() async throws {
        let html = #"<div style="background:url(https://t.com/bg.gif) no-repeat"></div>"#
        let out = stripped(html)
        #expect(!hasLiveRemoteRequest(out), "background:url 短写法应该被替换，输出: \(out)")
    }

    @Test func blocksBackgroundImageLong() async throws {
        let html = #"<div style="background-image:url('https://t.com/bg.gif')"></div>"#
        let out = stripped(html)
        #expect(!hasLiveRemoteRequest(out), "background-image:url 应该被替换，输出: \(out)")
    }

    // MARK: - <style> 内 @import 与 url()

    @Test func blocksStyleTagAtImport() async throws {
        let html = """
        <style>
            @import url("https://cdn/style.css");
            body { color: red; }
        </style>
        """
        let out = stripped(html)
        #expect(!hasLiveRemoteRequest(out), "<style> 内 @import 应该被替换，输出: \(out)")
    }

    @Test func blocksStyleTagUrl() async throws {
        let html = """
        <style>
        .tracker { background: url(https://t.com/pixel.gif); }
        </style>
        """
        let out = stripped(html)
        #expect(!hasLiveRemoteRequest(out), "<style> 内 url(http) 应该被替换，输出: \(out)")
    }

    // MARK: - 早退 / 性能

    @Test func returnsUnchangedWhenNoRemoteResources() async throws {
        let html = #"<p>Hello world</p><img src="cid:logo">"#
        let out = stripped(html)
        #expect(out == html, "无 http/// 应该早退原样返回")
    }

    @Test func handlesEmptyInput() async throws {
        let out = stripped("")
        #expect(out == "")
    }

    // MARK: - 局部不动

    @Test func preservesNonImageHttpLinks() async throws {
        // <a href="http://..."> 是普通链接，点击才跳转，不会自动加载
        // 但我们目前的规则把 <link href=http> 替换了 —— <a href> 不在替换列表，应该保留
        let html = #"<a href="http://example.com">click</a>"#
        let out = stripped(html)
        #expect(out.contains(#"href="http://example.com""#), "<a href> 普通链接不该被改名，输出: \(out)")
    }
}
