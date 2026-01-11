# FastV DMG 打包分发指南

## 📦 完整打包流程

本指南介绍如何将 FastV 应用打包成 DMG 文件，用于分发给普通用户。

## 🚀 快速开始

### 一键打包脚本

使用 `package_for_distribution.sh` 脚本，它会自动完成所有步骤：

```bash
# 给脚本添加执行权限（首次使用）
chmod +x package_for_distribution.sh

# 完整打包（包含公证）
./package_for_distribution.sh

# 跳过公证（仅打包和签名）
./package_for_distribution.sh --skip-notarization

# 指定参数
./package_for_distribution.sh \
  --apple-id "your-email@example.com" \
  --team-id "W49B66SUW3" \
  --app-password "your-app-specific-password"
```

## 📋 脚本功能

`package_for_distribution.sh` 脚本会自动完成以下步骤：

1. ✅ **检查证书** - 验证 Developer ID Application 证书是否已安装
2. ✅ **检测 Team ID** - 自动从项目配置或证书中获取 Team ID
3. ✅ **构建 Archive** - 使用 Release 配置构建应用
4. ✅ **导出应用** - 使用 Developer ID 证书签名并导出
5. ✅ **创建 DMG** - 创建带 Applications 链接的 DMG 安装包
6. ✅ **签名 DMG** - 使用 Developer ID 证书签名 DMG 文件
7. ✅ **公证应用**（可选）- 提交到 Apple 进行公证，让 Gatekeeper 信任

## 🔧 前置要求

### 1. Developer ID Application 证书

**必需**：用于分发给外部用户的证书。

#### 申请步骤：

1. **登录 Apple Developer 网站**
   - 访问：https://developer.apple.com/account
   - 使用您的 Apple Developer 账号登录（需要付费账号，$99/年）

2. **创建证书**
   - 进入 "Certificates, Identifiers & Profiles"
   - 点击 "+" 创建新证书
   - 选择 **"Developer ID Application"**
   - 按照提示完成证书创建（需要上传 CSR 文件）

3. **下载并安装证书**
   - 下载证书文件（.cer）
   - 双击安装到 Keychain
   - 或者在 Xcode 中：
     - Xcode > Settings > Accounts
     - 选择您的 Apple ID
     - 点击 "Download Manual Profiles"

#### 验证证书安装：

```bash
security find-identity -v -p codesigning | grep "Developer ID"
```

应该看到类似输出：
```
"Developer ID Application: Your Name (TEAM_ID)"
```

### 2. App-Specific Password（用于公证）

**可选但推荐**：用于提交公证的密码。

#### 创建步骤：

1. 访问：https://appleid.apple.com
2. 登录您的 Apple ID
3. 进入 "App-Specific Passwords"
4. 点击 "+" 创建新密码
5. 输入描述（如 "FastV Notarization"）
6. 复制生成的密码（只显示一次）

## 📝 使用方法

### 方法 1：完整打包（推荐）

包含所有步骤，包括公证：

```bash
./package_for_distribution.sh
```

脚本会提示您输入：
- Apple ID
- App-Specific Password

### 方法 2：跳过公证

如果暂时不需要公证：

```bash
./package_for_distribution.sh --skip-notarization
```

### 方法 3：指定所有参数

避免交互式输入：

```bash
./package_for_distribution.sh \
  --apple-id "your-email@example.com" \
  --team-id "W49B66SUW3" \
  --app-password "abcd-efgh-ijkl-mnop"
```

## 📂 输出文件

打包完成后，会在 `build/` 目录下生成：

- `build/export/row1.app` - 已签名的应用
- `build/row1.dmg` - DMG 安装包（已签名，可选公证）

## ✅ 验证打包结果

### 1. 验证应用签名

```bash
codesign -dvv build/export/row1.app | grep -E "Authority=|TeamIdentifier="
```

应该显示：
```
Authority=Developer ID Application: Your Name (TEAM_ID)
TeamIdentifier=TEAM_ID
```

### 2. 验证 DMG 签名

