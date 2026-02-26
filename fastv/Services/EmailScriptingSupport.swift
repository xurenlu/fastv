//
//  EmailScriptingSupport.swift
//  fastv
//
//  Created by rocky on 2025/02/26.
//
//  AppleScript 脚本支持核心类
//  允许 AI 应用通过 AppleScript 访问邮件功能

import Foundation
import AppKit

// MARK: - AppleScript 命令处理类

/// FastV 脚本化应用类（NSApplication 的 AppleScript 代理）
@objc(FastVScriptingApplication)
class FastVScriptingApplication: NSObject {

    // MARK: - 属性访问

    /// 获取所有邮件账户
    @objc(accounts)
    func getAccounts() -> [FastVAccountScripting] {
        Task { @MainActor in
            let accounts = await EmailStore.shared.getAccounts()
            return accounts.map { FastVAccountScripting(account: $0) }
        }
        // 同步返回已加载的账户
        return []
    }

    /// 获取默认账户
    @objc(defaultAccount)
    func getDefaultAccount() -> FastVAccountScripting? {
        guard let account = EmailStore.shared.getDefaultAccountSync() else {
            return nil
        }
        return FastVAccountScripting(account: account)
    }

    /// 设置默认账户
    @objc(setDefaultAccount:)
    func setDefaultAccount(_ account: FastVAccountScripting) {
        Task { @MainActor in
            await EmailStore.shared.setDefaultAccount(accountId: account.accountId)
        }
    }

    /// 获取所有邮件（限制数量）
    @objc(mailMessages)
    func getMailMessages() -> [FastVMessageScripting] {
        return []
    }

    // MARK: - 命令处理

    /// 获取邮件列表
    @objc(getMailMessages:limit:folder:unreadOnly:since:search:)
    func handleGetMailMessages(
        specifier: NSScriptObjectSpecifier?,
        limit: Int = 50,
        folder: String? = nil,
        unreadOnly: Bool = false,
        since: Date? = nil,
        search: String? = nil
    ) -> NSArray {
        print("📜 [AppleScript] getMailMessages: limit=\(limit), folder=\(folder ?? "all"), unreadOnly=\(unreadOnly)")

        var messages: [EmailMessage] = []

        Task { @MainActor in
            do {
                // 获取所有启用的账户
                let accounts = await EmailStore.shared.getAccounts()
                let enabledAccounts = accounts.filter { $0.isEnabled }

                guard let account = enabledAccounts.first else {
                    print("⚠️ [AppleScript] 没有可用的邮件账户")
                    return
                }

                // 获取文件夹
                var targetFolder: EmailFolder?
                if let folderName = folder {
                    let folders = await EmailStore.shared.getFolders(for: account.id)
                    targetFolder = folders.first { $0.name.uppercased() == folderName.uppercased() || $0.type.rawValue.uppercased() == folderName.uppercased() }
                } else {
                    // 默认使用收件箱
                    let folders = await EmailStore.shared.getFolders(for: account.id)
                    targetFolder = folders.first { $0.type == .inbox }
                }

                guard let folder = targetFolder else {
                    print("⚠️ [AppleScript] 找不到文件夹: \(folder ?? "inbox")")
                    return
                }

                // 获取邮件
                let fetchedMessages = try await EmailService.shared.syncMessages(
                    account: account,
                    folder: folder,
                    since: since,
                    limit: limit
                )

                // 过滤
                var filteredMessages = fetchedMessages
                if unreadOnly {
                    filteredMessages = filteredMessages.filter { !$0.isRead }
                }
                if let searchQuery = search, !searchQuery.isEmpty {
                    filteredMessages = filteredMessages.filter { message in
                        message.subject.localizedCaseInsensitiveContains(searchQuery) ||
                        message.from.email.localizedCaseInsensitiveContains(searchQuery) ||
                        message.textBody?.localizedCaseInsensitiveContains(searchQuery) == true
                    }
                }

                // 保存到数据库
                try await EmailStore.shared.addMessages(filteredMessages, folderId: folder.id)

                messages = filteredMessages
                print("✅ [AppleScript] 获取到 \(messages.count) 封邮件")

            } catch {
                print("❌ [AppleScript] 获取邮件失败: \(error)")
            }
        }

        // 由于是异步操作，这里返回空数组，实际数据通过通知机制传递
        // 或者我们可以等待一小段时间让异步操作完成
        return [] as NSArray
    }

