//
//  EmailScriptingObjects.swift
//  fastv
//
//  Created by rocky on 2025/02/26.
//
//  可脚本化的邮件对象类
//  这些类将内部数据模型暴露给 AppleScript

import Foundation

// MARK: - 邮件账户

/// 邮件账户脚本化类
@objc(FastVAccountScripting)
class FastVAccountScripting: NSObject {

    private let _account: EmailAccount
    var accountId: UUID { _account.id }

    init(account: EmailAccount) {
        self._account = account
        super.init()
    }

    @objc(id)
    func getId() -> String {
        return _account.id.uuidString
    }

    @objc(name)
    func getName() -> String {
        return _account.displayName
    }

    @objc(emailAddress)
    func getEmailAddress() -> String {
        return _account.emailAddress
    }

    @objc(serviceType)
    func getServiceType() -> String {
        return _account.serviceType.rawValue
    }

    @objc(isEnabled)
    func getIsEnabled() -> Bool {
        return _account.isEnabled
    }

    @objc(setIsEnabled:)
    func setIsEnabled(_ value: Bool) {
        // TODO: 更新数据库
    }

    @objc(isDefault)
    func getIsDefault() -> Bool {
        return _account.isDefault
    }

    @objc(setIsDefault:)
    func setIsDefault(_ value: Bool) {
        Task { @MainActor in
            await EmailStore.shared.setDefaultAccount(accountId: _account.id)
        }
    }

    @objc(connectionStatus)
    func getConnectionStatus() -> String {
        return _account.connectionStatus.rawValue
    }

    @objc(folders)
    func getFolders() -> [FastVFolderScripting] {
        let folders = EmailStore.shared.getFoldersSync(for: _account.id)
        return folders.map { FastVFolderScripting(folder: $0, account: _account) }
    }

    @objc(lastSyncDate)
    func getLastSyncDate() -> Date? {
        return _account.lastSyncDate
    }

    @objc(sync:)
    func handleSync(_ sender: Any?) {
        print("📜 [AppleScript] sync account: \(_account.emailAddress)")

        Task { @MainActor in
            do {
                let folders = await EmailStore.shared.getFolders(for: _account.id)

                for folder in folders {
                    let messages = try await EmailService.shared.syncMessages(
                        account: _account,
                        folder: folder
                    )

                    try await EmailStore.shared.addMessages(messages, folderId: folder.id)
                    print("✅ [AppleScript] 已同步 \(folder.name): \(messages.count) 封邮件")
                }

            } catch {
                print("❌ [AppleScript] 同步失败: \(error)")
            }
        }
    }
}

// MARK: - 邮件文件夹

/// 邮件文件夹脚本化类
@objc(FastVFolderScripting)
class FastVFolderScripting: NSObject {

    private let _folder: EmailFolder
    private let _account: EmailAccount

    init(folder: EmailFolder, account: EmailAccount) {
        self._folder = folder
        self._account = account
        super.init()
    }

    @objc(id)
    func getId() -> String {
        return _folder.id.uuidString
    }

    @objc(name)
    func getName() -> String {
        return _folder.name
    }

    @objc(folderType)
    func getFolderType() -> String {
        return _folder.type.rawValue
    }

    @objc(unreadCount)
    func getUnreadCount() -> Int {
        return _folder.unreadCount
    }

    @objc(totalCount)
    func getTotalCount() -> Int {
        return _folder.totalCount
    }

    @objc(mailMessages)
    func getMailMessages() -> [FastVMessageScripting] {
        var messages: [EmailMessage] = []
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            do {
                messages = try await EmailStore.shared.getMessages(
                    folderId: _folder.id,
                    limit: 100,
                    offset: 0
                )
            } catch {
                print("❌ [AppleScript] 获取文件夹邮件失败: \(error)")
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10)

        return messages.map { FastVMessageScripting(message: $0, account: _account, folder: _folder) }
    }
}

// MARK: - 邮件消息

/// 邮件消息脚本化类
@objc(FastVMessageScripting)
class FastVMessageScripting: NSObject {

    private var _message: EmailMessage
    private let _account: EmailAccount
    private let _folder: EmailFolder

    init(message: EmailMessage, account: EmailAccount, folder: EmailFolder) {
        self._message = message
        self._account = account
        self._folder = folder
        super.init()
    }

