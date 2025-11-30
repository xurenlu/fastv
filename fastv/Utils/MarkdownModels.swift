//
//  MarkdownModels.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import Foundation

// MARK: - Range 扩展

extension Range where Bound: Comparable {
    func overlaps(_ other: Range<Bound>) -> Bool {
        return !(self.upperBound <= other.lowerBound || self.lowerBound >= other.upperBound)
    }
}

// MARK: - Markdown 数据模型

// Markdown 元素类型
enum MarkdownElementType: Equatable {
    case heading(level: Int)
    case paragraph
    case codeBlock(language: String?)
    case bulletList
    case numberedList
    case checkboxList
    case blockquote
    case horizontalRule
    case latexBlock
    case image(url: String, altText: String)
    case table(headers: [String], rows: [[String]])
    case link(text: String, url: String)
}

// Markdown 元素
struct MarkdownElement {
    let type: MarkdownElementType
    let content: String
    let children: [MarkdownElement]?
    
    init(type: MarkdownElementType, content: String, children: [MarkdownElement]? = nil) {
        self.type = type
        self.content = content
        self.children = children
    }
}

// MARK: - 解析辅助结构

// 图片解析结构
struct ImageMatch {
    let url: String
    let altText: String
}

// 链接解析结构
struct LinkMatch {
    let text: String
    let url: String
}

// 表格解析结构
struct TableData {
    let headers: [String]
    let rows: [[String]]
    let endIndex: Int
}

// 勾选框解析结构
struct CheckboxItem {
    let isChecked: Bool
    let text: String
}

// MARK: - Markdown 解析函数

