# ONNX Runtime 集成说明

## 概述

本项目已经实现了语音转文字功能的完整框架，包括：
- ✅ 音频特征提取（Mel 频谱图）
- ✅ 模型文件已复制到项目资源目录
- ✅ Token 映射和文本后处理
- ⚠️ ONNX Runtime 依赖需要手动添加

## 添加 ONNX Runtime 依赖

### 方法 1：使用 Swift Package Manager（推荐）

1. 在 Xcode 中打开项目
2. 选择项目文件（fastv.xcodeproj）
3. 选择 Target "fastv"
4. 切换到 "Package Dependencies" 标签
5. 点击 "+" 按钮添加新的包依赖
6. 输入以下 URL：
   ```
   https://github.com/microsoft/onnxruntime-swift
   ```
   或者使用 C API 版本：
   ```
   https://github.com/microsoft/onnxruntime
   ```
7. 选择最新版本并点击 "Add Package"

### 方法 2：使用 CocoaPods

1. 在项目根目录创建 `Podfile`：
   ```ruby
   platform :osx, '11.0'
   use_frameworks!
   
   target 'fastv' do
     pod 'onnxruntime-mobile-objc', '~> 1.15.0'
   end
   ```

2. 运行安装命令：
   ```bash
   pod install
   ```

3. 之后使用 `.xcworkspace` 文件打开项目

## 更新 ONNXRuntimeWrapper

添加依赖后，需要更新 `fastv/Services/ONNXRuntimeWrapper.swift` 文件，取消注释实际实现代码，并删除占位实现。

参考文件中的注释部分，那里有完整的实现示例。

## 模型文件位置

模型文件已复制到：
- `fastv/Resources/Models/sensevoice-small/model.onnx`
- `fastv/Resources/Models/sensevoice-small/tokens.json`
- `fastv/Resources/Models/sensevoice-small/config.yaml`

**重要**：确保这些文件已添加到 Xcode 项目的 Target Membership 中，以便打包到应用中。

## 测试

完成依赖添加后，可以测试语音转文字功能：
1. 选择一个包含音频的视频文件
2. 启用"提取音频"和"提取文本稿"选项
3. 开始处理
4. 查看生成的文本稿文件

## 故障排除

如果遇到模型文件未找到的错误：
1. 检查模型文件是否在项目资源目录中
2. 在 Xcode 中检查文件的 Target Membership
3. 确保文件已添加到 "Copy Bundle Resources" 构建阶段

如果遇到 ONNX Runtime 相关错误：
1. 确认依赖已正确添加
2. 检查 `ONNXRuntimeWrapper.swift` 中的实现是否正确
3. 查看 Xcode 构建日志中的详细错误信息

