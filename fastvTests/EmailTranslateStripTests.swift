//
//  EmailTranslateStripTests.swift
//  fastvTests
//
//  覆盖 EmailViewModel.stripHTMLTagsForTranslate：
//  之前只剥 <tag> 本身，<style>/<script> 之间的 CSS / JS 当正文交给 AI 翻译，
//  截图反馈用户看到"body {width: 600px;}"这一堆 CSS 文本被翻译出来。
//  这里把所有"应该被剥到"的输入用例固定下来。
//

import Testing
@testable import musetype

struct EmailTranslateStripTests {

    private func strip(_ html: String) -> String {
        EmailViewModel.stripHTMLTagsForTranslate(html)
    }

    // MARK: - <style> / <script> 整段剥离

    @Test func stripsStyleTagAndItsCSSBody() async throws {
        let html = """
        <html><head>
        <style>body {width: 600px;margin: 0 auto;}
        table {border-collapse: collapse;}
        img {-ms-interpolation-mode: bicubic;}</style>
        </head><body>
        <p>Hello world</p>
        </body></html>
        """
        let out = strip(html)
        #expect(!out.contains("body {"), "CSS body{} 不应被翻译，输出: \(out)")
        #expect(!out.contains("border-collapse"), "border-collapse 也不应留下")
        #expect(!out.contains("-ms-interpolation-mode"), "供 Outlook 用的 CSS 也得剥")
        #expect(out.contains("Hello world"), "正文必须保留")
    }

    @Test func stripsScriptTagAndItsJSBody() async throws {
        let html = """
        <p>Hi</p>
        <script type="text/javascript">
            window._track = function() { fetch('https://t/x'); };
        </script>
        <p>Bye</p>
        """
        let out = strip(html)
        #expect(!out.contains("window._track"), "JS 函数体不应留下")
        #expect(!out.contains("fetch("), "fetch 调用不应留下")
        #expect(out.contains("Hi"))
        #expect(out.contains("Bye"))
    }

    @Test func stripsMultipleStyleBlocks() async throws {
        let html = """
        <style>.a{}</style>
        <p>段一</p>
        <style>.b{}</style>
        <p>段二</p>
        """
        let out = strip(html)
        #expect(!out.contains(".a{"))
        #expect(!out.contains(".b{"))
        #expect(out.contains("段一"))
        #expect(out.contains("段二"))
    }

    @Test func stripsStyleWithAttributes() async throws {
        // <style type="text/css" media="screen"> 这种带属性的也得挡
        let html = #"""
        <style type="text/css" media="screen">
        .header { color: red; }
        </style>
        <h1>Real Title</h1>
        """#
        let out = strip(html)
        #expect(!out.contains(".header"))
        #expect(out.contains("Real Title"))
    }

    // MARK: - <head> / <noscript> / 注释 / DOCTYPE

    @Test func stripsHeadBlock() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>不应出现在翻译里的标题</title>
            <meta charset="utf-8">
        </head>
        <body>
            <p>正文段落</p>
        </body>
        </html>
        """
        let out = strip(html)
        #expect(!out.contains("不应出现在翻译里的标题"))
        #expect(!out.contains("<!DOCTYPE"))
        #expect(out.contains("正文段落"))
    }

    @Test func stripsHTMLComments() async throws {
        let html = """
        <!-- hidden tracking comment with https://t.com/pixel -->
        <p>visible</p>
        """
        let out = strip(html)
        #expect(!out.contains("hidden tracking"))
        #expect(out.contains("visible"))
    }

    @Test func stripsNoscript() async throws {
        let html = """
        <noscript>请启用 JavaScript（这是 fallback 文本，不该翻译）</noscript>
        <p>真正内容</p>
        """
        let out = strip(html)
        #expect(!out.contains("请启用 JavaScript"))
        #expect(out.contains("真正内容"))
    }

    // MARK: - 数字字符引用

    @Test func decodesDecimalNumericEntity() async throws {
        let html = "<p>&#20013;&#25991;</p>"
        let out = strip(html)
        #expect(out.contains("中文"), "数字实体 &#20013; 应被还原为 中, 输出: \(out)")
    }

    @Test func decodesHexNumericEntity() async throws {
        let html = "<p>&#x4e2d;&#x6587;</p>"
        let out = strip(html)
        #expect(out.contains("中文"), "hex 实体也应还原, 输出: \(out)")
    }

    @Test func decodesNamedEntities() async throws {
        let html = "<p>A&amp;B &lt;C&gt; &quot;D&quot; &apos;E&apos; &nbsp;F</p>"
        let out = strip(html)
        #expect(out.contains("A&B"))
        #expect(out.contains("<C>"))
        #expect(out.contains("\"D\""))
        #expect(out.contains("'E'"))
        #expect(out.contains("F"))
    }

    // MARK: - 段落保留

    @Test func keepsParagraphBreaks() async throws {
        let html = "<p>第一段</p><p>第二段</p><p>第三段</p>"
        let out = strip(html)
        let lines = out.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count >= 3, "三段 <p> 应该至少产出 3 行，输出: \(out)")
    }

    @Test func keepsBrAsNewline() async throws {
        let html = "Line1<br>Line2<br/>Line3<br />Line4"
        let out = strip(html)
        #expect(out.contains("Line1"))
        #expect(out.contains("Line4"))
        let lines = out.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 4)
    }

    // MARK: - 空白 / 边界

    @Test func handlesEmptyInput() async throws {
        #expect(strip("") == "")
    }

    @Test func collapsesExcessiveWhitespace() async throws {
        let html = "<p>多余    空格</p>\n\n\n\n\n<p>下一段</p>"
        let out = strip(html)
        #expect(!out.contains("    "), "连续空格应该压缩到 1 个")
        #expect(!out.contains("\n\n\n"), "三个以上换行应该压缩到 2 个")
    }
}
