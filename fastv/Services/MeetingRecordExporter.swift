//
//  MeetingRecordExporter.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// 会议记录导出服务
struct MeetingRecordExporter {

    /// 导出格式
    enum ExportFormat {
        case pdf
        case txt
        case markdown
        case html

        var fileExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .txt: return "txt"
            case .markdown: return "md"
            case .html: return "html"
            }
        }

        var displayName: String {
            switch self {
            case .pdf: return "PDF 文档"
            case .txt: return "纯文本"
            case .markdown: return "Markdown"
            case .html: return "网页 (HTML)"
            }
        }

        var utType: UTType {
            switch self {
            case .pdf: return .pdf
            case .txt: return .plainText
            case .markdown: return .markdownText
            case .html: return .html
            }
        }
    }

    /// 导出记录
    static func export(_ record: MeetingRecord, format: ExportFormat) {
        switch format {
        case .pdf:
            exportAsPDF(record)
        case .txt:
            exportAsTXT(record)
        case .markdown:
            exportAsMarkdown(record)
        case .html:
            exportAsHTML(record)
        }
    }

    // MARK: - 辅助方法

    private static func formatCurrentDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: Date())
    }

    // MARK: - TXT 格式

    private static func exportAsTXT(_ record: MeetingRecord) {
        let content = generateTXTContent(record)
        savePanel(content: content, fileName: "\(sanitizeFileName(record.title)).txt", utType: .plainText)
    }

    private static func generateTXTContent(_ record: MeetingRecord) -> String {
        var lines: [String] = []

        // 标题
        lines.append("========================================")
        lines.append(record.title.isEmpty ? "会议记录" : record.title)
        lines.append("========================================")
        lines.append("")

        // 元数据
        lines.append("📅 时间: \(record.formattedDate)")
        lines.append("⏱️ 时长: \(record.formattedDuration)")
        lines.append("📝 字数: \(record.characterCount)")
        lines.append("")

        // 摘要
        if !record.summary.isEmpty {
            lines.append("----------------------------------------")
            lines.append("📋 摘要")
            lines.append("----------------------------------------")
            lines.append(record.summary)
            lines.append("")
        }

        // 行动项
        if !record.actionItems.isEmpty {
            lines.append("----------------------------------------")
            lines.append("✅ 行动项 (\(record.actionItems.count))")
            lines.append("----------------------------------------")
            for (index, item) in record.actionItems.enumerated() {
                lines.append("\(index + 1). \(item)")
            }
            lines.append("")
        }

        // 全文
        let fullText = record.correctedText.isEmpty ? record.originalText : record.correctedText
        if !fullText.isEmpty {
            lines.append("----------------------------------------")
            lines.append("📄 全文")
            lines.append("----------------------------------------")
            lines.append(fullText)
            lines.append("")
        }

        lines.append("========================================")
        lines.append("导出时间: \(formatCurrentDate())")
        lines.append("由 fastv 生成")
        lines.append("========================================")

        return lines.joined(separator: "\n")
    }

    // MARK: - Markdown 格式

    private static func exportAsMarkdown(_ record: MeetingRecord) {
        let content = generateMarkdownContent(record)
        savePanel(content: content, fileName: "\(sanitizeFileName(record.title)).md", utType: .markdownText)
    }

    private static func generateMarkdownContent(_ record: MeetingRecord) -> String {
        var lines: [String] = []

        // 标题
        lines.append("# \(record.title.isEmpty ? "会议记录" : record.title)")
        lines.append("")

        // 元数据表格
        lines.append("| 项目 | 内容 |")
        lines.append("|------|------|")
        lines.append("| 📅 时间 | \(record.formattedDate) |")
        lines.append("| ⏱️ 时长 | \(record.formattedDuration) |")
        lines.append("| 📝 字数 | \(record.characterCount) |")
        lines.append("")

        // 摘要
        if !record.summary.isEmpty {
            lines.append("## 📋 摘要")
            lines.append("")
            lines.append(record.summary)
            lines.append("")
        }

        // 行动项
        if !record.actionItems.isEmpty {
            lines.append("## ✅ 行动项")
            lines.append("")
            for (index, item) in record.actionItems.enumerated() {
                lines.append("\(index + 1). \(item)")
            }
            lines.append("")
        }

        // 全文
        let fullText = record.correctedText.isEmpty ? record.originalText : record.correctedText
        if !fullText.isEmpty {
            lines.append("## 📄 全文")
            lines.append("")
            lines.append(fullText)
            lines.append("")
        }

        // 导出信息
        lines.append("---")
        lines.append("")
        lines.append("*导出时间: \(formatCurrentDate()) | 由 fastv 生成*")

        return lines.joined(separator: "\n")
    }

    // MARK: - HTML 格式

    private static func exportAsHTML(_ record: MeetingRecord) {
        let content = generateHTMLContent(record)
        savePanel(content: content, fileName: "\(sanitizeFileName(record.title)).html", utType: .html)
    }

    private static func generateHTMLContent(_ record: MeetingRecord) -> String {
        let fullText = record.correctedText.isEmpty ? record.originalText : record.correctedText
        let escapedFullText = escapeHTML(fullText).replacingOccurrences(of: "\n", with: "<br>")
        let escapedSummary = escapeHTML(record.summary).replacingOccurrences(of: "\n", with: "<br>")
        let escapedTitle = escapeHTML(record.title.isEmpty ? "会议记录" : record.title)

        var html = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapedTitle)</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Microsoft YaHei", sans-serif;
                    line-height: 1.7;
                    color: #333;
                    background: #f5f5f7;
                    padding: 40px 20px;
                }
                .container {
                    max-width: 800px;
                    margin: 0 auto;
                    background: white;
                    border-radius: 16px;
                    box-shadow: 0 4px 30px rgba(0,0,0,0.1);
                    overflow: hidden;
                }
                .header {
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    padding: 40px;
                }
                .header h1 {
                    font-size: 32px;
                    font-weight: 700;
                    margin-bottom: 20px;
                }
                .meta {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 24px;
                    font-size: 15px;
                    opacity: 0.95;
                }
                .meta-item {
                    display: flex;
                    align-items: center;
                    gap: 6px;
                }
                .content { padding: 40px; }
                .section { margin-bottom: 35px; }
                .section-title {
                    font-size: 20px;
                    font-weight: 600;
                    margin-bottom: 18px;
                    padding-bottom: 12px;
                    border-bottom: 2px solid #e5e5e7;
                    display: flex;
                    align-items: center;
                    gap: 10px;
                }
                .section-title .icon { font-size: 22px; }
                .section-title.summary .icon { color: #007AFF; }
                .section-title.action-items .icon { color: #34C759; }
                .section-title.fulltext .icon { color: #5856D6; }
                .section-body {
                    color: #444;
                    white-space: pre-wrap;
                    line-height: 1.9;
                    font-size: 15px;
                }
                .action-items { list-style: none; }
                .action-items li {
                    padding: 14px 0;
                    padding-left: 36px;
                    position: relative;
                    border-bottom: 1px solid #f0f0f0;
                }
                .action-items li:last-child { border-bottom: none; }
                .action-items li::before {
                    content: "✓";
                    position: absolute;
                    left: 0;
                    color: #34C759;
                    font-weight: bold;
                    font-size: 20px;
                }
                .footer {
                    text-align: center;
                    padding: 25px;
                    color: #999;
                    font-size: 13px;
                    border-top: 1px solid #e5e5e7;
                    background: #fafafa;
                }
                @media print {
                    body { background: white; padding: 0; }
                    .container { box-shadow: none; border-radius: 0; }
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>\(escapedTitle)</h1>
                    <div class="meta">
                        <div class="meta-item">📅 \(record.formattedDate)</div>
                        <div class="meta-item">⏱️ \(record.formattedDuration)</div>
                        <div class="meta-item">📝 \(record.characterCount) 字</div>
                    </div>
                </div>
                <div class="content">
        """

        // 摘要
        if !record.summary.isEmpty {
            html += """
                    <div class="section">
                        <div class="section-title summary">
                            <span class="icon">📋</span>摘要
                        </div>
                        <div class="section-body">\(escapedSummary)</div>
                    </div>
            """
        }

        // 行动项
        if !record.actionItems.isEmpty {
            html += """
                    <div class="section">
                        <div class="section-title action-items">
                            <span class="icon">✅</span>行动项 (\(record.actionItems.count))
                        </div>
                        <ul class="action-items">
            """
            for item in record.actionItems {
                html += """
                            <li>\(escapeHTML(item))</li>
                """
            }
            html += """
                        </ul>
                    </div>
            """
        }

        // 全文
        if !escapedFullText.isEmpty {
            html += """
                    <div class="section">
                        <div class="section-title fulltext">
                            <span class="icon">📄</span>全文
                        </div>
                        <div class="section-body">\(escapedFullText)</div>
                    </div>
            """
        }

        html += """
                </div>
                <div class="footer">
                    导出时间: \(formatCurrentDate()) | 由 fastv 生成
                </div>
            </div>
        </body>
        </html>
        """

        return html
    }

    // MARK: - PDF 格式

    private static func exportAsPDF(_ record: MeetingRecord) {
        // 使用 NSAttributedString + NSTextView 导出 PDF
        let title = record.title.isEmpty ? "会议记录" : record.title
        let fullText = record.correctedText.isEmpty ? record.originalText : record.correctedText

        // 创建 attributed string
        let attrString = NSMutableAttributedString()

        // 标题
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        attrString.append(NSAttributedString(string: title + "\n\n", attributes: titleAttr))

        // 元数据
        let metaAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let metaText = "时间: \(record.formattedDate)  |  时长: \(record.formattedDuration)  |  字数: \(record.characterCount)\n\n"
        attrString.append(NSAttributedString(string: metaText, attributes: metaAttr))

        // 摘要
        if !record.summary.isEmpty {
            let sectionAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
            attrString.append(NSAttributedString(string: "📋 摘要\n\n", attributes: sectionAttr))

            let bodyAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
            attrString.append(NSAttributedString(string: record.summary + "\n\n", attributes: bodyAttr))
        }

        // 行动项
        if !record.actionItems.isEmpty {
            let sectionAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
            attrString.append(NSAttributedString(string: "✅ 行动项 (\(record.actionItems.count))\n\n", attributes: sectionAttr))

            let bodyAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
            for (index, item) in record.actionItems.enumerated() {
                attrString.append(NSAttributedString(string: "\(index + 1). \(item)\n", attributes: bodyAttr))
            }
            attrString.append(NSAttributedString(string: "\n", attributes: bodyAttr))
        }

        // 全文
        if !fullText.isEmpty {
            let sectionAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
            attrString.append(NSAttributedString(string: "📄 全文\n\n", attributes: sectionAttr))

            let bodyAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
            attrString.append(NSAttributedString(string: fullText + "\n\n", attributes: bodyAttr))
        }

        // 导出信息
        let footerAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        attrString.append(NSAttributedString(string: "导出时间: \(formatCurrentDate()) | 由 fastv 生成", attributes: footerAttr))

        // 保存对话框
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "\(sanitizeFileName(record.title)).pdf"
        savePanel.allowedContentTypes = [.pdf]

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                self.savePDF(attrString: attrString, to: url)
            }
        }
    }

    private static func savePDF(attrString: NSAttributedString, to url: URL) {
        let view = NSTextView()
        view.textStorage?.setAttributedString(attrString)
        view.isEditable = false
        view.isSelectable = false

        // 计算所需尺寸
        let size = attrString.boundingRect(
            with: NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
        view.frame = NSRect(origin: .zero, size: NSSize(width: 680, height: max(size.height + 100, 600)))

        // 保存到 PDF
        let pdfData = view.dataWithPDF(inside: view.bounds)
        try? pdfData.write(to: url)
    }

    // MARK: - 通用保存面板

    private static func savePanel(content: String, fileName: String, utType: UTType) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = fileName
        savePanel.allowedContentTypes = [utType]

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - 辅助方法

    private static func escapeHTML(_ string: String) -> String {
        var escaped = string
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&#39;")
        return escaped
    }

    private static func sanitizeFileName(_ name: String) -> String {
        var sanitized = name
        let invalidChars = CharacterSet(charactersIn: ":/\\?*|\"<>")
        sanitized = sanitized.components(separatedBy: invalidChars).joined(separator: "_")
        return sanitized.isEmpty ? "untitled" : sanitized
    }
}
