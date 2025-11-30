# 更改 Bundle ID 解决权限问题

## 问题说明

如果提醒事项权限窗口无法弹出，可能是因为 macOS 的 TCC 数据库缓存了权限状态。更改 Bundle ID 会创建一个全新的应用标识，权限状态会完全重置。

## 当前 Bundle ID

- **当前**: `com.wxside.typecho`
- **建议新**: `com.wxside.miaoda` 或 `com.wxside.fastv`

## 更改步骤

### 步骤 1：在 Xcode 中更改 Bundle ID

1. 打开 Xcode
2. 选择项目 "fastv"
3. 选择 Target "typecho"
4. 进入 "Signing & Capabilities" 标签
5. 修改 "Bundle Identifier"：
   - 从 `com.wxside.typecho`
   - 改为 `com.wxside.miaoda`（或其他唯一标识）

### 步骤 2：更新 project.pbxproj 文件

我已经创建了一个脚本来自动更新，或者你可以手动修改：

**需要修改的位置**：
- `PRODUCT_BUNDLE_IDENTIFIER = com.wxside.typecho;` 
- 改为 `PRODUCT_BUNDLE_IDENTIFIER = com.wxside.miaoda;`

### 步骤 3：清理构建缓存

```bash
# 清理 Xcode 的 DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/fastv-*

# 清理构建文件夹
cd /Users/rocky/Sites/fastv
rm -rf build/
```

### 步骤 4：重新构建和运行

1. 在 Xcode 中清理项目（Product > Clean Build Folder，Shift+Command+K）
2. 重新构建项目（Command+B）
3. 运行应用（Command+R）

### 步骤 5：测试权限请求

1. 运行应用
2. 尝试使用提醒事项同步功能
3. 应该会弹出权限请求对话框

---

## 使用脚本自动更改（推荐）

我可以帮你创建一个脚本来自动更改 Bundle ID。告诉我你想要的新 Bundle ID，我可以：

1. 更新 `project.pbxproj` 文件
2. 更新所有相关的配置
3. 确保所有地方都使用新的 Bundle ID

---

## 注意事项

### 1. 应用签名

更改 Bundle ID 后，需要：
- 重新配置签名证书
- 确保 Team ID 正确
- 如果是 App Store 发布，需要在 App Store Connect 中创建新的应用

### 2. 用户数据

- 更改 Bundle ID 后，应用会被视为全新的应用
- 用户需要重新授权所有权限
- 应用数据可能无法迁移（取决于存储位置）

### 3. 测试

- 在更改 Bundle ID 后，建议在干净的系统中测试
- 确保所有功能正常工作
- 测试权限请求流程

---

## 推荐的 Bundle ID 选项

1. **`com.wxside.miaoda`** - 使用中文应用名称的拼音
2. **`com.wxside.fastv`** - 使用项目名称
3. **`com.wxside.miaoda.app`** - 更明确的标识
4. **`com.wxside.voiceinput`** - 描述性名称

选择哪个取决于你的偏好和 App Store 的命名要求。

---

## 快速重置权限（不更改 Bundle ID）

如果你想先尝试不更改 Bundle ID，可以使用以下命令：

```bash
# 重置提醒事项权限
tccutil reset Reminders com.wxside.typecho

# 重启应用后再试
```

如果这个命令不起作用，再考虑更改 Bundle ID。
