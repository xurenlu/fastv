# FastV - 完整功能说明

## ✅ 已完成的功能

所有代码已经完成并准备就绪！

### 1. 视频下载功能 ✅
- 支持抖音、快手、B站、微博、Twitter、Instagram、TikTok 等平台
- 自动选择最佳质量视频
- 实时下载进度显示

### 2. 视频处理功能 ✅
- 提取视频首尾帧
- 提取音频（支持 M4A、MP3、WAV）
- 语音转文字（需要添加 ONNX Runtime 依赖）

### 3. 用户界面 ✅
- 符合 macOS 设计规范
- URL 输入框支持在线视频下载
- 拖拽支持
- 实时进度显示
- 结果预览和复制功能

## 🚀 最后一步：添加 ONNX Runtime 依赖

代码已经准备好，只需要在 Xcode 中添加依赖即可使用语音转文字功能。

### 快速步骤（3 步）

1. **打开项目**
   ```bash
   open fastv.xcodeproj
   ```

2. **添加 Swift Package**（在 Xcode 中）
   - 选择项目文件 → Target "fastv" → "Package Dependencies"
   - 点击 "+"，输入：`https://github.com/microsoft/onnxruntime-swift`
   - 添加最新版本

3. **构建项目**
   - 按 `⌘B` 构建
   - 完成！

**详细步骤**：参考 `QUICK_START.md`

## 📁 项目文件结构

```
fastv/
├── fastv/
│   ├── Resources/
│   │   └── Models/sensevoice-small/    # 语音识别模型
│   │       ├── model.onnx (894MB)      # ONNX 模型
│   │       ├── tokens.json             # Token 映射
│   │       └── config.yaml             # 模型配置
│   ├── Services/
│   │   ├── VideoDownloader.swift      # 视频下载
│   │   ├── SpeechTranscriber.swift     # 语音转文字（已实现）
│   │   ├── AudioFeatureExtractor.swift # 音频特征提取
│   │   ├── ONNXRuntimeWrapper.swift    # ONNX Runtime 包装（自动检测）
│   │   └── CoreMLWrapper.swift        # CoreML 包装（备选）
│   └── ...
├── QUICK_START.md          # 快速开始指南
├── INSTALL_GUIDE.md        # 详细安装指南
└── README.md               # 项目说明
```

## 🎯 使用流程

1. **从在线平台下载视频**
   - 在 URL 输入框中粘贴视频链接
   - 点击"下载"按钮
   - 等待下载完成

2. **处理视频**
   - 选择处理选项：
     - ✅ 提取第一帧
     - ✅ 提取最后一帧
     - ✅ 提取音频
     - ✅ 提取文本稿（需要 ONNX Runtime）
   - 点击"开始处理"

3. **查看结果**
   - 在结果卡片中查看：
     - 首尾帧图片
     - 音频文件
     - 转录文本（如果启用）

## 🔧 技术实现

### 代码架构

- **条件编译**：代码使用 `#if canImport(onnxruntime)` 自动检测依赖
- **自动回退**：如果没有 ONNX Runtime，会提示添加依赖
- **双方案支持**：同时支持 CoreML 和 ONNX Runtime（优先 CoreML）

### 模型信息

- **模型**：SenseVoice Small
- **大小**：894MB
- **格式**：ONNX
- **支持语言**：中文、英文、日文、韩文等

## 📝 注意事项

1. **模型文件**：确保 `model.onnx`、`tokens.json`、`config.yaml` 已添加到 Xcode 项目资源中
2. **依赖添加**：必须在 Xcode GUI 中添加 Swift Package（无法通过命令行完成）
3. **首次运行**：添加依赖后，首次构建可能需要几分钟下载依赖

## 🎉 完成！

所有代码已经完成，只需要：
1. 在 Xcode 中添加 ONNX Runtime Swift Package
2. 构建并运行

就这么简单！

