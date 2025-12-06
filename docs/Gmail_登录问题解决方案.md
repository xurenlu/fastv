# Gmail IMAP 登录错误 28 解决方案

## 问题分析

根据日志：
```
✅ [LibEtPan] IMAP 连接成功
🔐 [LibEtPan] 尝试登录 IMAP，用户名: xurenlu@gmail.com
❌ [LibEtPan] IMAP 登录失败，错误代码: 28
```

**连接成功但登录失败**，错误代码 28 表示认证失败。

## 原因

Gmail 不再支持使用普通密码进行 IMAP 登录，必须使用以下方式之一：

### 方案 1：使用应用专用密码（推荐）

如果您的 Google 账号启用了两步验证，需要生成应用专用密码：

1. 访问 Google 账号设置：https://myaccount.google.com/security
2. 找到"两步验证"部分
3. 点击"应用专用密码"
4. 选择"邮件"和"Mac"
5. 生成密码（16位，无空格）
6. **在应用中使用这个密码代替原密码**

### 方案 2：使用 OAuth 2.0（更安全，但实现复杂）

Gmail 推荐使用 OAuth 2.0 进行身份验证，但需要：
- 在 Google Cloud Console 注册应用
- 实现 OAuth 2.0 授权流程
- 使用 access token 代替密码

### 方案 3：启用 IMAP（必须）

确保您的 Gmail 账号已启用 IMAP：

1. 登录 Gmail 网页版
2. 点击右上角齿轮图标 → 查看所有设置
3. 转到"转发和 POP/IMAP"选项卡
4. 在"IMAP 访问"部分，选择"启用 IMAP"
5. 保存更改

## LibEtPan 错误代码对照

```
MAILIMAP_ERROR_BAD_STATE = 0
MAILIMAP_ERROR_STREAM = 1
MAILIMAP_ERROR_PARSE = 2
MAILIMAP_ERROR_CONNECTION_REFUSED = 3
MAILIMAP_ERROR_MEMORY = 4
MAILIMAP_ERROR_FATAL = 5
MAILIMAP_ERROR_PROTOCOL = 6
MAILIMAP_ERROR_DONT_ACCEPT_CONNECTION = 7
MAILIMAP_ERROR_APPEND = 8
MAILIMAP_ERROR_NOOP = 9
MAILIMAP_ERROR_LOGOUT = 10
MAILIMAP_ERROR_CAPABILITY = 11
MAILIMAP_ERROR_CHECK = 12
MAILIMAP_ERROR_CLOSE = 13
MAILIMAP_ERROR_EXPUNGE = 14
MAILIMAP_ERROR_COPY = 15
MAILIMAP_ERROR_UID_COPY = 16
MAILIMAP_ERROR_CREATE = 17
MAILIMAP_ERROR_DELETE = 18
MAILIMAP_ERROR_EXAMINE = 19
MAILIMAP_ERROR_FETCH = 20
MAILIMAP_ERROR_UID_FETCH = 21
MAILIMAP_ERROR_LIST = 22
MAILIMAP_ERROR_LOGIN = 23
MAILIMAP_ERROR_LSUB = 24
MAILIMAP_ERROR_RENAME = 25
MAILIMAP_ERROR_SEARCH = 26
MAILIMAP_ERROR_UID_SEARCH = 27
MAILIMAP_ERROR_SELECT = 28  ← 您的错误
```

**错误 28 = MAILIMAP_ERROR_SELECT**，表示无法选择/认证邮箱。

## 立即行动

1. **生成 Gmail 应用专用密码**（如果启用了两步验证）
2. **确认 IMAP 已启用**
3. **在应用中使用应用专用密码测试连接**

## 关于代理

日志显示"代理未启用"，这是因为 UserPreferences 中 `emailProxyEnabled` 默认为 true，但可能还未同步。
既然连接成功了，说明：
- 系统代理（127.0.0.1:7856）已经在起作用
- LibEtPan 通过 CFNetwork 自动使用了系统代理
- 不需要在应用中额外设置代理

## 下一步

如果使用应用专用密码后仍然失败，可能需要实现 OAuth 2.0。