    @objc(id)
    func getId() -> String {
        return _message.id.uuidString
    }

    @objc(subject)
    func getSubject() -> String {
        return _message.subject
    }

    @objc(from)
    func getFrom() -> String {
        return _message.from.displayName
    }

    @objc(fromAddress)
    func getFromAddress() -> String {
        return _message.from.email
    }

    @objc(to)
    func getTo() -> [String] {
        return _message.to.map { $0.email }
    }

    @objc(cc)
    func getCc() -> [String] {
        return _message.cc.map { $0.email }
    }

    @objc(bcc)
    func getBcc() -> [String] {
        return _message.bcc.map { $0.email }
    }

    @objc(textBody)
    func getTextBody() -> String? {
        return _message.textBody
    }

    @objc(htmlBody)
    func getHtmlBody() -> String? {
        return _message.htmlBody
    }

    @objc(preview)
    func getPreview() -> String {
        return _message.preview
    }

    @objc(dateSent)
    func getDateSent() -> Date {
        return _message.date
    }

    @objc(dateReceived)
    func getDateReceived() -> Date {
        return _message.receivedDate ?? _message.date
    }

    @objc(isRead)
    func getIsRead() -> Bool {
        return _message.isRead
    }

    @objc(setIsRead:)
    func setIsRead(_ value: Bool) {
        _message.isRead = value

        Task { @MainActor in
            if value {
                try? await EmailService.shared.markAsRead(account: _account, folder: _folder, message: _message)
            }
            // 更新数据库
            try? await EmailStore.shared.updateMessage(_message)
        }
    }

    @objc(isStarred)
    func getIsStarred() -> Bool {
        return _message.isStarred
    }

    @objc(setIsStarred:)
    func setIsStarred(_ value: Bool) {
        _message.isStarred = value

        Task { @MainActor in
            try? await EmailService.shared.toggleStar(account: _account, message: _message)
            try? await EmailStore.shared.updateMessage(_message)
        }
    }

    @objc(isImportant)
    func getIsImportant() -> Bool {
        return _message.isImportant
    }

    @objc(isSpam)
    func getIsSpam() -> Bool {
        return _message.isSpam
    }

    @objc(hasAttachments)
    func getHasAttachments() -> Bool {
        return _message.hasAttachments
    }

    @objc(attachments)
    func getAttachments() -> [FastVAttachmentScripting] {
        return _message.attachments.map { FastVAttachmentScripting(attachment: $0) }
    }

    @objc(tags)
    func getTags() -> [String] {
        return _message.tags
    }

    @objc(setTags:)
    func setTags(_ value: [String]) {
        _message.tags = value

        Task { @MainActor in
            try? await EmailStore.shared.updateMessage(_message)
        }
    }

    @objc(aiTags)
    func getAiTags() -> [String] {
        return _message.aiTags
    }

    @objc(aiSummary)
    func getAiSummary() -> String? {
        return _message.aiSummary
    }

    @objc(aiPriority)
    func getAiPriority() -> String? {
        return _message.aiPriority?.rawValue
    }

    @objc(account)
    func getAccount() -> FastVAccountScripting {
        return FastVAccountScripting(account: _account)
    }

    @objc(folder)
    func getFolder() -> FastVFolderScripting {
        return FastVFolderScripting(folder: _folder, account: _account)
    }

    // MARK: - 命令

    @objc(markAsRead)
    func handleMarkAsRead() {
        print("📜 [AppleScript] markAsRead: \(_message.subject)")

        Task { @MainActor in
            try? await EmailService.shared.markAsRead(account: _account, folder: _folder, message: _message)
            _message.isRead = true
            try? await EmailStore.shared.updateMessage(_message)
        }
    }

    @objc(markAsUnread)
    func handleMarkAsUnread() {
        print("📜 [AppleScript] markAsUnread: \(_message.subject)")

        Task { @MainActor in
            // TODO: 实现标记为未读
            _message.isRead = false
            try? await EmailStore.shared.updateMessage(_message)
        }
    }

    @objc(markStarred:)
    func handleMarkStarred(_ starred: Bool) {
        print("📜 [AppleScript] markStarred: \(_message.subject), starred=\(starred)")

        setIsStarred(starred)
    }

