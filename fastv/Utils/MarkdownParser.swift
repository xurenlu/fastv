//
//  MarkdownParser.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import SwiftUI

/// Markdown 代码块
struct MarkdownCodeBlock: Identifiable {
    let id: UUID
    let code: String
    let language: String?
    
    init(code: String, language: String? = nil) {
        self.id = UUID()
        self.code = code
        self.language = language
    }
}

/// Markdown 表格
struct MarkdownTable: Identifiable {
    let id: UUID
    let headers: [String]
    let rows: [[String]]
    let alignments: [TableAlignment]  // 每列的对齐方式
    
    enum TableAlignment {
        case left
        case center
        case right
        case none
    }
    
    init(headers: [String], rows: [[String]], alignments: [TableAlignment] = []) {
        self.id = UUID()
        self.headers = headers
        self.rows = rows
        self.alignments = alignments
    }
}

/// Markdown 解析结果
struct MarkdownContent {
    var text: String
    var images: [MarkdownMedia]
    var videos: [MarkdownMedia]
    var codeBlocks: [MarkdownCodeBlock]
    var tables: [MarkdownTable]
    
    init(text: String = "", images: [MarkdownMedia] = [], videos: [MarkdownMedia] = [], codeBlocks: [MarkdownCodeBlock] = [], tables: [MarkdownTable] = []) {
        self.text = text
        self.images = images
        self.videos = videos
        self.codeBlocks = codeBlocks
        self.tables = tables
    }
}

/// Markdown 中的媒体内容
struct MarkdownMedia: Identifiable {
    let id: UUID
    let url: String
    let alt: String?
    let type: MediaType
    
    enum MediaType {
        case image
        case video
    }
}

