# ============================================================
# 妙打 (FastV) AppleScript 基础测试脚本
# ============================================================
# 用于测试邮件应用的基本 AppleScript 功能
#
# 使用方法：
# 1. 构建并运行 fastv 应用
# 2. 在脚本编辑器中打开此脚本
# 3. 点击运行按钮
# ============================================================

tell application "FastV"
	activate

	-- 测试 1: 获取所有账户
	log "=== 测试 1: 获取账户列表 ==="
	set allAccounts to accounts
	if (count of allAccounts) > 0 then
		log "找到 " & (count of allAccounts) & " 个账户"
		repeat with currentAccount in allAccounts
			log "  - " & (name of currentAccount) & " (" & (email address of currentAccount) & ")"
		end repeat
	else
		log "  没有找到账户，请先在应用中添加邮件账户"
	end if

	-- 测试 2: 获取默认账户
	log ""
	log "=== 测试 2: 获取默认账户 ==="
	try
		set defaultAccount to default account
		log "默认账户: " & (name of defaultAccount)
	on error errMsg
		log "  错误: " & errMsg
		log "  提示: 请在应用中设置默认账户"
	end try

	-- 测试 3: 获取账户的文件夹
	log ""
	log "=== 测试 3: 获取文件夹列表 ==="
	if (count of allAccounts) > 0 then
		set firstAccount to item 1 of allAccounts
		set accountFolders to folders of firstAccount
		log "账户 " & (name of firstAccount) & " 的文件夹:"
		repeat with currentFolder in accountFolders
			log "  - " & (name of currentFolder) & " (未读: " & (unread count of currentFolder) & ")"
		end repeat
	end if

	-- 测试 4: 获取邮件列表
	log ""
	log "=== 测试 4: 获取收件箱邮件 ==="
	if (count of allAccounts) > 0 then
		set firstAccount to item 1 of allAccounts
		set accountFolders to folders of firstAccount

		-- 查找收件箱
		set inboxFolder to missing value
		repeat with currentFolder in accountFolders
			if (folder type of currentFolder) is "inbox" then
				set inboxFolder to currentFolder
				exit repeat
			end if
		end repeat

		if inboxFolder is not missing value then
			set inboxMessages to mail messages of inboxFolder
			log "收件箱邮件数量: " & (count of inboxMessages)

			-- 显示前 5 封邮件
			set displayCount to 5
			if (count of inboxMessages) < displayCount then
				set displayCount to (count of inboxMessages)
			end if

			log "最新 " & displayCount & " 封邮件:"
			repeat with i from 1 to displayCount
				set msg to item i of inboxMessages
				log "  " & i & ". " & (subject of msg)
				log "     发件人: " & (from of msg)
				log "     日期: " & (date sent of msg)
				log "     已读: " & (is read of msg)
			end repeat
		else
			log "  未找到收件箱文件夹"
		end if
	end if

	log ""
	log "=== 测试完成 ==="
end tell

-- ============================================================
-- 更多测试示例（注释掉的代码，可以取消注释进行测试）
-- ============================================================

(*
-- 测试 5: 创建邮件草稿
tell application "FastV"
	create mail to "recipient@example.com" ¬
		with subject "测试邮件" ¬
		with body "这是一封测试邮件" ¬
		save as draft true
end tell

-- 测试 6: 获取未读邮件
tell application "FastV"
	set defaultAccount to default account
	set inboxFolder to first folder of defaultAccount whose folder type is "inbox"
	set unreadMessages to every mail message of inboxFolder whose is read is false
	log "未读邮件数量: " & (count of unreadMessages)
end tell

-- 测试 7: 标记邮件为已读
tell application "FastV"
	set defaultAccount to default account
	set inboxFolder to first folder of defaultAccount whose folder type is "inbox"
	set firstMessage to first mail message of inboxFolder
	mark as read firstMessage
	log "已标记第一封邮件为已读"
end tell

-- 测试 8: 同步账户
tell application "FastV"
	set defaultAccount to default account
	sync account defaultAccount folder "INBOX"
end tell

-- 测试 9: 回复邮件
tell application "FastV"
	set defaultAccount to default account
	set inboxFolder to first folder of defaultAccount whose folder type is "inbox"
	set firstMessage to first mail message of inboxFolder
	reply to firstMessage with body "谢谢你的邮件，我会尽快回复。" send false
end tell

-- 测试 10: 搜索邮件
tell application "FastV"
	set allMessages to get mail messages search "测试"
	log "搜索到 " & (count of allMessages) & " 封包含'测试'的邮件"
end tell
*)