```bash
codesign -dvv build/row1.dmg | grep -E "Authority=|TeamIdentifier="
```

### 3. 验证公证（如果已公证）

```bash
xcrun stapler validate build/row1.dmg
```

应该显示：
```
The validate action worked!
```

### 4. 测试 DMG

1. 双击打开 DMG 文件
2. 将应用拖到 Applications 文件夹
3. 运行应用，检查是否正常工作

## 🔍 故障排查

### 问题 1：未找到 Developer ID 证书

**错误信息：**
```
❌ 未找到 Developer ID Application 证书
```

**解决方案：**
1. 确认已申请 Developer ID Application 证书
2. 确认证书已安装到 Keychain
3. 运行 `security find-identity -v -p codesigning` 检查

### 问题 2：Archive 构建失败

**可能原因：**
- 编译错误
- 证书配置问题
- 依赖项缺失

**解决方案：**
1. 查看日志：`build/archive.log`
2. 在 Xcode 中手动构建，检查错误
3. 确保所有依赖项已正确安装

### 问题 3：导出失败

**可能原因：**
- Team ID 不匹配
- 证书权限不足
- Entitlements 配置问题

**解决方案：**
1. 查看日志：`build/export.log`
2. 检查项目配置中的 Team ID
3. 确认证书的 Team ID 与项目配置匹配

### 问题 4：公证失败

**可能原因：**
- App-Specific Password 错误
- Team ID 不匹配
- 应用签名有问题

**解决方案：**
1. 检查 App-Specific Password 是否正确
2. 确认 Team ID 与证书匹配
3. 先验证应用签名是否正确
4. 查看公证日志：
   ```bash
   xcrun notarytool log <submission-id> \
     --apple-id "your-email@example.com" \
     --team-id "TEAM_ID" \
     --password "app-specific-password"
   ```

### 问题 5：用户无法打开应用

**可能原因：**
- 未使用 Developer ID 证书签名
- 未进行公证
- Gatekeeper 阻止

**解决方案：**
1. 确认使用 Developer ID 证书签名（不是开发证书）
2. 进行公证并装订票据
3. 如果用户仍无法打开，可以临时使用：
   ```bash
   sudo xattr -rd com.apple.quarantine /path/to/row1.app
   ```
   （不推荐，仅用于测试）

## 📚 相关文档

- `Archive分发说明.md` - Archive 分发的详细说明
- `分发签名说明.md` - 签名配置说明
- `签名配置指南.md` - 完整的签名配置指南

## 🔗 相关脚本

- `build_and_sign.sh` - 仅构建和签名（不创建 DMG）
- `create_dmg.sh` - 仅创建 DMG（需要已签名的 .app）
- `notarize.sh` - 仅进行公证（需要已签名的文件）

## 💡 最佳实践

1. **始终使用 Developer ID 证书** - 不要使用开发证书分发
2. **进行公证** - 让 Gatekeeper 信任您的应用
3. **测试 DMG** - 在干净的 Mac 上测试安装和运行
4. **验证签名** - 打包后验证所有签名是否正确
5. **保存日志** - 保留构建日志以便故障排查

## ⚠️ 注意事项

1. **证书有效期** - 确保证书未过期
2. **Team ID 匹配** - 证书的 Team ID 必须与项目配置匹配
3. **权限配置** - 确保 Entitlements 配置正确
4. **动态库签名** - 确保所有动态库都已正确签名
5. **公证有效期** - 公证后的应用在更新后需要重新公证

## 🎯 分发流程总结

```
1. 申请 Developer ID Application 证书
   ↓
2. 安装证书到 Keychain
   ↓
3. 运行打包脚本
   ./package_for_distribution.sh
   ↓
4. 测试 DMG 和应用
   ↓
5. 分发给用户
```

## 📞 需要帮助？

如果遇到问题：
1. 查看构建日志：`build/archive.log`、`build/export.log`
2. 检查证书状态：`security find-identity -v -p codesigning`
3. 验证签名：`codesign -dvv build/export/row1.app`
4. 查看相关文档