/// Markdown 解析器
class MarkdownParser {
    /// 解析 Markdown 文本，提取图片、视频和代码块
    /// - Parameter markdown: Markdown 文本
    /// - Returns: 解析结果
    static func parse(_ markdown: String) -> MarkdownContent {
        var content = MarkdownContent(text: markdown, images: [], videos: [], codeBlocks: [], tables: [])
        
        // 首先提取表格（避免表格中的内容被误解析）
        var processedText = markdown
        var tables: [MarkdownTable] = []
        
        // 匹配 Markdown 表格格式，支持两种格式：
        // 标准格式：| Header 1 | Header 2 |
        //           |----------|----------|
        //           | Cell 1   | Cell 2   |
        // GFM 格式：| Header 1 | Header 2 |
        //           :---:---:
        //           | Cell 1   | Cell 2   |
        // 使用更灵活的方式：先找到表头行，然后查找后续的分隔行和数据行
        let lines = processedText.components(separatedBy: "\n")
        var processedLines = lines
        var lineOffsets: [Int] = [0] // 每行的起始位置
        var currentOffset = 0
        for line in lines {
            currentOffset += line.count + 1 // +1 for newline
            lineOffsets.append(currentOffset)
        }
        
        var i = 0
        while i < processedLines.count {
            let line = processedLines[i].trimmingCharacters(in: .whitespaces)
            
            // 检查是否是表头行（以 | 开头和结尾）
            if line.hasPrefix("|") && line.hasSuffix("|") && line.contains("|") {
                let headers = parseTableRow(line)
                
                if !headers.isEmpty && i + 1 < processedLines.count {
                    // 检查下一行是否是分隔行
                    let separatorLine = processedLines[i + 1].trimmingCharacters(in: .whitespaces)
                    
                    // 分隔行可能是 |:---:| 或 :---: 格式
                    // 检查是否包含 - 和可能的 : 或 |
                    let hasDashes = separatorLine.contains("-")
                    let hasColons = separatorLine.contains(":")
                    let hasPipes = separatorLine.contains("|")
                    
                    if hasDashes && (hasColons || hasPipes || separatorLine.allSatisfy { $0 == "-" || $0 == ":" || $0 == "|" || $0 == " " }) {
                        
                        let alignments = parseTableAlignments(separatorLine, columnCount: headers.count)
                        
                        // 收集后续的数据行
                        var rows: [[String]] = []
                        var j = i + 2
                        while j < processedLines.count {
                            let dataLine = processedLines[j].trimmingCharacters(in: .whitespaces)
                            
                            // 检查是否是数据行（以 | 开头和结尾）
                            if dataLine.hasPrefix("|") && dataLine.hasSuffix("|") && dataLine.count > 2 {
                                let row = parseTableRow(dataLine)
                                if !row.isEmpty {
                                    // 允许列数不完全匹配，但至少要有一列
                                    rows.append(row)
                                    j += 1
                                } else {
                                    // 如果解析失败，可能是表格结束了
                                    break
                                }
                            } else if dataLine.isEmpty {
                                // 空行，跳过
                                j += 1
                            } else {
                                // 非表格行，表格结束
                                break
                            }
                        }
                        
                        // 如果找到了表头、分隔行和数据行，创建表格
                        if !rows.isEmpty {
                            let table = MarkdownTable(headers: headers, rows: rows, alignments: alignments)
                            tables.append(table)
                            
                            // 用占位符替换表格行
                            let placeholder = "```TABLE_\(tables.count - 1)```"
                            // 替换从表头到最后一行的所有行
                            for k in (i..<j).reversed() {
                                processedLines.remove(at: k)
                            }
                            processedLines.insert(placeholder, at: i)
                            
                            // 重新构建文本
                            processedText = processedLines.joined(separator: "\n")
                            
                            // 更新行索引，跳过已处理的表格
                            i += 1
                            continue
                        }
                    }
                }
            }
            i += 1
        }
        
        content.tables = tables
        
        // 然后提取代码块（避免代码块中的内容被误解析）
        // 匹配 ```language\ncode\n``` 或 ```\ncode\n```
        let codeBlockPattern = "```(\\w+)?\\s*\\n([\\s\\S]*?)\\n```"
        var codeBlocks: [MarkdownCodeBlock] = []
        
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
            let nsString = processedText as NSString
            let matches = regex.matches(in: processedText, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // 反向遍历，从后往前提取，避免索引变化
            for match in matches.reversed() {
                if match.numberOfRanges >= 3 {
                    let languageRange = match.range(at: 1)
                    let codeRange = match.range(at: 2)
                    
                    if codeRange.location != NSNotFound {
                        var code = nsString.substring(with: codeRange)
                        // 移除末尾可能的换行符
                        code = code.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        let language = languageRange.location != NSNotFound && languageRange.length > 0 
                            ? nsString.substring(with: languageRange).trimmingCharacters(in: .whitespacesAndNewlines)
                            : nil
                        
                        codeBlocks.insert(MarkdownCodeBlock(code: code, language: language), at: 0)
                        
                        // 用占位符替换代码块
                        let placeholder = "```CODE_BLOCK_\(codeBlocks.count - 1)```"
                        processedText = (processedText as NSString).replacingCharacters(in: match.range, with: placeholder)
                    }
                }
            }
        }
        
        content.codeBlocks = codeBlocks
        
        // 匹配图片：![alt](url) 或 <img src="url" alt="alt" />
        let imagePatterns = [
            "!\\[([^\\]]*)\\]\\(([^\\)]+)\\)",  // ![alt](url)
            "<img[^>]+src=[\"']([^\"']+)[\"'][^>]*>",  // <img src="url" />
        ]
        
        // 匹配视频：<video src="url" /> 或 ![video](url) 或视频 URL
        let videoPatterns = [
            "<video[^>]+src=[\"']([^\"']+)[\"'][^>]*>",  // <video src="url" />
            "!\\[video\\]\\(([^\\)]+)\\)",  // ![video](url)
        ]
        
        // 提取图片
        for pattern in imagePatterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
            let nsString = markdown as NSString
            let matches = regex?.matches(in: markdown, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
            
            for match in matches {
                if match.numberOfRanges >= 3 {
                    let altRange = match.range(at: 1)
                    let urlRange = match.range(at: 2)
                    
                    if urlRange.location != NSNotFound {
                        let url = nsString.substring(with: urlRange)
                        let alt = altRange.location != NSNotFound ? nsString.substring(with: altRange) : nil
                        
                        // 检查是否是有效的图片 URL
                        if isValidImageURL(url) {
                            content.images.append(MarkdownMedia(
                                id: UUID(),
                                url: url,
                                alt: alt,
                                type: .image
                            ))
                        }
                    }
                } else if match.numberOfRanges >= 2 {
                    // 对于 <img> 标签，URL 在第一个捕获组
                    let urlRange = match.range(at: 1)
                    if urlRange.location != NSNotFound {
                        let url = nsString.substring(with: urlRange)
                        if isValidImageURL(url) {
                            content.images.append(MarkdownMedia(
                                id: UUID(),
                                url: url,
                                alt: nil,
                                type: .image
                            ))
                        }
                    }
                }
            }
        }
        
        // 提取视频
        for pattern in videoPatterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
            let nsString = markdown as NSString
            let matches = regex?.matches(in: markdown, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
            
            for match in matches {
                if match.numberOfRanges >= 2 {
                    let urlRange = match.range(at: 1)
                    if urlRange.location != NSNotFound {
                        let url = nsString.substring(with: urlRange)
                        if isValidVideoURL(url) {
                            content.videos.append(MarkdownMedia(
                                id: UUID(),
                                url: url,
                                alt: nil,
                                type: .video
                            ))
                        }
                    }
                }
            }
        }
        
        // 移除已提取的媒体标签和代码块占位符，保留纯文本
        // 使用反向遍历避免索引问题
        // 移除图片标记
        for pattern in imagePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsString = processedText as NSString
                let matches = regex.matches(in: processedText, options: [], range: NSRange(location: 0, length: nsString.length))
                
                // 反向遍历，从后往前移除，避免索引变化
                for match in matches.reversed() {
                    if match.range.location != NSNotFound {
                        processedText = (processedText as NSString).replacingCharacters(in: match.range, with: "")
                    }
                }
            }
        }
        
        // 移除视频标记
        for pattern in videoPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsString = processedText as NSString
                let matches = regex.matches(in: processedText, options: [], range: NSRange(location: 0, length: nsString.length))
                
                // 反向遍历，从后往前移除，避免索引变化
                for match in matches.reversed() {
                    if match.range.location != NSNotFound {
                        processedText = (processedText as NSString).replacingCharacters(in: match.range, with: "")
                    }
                }
            }
        }
        
        // 移除代码块占位符（代码块已经单独提取）
        for index in 0..<codeBlocks.count {
            let placeholder = "```CODE_BLOCK_\(index)```"
            processedText = processedText.replacingOccurrences(of: placeholder, with: "")
        }
        
        // 移除表格占位符（表格已经单独提取）
        for index in 0..<tables.count {
            let placeholder = "```TABLE_\(index)```"
            processedText = processedText.replacingOccurrences(of: placeholder, with: "")
        }
        
        // 智能添加换行，让文本更易读
        processedText = addSmartLineBreaks(to: processedText)
        
        content.text = processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return content
    }
    
    /// 智能添加换行，让 Markdown 文本更易读
    /// - Parameter text: 原始文本
    /// - Returns: 处理后的文本
    private static func addSmartLineBreaks(to text: String) -> String {
        var result = text
        
        // 简化处理：只在以下情况添加换行
        // 1. 表格开始前（| 开头的行）
        // 2. 中文句号（。）后面
        // 3. 加粗文本（**text**）前面
        
        // 1. 在表格开始前添加换行（匹配 | 开头的行）
        result = result.replacingOccurrences(
            of: "([^\\n])(\\n\\s*\\|)",
            with: "$1\n$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "([^\\n\\s])(\\s*\\|)",
            with: "$1\n$2",
            options: .regularExpression
        )
        
        // 2. 在中文句号后添加换行
        result = result.replacingOccurrences(
            of: "([。])([^\\n\\s])",
            with: "$1\n$2",
            options: .regularExpression
        )
        
        // 3. 在加粗文本前添加换行（匹配 **text** 或 __text__）
        result = result.replacingOccurrences(
            of: "([^\\n])(\\*\\*[^\\*\\n]+\\*\\*)",
            with: "$1\n$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "([^\\n])(__[^_\\n]+__)",
            with: "$1\n$2",
            options: .regularExpression
        )
        
        // 4. 清理多余的连续换行（保留两个换行作为段落分隔，但不要超过两个）
        result = result.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        
        return result
    }
    
    /// 检查是否是有效的图片 URL
    private static func isValidImageURL(_ url: String) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg"]
        let lowercased = url.lowercased()
        
        // 检查文件扩展名
        if imageExtensions.contains(where: { lowercased.hasSuffix(".\($0)") }) {
            return true
        }
        
        // 检查是否是 data URL (base64 图片)
        if lowercased.hasPrefix("data:image/") {
            return true
        }
        
        // 检查是否是 HTTP(S) URL
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return true
        }
        
        return false
    }
    
    /// 检查是否是有效的视频 URL
    private static func isValidVideoURL(_ url: String) -> Bool {
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "webm", "m4v"]
        let lowercased = url.lowercased()
        
        // 检查文件扩展名
        if videoExtensions.contains(where: { lowercased.hasSuffix(".\($0)") }) {
            return true
        }
        
        // 检查是否是 data URL (base64 视频)
        if lowercased.hasPrefix("data:video/") {
            return true
        }
        
        // 检查是否是 HTTP(S) URL
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return true
        }
        
        return false
    }
    
    /// 解析表格行，提取单元格
    private static func parseTableRow(_ row: String) -> [String] {
        // 移除首尾的 |，然后按 | 分割
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else {
            return []
        }
        
        let cells = trimmed.dropFirst().dropLast()
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        return cells.filter { !$0.isEmpty }
    }
    
    /// 解析表格对齐方式
    private static func parseTableAlignments(_ separatorLine: String, columnCount: Int) -> [MarkdownTable.TableAlignment] {
        var alignments: [MarkdownTable.TableAlignment] = []
        let trimmed = separatorLine.trimmingCharacters(in: .whitespaces)
        
        // 如果分隔行用 | 包裹，先解析单元格
        if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
            let cells = parseTableRow(separatorLine)
            for cell in cells.prefix(columnCount) {
                let cellTrimmed = cell.trimmingCharacters(in: .whitespaces)
                if cellTrimmed.hasPrefix(":") && cellTrimmed.hasSuffix(":") {
                    alignments.append(.center)
                } else if cellTrimmed.hasSuffix(":") {
                    alignments.append(.right)
                } else if cellTrimmed.hasPrefix(":") {
                    alignments.append(.left)
                } else {
                    alignments.append(.none)
                }
            }
        } else {
            // 如果分隔行没有 | 包裹（如 :---:---:），需要智能解析
            // 匹配模式：:---: (居中), :--- (左对齐), ---: (右对齐), --- (默认)
            // 改进的正则表达式，更准确地匹配对齐模式
            // 匹配 :---: 或 :--- 或 ---: 或 ---
            let alignmentPattern = "(:?-{2,}:?)"
            if let regex = try? NSRegularExpression(pattern: alignmentPattern, options: []) {
                let nsString = trimmed as NSString
                let matches = regex.matches(in: trimmed, options: [], range: NSRange(location: 0, length: nsString.length))
                
                for match in matches.prefix(columnCount) {
                    if match.range.location != NSNotFound {
                        let alignmentStr = nsString.substring(with: match.range)
                        let trimmedAlignment = alignmentStr.trimmingCharacters(in: .whitespaces)
                        
                        if trimmedAlignment.hasPrefix(":") && trimmedAlignment.hasSuffix(":") {
                            // :---: 格式，居中
                            alignments.append(.center)
                        } else if trimmedAlignment.hasSuffix(":") {
                            // ---: 格式，右对齐
                            alignments.append(.right)
                        } else if trimmedAlignment.hasPrefix(":") {
                            // :--- 格式，左对齐
                            alignments.append(.left)
                        } else {
                            // --- 格式，默认对齐
                            alignments.append(.none)
                        }
                    }
                }
            }
            
            // 如果正则表达式没有匹配到足够的对齐方式，使用默认值填充
            while alignments.count < columnCount {
                alignments.append(.none)
            }
        }
        
        // 如果对齐方式数量不足，用 .none 填充
        while alignments.count < columnCount {
            alignments.append(.none)
        }
        
        return alignments
    }
    
    /// 解析表格数据行
    private static func parseTableRows(_ rowsText: String) -> [[String]] {
        let lines = rowsText.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.hasPrefix("|") }
        
        return lines.map { parseTableRow($0) }
    }
}

