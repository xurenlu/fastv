//
//  EmailViewModel+Compose.swift
//  fastv
//
//  从 EmailViewModel.swift 拆出的"新邮件撰写 / 回复 / 发送 / 已发送本地保存 / 系统通知"相关方法。
//  这部分的状态 (composeDraft / replyDraft / isSendingCompose / isSendingReply / sendProgress 等)
//  全部留在主 ViewModel 中，这里只是把方法实现集中到一处便于维护。
//

import Foundation
import AppKit
import UserNotifications

extension EmailViewModel {
    // MARK: - Reply Methods

    /// 初始化回复草稿
    func initReplyDraft(for message: EmailMessage, type: ReplyDraft.ReplyType) {
        var draft = ReplyDraft()
        draft.replyType = type

        guard let account = currentAccount else { return }

        switch type {
        case .reply:
            // 回复：发给发件人
            draft.to = message.replyTo.isEmpty ? [message.from] : message.replyTo
            draft.subject = message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)"
            // 引用原邮件
            if let textBody = message.textBody {
                let quotedBody = textBody.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
                draft.body = "\n\n在 \(formatComposeDate(message.date))，\(message.from.displayName) 写道：\n\n\(quotedBody)"
            }
        case .replyAll:
            // 回复全部：发给发件人 + 所有收件人（排除自己）
            var recipients = message.replyTo.isEmpty ? [message.from] : message.replyTo
            recipients.append(contentsOf: message.to.filter { $0.email != account.emailAddress })
            recipients.append(contentsOf: message.cc.filter { $0.email != account.emailAddress })
            draft.to = Array(Set(recipients))
            draft.cc = message.cc.filter { $0.email != account.emailAddress }
            draft.subject = message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)"
            // 引用原邮件
            if let textBody = message.textBody {
                let quotedBody = textBody.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
                draft.body = "\n\n在 \(formatComposeDate(message.date))，\(message.from.displayName) 写道：\n\n\(quotedBody)"
            }
        case .forward:
            // 转发：主题加 Fw:
            draft.subject = message.subject.hasPrefix("Fw:") ? message.subject : "Fw: \(message.subject)"
            // 转发时包含原邮件内容
            if let textBody = message.textBody {
                draft.body = "\n\n---------- 转发邮件 ----------\n\(textBody)"
            } else if let htmlBody = message.htmlBody {
                draft.htmlBody = "<br><br>---------- 转发邮件 ----------<br>\(htmlBody)"
            }
        }

        // 关闭编写面板
        showComposePanel = false
        composeDraft = nil

        replyDraft = draft
        showReplyPanel = true
        showCcBcc = false  // 重置 Cc/Bcc 展开状态
    }

    /// 初始化编写草稿（新邮件）
    func initComposeDraft() {
        // 关闭回复面板
        showReplyPanel = false
        replyDraft = nil

        var draft = ReplyDraft()
        draft.replyType = .reply  // 新邮件也使用 reply 类型，但不会引用原邮件
        composeDraft = draft
        showComposePanel = true
        showCcBcc = false
    }

    /// 更新编写字段
    func updateComposeField(to: [EmailContact]? = nil, cc: [EmailContact]? = nil, bcc: [EmailContact]? = nil, subject: String? = nil, body: String? = nil) {
        guard var draft = composeDraft else { return }
        if let to = to { draft.to = to }
        if let cc = cc { draft.cc = cc }
        if let bcc = bcc { draft.bcc = bcc }
        if let subject = subject { draft.subject = subject }
        if let body = body { draft.body = body }
        composeDraft = draft
    }

    /// 添加附件到编写草稿
    func addAttachmentToCompose(_ attachment: EmailAttachment) {
        guard var draft = composeDraft else { return }
        draft.attachments.append(attachment)
        composeDraft = draft
    }

    /// 从编写草稿中移除附件
    func removeAttachmentFromCompose(_ attachmentId: UUID) {
        guard var draft = composeDraft else { return }
        draft.attachments.removeAll { $0.id == attachmentId }
        composeDraft = draft
    }

    /// 发送新邮件（从撰写窗口调用）
    func sendComposeMessage(
        account: EmailAccount,
        to: [EmailContact],
        cc: [EmailContact] = [],
        bcc: [EmailContact] = [],
        subject: String,
        body: String,
        htmlBody: String? = nil
    ) async throws {
        // 更新草稿
        var draft = composeDraft ?? ReplyDraft()
        draft.to = to
        draft.cc = cc
        draft.bcc = bcc
        draft.subject = subject
        draft.body = body
        draft.htmlBody = htmlBody
        composeDraft = draft

        // 发送
        try await sendCompose()
    }

    /// 发送回复（从撰写窗口调用）
    func sendReplyMessage(
        account: EmailAccount,
        originalMessage: EmailMessage,
        to: [EmailContact],
        cc: [EmailContact] = [],
        bcc: [EmailContact] = [],
        subject: String,
        body: String,
        htmlBody: String? = nil,
        replyType: ReplyDraft.ReplyType = .reply
    ) async throws {
        // 初始化回复草稿
        initReplyDraft(for: originalMessage, type: replyType)

        // 更新草稿
        var draft = replyDraft ?? ReplyDraft()
        draft.to = to
        draft.cc = cc
        draft.bcc = bcc
        draft.subject = subject
        draft.body = body
        draft.htmlBody = htmlBody
        replyDraft = draft

        // 发送
        try await sendReply()
    }

    /// 标记邮件为已回复
    func markMessageAsReplied(messageId: UUID) async {
        guard let message = messages.first(where: { $0.id == messageId }) else {
            print("⚠️ [EmailViewModel] 未找到要标记的邮件: \(messageId)")
            return
        }

        var updated = message
        updated.hasBeenReplied = true

        do {
            try await emailStore.updateMessage(updated)
            print("✅ [EmailViewModel] 邮件已标记为已回复: id=\(message.id)")
        } catch {
            print("❌ [EmailViewModel] 标记邮件失败: \(error)")
        }
    }

    // MARK: - Reply body 切分（供 AI Polish 使用）

    /// 切分回复正文，分离用户撰写部分和引用部分
    func splitReplyBody(_ body: String) -> (userPart: String, quotedPart: String) {
        // 常见的引用分隔符模式
        let separators = [
            "\n\n--- 原始邮件 ---",
            "\n\n--- 转发邮件 ---",
            "\n\n在 ",
            "\n\n> ",
            "\n\nOn ",
            "\n\nFrom:",
            "\n\n发件人:"
        ]

        // 查找第一个匹配的分隔符
        for separator in separators {
            if let range = body.range(of: separator) {
                let userPart = String(body[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let quotedPart = String(body[range.lowerBound...])
                return (userPart, quotedPart)
            }
        }

        // 如果没有找到分隔符，检查是否有以 ">" 开头的行（常见引用格式）
        let lines = body.components(separatedBy: .newlines)
        var userLines: [String] = []
        var quotedLines: [String] = []
        var foundQuotedStart = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") || trimmed.hasPrefix("|") {
                foundQuotedStart = true
                quotedLines.append(line)
            } else if foundQuotedStart {
                quotedLines.append(line)
            } else {
                userLines.append(line)
            }
        }

        if !quotedLines.isEmpty {
            let userPart = userLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let quotedPart = quotedLines.joined(separator: "\n")
            return (userPart, quotedPart)
        }

        // 如果都没有找到，返回整个正文作为用户部分
        return (body, "")
    }

    // MARK: - Compose / Reply 发送

    /// 发送新邮件（发送完成后通知用户）
    /// 注意：LibEtPan 的 SMTP 操作必须在主线程执行，所以这里不能用 Task.detached
    func sendCompose() async throws {
        guard let draft = composeDraft else {
            throw EmailServiceError.invalidConfiguration("编写草稿不存在")
        }

        // 检查必填字段
        guard !draft.to.isEmpty else {
            throw EmailServiceError.invalidConfiguration("请填写收件人")
        }

        // 检查是否提到附件但没有添加
        let subjectLower = draft.subject.lowercased()
        let bodyLower = draft.body.lowercased()
        let mentionsAttachment = subjectLower.contains("附件") || subjectLower.contains("attachment") ||
                                 bodyLower.contains("附件") || bodyLower.contains("attachment")
        if mentionsAttachment && draft.attachments.isEmpty {
            throw EmailServiceError.invalidConfiguration("您提到了附件，但还没有添加任何附件。请添加附件后再发送，或修改邮件内容。")
        }

        // 设置发送状态和进度
        isSendingCompose = true
        errorMessage = nil
        sendProgress = 0.0
        sendStatusText = "准备发送..."

        // 保存草稿信息
        let draftToSend = draft
        let subject = draft.subject
        let hasAttachments = !draft.attachments.isEmpty

        // 让 UI 有机会更新
        await Task.yield()

        do {
            // 阶段1: 连接服务器
            sendProgress = 0.1
            sendStatusText = "正在连接邮件服务器..."
            await Task.yield()

            // 阶段2: 准备邮件内容
            sendProgress = 0.3
            if hasAttachments {
                sendStatusText = "正在准备附件 (\(draftToSend.attachments.count) 个)..."
            } else {
                sendStatusText = "正在准备邮件内容..."
            }
            await Task.yield()

            // 阶段3: 发送邮件
            sendProgress = 0.5
            sendStatusText = "正在发送邮件..."

            try await sendMessage(
                to: draftToSend.to,
                cc: draftToSend.cc,
                bcc: draftToSend.bcc,
                subject: draftToSend.subject,
                body: draftToSend.body,
                htmlBody: draftToSend.htmlBody,
                attachments: draftToSend.attachments
            )

            // 阶段4: 发送成功
            sendProgress = 1.0
            sendStatusText = "发送成功！"
            await Task.yield()

            // 短暂显示成功状态后关闭面板
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

            // 发送成功后关闭面板
            composeDraft = nil
            showComposePanel = false
            showCcBcc = false
            isSendingCompose = false
            sendProgress = 0.0
            sendStatusText = ""

            // 保存到"已发送(本地)"文件夹，便于在客户端查看
            if let account = currentAccount {
                saveSentMessageToLocalFolder(
                    account: account,
                    to: draftToSend.to,
                    cc: draftToSend.cc,
                    bcc: draftToSend.bcc,
                    subject: draftToSend.subject,
                    body: draftToSend.body,
                    htmlBody: draftToSend.htmlBody
                )
            }
            notifyEmailSent(subject: subject, success: true)
        } catch {
            // 发送失败
            sendProgress = 0.0
            sendStatusText = ""
            isSendingCompose = false
            errorMessage = error.localizedDescription
            notifyEmailSent(subject: subject, success: false, error: error.localizedDescription)
            throw error
        }
    }

    /// 更新回复字段
    func updateReplyField(to: [EmailContact]? = nil, cc: [EmailContact]? = nil, bcc: [EmailContact]? = nil, subject: String? = nil, body: String? = nil) {
        guard var draft = replyDraft else { return }
        if let to = to { draft.to = to }
        if let cc = cc { draft.cc = cc }
        if let bcc = bcc { draft.bcc = bcc }
        if let subject = subject { draft.subject = subject }
        if let body = body { draft.body = body }
        replyDraft = draft
    }

    /// 添加附件到回复草稿
    func addAttachmentToReply(_ attachment: EmailAttachment) {
        guard var draft = replyDraft else { return }
        draft.attachments.append(attachment)
        replyDraft = draft
    }

    /// 从回复草稿中移除附件
    func removeAttachmentFromReply(_ attachmentId: UUID) {
        guard var draft = replyDraft else { return }
        draft.attachments.removeAll { $0.id == attachmentId }
        replyDraft = draft
    }

    /// 检查主题中提到附件但实际没有附件
    func checkAttachmentMention() -> Bool {
        guard let draft = replyDraft else { return false }
        let subjectLower = draft.subject.lowercased()
        let bodyLower = draft.body.lowercased()
        let mentionsAttachment = subjectLower.contains("附件") || subjectLower.contains("attachment") ||
                                 bodyLower.contains("附件") || bodyLower.contains("attachment")
        return mentionsAttachment && draft.attachments.isEmpty
    }

    /// 发送回复（发送完成后通知用户）
    /// 注意：LibEtPan 的 SMTP 操作必须在主线程执行，所以这里不能用 Task.detached
    func sendReply() async throws {
        guard let draft = replyDraft else {
            throw EmailServiceError.invalidConfiguration("回复草稿不存在")
        }

        // 检查是否提到附件但没有添加
        if checkAttachmentMention() {
            throw EmailServiceError.invalidConfiguration("您提到了附件，但还没有添加任何附件。请添加附件后再发送，或修改邮件内容。")
        }

        // 设置发送状态和进度
        isSendingReply = true
        errorMessage = nil
        sendProgress = 0.0
        sendStatusText = "准备发送..."

        // 保存草稿信息
        let draftToSend = draft
        let subject = draft.subject
        let hasAttachments = !draft.attachments.isEmpty

        // 让 UI 有机会更新
        await Task.yield()

        do {
            // 阶段1: 连接服务器
            sendProgress = 0.1
            sendStatusText = "正在连接邮件服务器..."
            await Task.yield()

            // 阶段2: 准备邮件内容
            sendProgress = 0.3
            if hasAttachments {
                sendStatusText = "正在准备附件 (\(draftToSend.attachments.count) 个)..."
            } else {
                sendStatusText = "正在准备邮件内容..."
            }
            await Task.yield()

            // 阶段3: 发送邮件
            sendProgress = 0.5
            sendStatusText = "正在发送邮件..."

            try await sendMessage(
                to: draftToSend.to,
                cc: draftToSend.cc,
                bcc: draftToSend.bcc,
                subject: draftToSend.subject,
                body: draftToSend.body,
                htmlBody: draftToSend.htmlBody,
                attachments: draftToSend.attachments
            )

            // 阶段4: 发送成功
            sendProgress = 1.0
            sendStatusText = "发送成功！"
            await Task.yield()

            // 短暂显示成功状态后关闭面板
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

            // 发送成功后关闭面板
            replyDraft = nil
            showReplyPanel = false
            showCcBcc = false
            isSendingReply = false
            sendProgress = 0.0
            sendStatusText = ""

            // 保存到"已发送(本地)"文件夹
            if let account = currentAccount {
                saveSentMessageToLocalFolder(
                    account: account,
                    to: draftToSend.to,
                    cc: draftToSend.cc,
                    bcc: draftToSend.bcc,
                    subject: draftToSend.subject,
                    body: draftToSend.body,
                    htmlBody: draftToSend.htmlBody
                )
            }
            notifyEmailSent(subject: subject, success: true)
        } catch {
            // 发送失败
            sendProgress = 0.0
            sendStatusText = ""
            isSendingReply = false
            errorMessage = error.localizedDescription
            notifyEmailSent(subject: subject, success: false, error: error.localizedDescription)
            throw error
        }
    }

    // MARK: - 已发送保存到本地

    /// 将刚发出的邮件保存到"已发送(本地)"文件夹，便于在客户端查看
    fileprivate func saveSentMessageToLocalFolder(
        account: EmailAccount,
        to: [EmailContact],
        cc: [EmailContact],
        bcc: [EmailContact],
        subject: String,
        body: String,
        htmlBody: String?
    ) {
        guard let folder = emailStore.getLocalSentFolder(for: account.id) else { return }
        let from = EmailContact(name: account.displayName.isEmpty ? nil : account.displayName, email: account.emailAddress)
        let preview = body.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let sentMessage = EmailMessage(
            accountId: account.id,
            folderId: folder.id,
            uid: nil,
            messageId: nil,
            threadId: nil,
            subject: subject.isEmpty ? "(无主题)" : subject,
            from: from,
            to: to,
            cc: cc,
            bcc: bcc,
            replyTo: [],
            textBody: body.isEmpty ? nil : body,
            htmlBody: htmlBody,
            preview: String(preview),
            date: now,
            receivedDate: now,
            isRead: true,
            isStarred: false,
            isImportant: false,
            isNoReply: false,
            hasAttachments: false,
            isSpam: false,
            isDeleted: false,
            containsRemoteResources: false,
            hasBeenReplied: false,
            isDraft: false,
            syncedAt: now,
            updatedAt: now,
            isBodyLoaded: true
        )
        Task {
            try? await emailStore.addMessages([sentMessage], folderId: folder.id)
        }
    }

    // MARK: - Send Notification

    /// 邮件发送完成后通知用户
    fileprivate func notifyEmailSent(subject: String, success: Bool, error: String? = nil) {
        // 播放系统提示音
        if success {
            if let sound = NSSound(named: .init("Mail Sent")) {
                sound.play()
            } else {
                NSSound.beep()
            }
        } else {
            NSSound.beep()
        }

        // 发送系统通知
        let content = UNMutableNotificationContent()
        if success {
            content.title = "邮件已发送"
            content.body = subject.isEmpty ? "邮件发送成功" : "「\(subject)」已发送"
            content.sound = .default
        } else {
            content.title = "邮件发送失败"
            content.body = error ?? "发送时遇到问题，请稍后重试"
            content.sound = .defaultCritical
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // 立即显示
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ [EmailViewModel] 发送通知失败: \(error)")
            }
        }
    }

    // MARK: - 内部 helper

    /// 格式化日期用于引用（仅给本 extension 使用）
    fileprivate func formatComposeDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}
