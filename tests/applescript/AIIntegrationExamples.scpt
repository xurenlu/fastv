# ============================================================
# 妙打 (FastV) AI 集成示例脚本
# ============================================================
# 展示 AI 应用如何通过 AppleScript 与 FastV 邮件应用交互
#
# 适用场景:
# - Claude/ChatGPT 等 AI 应用读取用户邮件
# - AI 生成回复草稿并存入草稿箱
# - AI 批量处理邮件（分类、标记等）
# ============================================================

# ============================================================
# 场景 1: AI 获取最新邮件进行分析
# ============================================================

on GetRecentEmailsForAnalysis()
	tell application "FastV"
		activate

		-- 获取默认账户的收件箱
		set defaultAccount to default account
		set inboxFolder to first folder of defaultAccount whose folder type is "inbox"

		-- 获取最新 10 封邮件
		set recentMessages to mail messages of inboxFolder
		set maxCount to 10
		if (count of recentMessages) < maxCount then
			set maxCount to (count of recentMessages)
		end if

		-- 构建邮件摘要文本（供 AI 分析）
		set emailSummary to ""
		repeat with i from 1 to maxCount
			set msg to item i of recentMessages
			set emailSummary to emailSummary & "邮件 " & i & ": " & (subject of msg) & linefeed
			set emailSummary to emailSummary & "  发件人: " & (from of msg) & linefeed
			set emailSummary to emailSummary & "  日期: " & (date sent of msg) & linefeed
			set emailSummary to emailSummary & "  预览: " & (preview of msg) & linefeed
			set emailSummary to emailSummary & linefeed
		end repeat

		return emailSummary
	end tell
end GetRecentEmailsForAnalysis

# ============================================================
# 场景 2: AI 生成回复并存为草稿
# ============================================================

on CreateAIReplyToMessage(messageId, replyBody, sendDirectly)
	tell application "FastV"
		-- 根据消息 ID 找到对应邮件（实际实现中可能需要改进）
		set defaultAccount to default account
		set inboxFolder to first folder of defaultAccount whose folder type is "inbox"
		set targetMessage to first mail message of inboxFolder

		-- 创建回复
		reply to targetMessage with body replyBody send sendDirectly

		return "已创建回复草稿"
	end tell
end CreateAIReplyToMessage

# ============================================================
# 场景 3: AI 批量标记邮件
# ============================================================

on MarkEmailsAsImportant(keywordList)
	tell application "FastV"
		set defaultAccount to default account
		set inboxFolder to first folder of defaultAccount whose folder type is "inbox"
		set allMessages to mail messages of inboxFolder

		-- 遍历所有邮件，根据关键词标记重要邮件
		set markedCount to 0
		repeat with msg in allMessages
			set msgSubject to subject of msg
			set msgPreview to preview of msg

			-- 检查是否包含关键词
			repeat with keyword in keywordList
				if msgSubject contains keyword or msgPreview contains keyword then
					-- 标记为星标
					set is starred of msg to true
					set markedCount to markedCount + 1
					exit repeat
				end if
			end repeat
		end repeat

		return "已标记 " & markedCount & " 封邮件为重要"
	end tell
end MarkEmailsAsImportant

# ============================================================
# 场景 4: AI 获取未读邮件摘要
# ============================================================

on GetUnreadEmailsSummary()
	tell application "FastV"
		set defaultAccount to default account
		set inboxFolder to first folder of defaultAccount whose folder type is "inbox"

		-- 获取所有邮件
		set allMessages to mail messages of inboxFolder

		-- 筛选未读邮件
		set unreadMessages to {}
		repeat with msg in allMessages
			if (is read of msg) is false then
				set end of unreadMessages to msg
			end if
		end repeat

		-- 构建未读邮件摘要
		set summary to "未读邮件数量: " & (count of unreadMessages) & linefeed & linefeed

		repeat with i from 1 to (count of unreadMessages)
			set msg to item i of unreadMessages
			set summary to summary & i & ". " & (subject of msg) & linefeed
			set summary to summary & "   来自: " & (from of msg) & linefeed
			set summary to summary & "   时间: " & (date sent of msg) & linefeed

			-- 获取 AI 摘要（如果有）
			set aiSummary to ai summary of msg
			if aiSummary is not missing value and aiSummary is not "" then
				set summary to summary & "   AI 摘要: " & aiSummary & linefeed
			end if

			set summary to summary & linefeed
		end repeat

		return summary
	end tell
end GetUnreadEmailsSummary

# ============================================================
# 场景 5: AI 创建新邮件
# ============================================================

on CreateEmailWithAI(toAddress, emailSubject, emailBody, attachmentPaths)
	tell application "FastV"
		-- 如果提供了附件路径，则包含附件
		if attachmentPaths is not missing value and (count of attachmentPaths) > 0 then
			create mail to toAddress ¬
				with subject emailSubject ¬
				with body emailBody ¬
				attachments attachmentPaths ¬
				save as draft true
		else
			create mail to toAddress ¬
				with subject emailSubject ¬
				with body emailBody ¬
				save as draft true
		end if

		return "已创建邮件草稿"
	end tell
end CreateEmailWithAI

# ============================================================
# 场景 6: AI 获取邮件全文内容
# ============================================================

on GetEmailFullContent(messageIndex)
	tell application "FastV"
		set defaultAccount to default account
		set inboxFolder to first folder of defaultAccount whose folder type is "inbox"
		set allMessages to mail messages of inboxFolder

		if messageIndex > 0 and messageIndex ≤ (count of allMessages) then
			set msg to item messageIndex of allMessages

			set fullContent to "主题: " & (subject of msg) & linefeed
			set fullContent to fullContent & "发件人: " & (from of msg) & linefeed
			set fullContent to fullContent & "收件人: " & (to of msg) & linefeed
			set fullContent to fullContent & "日期: " & (date sent of msg) & linefeed
			set fullContent to fullContent & linefeed

			-- 获取正文
			set textBody to text body of msg
			if textBody is not missing value then
				set fullContent to fullContent & "正文:" & linefeed & textBody
			end if

			-- 获取附件信息
			if (has attachments of msg) is true then
				set attachmentsList to attachments of msg
				set fullContent to fullContent & linefeed & lineFeed & "附件: "
				repeat with att in attachmentsList
					set fullContent to fullContent & (name of att) & " (" & (size of att) & " bytes)"
				end repeat
			end if

			return fullContent
		else
			return "错误: 邮件索引超出范围"
		end if
	end tell
end GetEmailFullContent

# ============================================================
# 测试入口点
# ============================================================

on run
	-- 测试示例：获取未读邮件摘要
	set unreadSummary to GetUnreadEmailsSummary()
	display dialog unreadSummary with title "未读邮件摘要" buttons {"确定"} default button 1

	-- 测试示例：获取最新 5 封邮件
	-- set recentEmails to GetRecentEmailsForAnalysis()
	-- display dialog recentEmails with title "最近邮件" buttons {"确定"} default button 1
end run
