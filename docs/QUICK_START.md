# 快速开始 - 3 步完成 ONNX Runtime 集成

## ✅ 代码已准备就绪

代码已经更新，使用条件编译自动检测 ONNX Runtime。你只需要在 Xcode 中添加依赖即可。

## 🚀 3 步完成

### 步骤 1：打开项目

```bash
cd /Users/rocky/Sites/fastv
open fastv.xcodeproj
```

### 步骤 2：添加 Swift Package（在 Xcode 中）

1. 点击项目文件（最顶部的蓝色图标 "fastv"）
2. 选择 Target "fastv"（在 TARGETS 列表中）
3. 切换到 **"Package Dependencies"** 标签页
4. 点击左下角的 **"+"** 按钮
5. 在搜索框中输入：
   ```
   https://github.com/microsoft/onnxruntime-swift
   ```
6. 选择最新版本（建议选择 "Up to Next Major Version" 或最新版本）
7. 点击 **"Add Package"**
8. 确保 "fastv" target 被选中，点击 **"Add Package"**

### 步骤 3：构建项目

- 按 `⌘B` 构建项目
- 如果成功，说明集成完成！

## ✨ 完成！

代码会自动检测到 ONNX Runtime 并启用实际实现。无需修改任何代码文件！

## 验证

运行应用并测试语音转文字功能：
1. 选择一个包含音频的视频文件
2. 启用"提取音频"和"提取文本稿"选项
3. 开始处理
4. 查看生成的文本稿

## 如果遇到问题

### 问题：找不到 onnxruntime 模块

**解决**：
1. 确保使用 `.xcodeproj` 打开项目（不是 `.xcworkspace`）
2. 清理构建：Product → Clean Build Folder (⇧⌘K)
3. 重新构建：Product → Build (⌘B)

### 问题：Package 下载失败

**解决**：
1. 检查网络连接
2. 如果使用代理，确保代理正常工作
3. 在 Xcode 的 Preferences → Accounts → Package Repositories 中检查

## 技术说明

代码使用 `#if canImport(onnxruntime)` 条件编译：
- ✅ 如果检测到 ONNX Runtime，自动使用实际实现
- ✅ 如果未检测到，使用占位实现（会提示添加依赖）

**无需手动修改任何代码文件！**

