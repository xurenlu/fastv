# 生成 CSR（Certificate Signing Request）文件指南

## 方法 1：使用 Keychain Access（推荐，最简单）

### 步骤：

1. **打开 Keychain Access（钥匙串访问）**
   - 按 `⌘ + Space` 搜索 "Keychain Access" 或 "钥匙串访问"
   - 或从 `应用程序 > 实用工具 > 钥匙串访问`

2. **创建证书请求**
   - 菜单栏：`钥匙串访问 > 证书助理 > 从证书颁发机构请求证书...`
   - 或使用快捷键：`⌘ + Option + K`

3. **填写证书信息**
   - **用户电子邮件地址**：输入您的 Apple ID 邮箱（如：your-email@example.com）
   - **常用名称**：输入您的姓名或公司名称（如：suhang hu）
   - **CA 电子邮件地址**：留空
   - **请求是**：选择 **"存储到磁盘"**（重要！）
   - 点击 **"继续"**

4. **保存 CSR 文件**
   - 选择保存位置（建议保存到桌面或文档文件夹）
   - 文件名会自动命名为 `CertificateSigningRequest.certSigningRequest`
   - 点击 **"存储"**

5. **完成**
   - CSR 文件已生成，可以上传到 Apple Developer 网站

## 方法 2：使用命令行（适合开发者）

### 步骤：

1. **打开终端（Terminal）**

2. **运行以下命令生成 CSR**

```bash
# 创建私钥（如果还没有）
openssl genrsa -out private_key.pem 2048

# 生成 CSR 文件
openssl req -new -key private_key.pem -out CertificateSigningRequest.certSigningRequest -subj "/emailAddress=your-email@example.com/CN=suhang hu/C=CN"
```

**参数说明：**
- `emailAddress`: 您的 Apple ID 邮箱
- `CN` (Common Name): 您的姓名或公司名称
- `C` (Country): 国家代码（CN=中国，US=美国等）

3. **上传 CSR 文件**
   - 将生成的 `CertificateSigningRequest.certSigningRequest` 文件上传到 Apple Developer 网站

## 方法 3：使用 Xcode（最简单，但需要先登录）

### 步骤：

1. **打开 Xcode**

2. **登录 Apple ID**
   - `Xcode > Settings > Accounts`（或 `Preferences > Accounts`）
   - 点击 "+" 添加 Apple ID
   - 输入您的 Apple Developer 账号

3. **自动管理证书**
   - Xcode 可以自动创建和管理证书
   - 但如果您需要手动创建 CSR，仍然使用方法 1 或 2

## 重要提示

### CSR 文件信息要求：

- **邮箱地址**：必须与您的 Apple Developer 账号邮箱一致
- **常用名称**：建议使用您的真实姓名或公司名称
- **私钥安全**：CSR 文件包含公钥，私钥保存在您的 Mac 上，请妥善保管

### 上传 CSR 到 Apple Developer：

1. 访问：https://developer.apple.com/account/resources/certificates/list
2. 点击 "+" 创建新证书
3. 选择 "Developer ID Application"
4. 点击 "Continue"
5. 上传刚才生成的 CSR 文件
6. 下载生成的证书（.cer 文件）
7. 双击安装到 Keychain

## 验证 CSR 文件

生成 CSR 后，可以验证其内容：

```bash
# 查看 CSR 文件信息
openssl req -in CertificateSigningRequest.certSigningRequest -text -noout
```

应该看到您的邮箱和常用名称信息。

## 常见问题

### Q: CSR 文件可以重复使用吗？
A: 可以，一个 CSR 文件可以用于申请多个证书（但通常建议为每个证书类型创建新的 CSR）。

### Q: 如果我的 Mac 重装了系统怎么办？
A: 如果您重装了系统，私钥会丢失。需要：
1. 撤销旧证书
2. 生成新的 CSR
3. 申请新证书

### Q: CSR 文件过期吗？
A: CSR 文件本身不过期，但证书有时效性。建议保存 CSR 文件备份。

## 下一步

生成 CSR 文件后：
1. 访问 Apple Developer 网站
2. 上传 CSR 文件申请 Developer ID Application 证书
3. 下载并安装证书
4. 使用 `build_release_distribution.sh` 重新构建应用

