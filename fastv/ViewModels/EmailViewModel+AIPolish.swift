//
//  EmailViewModel+AIPolish.swift
//  fastv
//
//  从 EmailViewModel.swift 拆出的 AI 美化 / 润色相关方法。
//  这一段相对独立：依赖 EmailViewModel 已有的 composeDraft / replyDraft / errorMessage
//  / emailAIService / splitReplyBody。
//

import Foundation
import AppKit

extension EmailViewModel {
    /// AI 美化新邮件草稿（支持选中文本）
    func aiPolishComposeDraft(mode: EmailAIService.PolishMode, selectedText: String? = nil, selectedRange: NSRange? = nil) async -> String? {
        guard var draft = composeDraft else {
            errorMessage = "没有正在编写的邮件"
            return nil
        }

        let originalBody = draft.body

        // 如果有选中文本，只美化选中部分
        if let selectedText = selectedText, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let selectedRange = selectedRange else {
                errorMessage = "选中范围无效"
                return nil
            }

            isPolishingCompose = true
            errorMessage = nil

            do {
                let polishedSelection = try await emailAIService.polishEmailBody(text: selectedText, mode: mode)

                // 替换选中部分
                let nsString = originalBody as NSString
                let newBody = nsString.replacingCharacters(in: selectedRange, with: polishedSelection)

                draft.body = newBody
                composeDraft = draft
                print("✅ [EmailViewModel] AI 美化选中文本成功")
                isPolishingCompose = false
                return newBody
            } catch {
                errorMessage = "AI 美化失败: \(error.localizedDescription)"
                print("❌ [EmailViewModel] AI 美化选中文本失败: \(error)")
                isPolishingCompose = false
                return nil
            }
        }

        // 美化整个正文
        let trimmedBody = originalBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            errorMessage = "正文内容为空，无法美化"
            return nil
        }

        isPolishingCompose = true
        errorMessage = nil

        do {
            let polishedBody = try await emailAIService.polishEmailBody(text: trimmedBody, mode: mode)
            draft.body = polishedBody
            composeDraft = draft
            print("✅ [EmailViewModel] AI 美化新邮件成功")
            isPolishingCompose = false
            return polishedBody
        } catch {
            errorMessage = "AI 美化失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] AI 美化新邮件失败: \(error)")
            isPolishingCompose = false
            return nil
        }
    }

    /// AI 美化回复草稿（支持选中文本）
    func aiPolishReplyDraft(mode: EmailAIService.PolishMode, selectedText: String? = nil, selectedRange: NSRange? = nil) async -> String? {
        guard var draft = replyDraft else {
            errorMessage = "没有正在回复的邮件"
            return nil
        }

        let originalBody = draft.body

        // 如果有选中文本，检查选中部分是否在引用区域内
        if let selectedText = selectedText, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let selectedRange = selectedRange else {
                errorMessage = "选中范围无效"
                return nil
            }

            // 检查选中部分是否包含引用内容
            let (userPart, quotedPart) = splitReplyBody(originalBody)

            // 如果选中范围与引用部分重叠，不允许美化
            if !quotedPart.isEmpty && selectedRange.location + selectedRange.length > userPart.count {
                errorMessage = "不能美化引用内容，请只选择您撰写的部分"
                return nil
            }

            isPolishingReply = true
            errorMessage = nil

            do {
                let polishedSelection = try await emailAIService.polishEmailBody(text: selectedText, mode: mode)

                // 替换选中部分
                let nsString = originalBody as NSString
                let newBody = nsString.replacingCharacters(in: selectedRange, with: polishedSelection)

                draft.body = newBody
                replyDraft = draft
                print("✅ [EmailViewModel] AI 美化回复选中文本成功")
                isPolishingReply = false
                return newBody
            } catch {
                errorMessage = "AI 美化失败: \(error.localizedDescription)"
                print("❌ [EmailViewModel] AI 美化回复选中文本失败: \(error)")
                isPolishingReply = false
                return nil
            }
        }

        // 美化整个用户撰写部分
        let (userPart, quotedPart) = splitReplyBody(originalBody)

        guard !userPart.isEmpty else {
            errorMessage = "没有可美化的内容（可能只有引用部分）"
            return nil
        }

        isPolishingReply = true
        errorMessage = nil

        do {
            let polishedUserPart = try await emailAIService.polishEmailBody(text: userPart, mode: mode)

            // 拼接美化后的用户部分和原始引用部分
            if quotedPart.isEmpty {
                draft.body = polishedUserPart
            } else {
                // 确保两部分之间有适当的换行
                let separator = originalBody.contains("\n\n") ? "\n\n" : "\n"
                draft.body = polishedUserPart + separator + quotedPart
            }

            replyDraft = draft
            print("✅ [EmailViewModel] AI 美化回复成功")
            isPolishingReply = false
            return draft.body
        } catch {
            errorMessage = "AI 美化失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] AI 美化回复失败: \(error)")
            isPolishingReply = false
            return nil
        }
    }
}