    /// 创建邮件
    @objc(createMail:subject:body:htmlBody:cc:bcc:attachments:saveAsDraft:)
    func handleCreateMail(
        to: String,
        subject: String,
        body: String? = nil,
        htmlBody: String? = nil,
        cc: String? = nil,
        bcc: String? = nil,
        attachments: [String]? = nil,
        saveAsDraft: Bool = true
    ) -> FastVMessageScripting? {
        print("📜 [AppleScript] createMail: to=\(to), subject=\(subject)")

        Task { @MainActor in
            do {
                // 获取默认账户
                let accounts = await EmailStore.shared.getAccounts()
                guard let account = accounts.first(where: { $0.isDefault }) ?? accounts.first else {
                    print("⚠️ [AppleScript] 没有可用的邮件账户")
                    return
                }

                // 解析收件人
                let toContacts = parseEmailAddresses(to)
                let ccContacts = cc.flatMap { parseEmailAddresses($0) } ?? []
                let bccContacts = bcc.flatMap { parseEmailAddresses($0) } ?? []

                // 处理附件
                let emailAttachments: [EmailAttachment] = (attachments ?? []).compactMap { filePath in
                    let fileURL = URL(fileURLWithPath: filePath)
                    let attributes = try? FileManager.default.attributesOfItem(atPath: filePath)
                    let fileSize = attributes?[.size] as? Int64 ?? 0

                    return EmailAttachment(
                        filename: fileURL.lastPathComponent,
                        mimeType: mimeTypeForFile(at: filePath),
                        size: fileSize,
                        localPath: filePath
                    )
                }

                // 创建邮件消息
                let message = EmailMessage(
                    accountId: account.id,
                    subject: subject,
                    from: EmailContact(email: account.emailAddress),
                    to: toContacts,
                    cc: ccContacts,
                    bcc: bccContacts,
                    textBody: body,
                    htmlBody: htmlBody,
                    isDraft: saveAsDraft,
                    attachments: emailAttachments
                )

                if saveAsDraft {
                    // 保存为草稿
                    let draftsFolder = await EmailStore.shared.getDraftsFolder(for: account.id)
                    if let folder = draftsFolder {
                        try await EmailStore.shared.addMessages([message], folderId: folder.id)
                        print("✅ [AppleScript] 草稿已保存")
                    }
                } else {
                    // 直接发送
                    try await EmailService.shared.sendMessage(
                        account: account,
                        to: toContacts,
                        cc: ccContacts,
                        bcc: bccContacts,
                        subject: subject,
                        body: body ?? "",
                        htmlBody: htmlBody,
                        attachments: emailAttachments
                    )
                    print("✅ [AppleScript] 邮件已发送")
                }

            } catch {
                print("❌ [AppleScript] 创建/发送邮件失败: \(error)")
            }
        }

        return nil
    }

    /// 同步账户
    @objc(syncAccount:folder:)
    func handleSyncAccount(_ accountSpecifier: NSScriptObjectSpecifier?, folder: String? = nil) {
        print("📜 [AppleScript] syncAccount")

        Task { @MainActor in
            do {
                let accounts = await EmailStore.shared.getAccounts()
                let enabledAccounts = accounts.filter { $0.isEnabled }

                for account in enabledAccounts {
                    let folders = await EmailStore.shared.getFolders(for: account.id)

                    for folderObj in folders {
                        if let folderName = folder {
                            if folderObj.name.uppercased() != folderName.uppercased() &&
                               folderObj.type.rawValue.uppercased() != folderName.uppercased() {
                                continue
                            }
                        }

                        let messages = try await EmailService.shared.syncMessages(
                            account: account,
                            folder: folderObj
                        )

                        try await EmailStore.shared.addMessages(messages, folderId: folderObj.id)
                        print("✅ [AppleScript] 同步完成: \(account.emailAddress) - \(folderObj.name), \(messages.count) 封邮件")
                    }
                }

            } catch {
                print("❌ [AppleScript] 同步失败: \(error)")
            }
        }
    }

    // MARK: - 便捷获取命令