    @objc(moveTo:)
    func handleMoveTo(_ folderName: String) {
        print("📜 [AppleScript] move: \(_message.subject) to \(folderName)")

        Task { @MainActor in
            let folders = await EmailStore.shared.getFolders(for: _account.id)
            guard let targetFolder = folders.first(where: { $0.name.uppercased() == folderName.uppercased() }) else {
                print("❌ [AppleScript] 找不到目标文件夹: \(folderName)")
                return
            }

            try? await EmailService.shared.moveMessage(account: _account, message: _message, to: targetFolder)
        }
    }

    @objc(delete)
    func handleDelete() {
        print("📜 [AppleScript] delete: \(_message.subject)")

        Task { @MainActor in
            try? await EmailService.shared.deleteMessage(account: _account, message: _message)
        }
    }

    @objc(replyTo:body:htmlBody:replyAll:send:)
    func handleReply(
        body: String,
        htmlBody: String? = nil,
        replyAll: Bool = false,
        send: Bool = false
    ) -> FastVMessageScripting? {
        print("📜 [AppleScript] reply: \(_message.subject), replyAll=\(replyAll), send=\(send)")

        Task { @MainActor in
            do {
                // 构建回复收件人
                var toContacts: [EmailContact] = [_message.from]
                var ccContacts: [EmailContact] = []

                if replyAll {
                    toContacts.append(contentsOf: _message.to)
                    ccContacts = _message.cc
                }

                // 构建主题
                let subject = _message.subject.hasPrefix("Re:") ? _message.subject : "Re: \(_message.subject)"

                // 构建回复正文
                let replyBody = """
                \(body)

                > 在 \(_message.date.formatted())，\( _message.from.displayName) 写道：
                > \(_message.textBody?.prefix(500) ?? "")
                """

                // 创建草稿
                let draftMessage = EmailMessage(
                    accountId: _account.id,
                    subject: subject,
                    from: EmailContact(email: _account.emailAddress),
                    to: toContacts,
                    cc: ccContacts,
                    textBody: replyBody,
                    htmlBody: htmlBody,
                    isDraft: !send
                )

                if send {
                    // 发送回复
                    try await EmailService.shared.sendMessage(
                        account: _account,
                        to: toContacts,
                        cc: ccContacts,
                        subject: subject,
                        body: replyBody,
                        htmlBody: htmlBody
                    )
                    print("✅ [AppleScript] 回复已发送")
                } else {
                    // 保存为草稿
                    let draftsFolder = await EmailStore.shared.getDraftsFolder(for: _account.id)
                    if let folder = draftsFolder {
                        try await EmailStore.shared.addMessages([draftMessage], folderId: folder.id)
                        print("✅ [AppleScript] 回复草稿已保存")
                    }
                }

            } catch {
                print("❌ [AppleScript] 回复失败: \(error)")
            }
        }

        return nil
    }

    // MARK: - 新增命令

    @objc(forwardTo:body:send:)
    func handleForward(to: String, body: String? = nil, send: Bool = false) -> FastVMessageScripting? {
        print("📜 [AppleScript] forward: \(_message.subject) to \(to)")

        Task { @MainActor in
            do {
                // 解析收件人
                let toContacts = parseEmailAddresses(to)

                // 构建主题
                let subject = "Fwd: \(_message.subject)"

                // 构建转发正文
                let forwardBody: String
                if let customBody = body, !customBody.isEmpty {
                    forwardBody = """
                    \(customBody)

                    ---------- 转发的邮件 ---------
                    发件人: \(_message.from.displayName)
                    日期: \(_message.date.formatted())
                    主题: \(_message.subject)

                    \(_message.textBody ?? "")
                    """
                } else {
                    forwardBody = """
                    ---------- 转发的邮件 ---------
                    发件人: \(_message.from.displayName)
                    日期: \(_message.date.formatted())
                    主题: \(_message.subject)

                    \(_message.textBody ?? "")
                    """
                }

                // 创建草稿
                let draftMessage = EmailMessage(
                    accountId: _account.id,
                    subject: subject,
                    from: EmailContact(email: _account.emailAddress),
                    to: toContacts,
                    textBody: forwardBody,
                    isDraft: !send
                )

                if send {
                    try await EmailService.shared.sendMessage(
                        account: _account,
                        to: toContacts,
                        subject: subject,
                        body: forwardBody
                    )
                    print("✅ [AppleScript] 转发已发送")
                } else {
                    let draftsFolder = await EmailStore.shared.getDraftsFolder(for: _account.id)
                    if let folder = draftsFolder {
                        try await EmailStore.shared.addMessages([draftMessage], folderId: folder.id)
                        print("✅ [AppleScript] 转发草稿已保存")
                    }
                }

            } catch {
                print("❌ [AppleScript] 转发失败: \(error)")
            }
        }

        return nil
    }

