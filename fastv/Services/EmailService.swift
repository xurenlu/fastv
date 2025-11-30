//
//  EmailService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 邮件服务错误
enum EmailServiceError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case invalidConfiguration(String)
    case networkError(Error)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "连接失败: \(message)"
        case .authenticationFailed(let message):
            return "认证失败: \(message)"
        case .invalidConfiguration(let message):
            return "配置无效: \(message)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .parseError(let message):
            return "解析错误: \(message)"
        }
    }
}

/// 邮件服务
/// 使用 LibEtPan C 库实现 IMAP/SMTP 协议
@MainActor
class EmailService {
    static let shared = EmailService()
    
    private var imapSessions: [UUID: LibEtPanIMAPSession] = [:] // accountId -> IMAP Session
    private var smtpSessions: [UUID: LibEtPanSMTPSession] = [:] // accountId -> SMTP Session
    
    private init() {}
    
    // MARK: - Helper Methods
    
    /// 将 EmailEncryption 转换为 LibEtPan 需要的字符串格式
    private func encryptionString(from encryption: EmailEncryption) -> String {
        switch encryption {
        case .ssl:
            return "ssl"
        case .startTLS:
            return "startTLS"
        case .none:
            return "none"
        }
    }
    
    // MARK: - Connection Testing
    
    /// 测试账号连接
    func testConnection(account: EmailAccount, password: String) async throws -> Bool {
        // 验证基本配置
        guard !account.imapHost.isEmpty,
              !account.smtpHost.isEmpty,
              !password.isEmpty else {
            throw EmailServiceError.invalidConfiguration("服务器地址或密码不能为空")
        }
        
        // 测试 IMAP 连接
        guard let imap = LibEtPanIMAPSession(
            host: account.imapHost,
            port: account.imapPort,
            encryption: encryptionString(from: account.imapEncryption),
            username: account.emailAddress,
            password: password
        ) else {
            throw EmailServiceError.connectionFailed("无法创建 IMAP 会话")
        }
        
        do {
            try imap.connect()
        } catch {
            imap.disconnect()
            throw EmailServiceError.connectionFailed(error.localizedDescription)
        }
        
        do {
            try imap.login()
        } catch {
            imap.disconnect()
            throw EmailServiceError.authenticationFailed(error.localizedDescription)
        }
        
        imap.disconnect() // Disconnect after testing
        return true
    }
    
    // MARK: - IMAP Operations
    
    /// 获取或创建 IMAP 会话
    private func getOrCreateIMAPSession(account: EmailAccount) throws -> LibEtPanIMAPSession {
        if let existing = imapSessions[account.id] {
            return existing
        }
        
        guard let password = try EmailCredentialStore.shared.getPassword(accountId: account.id) else {
            throw EmailServiceError.authenticationFailed("密码未找到")
        }
        
        guard let imap = LibEtPanIMAPSession(
            host: account.imapHost,
            port: account.imapPort,
            encryption: encryptionString(from: account.imapEncryption),
            username: account.emailAddress,
            password: password
        ) else {
            throw EmailServiceError.connectionFailed("无法创建 IMAP 会话")
        }
        
        do {
            try imap.connect()
        } catch {
            throw EmailServiceError.connectionFailed(error.localizedDescription)
        }
        
        do {
            try imap.login()
        } catch {
            imap.disconnect()
            throw EmailServiceError.authenticationFailed(error.localizedDescription)
        }
        
        imapSessions[account.id] = imap
        return imap
    }
    
