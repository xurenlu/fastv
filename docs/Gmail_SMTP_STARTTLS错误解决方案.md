# Gmail SMTP STARTTLS 错误代码 24 解决方案

## 问题分析

根据日志显示：
```
🔌 [LibEtPan SMTP] Socket 连接成功，开始 STARTTLS 握手
❌ [LibEtPan SMTP] 连接失败，错误代码: 24
```

**错误代码 24** 对应 `MAILSMTP_ERROR_STARTTLS_NOT_SUPPORTED`，表示 STARTTLS 握手失败。

虽然 Gmail 支持 STARTTLS，但 LibEtPan 的 STARTTLS 实现可能在 SSL/TLS 握手过程中遇到了问题。

## 可能的原因

1. **SSL/TLS 证书验证失败**：LibEtPan 可能无法验证 Gmail 的 SSL 证书
2. **TLS 版本不兼容**：LibEtPan 使用的 TLS 版本可能与 Gmail 服务器不兼容
3. **LibEtPan STARTTLS 实现问题**：底层实现可能存在 bug

## 解决方案

### 方案 1：使用 SSL 直接连接（推荐）

Gmail 支持两种 SMTP 连接方式：
- **STARTTLS**：端口 587（先建立普通连接，然后升级到 TLS）
- **SSL 直接连接**：端口 465（直接建立 SSL 连接）

**操作步骤：**
1. 在邮箱账号设置中，将 SMTP 端口从 587 改为 465
2. 将加密方式从 "startTLS" 改为 "ssl"
3. 重新尝试发送邮件

**优点：**
- SSL 直接连接通常更稳定
- 避免了 STARTTLS 握手的问题
- Gmail 官方推荐使用端口 465

### 方案 2：检查网络和代理设置

如果使用代理，确保代理配置正确：
1. 检查代理是否支持 SMTP 流量
2. 某些代理可能不支持 STARTTLS 升级
3. 尝试禁用代理后重试

### 方案 3：检查 Gmail 账号设置

确保 Gmail 账号已启用"允许不够安全的应用访问"或使用应用专用密码：
1. 访问 https://myaccount.google.com/security
2. 如果启用了两步验证，生成应用专用密码
3. 在应用中使用应用专用密码代替普通密码

## LibEtPan 错误代码对照表

根据 `mailsmtp_types.h`，常见错误代码：

| 错误代码 | 常量名 | 含义 |
|---------|--------|------|
| 0 | MAILSMTP_NO_ERROR | 成功 |
| 23 | MAILSMTP_ERROR_STARTTLS_TEMPORARY_FAILURE | STARTTLS 临时失败 |
| **24** | **MAILSMTP_ERROR_STARTTLS_NOT_SUPPORTED** | **STARTTLS 不支持或握手失败** |
| 75 | MAILSMTP_ERROR_SSL | SSL/TLS 错误 |
| 73 | MAILSMTP_ERROR_CONNECTION_REFUSED | 连接被拒绝 |

## 日志改进

已添加详细的日志记录，现在会显示：
- 详细的错误类型和原因
- LibEtPan 错误代码
- 针对性的解决建议

## 测试建议

1. **先尝试方案 1**（使用 SSL 端口 465）
2. 如果仍然失败，查看新的日志输出，获取更详细的错误信息
3. 根据日志中的建议进行排查

## 相关文件

- `fastv/Services/EmailService.swift` - 邮件服务层
- `fastv/Services/LibEtPanWrapper.m` - LibEtPan 包装层
- `ThirdParty/libetpan/include/libetpan/mailsmtp_types.h` - SMTP 错误代码定义