    @objc(archive)
    func handleArchive() {
        print("📜 [AppleScript] archive: \(_message.subject)")

        Task { @MainActor in
            let folders = await EmailStore.shared.getFolders(for: _account.id)
            guard let archiveFolder = folders.first(where: { $0.type == .archive }) else {
                print("❌ [AppleScript] 未找到归档文件夹")
                return
            }

            try? await EmailService.shared.moveMessage(account: _account, message: _message, to: archiveFolder)
            print("✅ [AppleScript] 邮件已归档")
        }
    }

    @objc(markAsSpam)
    func handleMarkAsSpam() {
        print("📜 [AppleScript] markAsSpam: \(_message.subject)")

        Task { @MainActor in
            try? await EmailService.shared.markAsSpam(account: _account, message: _message)
            print("✅ [AppleScript] 已标记为垃圾邮件")
        }
    }

    @objc(unmarkSpam)
    func handleUnmarkSpam() {
        print("📜 [AppleScript] unmarkSpam: \(_message.subject)")

        Task { @MainActor in
            try? await EmailService.shared.unmarkSpam(account: _account, message: _message)
            print("✅ [AppleScript] 已取消垃圾邮件标记")
        }
    }

    @objc(addTag:)
    func handleAddTag(tag: String) {
        print("📜 [AppleScript] addTag '\(tag)' to \(_message.subject)")

        var tags = _message.tags
        if !tags.contains(tag) {
            tags.append(tag)
            _message.tags = tags

            Task { @MainActor in
                try? await EmailStore.shared.updateMessage(_message)
                print("✅ [AppleScript] 已添加标签")
            }
        }
    }

    @objc(removeTag:)
    func handleRemoveTag(tag: String) {
        print("📜 [AppleScript] removeTag '\(tag)' from \(_message.subject)")

        _message.tags.removeAll { $0 == tag }

        Task { @MainActor in
            try? await EmailStore.shared.updateMessage(_message)
            print("✅ [AppleScript] 已移除标签")
        }
    }

    @objc(getMailBody:)
    func handleGetMailBody(plainTextOnly: Bool = false) -> String {
        print("📜 [AppleScript] getMailBody: \(_message.subject)")

        if plainTextOnly {
            return _message.textBody ?? _message.preview
        } else {
            // 优先返回 HTML，如果没有则返回纯文本
            return _message.htmlBody ?? _message.textBody ?? _message.preview
        }
    }

    // MARK: - 辅助方法

    private func parseEmailAddresses(_ addressString: String) -> [EmailContact] {
        let addresses = addressString.components(separatedBy: ",")
        return addresses.compactMap { address in
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }

            if let range = trimmed.range(of: "<", options: .backwards),
               let endRange = trimmed.range(of: ">", options: [], range: range.upperBound..<trimmed.endIndex) {
                let email = String(trimmed[range.upperBound..<endRange.lowerBound])
                let name = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return EmailContact(name: name.isEmpty ? nil : name, email: email)
            }

            return EmailContact(email: trimmed)
        }
    }
}

// MARK: - 邮件附件

/// 邮件附件脚本化类
@objc(FastVAttachmentScripting)
class FastVAttachmentScripting: NSObject {

    private let _attachment: EmailAttachment

    init(attachment: EmailAttachment) {
        self._attachment = attachment
        super.init()
    }

    @objc(id)
    func getId() -> String {
        return _attachment.id.uuidString
    }

    @objc(name)
    func getName() -> String {
        return _attachment.filename
    }

    @objc(mimeType)
    func getMimeType() -> String {
        return _attachment.mimeType
    }

    @objc(size)
    func getSize() -> Int {
        return Int(_attachment.size)
    }

    @objc(filePath)
    func getFilePath() -> String? {
        return _attachment.localPath
    }
}