    /// 同步邮件（增量同步）
    func syncMessages(account: EmailAccount, folder: EmailFolder, since: Date? = nil) async throws -> [EmailMessage] {
        let imap = try getOrCreateIMAPSession(account: account)
        
        do {
            try imap.selectFolder(folder.name)
        } catch {
            throw EmailServiceError.connectionFailed(error.localizedDescription)
        }
        
        // 获取邮件列表（从 UID 1 开始，0 表示到最新）
        let messageUIDs: [Any]
        do {
            let result = try imap.fetchMessages(fromUID: 1, toUID: 0)
            messageUIDs = result as? [NSDictionary] ?? []
        } catch {
            throw EmailServiceError.parseError(error.localizedDescription)
        }
        
        // 解析每个邮件的头信息并转换为 EmailMessage
        var emailMessages: [EmailMessage] = []
        for msgDictAny in messageUIDs {
            guard let msgDict = msgDictAny as? NSDictionary,
                  let uidValue = msgDict["uid"] as? NSNumber else { continue }
            let uid = uidValue.uint32Value
            
            // 获取邮件头信息
            let headers: [String: Any]
            do {
                let headerDict = try imap.fetchMessageHeaders(withUID: uid)
                headers = headerDict as? [String: Any] ?? [:]
            } catch {
                print("⚠️ [EmailService] 无法获取邮件头，UID: \(uid), 错误: \(error.localizedDescription)")
                continue
            }
            
            // 解析邮件头并创建 EmailMessage
            if let emailMessage = parseEmailMessage(from: headers, accountId: account.id, folderId: folder.id, uid: uid) {
                emailMessages.append(emailMessage)
            }
        }
        
        return emailMessages
    }
    
    /// 获取文件夹列表
    func fetchFolders(account: EmailAccount) async throws -> [EmailFolder] {
        let imap = try getOrCreateIMAPSession(account: account)
        
        let folderNames: [String]
        do {
            folderNames = try imap.fetchFolders() ?? []
        } catch {
            throw EmailServiceError.connectionFailed(error.localizedDescription)
        }
        
        return folderNames.map { name in
            let folderType: EmailFolderType
            let upperName = name.uppercased()
            if upperName == "INBOX" {
                folderType = .inbox
            } else if upperName.contains("SENT") {
                folderType = .sent
            } else if upperName.contains("DRAFT") {
                folderType = .drafts
            } else if upperName.contains("TRASH") || upperName.contains("DELETED") {
                folderType = .trash
            } else if upperName.contains("SPAM") || upperName.contains("JUNK") {
                folderType = .spam
            } else if upperName.contains("ARCHIVE") {
                folderType = .archive
            } else {
                folderType = .custom
            }
            
            return EmailFolder(
                id: UUID(),
                accountId: account.id,
                name: name,
                type: folderType,
                path: name,
                unreadCount: 0
            )
        }
    }
    
    /// 标记邮件为已读
    func markAsRead(account: EmailAccount, message: EmailMessage) async throws {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }
        
        let imap = try getOrCreateIMAPSession(account: account)
        
