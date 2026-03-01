# 妙打 (FastV) AppleScript 功能清单

本文档列出了所有通过 AppleScript 可用的邮件操作功能。

---

## 目录

1. [账户管理](#账户管理)
2. [邮件获取](#邮件获取)
3. [邮件创建与发送](#邮件创建与发送)
4. [邮件操作](#邮件操作)
5. [搜索与过滤](#搜索与过滤)
6. [标签管理](#标签管理)
7. [附件处理](#附件处理)

---

## 账户管理

### 获取所有账户
```applescript
tell application "FastV"
    set allAccounts to accounts
    repeat with acc in allAccounts
        log "账户: " & (name of acc) & " (" & (email address of acc) & ")"
    end repeat
end tell
```

### 获取默认账户
```applescript
tell application "FastV"
    set defaultAccount to default account
    log "默认账户: " & (name of defaultAccount)
end tell
```

### 设置默认账户
```applescript
tell application "FastV"
    set defaultAccount to account "邮箱地址"
    -- 或通过对象引用设置
end tell
```

### 获取账户文件夹
```applescript
tell application "FastV"
    set acc to default account
    set accFolders to folders of acc
    repeat with fld in accFolders
        log "文件夹: " & (name of fld) & " (未读: " & (unread count of fld) & ")"
    end repeat
end tell
```

### 同步账户
```applescript
tell application "FastV"
    set acc to default account
    sync account acc
    -- 同步特定文件夹
    sync account acc folder "INBOX"
end tell
```

---

## 邮件获取

### 获取最近的邮件
```applescript
tell application "FastV"
    -- 获取收件箱最近 10 封邮件（默认）
    set recentMails to get recent mails

    -- 获取最近 20 封
    set recentMails to get recent mails count 20

    -- 获取特定文件夹的最近邮件
    set recentMails to get recent mails count 10 folder "Sent"
end tell
```

### 获取未读邮件
```applescript
tell application "FastV"
    -- 获取所有未读邮件
    set unreadMails to get unread mails

    -- 获取最近 5 封未读邮件
    set unreadMails to get unread mails count 5

    -- 获取特定文件夹的未读邮件
    set unreadMails to get unread mails count 10 folder "INBOX"
end tell
```

### 获取草稿列表
```applescript
tell application "FastV"
    -- 获取最近 20 封草稿（默认）
    set drafts to get drafts

    -- 获取最近 10 封草稿
    set drafts to get drafts limit 10
end tell
```

### 获取文件夹中的邮件
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set messages to mail messages of inboxFolder

    repeat with msg in messages
        log (subject of msg) & " - " & (from of msg)
    end repeat
end tell
```

### 获取邮件正文
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set firstMessage to first mail message of inboxFolder

    -- 获取完整正文（HTML 优先）
    set fullBody to get mail body of firstMessage

    -- 仅获取纯文本
    set plainBody to get mail body of firstMessage plain text only true
end tell
```

---

## 邮件创建与发送

### 创建邮件草稿
```applescript
tell application "FastV"
    create mail to "recipient@example.com" ¬
        with subject "会议纪要" ¬
        with body "这是今天的会议纪要..." ¬
        save as draft true
end tell
```

### 创建带抄送/密送的邮件
```applescript
tell application "FastV"
    create mail to "recipient@example.com" ¬
        subject "项目更新" ¬
        body "附件是项目进度报告" ¬
        cc "cc@example.com" ¬
        bcc "bcc@example.com" ¬
        save as draft true
end tell
```

### 创建带附件的邮件
```applescript
tell application "FastV"
    create mail to "recipient@example.com" ¬
        subject "发送文件" ¬
        body "请查收附件" ¬
        attachments {"/path/to/file1.pdf", "/path/to/file2.docx"} ¬
        save as draft true
end tell
```

### 直接发送邮件
```applescript
tell application "FastV"
    create mail to "recipient@example.com" ¬
        subject "紧急通知" ¬
        body "这是一封紧急邮件" ¬
        save as draft false
end tell
```

### 回复邮件
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    -- 回复发件人，保存为草稿
    reply to msg with body "收到，我会尽快处理。"

    -- 回复所有人
    reply to msg with body "谢谢所有人的回复。" reply all true

    -- 回复并直接发送
    reply to msg with body "确认。" send true
end tell
```

### 转发邮件
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    -- 转发，保存为草稿
    forward msg to "colleague@example.com"

    -- 转发并添加说明
    forward msg to "colleague@example.com" with body "请查看这封邮件。"

    -- 转发并直接发送
    forward msg to "colleague@example.com" with body "请及时处理。" send true
end tell
```

---

## 邮件操作

### 标记已读/未读
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    -- 标记为已读
    mark as read msg

    -- 或直接设置属性
    set is read of msg to true

    -- 标记为未读
    mark as unread msg
    set is read of msg to false
end tell
```

### 标记星标
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    -- 添加星标
    set is starred of msg to true

    -- 或使用命令
    mark mail starred msg starred true

    -- 移除星标
    set is starred of msg to false
end tell
```

### 移动邮件
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    -- 移动到归档
    move mail msg to "Archive"

    -- 移动到自定义文件夹
    move mail msg to "项目文档"
end tell
```

### 归档邮件
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    archive mail msg
end tell
```

### 标记垃圾邮件
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    -- 标记为垃圾邮件
    mark as spam msg

    -- 取消垃圾邮件标记
    unmark spam msg
end tell
```

### 删除邮件
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    delete mail msg
end tell
```

### 删除草稿
```applescript
tell application "FastV"
    set drafts to get drafts
    if (count of drafts) > 0 then
        set firstDraft to first item of drafts
        delete draft firstDraft
    end if
end tell
```

### 更新草稿
```applescript
tell application "FastV"
    set drafts to get drafts
    if (count of drafts) > 0 then
        set firstDraft to first item of drafts
        update draft firstDraft subject "新主题" body "新内容"
    end if
end tell
```

---

## 搜索与过滤

### 搜索邮件
```applescript
tell application "FastV"
    -- 搜索所有邮件
    set results to search mails query "项目"

    -- 在特定文件夹搜索
    set results to search mails query "会议" in folder "INBOX"

    -- 搜索并限制数量
    set results to search mails query "报告" limit 20

    -- 仅搜索未读邮件
    set results to search mails query "紧急" unread only true

    repeat with msg in results
        log (subject of msg) & " - " & (from of msg)
    end repeat
end tell
```

### 获取带标签的邮件
```applescript
tell application "FastV"
    -- 获取带特定标签的邮件
    set taggedMails to get mails with tag "工作"

    -- 限制数量
    set taggedMails to get mails with tag "重要" limit 10

    repeat with msg in taggedMails
        log (subject of msg)
    end repeat
end tell
```

### 使用过滤器获取邮件
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set allMessages to mail messages of inboxFolder

    -- 获取所有未读邮件
    set unreadMessages to every mail message of inboxFolder whose is read is false

    -- 获取所有星标邮件
    set starredMessages to every mail message of inboxFolder whose is starred is true

    -- 获取带附件的邮件
    set messagesWithAttachments to every mail message of inboxFolder whose has attachments is true
end tell
```

---

## 标签管理

### 添加标签
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    -- 添加单个标签
    add tag "重要" to mail msg

    -- 直接设置标签列表
    set tags of msg to {"工作", "紧急", "待处理"}
end tell
```

### 移除标签
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    remove tag "旧标签" from mail msg
end tell
```

### 获取邮件标签
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    set mailTags to tags of msg
    repeat with tagItem in mailTags
        log tagItem
    end repeat

    -- 获取 AI 生成的标签
    set aiTags to ai tags of msg
end tell
```

---

## 附件处理

### 获取邮件附件列表
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    if (has attachments of msg) is true then
        set attachmentsList to attachments of msg
        repeat with att in attachmentsList
            log "附件: " & (name of att) & " (" & (size of att) & " bytes)"
        end repeat
    end if
end tell
```

### 检查邮件是否有附件
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    if (has attachments of msg) then
        log "此邮件包含附件"
    else
        log "此邮件无附件"
    end if
end tell
```

---

## 邮件属性访问

### 读取邮件基本信息
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    log "主题: " & (subject of msg)
    log "发件人: " & (from of msg)
    log "发件人邮箱: " & (from address of msg)
    log "收件人: " & (to of msg)
    log "抄送: " & (cc of msg)
    log "日期: " & (date sent of msg)
    log "已读: " & (is read of msg)
    log "星标: " & (is starred of msg)
    log "重要: " & (is important of msg)
    log "预览: " & (preview of msg)
end tell
```

### 获取 AI 分析信息
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set msg to first mail message of inboxFolder

    -- AI 生成的摘要
    set summary to ai summary of msg
    log "AI 摘要: " & summary

    -- AI 生成的标签
    set aiTags to ai tags of msg
    log "AI 标签: " & aiTags

    -- AI 识别的优先级
    set priority to ai priority of msg
    log "AI 优先级: " & priority
end tell
```

---

## 实用示例

### 批量标记未读邮件为已读
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set unreadMessages to every mail message of inboxFolder whose is read is false

    repeat with msg in unreadMessages
        mark as read msg
    end repeat

    log "已标记 " & (count of unreadMessages) & " 封邮件为已读"
end tell
```

### 清理旧邮件
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set allMessages to mail messages of inboxFolder

    -- 归档 30 天前的已读邮件
    set thirtyDaysAgo to (current date) - (30 * days)
    set oldMessages to {}

    repeat with msg in allMessages
        if (is read of msg) is true and (date received of msg) < thirtyDaysAgo then
            set end of oldMessages to msg
        end if
    end repeat

    repeat with msg in oldMessages
        archive mail msg
    end repeat

    log "已归档 " & (count of oldMessages) & " 封旧邮件"
end tell
```

### 自动分类邮件
```applescript
tell application "FastV"
    set acc to default account
    set inboxFolder to first folder of acc whose folder type is "inbox"
    set allMessages to mail messages of inboxFolder

    -- 根据发件人自动分类
    repeat with msg in allMessages
        set sender to from address of msg

        if sender contains "boss@company.com" then
            add tag "老板" to mail msg
            set is starred of msg to true
        else if sender contains "newsletter@" then
            move mail msg to "Archive"
            mark as read msg
        else if sender contains "hr@company.com" then
            add tag "人事" to mail msg
        end if
    end repeat
end tell
```

---

## 错误处理

### 基本错误处理
```applescript
tell application "FastV"
    try
        set acc to default account
        set inboxFolder to first folder of acc whose folder type is "inbox"
        set msg to first mail message of inboxFolder
        log "成功获取邮件"
    on error errMsg
        log "错误: " & errMsg
    end try
end tell
```

---

## 注意事项

1. **异步操作**：某些操作（如同步、发送邮件）是异步的，可能需要几秒钟才能完成
2. **性能**：处理大量邮件时，建议使用 `limit` 参数限制返回数量
3. **文件夹名称**：文件夹名称区分大小写，或使用文件夹类型（如 "inbox", "sent", "drafts"）
4. **日期格式**：AppleScript 使用系统本地化的日期格式

---

## 更多帮助

- 查看 `tests/applescript/BasicAppleScriptTest.scpt` 了解基础用法
- 查看 `tests/applescript/AIIntegrationExamples.scpt` 了解 AI 集成示例
- 查看 `tests/applescript/python_fastv_example.py` 了解 Python 调用示例
