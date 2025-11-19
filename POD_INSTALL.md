# CocoaPods 安装指南

## ⚠️ 重要提示

`onnxruntime-mobile-objc` **不支持 macOS**，只支持 iOS。

对于 macOS 项目，**强烈推荐使用 Swift Package Manager**，而不是 CocoaPods。

## 推荐方案：使用 Swift Package Manager

### 步骤 1：在 Xcode 中添加 Swift Package

1. 打开 Xcode，打开项目 `fastv.xcodeproj`
2. 选择项目文件（最顶部的蓝色图标）
3. 选择 Target "fastv"
4. 切换到 **"Package Dependencies"** 标签页
5. 点击 **"+"** 按钮
6. 在搜索框中输入：
   ```
   https://github.com/microsoft/onnxruntime-swift
   ```
7. 选择最新版本（建议 1.15.0 或更高）
8. 点击 **"Add Package"**
9. 确保 "fastv" target 被选中，点击 **"Add Package"**

### 步骤 2：更新 ONNX Runtime 包装类

1. 打开 `fastv/Services/ONNXRuntimeWrapper.swift`
2. 在文件顶部添加：
   ```swift
   import onnxruntime
   ```
3. 参考 `ONNXRuntimeWrapper_Implementation.swift` 中的实现代码
4. 将实现代码复制到 `ONNXRuntimeWrapper.swift` 替换占位实现

### 步骤 3：构建项目

- Product → Clean Build Folder (⇧⌘K)
- Product → Build (⌘B)

## 备选方案：使用 CocoaPods（需要修改）

如果你想使用 CocoaPods，需要：

1. 使用支持 macOS 的 ONNX Runtime 版本（可能需要从源码编译）
2. 或者使用 C API 版本并手动集成

**不推荐此方案**，因为 macOS 支持不完善。

## 验证安装

安装成功后：
1. 在 Xcode 项目导航器中看到 `Package Dependencies` 或 `Pods` 文件夹
2. 能够成功导入 `onnxruntime` 模块
3. 项目能够成功编译

## 常见问题

### 问题：找不到 onnxruntime 模块

**解决方案：**
1. 确保使用正确的打开方式（SPM 用 .xcodeproj，CocoaPods 用 .xcworkspace）
2. 清理构建文件夹：Product → Clean Build Folder
3. 重新构建：Product → Build

### 问题：版本冲突

如果遇到版本冲突：
1. 在 Xcode 中更新 Package Dependencies
2. 或者删除并重新添加依赖
