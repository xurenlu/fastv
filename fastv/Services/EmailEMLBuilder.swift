//
//  EmailEMLBuilder.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 构建 .eml 文件的工具类
enum EmailEMLBuilder {
    /// 从 EmailMessage 构建符合 RFC 822 格式的 .eml 文件内容
    static func buildEML(from message: EmailMessage) -> String {
        var lines: [String] = []
        
        // 邮件头
        lines.append("From: \(formatEmailAddress(message.from))")
        
        if !message.to.isEmpty {
            lines.append("To: \(formatEmailAddresses(message.to))")
        }
        
        if !message.cc.isEmpty {
            lines.append("Cc: \(formatEmailAddresses(message.cc))")
        }
        
        if !message.bcc.isEmpty {
            lines.append("Bcc: \(formatEmailAddresses(message.bcc))")
        }
        
        if !message.replyTo.isEmpty {
            lines.append("Reply-To: \(formatEmailAddresses(message.replyTo))")
        }
        
        if let messageId = message.messageId {
            lines.append("Message-ID: \(messageId)")
        }
        
        if let threadId = message.threadId {
            lines.append("In-Reply-To: \(threadId)")
        }
        
        // Subject（需要处理编码）
        let subject = encodeHeaderValue(message.subject)
        lines.append("Subject: \(subject)")
        
        // Date
        let dateString = formatRFC822Date(message.date)
        lines.append("Date: \(dateString)")
        
        // MIME Version
        lines.append("MIME-Version: 1.0")
        
        // Content-Type
        if message.htmlBody != nil && !message.htmlBody!.isEmpty {
            // 多部分邮件（HTML + 纯文本）
            let boundary = generateBoundary()
            lines.append("Content-Type: multipart/alternative; boundary=\"\(boundary)\"")
            lines.append("")
            lines.append("This is a multi-part message in MIME format.")
            lines.append("")
            
            // 纯文本部分
            if let textBody = message.textBody, !textBody.isEmpty {
                lines.append("--\(boundary)")
                lines.append("Content-Type: text/plain; charset=UTF-8")
                lines.append("Content-Transfer-Encoding: quoted-printable")
                lines.append("")
                lines.append(encodeQuotedPrintable(textBody))
                lines.append("")
            }
            
            // HTML 部分
            if let htmlBody = message.htmlBody, !htmlBody.isEmpty {
                lines.append("--\(boundary)")
                lines.append("Content-Type: text/html; charset=UTF-8")
                lines.append("Content-Transfer-Encoding: quoted-printable")
                lines.append("")
                lines.append(encodeQuotedPrintable(htmlBody))
                lines.append("")
            }
            
            // 结束边界
            lines.append("--\(boundary)--")
        } else if let textBody = message.textBody, !textBody.isEmpty {
            // 纯文本邮件
            lines.append("Content-Type: text/plain; charset=UTF-8")
            lines.append("Content-Transfer-Encoding: quoted-printable")
            lines.append("")
            lines.append(encodeQuotedPrintable(textBody))
        } else {
            // 空邮件
            lines.append("Content-Type: text/plain; charset=UTF-8")
            lines.append("")
        }
        
        return lines.joined(separator: "\r\n")
    }
    
    /// 格式化单个邮箱地址
    private static func formatEmailAddress(_ contact: EmailContact) -> String {
        if let name = contact.name, !name.isEmpty {
            return "\(encodeHeaderValue(name)) <\(contact.email)>"
        }
        return contact.email
    }
    
    /// 格式化多个邮箱地址
    private static func formatEmailAddresses(_ contacts: [EmailContact]) -> String {
        return contacts.map { formatEmailAddress($0) }.joined(separator: ", ")
    }
    
    /// 编码邮件头值（处理非 ASCII 字符）
    private static func encodeHeaderValue(_ value: String) -> String {
        // 检查是否包含非 ASCII 字符
        let needsEncoding = value.unicodeScalars.contains { $0.value > 127 }
        
        if !needsEncoding {
            return value
        }
        
        // 使用 RFC 2047 Base64 编码
        if let data = value.data(using: .utf8) {
            let base64 = data.base64EncodedString()
            return "=?UTF-8?B?\(base64)?="
        }
        
        return value
    }
    
    /// 格式化 RFC 822 日期
    private static func formatRFC822Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
    
    /// 生成 MIME 边界字符串
    private static func generateBoundary() -> String {
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return "----=_Part_\(uuid.prefix(16))"
    }
    
    /// 编码为 quoted-printable 格式
    private static func encodeQuotedPrintable(_ text: String) -> String {
        var result = ""
        var lineLength = 0
        let maxLineLength = 76
        
        for char in text {
            let scalar = char.unicodeScalars.first!
            let value = scalar.value
            
            // 可打印 ASCII 字符（除了 =）
            if value >= 33 && value <= 126 && value != 61 {
                if lineLength + 1 > maxLineLength {
                    result += "=\r\n"
                    lineLength = 0
                }
                result.append(char)
                lineLength += 1
            } else if value == 32 { // 空格
                if lineLength + 1 > maxLineLength {
                    result += "=\r\n"
                    lineLength = 0
                }
                result.append(" ")
                lineLength += 1
            } else if value == 9 { // Tab
                if lineLength + 1 > maxLineLength {
                    result += "=\r\n"
                    lineLength = 0
                }
                result.append("\t")
                lineLength += 1
            } else if value == 13 || value == 10 { // 换行
                result.append(char)
                lineLength = 0
            } else {
                // 需要编码的字符
                if let data = String(char).data(using: .utf8) {
                    let hex = data.map { String(format: "=%02X", $0) }.joined()
                    if lineLength + hex.count > maxLineLength {
                        result += "=\r\n"
                        lineLength = 0
                    }
                    result += hex
                    lineLength += hex.count
                }
            }
        }
        
        return result
    }
}

