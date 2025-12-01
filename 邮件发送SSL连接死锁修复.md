# 邮件发送 SSL 连接死锁修复

## 问题描述

在发送邮件时，应用在 SMTP SSL 连接阶段挂起，最终收到 SIGTERM 信号终止：

```
Connection interrupted
signal SIGTERM
wait_runloop at mailstream_cfstream.c:812
mailstream_cfstream_set_ssl_enabled
mailsmtp_cfssl_connect
```

## 根本原因

LibEtPan 使用 CFStream 进行 SSL 连接，需要运行在有 runloop 的线程上。之前的实现在主线程（`MainActor.run`）中同步调用 SSL 连接函数，导致：

1. SSL 连接函数内部调用 `wait_runloop` 等待 runloop 处理 SSL 握手事件
2. 但主线程被阻塞在等待中，runloop 无法处理这些事件
3. 形成死锁，最终超时被系统终止

## 解决方案

将所有 LibEtPan 的网络操作从主线程移到后台线程执行，使用 `Task.detached(priority: .userInitiated)` 替代 `MainActor.run`。

### 修改的函数

#### SMTP 相关：
- `getOrCreateSMTPSession` - SMTP 会话创建和连接
- `sendMessage` - 发送邮件

#### IMAP 相关：
- `getOrCreateIMAPSession` - IMAP 会话创建和连接
- `syncMessages` - 同步邮件列表
- `scheduleBackgroundSync` - 后台同步邮件
- `fetchMessageBody` - 获取邮件正文
- `fetchFolders` - 获取文件夹列表
- `markAsRead` - 标记已读
- `deleteMessage` - 删除邮件
- `toggleStar` - 切换星标
- `downloadAttachment` - 下载附件
- `moveMessage` - 移动邮件

#### 测试相关：
- `testConnection` - 测试连接
- `testIMAPStage` - 测试 IMAP
- `testSMTPStage` - 测试 SMTP

## 技术细节

### 之前的实现（有问题）：
```swift
// LibEtPan 的 CFStream 操作必须在主线程执行
return try await MainActor.run {
    // ...
    try smtp.connect()  // 在主线程阻塞等待
    // ...
}
```

### 新的实现（修复后）：
```swift
// 在后台线程执行 SMTP 操作，避免主线程阻塞
return try await Task.detached(priority: .userInitiated) {
    // ...
    try smtp.connect()  // 在后台线程等待，有自己的 runloop
    // ...
}.value
```

## 为什么后台线程可以工作

1. **每个线程都有自己的 runloop**：后台线程可以创建自己的 runloop 来处理 CFStream 事件
2. **避免阻塞主线程**：网络操作在后台线程等待，不影响主线程和 UI
3. **LibEtPan 会自动管理 runloop**：LibEtPan 的 CFStream 实现会在需要时创建和运行 runloop

## 测试建议

1. **测试 SMTP 连接**：
   - 验证 SSL (465) 和 STARTTLS (587) 连接都能正常工作
   - 确认不会出现死锁或超时

2. **测试 IMAP 连接**：
   - 验证邮件同步功能正常
   - 确认大量邮件同步时不会卡顿

3. **测试 UI 响应性**：
   - 在发送邮件或同步邮件时，UI 应该保持响应
   - 不应该出现卡顿或冻结

## 注意事项

1. **线程安全**：确保共享数据（如 `smtpSessions`、`imapSessions`）的访问是线程安全的
2. **错误处理**：后台线程的错误会正确传播到调用方
3. **超时设置**：LibEtPan 的超时设置（30秒）仍然有效

## 相关文件

- `fastv/Services/EmailService.swift` - 主要修改
- `fastv/Services/LibEtPanWrapper.m` - LibEtPan 封装（未修改）

## 日期

2025-12-01