        do {
            try imap.markAsRead(withUID: uid)
        } catch {
            throw EmailServiceError.networkError(error)
        }
    }
    
    /// 删除邮件
    func deleteMessage(account: EmailAccount, message: EmailMessage) async throws {
        // TODO: 实现删除邮件
        // LibEtPan 需要实现删除功能
        throw EmailServiceError.invalidConfiguration("删除功能未实现")
    }
    
    /// 移动邮件到文件夹
    func moveMessage(account: EmailAccount, message: EmailMessage, to folder: EmailFolder) async throws {
        // TODO: 实现移动邮件
        // LibEtPan 需要实现移动功能
        throw EmailServiceError.invalidConfiguration("移动功能未实现")
    }
    
    // MARK: - SMTP Operations
    
    /// 获取或创建 SMTP 会话
    private func getOrCreateSMTPSession(account: EmailAccount) throws -> LibEtPanSMTPSession {
        if let existing = smtpSessions[account.id] {
            return existing
        }
        
        guard let password = try EmailCredentialStore.shared.getPassword(accountId: account.id) else {
            throw EmailServiceError.authenticationFailed("密码未找到")
        }
        
        guard let smtp = LibEtPanSMTPSession(
            host: account.smtpHost,
            port: account.smtpPort,
            encryption: encryptionString(from: account.smtpEncryption),
            username: account.emailAddress,
            password: password
        ) else {
            throw EmailServiceError.connectionFailed("无法创建 SMTP 会话")
        }
        
        do {
            try smtp.connect()
        } catch {
            throw EmailServiceError.connectionFailed(error.localizedDescription)
        }
        
        do {
            try smtp.login()
        } catch {
            smtp.disconnect()
            throw EmailServiceError.authenticationFailed(error.localizedDescription)
        }
        
        smtpSessions[account.id] = smtp
        return smtp
    }
    
    /// 发送邮件
    func sendMessage(
        account: EmailAccount,
        to: [EmailContact],
        cc: [EmailContact] = [],
        bcc: [EmailContact] = [],
        subject: String,
        body: String,
        htmlBody: String? = nil,
        attachments: [EmailAttachment] = [],
        readReceipt: Bool = false
    ) async throws {
        let smtp = try getOrCreateSMTPSession(account: account)
        
        let toAddresses: [String] = to.map { $0.email }
        let ccAddresses: [String] = cc.map { $0.email }
        let bccAddresses: [String] = bcc.map { $0.email }
        let attachmentData: [Data] = attachments.compactMap { attachment -> Data? in
            guard let path = attachment.localPath,
                  let data = NSData(contentsOfFile: path) else {
                return nil
            }
            return data as Data
        }
        
        do {
            let ccOpt: [String]? = ccAddresses.isEmpty ? nil : ccAddresses
            let bccOpt: [String]? = bccAddresses.isEmpty ? nil : bccAddresses
            let attachmentsOpt: [Data]? = attachmentData.isEmpty ? nil : attachmentData
            try smtp.sendMessage(to: toAddresses,
                                cc: ccOpt,
                                bcc: bccOpt,
                                subject: subject,
                                body: body,
                                htmlBody: htmlBody,
                                attachments: attachmentsOpt,
                                readReceipt: readReceipt)
        } catch {
            throw EmailServiceError.networkError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    /// 从邮件头信息解析 EmailMessage
    private func parseEmailMessage(from headers: [String: Any], accountId: UUID, folderId: UUID, uid: UInt32) -> EmailMessage? {
        let subject = (headers["subject"] as? String) ?? ""
        let fromString = (headers["from"] as? String) ?? ""
        let toString = (headers["to"] as? String) ?? ""
        let dateString = (headers["date"] as? String) ?? ""
        let messageId = headers["message-id"] as? String
        
        // 解析发件人
        let from = parseEmailAddress(fromString)
        
        // 解析收件人
        let to = parseEmailAddresses(toString)
        
        // 解析日期
        let date = parseEmailDate(dateString) ?? Date()
        
        // 检测是否为no-reply地址
        let isNoReply = isNoReplyAddress(from.email)
        
        // 生成预览文本（暂时为空，后续可以从正文获取）
        let preview = ""
        
        return EmailMessage(
            id: UUID(),
            accountId: accountId,
            folderId: folderId,
            uid: uid,
            messageId: messageId,
            subject: subject,
            from: from,
            to: to,
            preview: preview,
            date: date,
            isNoReply: isNoReply,
            isBodyLoaded: false
        )
    }
    
    /// 解析邮件地址列表（逗号分隔）
    private func parseEmailAddresses(_ addressString: String) -> [EmailContact] {
        guard !addressString.isEmpty else { return [] }
        
        let addresses = addressString.components(separatedBy: ",")
        return addresses.compactMap { parseEmailAddress($0.trimmingCharacters(in: .whitespaces)) }
    }
    
    /// 解析邮件日期
    private func parseEmailDate(_ dateString: String) -> Date? {
        guard !dateString.isEmpty else { return nil }
        
        // 使用多种日期格式解析
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "d MMM yyyy HH:mm:ss Z"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "EEE, d MMM yyyy HH:mm:ss zzz"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }()
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        return nil
    }
    
    /// 检测是否为no-reply地址
    func isNoReplyAddress(_ email: String) -> Bool {
        let lowercased = email.lowercased()
        return lowercased.contains("noreply") ||
               lowercased.contains("no-reply") ||
               lowercased.contains("donotreply") ||
               lowercased.contains("do-not-reply") ||
               lowercased.contains("mailer-daemon") ||
               lowercased.contains("postmaster")
    }
    
    /// 解析邮件地址
    func parseEmailAddress(_ addressString: String) -> EmailContact {
        // 解析 "Name <email@example.com>" 格式
        if let range = addressString.range(of: "<", options: .backwards),
           let endRange = addressString.range(of: ">", options: [], range: range.upperBound..<addressString.endIndex) {
            let email = String(addressString[range.upperBound..<endRange.lowerBound])
            let name = String(addressString[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            return EmailContact(name: name.isEmpty ? nil : name, email: email)
        }
        return EmailContact(email: addressString)
    }
}