// 主解析函数 - 优化性能版本
func parseMarkdown(_ markdown: String) -> [MarkdownElement] {
    var elements: [MarkdownElement] = []
    elements.reserveCapacity(50)
    
    guard !markdown.isEmpty && markdown.count > 3 else {
        return elements
    }
    
    let contentToProcess: String
    if markdown.count > 100000 {
        print("⚠️ 文档过长，截断处理前10万字符")
        contentToProcess = String(markdown.prefix(100000)) + "\n\n... (文档已截断，完整内容请查看编辑器)"
    } else {
        contentToProcess = markdown
    }
    
    let lines = contentToProcess.components(separatedBy: .newlines)
    var i = 0
    
    let maxLines = min(lines.count, 2000)
    
    // 跳过 Front Matter
    if lines.count > 0 && lines[0].trimmingCharacters(in: .whitespaces) == "---" {
        i += 1
        while i < maxLines && lines[i].trimmingCharacters(in: .whitespaces) != "---" {
            i += 1
        }
        i += 1
    }
    
    while i < maxLines && elements.count < 500 {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        
        if line.isEmpty {
            i += 1
            continue
        }
        
        // 标题解析
        if line.hasPrefix("#") {
            let level = line.prefix(while: { $0 == "#" }).count
            let title = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
            elements.append(MarkdownElement(type: .heading(level: level), content: title))
            i += 1
            continue
        }
        
        // 块级LaTeX公式解析
        if line == "$$" {
            var latexContent = ""
            i += 1
            
            while i < maxLines && lines[i].trimmingCharacters(in: .whitespaces) != "$$" {
                latexContent += lines[i] + "\n"
                i += 1
            }
            
            elements.append(MarkdownElement(type: .latexBlock, content: latexContent.trimmingCharacters(in: .whitespacesAndNewlines)))
            i += 1
            continue
        }
        
        // 代码块解析
        if line.hasPrefix("```") {
            let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var codeContent = ""
            i += 1
            
            while i < maxLines && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                codeContent += lines[i] + "\n"
                i += 1
            }
            
            elements.append(MarkdownElement(type: .codeBlock(language: language.isEmpty ? nil : language), content: codeContent.trimmingCharacters(in: .whitespacesAndNewlines)))
            i += 1
            continue
        }
        
        // 引用块解析
        if line.hasPrefix(">") {
            let content = String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            elements.append(MarkdownElement(type: .blockquote, content: content))
            i += 1
            continue
        }
        
        // 水平线解析
        if line.hasPrefix("---") || line.hasPrefix("***") {
            elements.append(MarkdownElement(type: .horizontalRule, content: ""))
            i += 1
            continue
        }
        
        // 勾选框列表解析
        if parseCheckboxSyntax(line) != nil {
            var checkboxItems: [MarkdownElement] = []
            
            while i < maxLines && elements.count < 500 {
                let currentLine = lines[i].trimmingCharacters(in: .whitespaces)
                if let checkbox = parseCheckboxSyntax(currentLine) {
                    let checkboxContent = checkbox.isChecked ? "[x]" : "[ ]"
                    checkboxItems.append(MarkdownElement(type: .paragraph, content: "\(checkboxContent) \(checkbox.text)"))
                    i += 1
                } else if currentLine.isEmpty {
                    i += 1
                    break
                } else {
                    break
                }
            }
            
            elements.append(MarkdownElement(type: .checkboxList, content: "", children: checkboxItems))
            continue
        }
        
        // 列表解析
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            var listItems: [MarkdownElement] = []
            
            while i < maxLines && elements.count < 500 {
                let currentLine = lines[i].trimmingCharacters(in: .whitespaces)
                if currentLine.hasPrefix("- ") || currentLine.hasPrefix("* ") || currentLine.hasPrefix("+ ") {
                    let content = String(currentLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    listItems.append(MarkdownElement(type: .paragraph, content: content))
                    i += 1
                } else if currentLine.isEmpty {
                    i += 1
                    break
                } else {
                    break
                }
            }
            
            elements.append(MarkdownElement(type: .bulletList, content: "", children: listItems))
            continue
        }
        
        // 数字列表解析
        if let regex = try? NSRegularExpression(pattern: "^\\d+\\. ") {
            let range = NSRange(location: 0, length: line.utf16.count)
            if regex.firstMatch(in: line, range: range) != nil {
                var listItems: [MarkdownElement] = []
                
                while i < maxLines && elements.count < 500 {
                    let currentLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if let match = regex.firstMatch(in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count)) {
                        let content = String(currentLine.dropFirst(match.range.length)).trimmingCharacters(in: .whitespaces)
                        listItems.append(MarkdownElement(type: .paragraph, content: content))
                        i += 1
                    } else if currentLine.isEmpty {
                        i += 1
                        break
                    } else {
                        break
                    }
                }
                
                elements.append(MarkdownElement(type: .numberedList, content: "", children: listItems))
                continue
            }
        }
        
        // 表格解析
        if line.contains("|") && line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            if let tableData = parseTable(lines: lines, startIndex: i) {
                elements.append(MarkdownElement(type: .table(headers: tableData.headers, rows: tableData.rows), content: ""))
                i = tableData.endIndex
                continue
            }
        }
        
        // 图片解析 ![alt text](url)
        if let imageMatch = parseImageSyntax(line) {
            elements.append(MarkdownElement(type: .image(url: imageMatch.url, altText: imageMatch.altText), content: line))
            i += 1
            continue
        }
        
        // 链接解析（仅当整行仅为一个链接时）
        if let linkMatch = parseFullLineLinkSyntax(line) {
            elements.append(MarkdownElement(type: .link(text: linkMatch.text, url: linkMatch.url), content: line))
            i += 1
            continue
        }
        
        // 段落解析
        var paragraphContent = line
        i += 1
        
        while i < maxLines && elements.count < 500 {
            let nextLine = lines[i].trimmingCharacters(in: .whitespaces)
            if nextLine.isEmpty || nextLine.hasPrefix("#") || nextLine.hasPrefix("```") || 
               nextLine.hasPrefix(">") || nextLine.hasPrefix("-") || nextLine.hasPrefix("*") ||
               nextLine.hasPrefix("+") || nextLine.hasPrefix("---") || nextLine.hasPrefix("***") {
                break
            }
            
            paragraphContent += " " + nextLine
            i += 1
        }
        
        elements.append(MarkdownElement(type: .paragraph, content: paragraphContent))
    }
    
    return elements
}

// 解析图片语法 ![alt text](url)
func parseImageSyntax(_ line: String) -> ImageMatch? {
    let pattern = "!\\[([^\\]]*)\\]\\(([^\\)]*)\\)"
    
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return nil
    }
    
    let range = NSRange(location: 0, length: line.utf16.count)
    guard let match = regex.firstMatch(in: line, range: range) else {
        return nil
    }
    
    let altTextRange = Range(match.range(at: 1), in: line)
    let urlRange = Range(match.range(at: 2), in: line)
    
    guard let altTextRange = altTextRange, let urlRange = urlRange else {
        return nil
    }
    
    let altText = String(line[altTextRange])
    let url = String(line[urlRange])
    
    return ImageMatch(url: url, altText: altText)
}

