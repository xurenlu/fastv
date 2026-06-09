//
//  EmailViewModel+Translate.swift
//  fastv
//
//  从 EmailViewModel.swift 拆出的"AI HTML 排版优化 / 邮件正文翻译 / 正文截断 banner helpers"。
//  这一段是邮件详情面板上"AI 加工原文显示"的相关能力，逻辑互相独立、与主 ViewModel 解耦。
//

import Foundation

extension EmailViewModel {
    // MARK: - AI HTML Layout Optimization

    /// AI智能优化邮件HTML排版（异步，不阻塞UI）
    /// - Parameter message: 要优化的邮件
    func optimizeHTMLLayout(for message: EmailMessage) {
        // 检查是否有HTML内容
        guard let htmlBody = message.htmlBody, !htmlBody.isEmpty else {
            errorMessage = "此邮件没有HTML内容可优化"
            return
        }

        // 检查是否已经优化过
        if optimizedHTMLCache[message.id] != nil {
            // 已经优化过，切换回原始版本（立即执行，不影响性能）
            optimizedHTMLCache.removeValue(forKey: message.id)
            print("🔄 [EmailViewModel] 恢复原始排版，邮件ID: \(message.id)")
            return
        }

        // 检查是否已经有优化任务在运行
        if optimizingMessageIds.contains(message.id) {
            print("⚠️ [EmailViewModel] 邮件正在优化中，跳过重复请求，邮件ID: \(message.id)")
            return
        }

        let messageId = message.id
        let textBody = message.textBody

        // 标记为正在优化
        optimizingMessageIds.insert(messageId)
        errorMessage = nil

        print("🚀 [EmailViewModel] 开始AI排版优化（后台任务），邮件ID: \(messageId)")

        // 创建后台任务，不阻塞UI
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                // 在后台线程执行AI优化（耗时操作）
                let optimizedHTML = try await self?.emailAIService.optimizeHTMLLayout(
                    htmlBody: htmlBody,
                    textBody: textBody,
                    existingStyles: nil
                )

                // 回到主线程更新UI状态
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    // 用户已取消（或换了别的邮件，cancelOptimization 已经清掉状态）就不要再写回 cache。
                    guard !Task.isCancelled, self.optimizingMessageIds.contains(messageId) else {
                        self.optimizationTasks.removeValue(forKey: messageId)
                        return
                    }

                    // 保存优化后的HTML到缓存
                    if let optimizedHTML = optimizedHTML {
                        self.optimizedHTMLCache[messageId] = optimizedHTML
                        print("✅ [EmailViewModel] AI排版优化成功，邮件ID: \(messageId)")
                        print("📊 [EmailViewModel] 原始长度: \(htmlBody.count), 优化后长度: \(optimizedHTML.count)")
                    }

                    self.optimizingMessageIds.remove(messageId)
                    self.optimizationTasks.removeValue(forKey: messageId)
                }
            } catch {
                // 回到主线程处理错误
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    // 取消导致的错误不当作真实失败提示。
                    let isCancellation = (error is CancellationError)
                        || ((error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled)
                    if !isCancellation, self.selectedMessageId == messageId {
                        self.errorMessage = "AI排版优化失败: \(error.localizedDescription)"
                    }
                    print("❌ [EmailViewModel] AI排版优化失败，邮件ID: \(messageId), 错误: \(error)")

                    self.optimizingMessageIds.remove(messageId)
                    self.optimizationTasks.removeValue(forKey: messageId)
                }
            }
        }

        // 保存任务引用，以便需要时可以取消
        optimizationTasks[messageId] = task
    }

    /// 取消正在进行的优化任务
    /// - Parameter messageId: 邮件ID
    func cancelOptimization(for messageId: UUID) {
        if let task = optimizationTasks[messageId] {
            task.cancel()
            optimizationTasks.removeValue(forKey: messageId)
            optimizingMessageIds.remove(messageId)
            print("🛑 [EmailViewModel] 取消AI排版优化，邮件ID: \(messageId)")
        }
    }

    /// 获取优化后的HTML（如果有）
    /// - Parameter message: 邮件
    /// - Returns: 优化后的HTML，如果没有优化过则返回nil
    func getOptimizedHTML(for message: EmailMessage) -> String? {
        return optimizedHTMLCache[message.id]
    }

    /// 检查邮件是否已优化排版
    /// - Parameter message: 邮件
    /// - Returns: 是否已优化
    func isLayoutOptimized(for message: EmailMessage) -> Bool {
        return optimizedHTMLCache[message.id] != nil
    }

    /// 检查邮件是否正在优化中
    /// - Parameter message: 邮件
    /// - Returns: 是否正在优化
    func isOptimizing(for message: EmailMessage) -> Bool {
        return optimizingMessageIds.contains(message.id)
    }

    // MARK: - AI Translate (邮件正文翻译，再点切回原文)

    /// 翻译邮件正文（首次点击触发 AI 翻译，再次点击切回原文）
    /// - Parameters:
    ///   - message: 要翻译的邮件
    ///   - targetLanguage: 目标语言，默认中文
    func translateBody(for message: EmailMessage, targetLanguage: String = "中文") {
        // 已有翻译 → 视为"切回原文"，清掉缓存
        if translatedBodyCache[message.id] != nil {
            translatedBodyCache.removeValue(forKey: message.id)
            print("🔄 [EmailViewModel] 切回邮件原文，邮件ID: \(message.id)")
            return
        }
        // 已经在翻译，忽略重复点击
        if translatingMessageIds.contains(message.id) { return }

        // 取一份"纯文本"喂给 AI：优先 textBody；没有就剥 htmlBody 的标签
        let sourceText: String = {
            if let t = message.textBody, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return t
            }
            if let html = message.htmlBody, !html.isEmpty {
                return Self.stripHTMLTagsForTranslate(html)
            }
            return message.preview
        }()
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            errorMessage = "该邮件没有可翻译的正文"
            return
        }
        // 控制单次翻译输入规模，避免超长邮件把 token / 超时打满（≈ 8000 字以内）
        let capped = trimmedSource.count > 8000 ? String(trimmedSource.prefix(8000)) + "\n\n…（原文过长，已截断）" : trimmedSource

        let messageId = message.id
        translatingMessageIds.insert(messageId)
        errorMessage = nil

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                guard let svc = await self?.emailAIService else { return }
                let translated = try await svc.translate(text: capped, targetLanguage: targetLanguage)
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    // 已被 cancelTranslation 提前清掉状态时，不再写回缓存。
                    guard !Task.isCancelled, self.translatingMessageIds.contains(messageId) else {
                        self.translationTasks.removeValue(forKey: messageId)
                        return
                    }
                    self.translatedBodyCache[messageId] = translated
                    self.translatingMessageIds.remove(messageId)
                    self.translationTasks.removeValue(forKey: messageId)
                    print("✅ [EmailViewModel] 邮件翻译完成，邮件ID: \(messageId)")
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    let isCancellation = (error is CancellationError)
                        || ((error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled)
                    if !isCancellation, self.selectedMessageId == messageId {
                        self.errorMessage = "翻译失败：\(error.localizedDescription)"
                    }
                    self.translatingMessageIds.remove(messageId)
                    self.translationTasks.removeValue(forKey: messageId)
                    print("❌ [EmailViewModel] 邮件翻译失败，邮件ID: \(messageId), 错误: \(error)")
                }
            }
        }
        translationTasks[messageId] = task
    }

    /// 取消翻译任务
    func cancelTranslation(for messageId: UUID) {
        translationTasks[messageId]?.cancel()
        translationTasks.removeValue(forKey: messageId)
        translatingMessageIds.remove(messageId)
    }

    /// 获取翻译结果
    func getTranslatedBody(for message: EmailMessage) -> String? {
        return translatedBodyCache[message.id]
    }

    /// 是否已显示翻译版
    func isShowingTranslation(for message: EmailMessage) -> Bool {
        return translatedBodyCache[message.id] != nil
    }

    /// 是否正在翻译
    func isTranslating(for message: EmailMessage) -> Bool {
        return translatingMessageIds.contains(message.id)
    }

    // MARK: - 正文截断提示

    /// 本次会话内该邮件正文是否被截断显示（用于 EmailView 的横幅提示）
    func isBodyTruncated(for message: EmailMessage) -> Bool {
        return truncatedMessageInfo[message.id] != nil
    }

    /// 返回截断邮件的原始字节大小（已格式化为 KB/MB 字符串），未截断返回 nil
    func truncatedOriginalSizeDescription(for message: EmailMessage) -> String? {
        guard let bytes = truncatedMessageInfo[message.id] else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - 内部 helper

    /// 极轻量的 HTML 标签剥离（仅用于翻译输入的兜底，不用于展示）。
    ///
    /// 之前的实现只用 `<[^>]+>` 剥标签本身，**`<style>` / `<script>` 标签之间的
    /// CSS / JS 文本会被留下来当正文喂给 AI**。结果就是用户点翻译后，正文区
    /// 出现 "body {width: 600px;margin: 0 auto;}" 这一堆 CSS。
    /// 现在先用非贪婪正则把这一类"标签 + 内容整段"一并删掉，再剥剩余标签。
    /// 可见性：internal 让单元测试能调用；非 fileprivate 的需求来自 @testable import。
    nonisolated static func stripHTMLTagsForTranslate(_ html: String) -> String {
        var text = html

        // 1) 先把 <style>...</style> / <script>...</script> / <head>...</head> / <noscript>...</noscript>
        //    / HTML 注释整段（含内容）一刀切掉。`[\s\S]*?` 跨行非贪婪。
        let dropWithBodyPatterns = [
            #"<style\b[^>]*>[\s\S]*?</style>"#,
            #"<script\b[^>]*>[\s\S]*?</script>"#,
            #"<head\b[^>]*>[\s\S]*?</head>"#,
            #"<noscript\b[^>]*>[\s\S]*?</noscript>"#,
            #"<!--[\s\S]*?-->"#,
            // <!DOCTYPE ...> / <?xml ...?> 等头部
            #"<!DOCTYPE[^>]*>"#,
            #"<\?xml[^>]*\?>"#,
            // 条件注释（Outlook 用得极多）：<!--[if ...]>...<![endif]-->
            #"<!\[if[\s\S]*?<!\[endif\]-->"#
        ]
        for pattern in dropWithBodyPatterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        // 2) 把常见块级标签转换为换行，避免剥完段落粘连
        let breakTags = ["</p>", "</div>", "</li>", "</tr>", "</br>", "<br>", "<br/>", "<br />",
                         "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>"]
        for t in breakTags {
            text = text.replacingOccurrences(of: t, with: "\n", options: .caseInsensitive)
        }

        // 3) 去掉所有剩余标签
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // 4) HTML 实体兜底
        let entities = [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                        ("&quot;", "\""), ("&apos;", "'")]
        for (e, r) in entities {
            text = text.replacingOccurrences(of: e, with: r)
        }
        // 通用数字字符引用 `&#1234;` 与 `&#x4e2d;` → Unicode 字符
        text = decodeNumericEntities(in: text)

        // 5) 压缩连续空白：水平方向用 trim + " {2,}" → 1 空格；垂直方向限 2 空行
        text = text.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        // 6) 行内 trim：每一行的首尾空白
        text = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 数字字符引用还原：`&#1234;` / `&#x4e2d;` → Unicode 字符。
    /// 非法值 / 越界静默丢弃。
    nonisolated private static func decodeNumericEntities(in text: String) -> String {
        let pattern = #"&#(x?)([0-9a-fA-F]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        var result = text
        for m in matches.reversed() {
            guard m.numberOfRanges == 3,
                  let whole = Range(m.range, in: result),
                  let hexMarker = Range(m.range(at: 1), in: result),
                  let numRange = Range(m.range(at: 2), in: result) else { continue }
            let isHex = !result[hexMarker].isEmpty
            let numStr = String(result[numRange])
            let radix = isHex ? 16 : 10
            if let code = UInt32(numStr, radix: radix),
               let scalar = Unicode.Scalar(code) {
                result.replaceSubrange(whole, with: String(Character(scalar)))
            } else {
                result.replaceSubrange(whole, with: "")
            }
        }
        return result
    }
}