    /// 获取最近的邮件
    @objc(getRecentMails:folder:)
    func handleGetRecentMails(count: Int = 10, folder: String? = nil) -> NSArray {
        print("📜 [AppleScript] getRecentMails: count=\(count), folder=\(folder ?? "inbox")")

        var resultMessages: [EmailMessage] = []
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            do {
                let accounts = await EmailStore.shared.getAccounts()
                guard let account = accounts.first(where: { $0.isDefault }) ?? accounts.first else {
                    semaphore.signal()
                    return
                }

                let folders = await EmailStore.shared.getFolders(for: account.id)
                let targetFolder: EmailFolder?

                if let folderName = folder {
                    targetFolder = folders.first { $0.name.uppercased() == folderName.uppercased() || $0.type.rawValue.uppercased() == folderName.uppercased() }
                } else {
                    targetFolder = folders.first { $0.type == .inbox }
                }

                guard let folder = targetFolder else {
                    print("⚠️ [AppleScript] 找不到文件夹")
                    semaphore.signal()
                    return
                }

                let messages = await EmailStore.shared.getMessages(folderId: folder.id, limit: count, offset: 0)
                resultMessages = messages

                semaphore.signal()
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10)

        return resultMessages.map { FastVMessageScripting(message: $0, account: EmailStore.shared.getDefaultAccountSync()!, folder: EmailFolder()) } as NSArray
    }

    /// 获取未读邮件
    @objc(getUnreadMails:folder:)
    func handleGetUnreadMails(count: Int = 0, folder: String? = nil) -> NSArray {
        print("📜 [AppleScript] getUnreadMails: count=\(count), folder=\(folder ?? "inbox")")

        var resultMessages: [EmailMessage] = []
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            do {
                let accounts = await EmailStore.shared.getAccounts()
                guard let account = accounts.first(where: { $0.isDefault }) ?? accounts.first else {
                    semaphore.signal()
                    return
                }

                let folders = await EmailStore.shared.getFolders(for: account.id)
                let targetFolder: EmailFolder?

                if let folderName = folder {
                    targetFolder = folders.first { $0.name.uppercased() == folderName.uppercased() || $0.type.rawValue.uppercased() == folderName.uppercased() }
                } else {
                    targetFolder = folders.first { $0.type == .inbox }
                }

                guard let folder = targetFolder else {
                    semaphore.signal()
                    return
                }

                let limit = count > 0 ? count : 100
                var messages = await EmailStore.shared.getMessages(folderId: folder.id, limit: limit, offset: 0)
                messages = messages.filter { !$0.isRead }

                if count > 0 {
                    messages = Array(messages.prefix(count))
                }

                resultMessages = messages
                semaphore.signal()
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10)

        return resultMessages.map { FastVMessageScripting(message: $0, account: EmailStore.shared.getDefaultAccountSync()!, folder: EmailFolder()) } as NSArray
    }

    /// 获取草稿列表
    @objc(getDrafts:)
    func handleGetDrafts(limit: Int = 20) -> NSArray {
        print("📜 [AppleScript] getDrafts: limit=\(limit)")

        var resultMessages: [EmailMessage] = []
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            do {
                let accounts = await EmailStore.shared.getAccounts()
                guard let account = accounts.first else {
                    semaphore.signal()
                    return
                }

                let drafts = await EmailStore.shared.getDrafts(for: account.id)
                resultMessages = Array(drafts.prefix(limit))

                semaphore.signal()
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10)

        return resultMessages.map { FastVMessageScripting(message: $0, account: EmailStore.shared.getDefaultAccountSync()!, folder: EmailFolder()) } as NSArray
    }