// 解析链接语法 [text](url)
func parseLinkSyntax(_ line: String) -> LinkMatch? {
    let pattern = "\\[([^\\]]*)\\]\\(([^\\)]*)\\)"
    
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return nil
    }
    
    let range = NSRange(location: 0, length: line.utf16.count)
    guard let match = regex.firstMatch(in: line, range: range) else {
        return nil
    }
    
    let textRange = Range(match.range(at: 1), in: line)
    let urlRange = Range(match.range(at: 2), in: line)
    
    guard let textRange = textRange, let urlRange = urlRange else {
        return nil
    }
    
    let text = String(line[textRange])
    let url = String(line[urlRange])
    
    return LinkMatch(text: text, url: url)
}

// 仅当整行是一个单独链接时匹配
func parseFullLineLinkSyntax(_ line: String) -> LinkMatch? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("[") && trimmed.hasSuffix(")") else { return nil }
    if let m = parseLinkSyntax(trimmed) {
        let pattern = "^\\[[^\\]]*\\]\\([^\\)]*\\)$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
            return m
        }
    }
    return nil
}

// 解析勾选框语法 - [ ] 或 - [x]
func parseCheckboxSyntax(_ line: String) -> CheckboxItem? {
    let pattern = "^\\s*-\\s*\\[\\s*([xX]?)\\s*\\]\\s*(.*)$"
    
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return nil
    }
    
    let range = NSRange(location: 0, length: line.utf16.count)
    guard let match = regex.firstMatch(in: line, range: range) else {
        return nil
    }
    
    let checkboxRange = Range(match.range(at: 1), in: line)
    let textRange = Range(match.range(at: 2), in: line)
    
    guard let textRange = textRange else {
        return nil
    }
    
    let checkboxContent = checkboxRange != nil ? String(line[checkboxRange!]) : ""
    let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
    
    let isChecked = !checkboxContent.isEmpty && (checkboxContent.lowercased() == "x")
    
    return CheckboxItem(isChecked: isChecked, text: text)
}

// MARK: - 内联格式解析

// 内联格式类型
enum InlineFormatType {
    case bold
    case italic
    case code
    case link(text: String, url: String)
    case inlineLatex
}

// 内联格式片段
struct InlineFormatSegment {
    let type: InlineFormatType
    let text: String
    let range: Range<String.Index>
}

