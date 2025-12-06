//
//  EmailContentDecoder.swift
//  fastv
//
//  Created by rocky on 2025/12/01.
//

import Foundation
import CoreFoundation
import AppKit

/// 解析后的邮件正文内容
struct EmailBodyContent {
    let textBody: String?
    let htmlBody: String?
    let containsRemoteResources: Bool
    
    /// 生成用于列表预览的文本
    var previewText: String {
        let base = textBody ??
                   htmlBody?.strippingHTML() ??
                   ""
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(200))
    }
}

/// MIME / 邮件内容解码工具
enum EmailContentDecoder {
    /// 解码 RFC 2047 编码头（=?UTF-8?B?...?=）
    nonisolated static func decodeRFC2047String(_ string: String) -> String {
        let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]+)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return string
        }
        
        let nsString = string as NSString
        let matches = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else {
            return string
        }
        
        var decoded = string
        for match in matches.reversed() {
            guard match.numberOfRanges == 4 else { continue }
            let charsetRange = match.range(at: 1)
            let encodingRange = match.range(at: 2)
            let valueRange = match.range(at: 3)
            
            let charset = nsString.substring(with: charsetRange)
            let encoding = nsString.substring(with: encodingRange).lowercased()
            let value = nsString.substring(with: valueRange)
            
            let decodedValue: String?
            if encoding == "b" {
                decodedValue = decodeBase64(value, charset: charset)
            } else {
                decodedValue = decodeQuotedPrintable(value, charset: charset)
            }
            
            if let decodedValue {
                decoded = (decoded as NSString).replacingCharacters(in: match.range, with: decodedValue)
            }
        }
        return decoded
    }
    
    /// 尝试自动解码可能是 base64 编码的文本（用于显示时的备用解码）
    /// 性能优化：只在必要时解码（快速检查是否已包含中文字符或明显不是 base64）
    nonisolated static func tryDecodeBase64TextIfNeeded(_ text: String) -> String {
        // 快速检查：如果文本很短，不需要解码
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return text }
        
        // 快速检查：如果包含中文字符，很可能已经解码过了，直接返回
        let quickCheckSize = min(100, trimmed.count)
        let quickCheck = String(trimmed.prefix(quickCheckSize))
        if quickCheck.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            return text
        }
        
        // 快速检查：如果包含 HTML 标签，说明内容已经是正常文本，不需要解码
        // 这可以避免将已解码的 HTML 内容错误地再次 base64 解码
        if containsHTMLTags(quickCheck) {
            return text
        }
        
        // 快速检查：如果包含明显的非 base64 字符（如常见标点），很可能不是 base64
        // 使用 Unicode 标量值来避免字符串中的引号问题
        let commonPunctuationChars: [Unicode.Scalar] = [
            "\u{FF0C}", // ，
            "\u{3002}", // 。
            "\u{FF01}", // ！
            "\u{FF1F}", // ？
            "\u{FF1B}", // ；
            "\u{FF1A}", // ：
            "\u{3001}", // 、
            "\u{201C}", // "
            "\u{201D}", // "
            "\u{2018}", // '
            "\u{2019}", // '
            "\u{FF08}", // （
            "\u{FF09}", // ）
            "\u{3010}", // 【
            "\u{3011}", // 】
            "\u{300A}", // 《
            "\u{300B}"  // 》
        ]
        let commonPunctuation = CharacterSet(commonPunctuationChars)
        if quickCheck.unicodeScalars.contains(where: { commonPunctuation.contains($0) }) {
            return text
        }
        
        // 如果快速检查通过，才进行完整的 base64 检测和解码
        return tryDecodeBase64Text(text)
    }
    
    /// 检测文本是否包含 HTML 标签（用于快速判断内容是否已经是正常文本）
    nonisolated private static func containsHTMLTags(_ text: String) -> Bool {
        // 检测常见的 HTML 标签模式
        let lowercased = text.lowercased()
        let commonTags = ["<!doctype", "<html", "<head", "<body", "<div", "<p>", "<br", "<table", "<span", "<img", "<a ", "</"]
        for tag in commonTags {
            if lowercased.contains(tag) {
                return true
            }
        }
        return false
    }
    
    /// 尝试自动解码可能是 base64 编码的文本（用于显示时的备用解码）
    /// 性能优化：只检查前 1024 个字符来判断是否是 base64，避免处理大文本
    nonisolated static func tryDecodeBase64Text(_ text: String) -> String {
        // 快速检查：如果文本很短或已经包含中文字符，很可能不是 base64
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return text }
        
        // 快速检查：如果包含中文字符，很可能已经解码过了
        let sampleSize = min(200, trimmed.count)
        let sample = String(trimmed.prefix(sampleSize))
        if sample.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            return text
        }
        
        // 快速检查：如果包含 HTML 标签，说明内容已经是正常文本，不需要解码
        if containsHTMLTags(sample) {
            return text
        }
        
        // 只检查前 1024 个字符来判断是否是 base64（性能优化）
        let checkSize = min(1024, trimmed.count)
        let checkText = String(trimmed.prefix(checkSize))
        
        // 先尝试快速检测是否是 base64
        if isLikelyBase64Fast(checkText) {
            let normalized = trimmed.replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: " ", with: "")
            
            // 只解码前 2048 个字符来测试编码（性能优化）
            let decodeSampleSize = min(2048, normalized.count)
            let decodeSample = String(normalized.prefix(decodeSampleSize))
            
            // 尝试多种字符编码，优先尝试 GBK（因为很多中文邮件使用 GBK）
            let charsets = ["gbk", "gb2312", "gb18030", "utf-8", "big5", "iso-8859-1"]
            for charset in charsets {
                if let decodedSample = decodeBase64(decodeSample, charset: charset), !decodedSample.isEmpty {
                    // 只验证前 512 个字符（性能优化）
                    let validationSize = min(512, decodedSample.count)
                    let validationText = String(decodedSample.prefix(validationSize))
                    if isValidDecodedTextFast(validationText) {
                        // 验证通过，解码完整文本
                        if let decoded = decodeBase64(normalized, charset: charset), !decoded.isEmpty {
                            return decoded
                        }
                    }
                }
            }
        }
        
        return text
    }
    
    /// 解析 MIME 邮件正文，返回纯文本与 HTML
    nonisolated static func parseBody(data: Data) -> EmailBodyContent {
        guard var raw = String(data: data, encoding: .utf8) ??
                        String(data: data, encoding: .isoLatin1) else {
            return EmailBodyContent(textBody: nil, htmlBody: nil, containsRemoteResources: false)
        }
        
        // 标准化换行
        raw = raw.replacingOccurrences(of: "\r\n", with: "\n")
        
        let components = raw.components(separatedBy: "\n\n")
        guard components.count >= 2 else {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return EmailBodyContent(textBody: text, htmlBody: nil, containsRemoteResources: false)
        }
        
        let headerString = components.first ?? ""
        let bodyString = components.dropFirst().joined(separator: "\n\n")
        let headers = parseHeaders(headerString)
        let contentType = headers["content-type"]?.lowercased() ?? "text/plain"
        
        if contentType.contains("multipart/") {
            return parseMultipart(body: bodyString, headers: headers)
        } else {
            let charset = extractCharset(from: headers["content-type"])
            let encoding = headers["content-transfer-encoding"]?.lowercased()
            let decoded = decodeBody(bodyString, encoding: encoding, charset: charset)
            
            if contentType.contains("text/html") {
                let hasRemote = containsRemoteResources(html: decoded)
                return EmailBodyContent(textBody: nil, htmlBody: decoded, containsRemoteResources: hasRemote)
            } else {
                return EmailBodyContent(textBody: decoded, htmlBody: nil, containsRemoteResources: false)
            }
        }
    }
    
    // MARK: - Private helpers
    
    nonisolated private static func parseMultipart(body: String, headers: [String: String]) -> EmailBodyContent {
        guard let boundary = extractBoundary(from: headers["content-type"]) else {
            return EmailBodyContent(textBody: nil, htmlBody: nil, containsRemoteResources: false)
        }
        
        let delimiter = "--\(boundary)"
        let closingDelimiter = "--\(boundary)--"
        let segments = body.components(separatedBy: delimiter)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "--" && $0 != closingDelimiter }
        
        var textBody: String?
        var htmlBody: String?
        var hasRemote = false
        
        for segment in segments {
            // 查找第一个空行来分离头部和正文
            let lines = segment.components(separatedBy: "\n")
            var headerLines: [String] = []
            var bodyLines: [String] = []
            var foundEmptyLine = false
            
            for line in lines {
                if !foundEmptyLine && (line.trimmingCharacters(in: .whitespaces).isEmpty || (!line.hasPrefix(" ") && !line.hasPrefix("\t") && line.contains(":"))) {
                    if line.trimmingCharacters(in: .whitespaces).isEmpty {
                        foundEmptyLine = true
                        continue
                    }
                    headerLines.append(line)
                } else {
                    if foundEmptyLine || headerLines.isEmpty {
                        foundEmptyLine = true
                        bodyLines.append(line)
                    } else {
                        headerLines.append(line)
                    }
                }
            }
            
            // 如果没有找到空行，尝试用 "\n\n" 分割
            if headerLines.isEmpty && bodyLines.isEmpty {
                let parts = segment.components(separatedBy: "\n\n")
                if parts.count >= 2 {
                    headerLines = parts.first?.components(separatedBy: "\n") ?? []
                    bodyLines = parts.dropFirst().joined(separator: "\n\n").components(separatedBy: "\n")
                } else {
                    continue
                }
            }
            
            let headerString = headerLines.joined(separator: "\n")
            let bodyString = bodyLines.joined(separator: "\n")
            let partHeaders = parseHeaders(headerString)
            let partContentType = partHeaders["content-type"]?.lowercased() ?? "text/plain"
            let charset = extractCharset(from: partHeaders["content-type"])
            let encoding = partHeaders["content-transfer-encoding"]?.lowercased()
            
            if partContentType.contains("multipart/") {
                let nested = parseMultipart(body: bodyString, headers: partHeaders)
                if textBody == nil { textBody = nested.textBody }
                if htmlBody == nil { htmlBody = nested.htmlBody }
                hasRemote = hasRemote || nested.containsRemoteResources
                continue
            }
            
            let decoded = decodeBody(bodyString, encoding: encoding, charset: charset)
            
            if partContentType.contains("text/html") {
                if htmlBody == nil {
                    htmlBody = decoded
                    hasRemote = hasRemote || containsRemoteResources(html: decoded)
                }
            } else if partContentType.contains("text/plain") {
                if textBody == nil { textBody = decoded }
            }
        }
        
        return EmailBodyContent(textBody: textBody, htmlBody: htmlBody, containsRemoteResources: hasRemote)
    }
    
    /// 检测 HTML 中是否包含远程资源
    nonisolated private static func containsRemoteResources(html: String) -> Bool {
        let lowercased = html.lowercased()
        // 检测外部图片、CSS、脚本等
        return lowercased.contains("http://") || lowercased.contains("https://") ||
               lowercased.contains("src=\"//") || lowercased.contains("href=\"//")
    }
    
    nonisolated private static func parseHeaders(_ headerString: String) -> [String: String] {
        var headers: [String: String] = [:]
        var currentKey: String?
        var currentValue = ""
        
        let lines = headerString.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix(" ") || line.hasPrefix("\t"), let key = currentKey {
                currentValue += line.trimmingCharacters(in: .whitespaces)
                headers[key] = currentValue
            } else if let separatorRange = line.range(of: ":") {
                if let key = currentKey {
                    headers[key] = currentValue
                }
                currentKey = String(line[..<separatorRange.lowerBound]).lowercased()
                currentValue = line[separatorRange.upperBound...].trimmingCharacters(in: .whitespaces)
            }
        }
        
        if let key = currentKey {
            headers[key] = currentValue
        }
        return headers
    }
    
    nonisolated private static func extractBoundary(from contentType: String?) -> String? {
        guard let contentType else { return nil }
        let pattern = #"boundary="?([^";]+)"?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(location: 0, length: (contentType as NSString).length)
        guard let match = regex.firstMatch(in: contentType, options: [], range: range),
              match.numberOfRanges == 2 else {
            return nil
        }
        return (contentType as NSString).substring(with: match.range(at: 1))
    }
    
    nonisolated private static func extractCharset(from contentType: String?) -> String {
        guard let contentType else { return "utf-8" }
        let pattern = #"charset="?([^";]+)"?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return "utf-8"
        }
        let range = NSRange(location: 0, length: (contentType as NSString).length)
        guard let match = regex.firstMatch(in: contentType, options: [], range: range),
              match.numberOfRanges == 2 else {
            return "utf-8"
        }
        return (contentType as NSString).substring(with: match.range(at: 1))
    }
    
    nonisolated private static func decodeBody(_ body: String, encoding: String?, charset: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // 对于 base64，需要移除所有空白字符（包括换行、空格、制表符）
        let normalized = trimmed.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
        
        if let encoding {
            switch encoding {
            case "base64":
                // 优先使用邮件头中指定的编码
                if let decoded = decodeBase64(normalized, charset: charset) {
                    // 快速验证解码结果（只检查前 512 字符）
                    let validationSize = min(512, decoded.count)
                    let validationText = String(decoded.prefix(validationSize))
                    if isValidDecodedTextFast(validationText) {
                        return decoded
                    }
                }
                // 如果指定编码失败，尝试其他编码（但优先使用指定的）
                let fallbackCharsets = ["utf-8", "gbk", "gb2312", "gb18030", "big5", charset]
                for testCharset in fallbackCharsets {
                    if let decoded = decodeBase64(normalized, charset: testCharset), !decoded.isEmpty {
                        let validationSize = min(512, decoded.count)
                        let validationText = String(decoded.prefix(validationSize))
                        if isValidDecodedTextFast(validationText) {
                            return decoded
                        }
                    }
                }
                // 如果所有编码验证都失败，但解码成功，仍然返回解码结果（可能是特殊格式）
                if let decoded = decodeBase64(normalized, charset: "utf-8"), !decoded.isEmpty {
                    return decoded
                }
                break
            case "quoted-printable":
                return decodeQuotedPrintable(trimmed, charset: charset) ?? trimmed
            default:
                break
            }
        }
        
        // 自动检测：如果内容看起来像 base64 编码，尝试解码
        // 只检查前 2048 字符来判断（性能优化，增加检测范围）
        let checkSize = min(2048, trimmed.count)
        let checkText = String(trimmed.prefix(checkSize))
        
        if isLikelyBase64Fast(checkText) {
            // 尝试多种字符编码，优先使用邮件头中指定的编码
            let charsets = [charset, "utf-8", "gbk", "gb2312", "gb18030", "big5", "iso-8859-1"]
            for testCharset in charsets {
                if let decoded = decodeBase64(normalized, charset: testCharset), !decoded.isEmpty {
                    // 只验证前 512 字符（性能优化）
                    let validationSize = min(512, decoded.count)
                    let validationText = String(decoded.prefix(validationSize))
                    if isValidDecodedTextFast(validationText) {
                        return decoded
                    }
                }
            }
            // 如果验证失败但解码成功，仍然返回解码结果（可能是特殊格式）
            if let decoded = decodeBase64(normalized, charset: "utf-8"), !decoded.isEmpty {
                return decoded
            }
        }
        
        // 尝试多种字符编码自动检测（用于解决乱码问题）
        // 性能优化：只检查前 2048 字节来测试编码
        let testSize = min(2048, trimmed.count)
        let testText = String(trimmed.prefix(testSize))
        let testCharsets = [charset, "utf-8", "gbk", "gb2312", "gb18030", "big5", "iso-8859-1", "windows-1252"]
        var bestResult: (text: String, score: Double)? = nil
        
        for testCharset in testCharsets {
            let stringEncoding = stringEncoding(for: testCharset)
            // 先尝试将字符串作为 ISO-8859-1 字节序列，然后用目标编码解析
            if let data = testText.data(using: .isoLatin1),
               let decoded = String(data: data, encoding: stringEncoding),
               !decoded.isEmpty {
                // 只计算前 512 字符的分数（性能优化）
                let scoreSize = min(512, decoded.count)
                let scoreText = String(decoded.prefix(scoreSize))
                let score = calculateDecodingScore(scoreText)
                if let currentBest = bestResult {
                    if score > currentBest.score {
                        // 如果这个编码更好，解码完整文本
                        if let fullData = trimmed.data(using: .isoLatin1),
                           let fullDecoded = String(data: fullData, encoding: stringEncoding) {
                            bestResult = (fullDecoded, score)
                        }
                    }
                } else {
                    // 解码完整文本
                    if let fullData = trimmed.data(using: .isoLatin1),
                       let fullDecoded = String(data: fullData, encoding: stringEncoding) {
                        bestResult = (fullDecoded, score)
                    }
                }
            }
        }
        
        // 如果找到了合理的解码结果，返回它
        if let best = bestResult, best.score > 0.3 {
            return best.text
        }
        
        // 如果所有编码都失败，返回原始文本
        return trimmed
    }
    
    /// 计算解码结果的合理性分数（0.0 - 1.0）
    /// 性能优化：只检查前 N 个字符来计算分数
    nonisolated private static func calculateDecodingScore(_ text: String) -> Double {
        guard !text.isEmpty else { return 0.0 }
        
        // 只检查前 512 个字符来计算分数（性能优化）
        let checkSize = min(512, text.count)
        let checkText = String(text.prefix(checkSize))
        
        var printableCount = 0
        var chineseCharCount = 0
        var asciiCount = 0
        var controlCharCount = 0
        
        let printableChars = CharacterSet.alphanumerics
            .union(.punctuationCharacters)
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        
        for scalar in checkText.unicodeScalars {
            if printableChars.contains(scalar) {
                printableCount += 1
                
                // 检测中文字符（CJK统一汉字）
                if (0x4E00...0x9FFF).contains(scalar.value) ||
                   (0x3400...0x4DBF).contains(scalar.value) ||
                   (0x20000...0x2A6DF).contains(scalar.value) {
                    chineseCharCount += 1
                }
                
                // 检测 ASCII 字符
                if scalar.value < 128 {
                    asciiCount += 1
                }
            } else if CharacterSet.controlCharacters.contains(scalar) {
                controlCharCount += 1
            }
        }
        
        let total = checkText.unicodeScalars.count
        guard total > 0 else { return 0.0 }
        
        let printableRatio = Double(printableCount) / Double(total)
        let chineseRatio = Double(chineseCharCount) / Double(total)
        let controlRatio = Double(controlCharCount) / Double(total)
        
        // 基础分数：可打印字符占比
        var score = printableRatio
        
        // 如果有中文字符，增加分数（说明可能是中文编码）
        if chineseCharCount > 0 {
            score += chineseRatio * 0.3
        }
        
        // 控制字符过多会降低分数
        if controlRatio > 0.1 {
            score *= (1.0 - controlRatio)
        }
        
        // 如果全是 ASCII 但文本很长，可能是编码错误，稍微降低分数
        if asciiCount == printableCount && total > 100 && chineseCharCount == 0 {
            score *= 0.8
        }
        
        return min(score, 1.0)
    }
    
    nonisolated private static func decodeBase64(_ value: String, charset: String) -> String? {
        let sanitized = value.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard let data = Data(base64Encoded: sanitized, options: .ignoreUnknownCharacters) else { return nil }
        let encoding = stringEncoding(for: charset)
        return String(data: data, encoding: encoding)
    }
    
    /// 检测字符串是否可能是 base64 编码（完整检查）
    nonisolated private static func isLikelyBase64(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return false }
        
        // Base64 字符集：A-Z, a-z, 0-9, +, /, = (填充)
        let base64Chars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        let whitespace = CharacterSet.whitespacesAndNewlines
        
        // 移除空白字符后检查
        let cleaned = trimmed.components(separatedBy: whitespace).joined()
        guard cleaned.count >= 20 else { return false }
        
        // 检查是否主要由 base64 字符组成（至少 75%）
        let base64Only = cleaned.unicodeScalars.filter { base64Chars.contains($0) }
        let ratio = Double(base64Only.count) / Double(max(cleaned.unicodeScalars.count, 1))
        
        return ratio >= 0.75 && cleaned.count >= 20
    }
    
    /// 快速检测字符串是否可能是 base64 编码（只检查前 N 个字符，性能优化）
    nonisolated private static func isLikelyBase64Fast(_ text: String) -> Bool {
        guard text.count >= 20 else { return false }
        
        // Base64 字符集
        let base64Chars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        let whitespace = CharacterSet.whitespacesAndNewlines
        
        // 只检查前 512 个字符（性能优化）
        let checkSize = min(512, text.count)
        let checkText = String(text.prefix(checkSize))
        
        // 快速排除：如果包含 HTML 标签特征字符（<, >, "），很可能不是 base64
        // 这些字符不在 base64 字符集中，且在 HTML 中非常常见
        let htmlIndicators: [Character] = ["<", ">"]
        for indicator in htmlIndicators {
            if checkText.contains(indicator) {
                return false
            }
        }
        
        // 移除空白字符后检查
        let cleaned = checkText.components(separatedBy: whitespace).joined()
        guard cleaned.count >= 20 else { return false }
        
        // 检查是否主要由 base64 字符组成（至少 75%）
        var base64Count = 0
        var totalCount = 0
        for scalar in cleaned.unicodeScalars {
            totalCount += 1
            if base64Chars.contains(scalar) {
                base64Count += 1
            }
        }
        
        guard totalCount > 0 else { return false }
        let ratio = Double(base64Count) / Double(totalCount)
        return ratio >= 0.75 && cleaned.count >= 20
    }
    
    /// 验证解码后的文本是否合理（包含可打印字符，不是乱码）
    nonisolated private static func isValidDecodedText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        
        // 检查是否包含足够的可打印字符（至少 40%，降低阈值以支持更多情况）
        let printableChars = CharacterSet.alphanumerics
            .union(.punctuationCharacters)
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        let whitespaceChars = CharacterSet.whitespacesAndNewlines
        var printableCount = 0
        var chineseCharCount = 0
        var controlCharCount = 0
        
        for scalar in text.unicodeScalars {
            if printableChars.contains(scalar) || whitespaceChars.contains(scalar) {
                printableCount += 1
                // 检测中文字符（CJK统一汉字）
                if (0x4E00...0x9FFF).contains(scalar.value) ||
                   (0x3400...0x4DBF).contains(scalar.value) ||
                   (0x20000...0x2A6DF).contains(scalar.value) {
                    chineseCharCount += 1
                }
            } else if CharacterSet.controlCharacters.contains(scalar) && scalar != "\n" && scalar != "\r" && scalar != "\t" {
                controlCharCount += 1
            }
        }
        
        let total = text.unicodeScalars.count
        let printableRatio = Double(printableCount) / Double(max(total, 1))
        let controlRatio = Double(controlCharCount) / Double(max(total, 1))
        
        // 如果可打印字符占比超过 40%，且控制字符占比不超过 20%，认为是有效文本
        if printableRatio >= 0.4 && controlRatio <= 0.2 {
            return true
        }
        
        // 如果包含中文字符，即使可打印字符比例稍低也认为是有效的（中文邮件常见）
        if chineseCharCount > 0 && printableRatio >= 0.3 && controlRatio <= 0.25 {
            return true
        }
        
        // 如果文本很短但全是可打印字符，也认为是有效的
        if text.count <= 100 && printableCount == total {
            return true
        }
        
        return false
    }
    
    /// 快速验证解码后的文本是否合理（只检查前 N 个字符，性能优化）
    nonisolated private static func isValidDecodedTextFast(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        
        // 只检查前 512 个字符（性能优化）
        let checkSize = min(512, text.count)
        let checkText = String(text.prefix(checkSize))
        
        let printableChars = CharacterSet.alphanumerics
            .union(.punctuationCharacters)
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        let whitespaceChars = CharacterSet.whitespacesAndNewlines
        var printableCount = 0
        var chineseCharCount = 0
        var controlCharCount = 0
        
        for scalar in checkText.unicodeScalars {
            if printableChars.contains(scalar) || whitespaceChars.contains(scalar) {
                printableCount += 1
                // 检测中文字符（CJK统一汉字）
                if (0x4E00...0x9FFF).contains(scalar.value) ||
                   (0x3400...0x4DBF).contains(scalar.value) ||
                   (0x20000...0x2A6DF).contains(scalar.value) {
                    chineseCharCount += 1
                }
            } else if CharacterSet.controlCharacters.contains(scalar) && scalar != "\n" && scalar != "\r" && scalar != "\t" {
                controlCharCount += 1
            }
        }
        
        let total = checkText.unicodeScalars.count
        guard total > 0 else { return false }
        
        let printableRatio = Double(printableCount) / Double(total)
        let controlRatio = Double(controlCharCount) / Double(total)
        
        // 如果可打印字符占比超过 40%，且控制字符占比不超过 20%，认为是有效文本
        if printableRatio >= 0.4 && controlRatio <= 0.2 {
            return true
        }
        
        // 如果包含中文字符，即使可打印字符比例稍低也认为是有效的（中文邮件常见）
        if chineseCharCount > 0 && printableRatio >= 0.3 && controlRatio <= 0.25 {
            return true
        }
        
        // 如果文本很短但全是可打印字符，也认为是有效的
        if checkText.count <= 100 && printableCount == total {
            return true
        }
        
        return false
    }
    
    nonisolated private static func decodeQuotedPrintable(_ value: String, charset: String) -> String? {
        var cleaned = value.replacingOccurrences(of: "=\r\n", with: "")
        cleaned = cleaned.replacingOccurrences(of: "=\n", with: "")
        
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        
        while index < cleaned.endIndex {
            let char = cleaned[index]
            if char == "=" {
                let nextIndex = cleaned.index(index, offsetBy: 1, limitedBy: cleaned.endIndex)
                let nextNextIndex = cleaned.index(index, offsetBy: 2, limitedBy: cleaned.endIndex)
                if let nextIndex, let nextNextIndex,
                   nextNextIndex < cleaned.endIndex {
                    let hex = String(cleaned[nextIndex...nextNextIndex])
                    if let byte = UInt8(hex, radix: 16) {
                        bytes.append(byte)
                        index = cleaned.index(index, offsetBy: 3)
                        continue
                    }
                }
            }
            if let scalar = char.unicodeScalars.first {
                bytes.append(UInt8(scalar.value & 0xFF))
            }
            index = cleaned.index(after: index)
        }
        
        let data = Data(bytes)
        let encoding = stringEncoding(for: charset)
        return String(data: data, encoding: encoding)
    }
    
    nonisolated private static func stringEncoding(for charset: String) -> String.Encoding {
        let lowercased = charset.lowercased()
        if lowercased == "gb2312" {
            return .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue)))
        }
        if lowercased == "gbk" {
            return .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        if cfEncoding != kCFStringEncodingInvalidId {
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            return String.Encoding(rawValue: nsEncoding)
        }
        return .utf8
    }
}

// MARK: - String helpers

extension String {
    /// 移除简单 HTML 标签
    func strippingHTML() -> String {
        guard let data = data(using: .utf8) else { return self }
        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributed.string
        }
        return replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}