    /// 搜索邮件
    @objc(searchMails:inFolder:limit:unreadOnly:)
    func handleSearchMails(query: String, inFolder: String? = nil, limit: Int = 50, unreadOnly: Bool = false) -> NSArray {
        print("📜 [AppleScript] searchMails: query=\(query)")

        var resultMessages: [EmailMessage] = []
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            do {
                let accounts = await EmailStore.shared.getAccounts()
                guard let account = accounts.first(where: { $0.isDefault }) ?? accounts.first else {
                    semaphore.signal()
                    return
                }

                let folders = await EmailStore.shared.getFolders(for: account.id)
                let foldersToSearch = inFolder == nil ? folders : folders.filter { $0.name.uppercased() == inFolder!.uppercased() || $0.type.rawValue.uppercased() == inFolder!.uppercased() }

                for folder in foldersToSearch {
                    var messages = await EmailStore.shared.getMessages(folderId: folder.id, limit: 100, offset: 0)

                    // 搜索过滤
                    messages = messages.filter { message in
                        message.subject.localizedCaseInsensitiveContains(query) ||
                        message.from.email.localizedCaseInsensitiveContains(query) ||
                        message.textBody?.localizedCaseInsensitiveContains(query) == true
                    }

                    // 未读过滤
                    if unreadOnly {
                        messages = messages.filter { !$0.isRead }
                    }

                    resultMessages.append(contentsOf: messages)

                    if resultMessages.count >= limit {
                        break
                    }
                }

                resultMessages = Array(resultMessages.prefix(limit))
                semaphore.signal()
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10)

        return resultMessages.map { FastVMessageScripting(message: $0, account: EmailStore.shared.getDefaultAccountSync()!, folder: EmailFolder()) } as NSArray
    }

    /// 获取带有指定标签的邮件
    @objc(getMailsWithTag:limit:)
    func handleGetMailsWithTag(tag: String, limit: Int = 50) -> NSArray {
        print("📜 [AppleScript] getMailsWithTag: tag=\(tag)")

        var resultMessages: [EmailMessage] = []
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            do {
                let accounts = await EmailStore.shared.getAccounts()
                guard let account = accounts.first else {
                    semaphore.signal()
                    return
                }

                let folders = await EmailStore.shared.getFolders(for: account.id)

                for folder in folders {
                    var messages = await EmailStore.shared.getMessages(folderId: folder.id, limit: 100, offset: 0)
                    messages = messages.filter { $0.tags.contains(tag) }
                    resultMessages.append(contentsOf: messages)

                    if resultMessages.count >= limit {
                        break
                    }
                }

                resultMessages = Array(resultMessages.prefix(limit))
                semaphore.signal()
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10)

        return resultMessages.map { FastVMessageScripting(message: $0, account: EmailStore.shared.getDefaultAccountSync()!, folder: EmailFolder()) } as NSArray
    }

    // MARK: - 辅助方法

    private func parseEmailAddresses(_ addressString: String) -> [EmailContact] {
        let addresses = addressString.components(separatedBy: ",")
        return addresses.compactMap { address in
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }

            // 解析 "Name <email>" 格式
            if let range = trimmed.range(of: "<", options: .backwards),
               let endRange = trimmed.range(of: ">", options: [], range: range.upperBound..<trimmed.endIndex) {
                let email = String(trimmed[range.upperBound..<endRange.lowerBound])
                let name = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return EmailContact(name: name.isEmpty ? nil : name, email: email)
            }

            return EmailContact(email: trimmed)
        }
    }

    private func mimeTypeForFile(at path: String) -> String {
        let extension = URL(fileURLWithPath: path).pathExtension.lowercased()
        let mimeTypes: [String: String] = [
            "pdf": "application/pdf",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "txt": "text/plain",
            "html": "text/html",
            "zip": "application/zip",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        ]
        return mimeTypes[extension] ?? "application/octet-stream"
    }
}

// MARK: - 同步访问 EmailStore 的扩展

extension EmailStore {
    /// 同步获取默认账户（用于 AppleScript）
    func getDefaultAccountSync() -> EmailAccount? {
        var result: EmailAccount?
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            result = await getDefaultAccount()
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5) // 等待最多 5 秒
        return result
    }

    /// 同步获取账户列表（用于 AppleScript）
    func getAccountsSync() -> [EmailAccount] {
        var result: [EmailAccount] = []
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            result = await getAccounts()
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }

    /// 同步获取文件夹列表（用于 AppleScript）
    func getFoldersSync(for accountId: UUID) -> [EmailFolder] {
        var result: [EmailFolder] = []
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            result = await getFolders(for: accountId)
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }

    /// 同步获取草稿文件夹
    func getDraftsFolder(for accountId: UUID) async -> EmailFolder? {
        let folders = await getFolders(for: accountId)
        return folders.first { $0.type == .drafts }
    }
}