// 解析内联格式
func parseInlineFormats(_ text: String) -> [InlineFormatSegment] {
    guard !text.isEmpty else {
        return []
    }
    
    var segments: [InlineFormatSegment] = []
    let nsText = text as NSString
    
    // 解析粗体 **text** 或 __text__
    let boldPatterns = ["\\*\\*([^*]+)\\*\\*", "__([^_]+)__"]
    for pattern in boldPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard match.range.location != NSNotFound,
                      match.range.length > 0,
                      match.range.location + match.range.length <= nsText.length,
                      let range = Range(match.range, in: text),
                      let _ = Range(match.range(at: 1), in: text) else {
                    continue
                }
                
                let content = String(nsText.substring(with: match.range(at: 1)))
                segments.append(InlineFormatSegment(
                    type: .bold,
                    text: content,
                    range: range
                ))
            }
        }
    }
    
    // 解析斜体 *text* 或 _text_
    let italicPatterns = ["\\*([^*]+)\\*", "(?<!\\w)_([^_]+)_(?!\\w)"]
    for pattern in italicPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard match.range.location != NSNotFound,
                      match.range.length > 0,
                      match.range.location + match.range.length <= nsText.length,
                      let range = Range(match.range, in: text),
                      let _ = Range(match.range(at: 1), in: text) else {
                    continue
                }
                
                let content = String(nsText.substring(with: match.range(at: 1)))
                segments.append(InlineFormatSegment(
                    type: .italic,
                    text: content,
                    range: range
                ))
            }
        }
    }
    
    // 解析行内代码 `code`
    let codePattern = "`([^`]+)`"
    if let regex = try? NSRegularExpression(pattern: codePattern, options: []) {
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard match.range.location != NSNotFound,
                  match.range.length > 0,
                  match.range.location + match.range.length <= nsText.length,
                  let range = Range(match.range, in: text),
                  let _ = Range(match.range(at: 1), in: text) else {
                continue
            }
            
            let content = String(nsText.substring(with: match.range(at: 1)))
            segments.append(InlineFormatSegment(
                type: .code,
                text: content,
                range: range
            ))
        }
    }
    
    // 解析链接 [text](url)
    let linkPattern = "\\[([^\\]]*)\\]\\(([^\\)]*)\\)"
    if let regex = try? NSRegularExpression(pattern: linkPattern, options: []) {
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard match.range.location != NSNotFound,
                  match.range.length > 0,
                  match.range.location + match.range.length <= nsText.length,
                  let range = Range(match.range, in: text),
                  let _ = Range(match.range(at: 1), in: text),
                  let _ = Range(match.range(at: 2), in: text) else {
                continue
            }
            
            let linkText = String(nsText.substring(with: match.range(at: 1)))
            let url = String(nsText.substring(with: match.range(at: 2)))
            segments.append(InlineFormatSegment(
                type: .link(text: linkText, url: url),
                text: linkText,
                range: range
            ))
        }
    }
    
    // Parse inline LaTeX $...$ (but not $$...$$)
    let latexPattern = "(?<!\\$)\\$([^$]+?)\\$(?!\\$)"
    if let regex = try? NSRegularExpression(pattern: latexPattern, options: []) {
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard match.range.location != NSNotFound,
                  match.range.length > 0,
                  match.range.location + match.range.length <= nsText.length,
                  let range = Range(match.range, in: text),
                  let _ = Range(match.range(at: 1), in: text) else {
                continue
            }
            
            let content = String(nsText.substring(with: match.range(at: 1)))
            
            // LaTeX验证：只有包含数学符号或LaTeX命令的内容才被认为是LaTeX
            let mathSymbols = ["\\", "+", "-", "*", "/", "=", "^", "_", "{", "}", "\\frac", "\\sum", "\\int", "\\sqrt", "\\alpha", "\\beta", "\\gamma", "\\pi", "\\theta", "\\sin", "\\cos", "\\tan", "\\log", "\\ln", "\\infty", "\\partial", "\\nabla", "\\leq", "\\geq", "\\neq", "\\approx", "\\times", "\\div", "\\pm", "\\mp"]
            
            let isValidLatex = mathSymbols.contains { content.contains($0) } || 
                              content.rangeOfCharacter(from: CharacterSet(charactersIn: "∫∑∏√αβγδπθλμσΩ±≤≥≠≈×÷∞∂∇")) != nil
            
            if isValidLatex {
                segments.append(InlineFormatSegment(
                    type: .inlineLatex,
                    text: content,
                    range: range
                ))
            }
        }
    }
    
    return removeOverlappingSegments(segments)
}

// 移除重叠的片段
private func removeOverlappingSegments(_ segments: [InlineFormatSegment]) -> [InlineFormatSegment] {
    guard segments.count > 1 else {
        return segments
    }
    
    var result: [InlineFormatSegment] = []
    let sortedSegments = segments.sorted { $0.range.lowerBound < $1.range.lowerBound }
    
    for segment in sortedSegments {
        let hasOverlap = result.contains { existing in
            segment.range.overlaps(existing.range)
        }
        
        if !hasOverlap {
            result.append(segment)
        }
    }
    
    return result
}

// 解析表格语法
func parseTable(lines: [String], startIndex: Int) -> TableData? {
    var i = startIndex
    var tableLines: [String] = []
    
    while i < lines.count && tableLines.count < 50 {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        if line.isEmpty || !line.contains("|") {
            break
        }
        tableLines.append(line)
        i += 1
    }
    
    if tableLines.count < 2 {
        return nil
    }
    
    let headerLine = tableLines[0]
    let headers = parseTableRow(headerLine)
    
    let separatorLine = tableLines[1]
    let separatorCells = parseTableRow(separatorLine)
    
    for cell in separatorCells {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !trimmed.allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " }) {
            return nil
        }
    }
    
    var rows: [[String]] = []
    for j in 2..<tableLines.count {
        let rowData = parseTableRow(tableLines[j])
        if rowData.count == headers.count {
            rows.append(rowData)
        }
    }
    
    return TableData(headers: headers, rows: rows, endIndex: i)
}

// 解析表格行
func parseTableRow(_ line: String) -> [String] {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("|") {
        let withoutPrefix = String(trimmed.dropFirst())
        let cells = withoutPrefix.components(separatedBy: "|")
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    } else {
        let cells = trimmed.components(separatedBy: "|")
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

