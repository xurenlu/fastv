# Archive 分发到其他 Mac 的说明

## ⚠️ 重要结论

**直接使用 Xcode Archive 生成的 APP 包分发到其他 Mac 电脑会遇到以下问题：**

### 1. ❌ 无法直接使用

**问题原因：**
- 当前项目使用的是 **"Apple Development"** 签名（开发签名）
- 开发签名只能在本机或注册的设备上运行
- 其他未注册的 Mac 无法运行使用开发签名的应用

**表现：**
- 双击应用会提示："无法打开，因为无法验证开发者"
- 或者提示："应用已损坏，无法打开"

### 2. ⚠️ 会提示不安全

**macOS Gatekeeper 行为：**
- macOS 15+ 的 Gatekeeper 会检测到应用使用开发签名
- 会显示警告："无法验证开发者"
- 用户需要手动绕过安全设置才能运行

**绕过方法（不推荐）：**
```bash
# 用户需要执行以下命令（在终端中）
sudo xattr -rd com.apple.quarantine /path/to/fastv.app
# 或者
sudo spctl --master-disable  # 完全禁用 Gatekeeper（非常不安全）
```

### 3. ⚠️ 权限申请可能有问题

**权限问题：**
- 开发签名的应用在其他 Mac 上运行时，权限请求对话框可能不会正常弹出
- 即使用户手动授权，权限也可能无法正常保存
- 特别是辅助功能权限，需要手动在系统设置中授权

**具体表现：**
- 麦克风权限：可能无法正常请求
- 辅助功能权限：必须手动在"系统设置 > 隐私与安全性 > 辅助功能"中授权
- 提醒事项权限：可能无法正常请求

## ✅ 正确的分发方案

### 方案一：使用 Developer ID 证书（推荐）

这是**唯一**可以分发给外部用户且不会提示不安全的方案。

#### 步骤 1：申请 Developer ID Application 证书

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

#### 步骤 2：验证证书安装

```bash
security find-identity -v -p codesigning | grep "Developer ID"
```

应该看到类似输出：
```
"Developer ID Application: Your Name (W49B66SUW3)"
```

#### 步骤 3：修改 Xcode 项目配置

1. **打开项目设置**
   - 选择项目 Target：`fastv`
   - 进入 "Signing & Capabilities" 标签

2. **修改签名配置**
   - 取消勾选 "Automatically manage signing"
   - 或者保持自动签名，但确保 Xcode 选择了 Developer ID 证书
   - 在 "Signing Certificate" 中选择 "Developer ID Application"

3. **修改 Archive 配置**
   - Product > Scheme > Edit Scheme
   - 选择 "Archive"
   - 在 "Build Configuration" 中选择 "Release"
   - 确保 "Archive" 使用的是 Release 配置

#### 步骤 4：执行 Archive

1. Product > Archive
2. 等待构建完成
3. 在 Organizer 窗口中，选择 Archive
4. 点击 "Distribute App"
5. 选择 "Developer ID"（不是 App Store）
6. 按照向导完成导出

#### 步骤 5：（推荐）进行公证（Notarization）

公证可以让 macOS Gatekeeper 完全信任您的应用，用户安装时不会看到任何警告。

**创建 App-Specific Password：**
1. 访问：https://appleid.apple.com
2. 登录 > App-Specific Passwords
3. 创建密码用于公证

**进行公证：**
```bash
# 使用 notarytool（推荐，macOS 13+）
xcrun notarytool submit fastv.app \
  --apple-id "your-email@example.com" \
  --team-id "W49B66SUW3" \
  --password "app-specific-password" \
  --wait

# 装订公证票据
xcrun stapler staple fastv.app
```

**验证公证：**
```bash
xcrun stapler validate fastv.app
```

### 方案二：使用 Ad-Hoc 签名（仅限测试）

**适用场景：** 仅分发给少量已知的测试用户

**限制：**
- 需要在 Apple Developer 网站注册每台设备的 UDID
- 最多只能注册 100 台设备
- 仍然可能提示不安全

**步骤：**
1. 在 Xcode 中选择 "Ad Hoc" 分发方式
2. 选择要分发的设备
3. 导出应用

### 方案三：通过 App Store 分发

**适用场景：** 正式发布，希望用户通过 App Store 下载

