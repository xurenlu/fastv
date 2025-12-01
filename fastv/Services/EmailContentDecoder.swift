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
    static func decodeRFC2047String(_ string: String) -> String {
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
    
    /// 解析 MIME 邮件正文，返回纯文本与 HTML
    static func parseBody(data: Data) -> EmailBodyContent {
        guard var raw = String(data: data, encoding: .utf8) ??
                        String(data: data, encoding: .isoLatin1) else {
            return EmailBodyContent(textBody: nil, htmlBody: nil)
        }
        
        // 标准化换行
        raw = raw.replacingOccurrences(of: "\r\n", with: "\n")
        
        let components = raw.components(separatedBy: "\n\n")
        guard components.count >= 2 else {
            return EmailBodyContent(textBody: raw.trimmingCharacters(in: .whitespacesAndNewlines), htmlBody: nil)
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
                return EmailBodyContent(textBody: nil, htmlBody: decoded)
            } else {
                return EmailBodyContent(textBody: decoded, htmlBody: nil)
            }
        }
    }
    
    // MARK: - Private helpers
    
    private static func parseMultipart(body: String, headers: [String: String]) -> EmailBodyContent {
        guard let boundary = extractBoundary(from: headers["content-type"]) else {
            return EmailBodyContent(textBody: nil, htmlBody: nil)
        }
        
        let delimiter = "--\(boundary)"
        let closingDelimiter = "--\(boundary)--"
        let segments = body.components(separatedBy: delimiter)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "--" && $0 != closingDelimiter }
        
        var textBody: String?
        var htmlBody: String?
        
        for segment in segments {
            let parts = segment.components(separatedBy: "\n\n")
            guard parts.count >= 2 else { continue }
            let headerString = parts.first ?? ""
            let bodyString = parts.dropFirst().joined(separator: "\n\n")
            let partHeaders = parseHeaders(headerString)
            let partContentType = partHeaders["content-type"]?.lowercased() ?? "text/plain"
            let charset = extractCharset(from: partHeaders["content-type"])
            let encoding = partHeaders["content-transfer-encoding"]?.lowercased()
            
            if partContentType.contains("multipart/") {
                let nested = parseMultipart(body: bodyString, headers: partHeaders)
                if textBody == nil { textBody = nested.textBody }
                if htmlBody == nil { htmlBody = nested.htmlBody }
                continue
            }
            
            let decoded = decodeBody(bodyString, encoding: encoding, charset: charset)
            
            if partContentType.contains("text/html") {
                if htmlBody == nil { htmlBody = decoded }
            } else if partContentType.contains("text/plain") {
                if textBody == nil { textBody = decoded }
            }
        }
        
        return EmailBodyContent(textBody: textBody, htmlBody: htmlBody)
    }
    
    private static func parseHeaders(_ headerString: String) -> [String: String] {
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
    
    private static func extractBoundary(from contentType: String?) -> String? {
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
    
    private static func extractCharset(from contentType: String?) -> String {
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
    
    private static func decodeBody(_ body: String, encoding: String?, charset: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.replacingOccurrences(of: "\n", with: "")
        
        if let encoding {
            switch encoding {
            case "base64":
                return decodeBase64(normalized, charset: charset) ?? trimmed
            case "quoted-printable":
                return decodeQuotedPrintable(trimmed, charset: charset) ?? trimmed
            default:
                break
            }
        }
        
        // 默认按照 charset 解析
        let encoding = stringEncoding(for: charset)
        if let data = trimmed.data(using: .isoLatin1),
           let decoded = String(data: data, encoding: encoding) {
            return decoded
        }
        return trimmed
    }
    
    private static func decodeBase64(_ value: String, charset: String) -> String? {
        let sanitized = value.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: sanitized) else { return nil }
        let encoding = stringEncoding(for: charset)
        return String(data: data, encoding: encoding)
    }
    
    private static func decodeQuotedPrintable(_ value: String, charset: String) -> String? {
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
    
    private static func stringEncoding(for charset: String) -> String.Encoding {
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


