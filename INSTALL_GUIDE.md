# ONNX Runtime 安装指南

## ⚠️ 重要说明

`onnxruntime-mobile-objc` **不支持 macOS**，只支持 iOS。

对于 macOS 项目，**必须使用 Swift Package Manager (SPM)**，而不是 CocoaPods。

## 推荐方案：Swift Package Manager

### 方法 1：在 Xcode 中手动添加（推荐）

1. **打开项目**
   ```bash
   cd /Users/rocky/Sites/fastv
   open fastv.xcodeproj
   ```

2. **添加 Swift Package**
   - 在 Xcode 中选择项目文件（最顶部的蓝色图标）
   - 选择 Target "fastv"
   - 切换到 **"Package Dependencies"** 标签页
   - 点击 **"+"** 按钮
   - 在搜索框中输入：
     ```
     https://github.com/microsoft/onnxruntime-swift
     ```
   - 选择最新版本（建议 1.15.0 或更高）
   - 点击 **"Add Package"**
   - 确保 "fastv" target 被选中，点击 **"Add Package"**

3. **更新代码**
   - 打开 `fastv/Services/ONNXRuntimeWrapper.swift`
   - 在文件顶部添加：`import onnxruntime`
   - 参考 `ONNXRuntimeWrapper_Implementation.swift` 中的实现代码
   - 将实现代码复制到 `ONNXRuntimeWrapper.swift` 替换占位实现

4. **构建项目**
   - Product → Clean Build Folder (⇧⌘K)
   - Product → Build (⌘B)

### 方法 2：使用命令行（需要设置代理）

如果你想通过命令行添加，可以创建一个 Package.swift 文件，但 macOS 项目通常直接在 Xcode 中管理更方便。

## 如果必须使用 CocoaPods

如果你坚持使用 CocoaPods，需要：

1. **设置代理**（端口 7856）：
   ```bash
   export https_proxy=http://127.0.0.1:7856
   export http_proxy=http://127.0.0.1:7856
   export all_proxy=socks5://127.0.0.1:7856
   ```

2. **尝试使用 C API 版本**（需要手动集成）：
   - 下载 ONNX Runtime C API
   - 手动添加到项目中
   - 创建桥接头文件

**不推荐此方案**，因为 macOS 支持不完善且配置复杂。

## 验证安装

安装成功后：
1. ✅ 在 Xcode 项目导航器中看到 `Package Dependencies` 文件夹
2. ✅ 能够成功导入 `onnxruntime` 模块
3. ✅ 项目能够成功编译
4. ✅ 运行应用时，语音转文字功能可以正常工作

## 故障排除

### 问题：找不到 onnxruntime 模块

**解决方案：**
1. 确保使用 `.xcodeproj` 打开项目（不是 `.xcworkspace`）
2. 检查 Package Dependencies 是否正确添加
3. 清理构建文件夹：Product → Clean Build Folder (⇧⌘K)
4. 重新构建：Product → Build (⌘B)

### 问题：Package 下载失败

**解决方案：**
1. 检查网络连接
2. 如果使用代理，确保代理正常工作
3. 在 Xcode 的 Package Dependencies 设置中，可以配置代理

## 总结

**最简单的方法**：
1. 打开 Xcode
2. 在 Package Dependencies 中添加 `https://github.com/microsoft/onnxruntime-swift`
3. 更新 `ONNXRuntimeWrapper.swift` 文件
4. 构建并运行

**不需要执行任何命令行命令！**