**要求：**
- 使用 "Apple Distribution" 证书
- 需要 App Store Connect 账号
- 需要通过 App Store 审核

### 关于 dropDMG 的说明

**dropDMG 是什么？**
- dropDMG 是一个 macOS 应用，用于创建专业的 DMG 安装包
- 可以创建带背景图、图标、窗口大小等自定义设置的 DMG 文件
- 可以对 DMG 文件本身进行签名

**dropDMG 能否解决签名问题？**
- ❌ **不能**解决应用的签名问题
- dropDMG 只是把应用打包成 DMG，**不会改变应用本身的签名类型**
- 如果应用使用的是开发签名，即使用 dropDMG 打包，签名问题依然存在

**dropDMG 的作用：**
1. ✅ **创建专业的安装包**：可以设置 DMG 的背景、图标、窗口大小等
2. ✅ **签名 DMG 文件**：如果配置了 Developer ID 证书，可以对 DMG 文件本身进行签名
3. ✅ **提升用户体验**：专业的 DMG 安装包看起来更正式

**使用 dropDMG 的正确流程：**
1. **首先**：确保应用本身使用 Developer ID 证书签名（不是开发签名）
2. **然后**：使用 dropDMG 创建 DMG 安装包
3. **配置**：在 dropDMG 中设置使用 Developer ID 证书签名 DMG
4. **可选**：对 DMG 进行公证

**总结：**
- dropDMG 是一个**打包工具**，不是签名解决方案
- 要解决分发问题，**必须先使用 Developer ID 证书签名应用**
- dropDMG 只是让安装包看起来更专业，但不能绕过签名限制

## 📋 签名类型对比

| 签名类型 | 用途 | 外部用户可用 | 是否提示不安全 | 权限是否正常 |
|---------|------|------------|--------------|------------|
| **Apple Development** | 开发测试 | ❌ 否 | ⚠️ 是 | ⚠️ 可能有问题 |
| **Developer ID Application** | 直接分发 | ✅ 是 | ✅ 否（需公证） | ✅ 是 |
| **Apple Distribution** | App Store | ✅ 是（通过 App Store） | ✅ 否 | ✅ 是 |
| **Ad Hoc** | 测试分发 | ⚠️ 是（需注册设备） | ⚠️ 可能 | ⚠️ 可能有问题 |

## 🔍 检查当前签名类型

在终端中执行以下命令检查 Archive 后的应用签名：

```bash
codesign -dvv /path/to/fastv.app | grep -E "Authority|TeamIdentifier"
```

**开发签名示例：**
```
Authority=Apple Development: Your Name (9K5FH5XTHD)
TeamIdentifier=W49B66SUW3
```

**Developer ID 签名示例：**
```
Authority=Developer ID Application: Your Name (W49B66SUW3)
TeamIdentifier=W49B66SUW3
```

## ⚠️ 当前项目状态

根据项目配置：
- ✅ 已配置 Development Team：`W49B66SUW3`
- ✅ 已配置 Entitlements 文件
- ✅ 已启用 App Sandbox
- ✅ 已启用 Hardened Runtime
- ❌ **当前使用开发签名，不能用于外部分发**

## 🚀 推荐操作步骤

1. **申请 Developer ID Application 证书**（如果还没有）
2. **修改 Xcode 项目配置**，使用 Developer ID 证书进行 Archive
3. **执行 Archive** 并导出应用
4. **进行公证**（强烈推荐）
5. **测试分发**：将应用发送给测试用户，验证：
   - 应用能否正常打开
   - 权限请求是否正常
   - 功能是否正常

## 📝 注意事项

1. **权限申请**：即使用 Developer ID 签名，首次运行时权限请求对话框会正常弹出，但辅助功能权限仍需要用户在系统设置中手动授权。

2. **macOS 版本兼容性**：项目配置的最低版本是 macOS 15.6，确保目标 Mac 的系统版本符合要求。

3. **动态库签名**：项目中的 ONNX Runtime 动态库也需要正确签名，构建脚本应该已经处理了这个问题。

4. **公证有效期**：公证后的应用在 macOS Gatekeeper 中会被信任，但如果应用更新，需要重新公证。

## 🔗 相关文档

- `分发签名说明.md` - 详细的签名配置说明
- `XCODE权限说明.md` - 权限配置和使用说明
- `签名问题最终修复.md` - 动态库签名问题解决方案

