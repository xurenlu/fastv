# FastV - 视频处理应用

一个功能强大的 macOS 视频处理应用，支持从在线视频平台下载视频、提取帧、提取音频，以及语音转文字功能。

## 功能特性

### ✅ 已实现功能

1. **视频下载**
   - 支持从抖音、快手、B站、微博、Twitter、Instagram、TikTok 等平台下载视频
   - 自动选择最佳质量视频
   - 实时下载进度显示

2. **视频处理**
   - 提取视频首尾帧
   - 提取音频（支持多种格式：M4A、MP3、WAV）
   - 自定义输出目录
   - 批量处理多个视频

3. **语音转文字** ⚠️ 需要添加 ONNX Runtime 依赖
   - 使用 SenseVoice Small 模型
   - 支持中文、英文、日文、韩文等多语言
   - 自动音频预处理和特征提取
   - Token 解码和文本规范化

4. **用户界面**
   - 符合 macOS 设计规范的现代化界面
   - 拖拽支持
   - URL 输入框支持在线视频下载
   - 实时进度显示
   - 结果预览和复制功能

## 项目结构

```
fastv/
├── fastv/
│   ├── Resources/
│   │   └── Models/
│   │       └── sensevoice-small/    # 语音识别模型文件
│   │           ├── model.onnx       # ONNX 模型（894MB）
│   │           ├── tokens.json      # Token 映射表
│   │           └── config.yaml      # 模型配置
│   ├── Services/
│   │   ├── VideoDownloader.swift           # 视频下载服务
│   │   ├── AudioExtractor.swift            # 音频提取服务
│   │   ├── FrameExtractor.swift            # 帧提取服务
│   │   ├── VideoProcessor.swift            # 视频处理协调器
│   │   ├── SpeechTranscriber.swift         # 语音转文字服务
│   │   ├── AudioFeatureExtractor.swift     # 音频特征提取
│   │   ├── ONNXRuntimeWrapper.swift        # ONNX Runtime 包装（占位）
│   │   └── ONNXRuntimeWrapper_Implementation.swift  # 完整实现示例
│   ├── ViewModels/
│   │   ├── VideoProcessorViewModel.swift   # 单视频处理视图模型
│   │   └── VideoListViewModel.swift        # 多视频列表视图模型
│   ├── Views/
│   │   ├── ContentView.swift              # 主界面
│   │   ├── DropZoneView.swift             # 拖拽区域（含 URL 输入）
│   │   ├── ProcessingOptionsView.swift    # 处理选项视图
│   │   └── ...
│   └── Models/
│       ├── VideoItem.swift
│       ├── UserPreferences.swift
│       └── ...
├── INTEGRATION_GUIDE.md      # ONNX Runtime 集成指南
├── ONNX_RUNTIME_SETUP.md     # ONNX Runtime 设置说明
└── README.md                 # 本文件
```

## 快速开始

### 1. 打开项目

```bash
cd /Users/rocky/Sites/fastv
open fastv.xcodeproj
```

### 2. 添加 ONNX Runtime 依赖（语音转文字功能需要）

**方法 A：Swift Package Manager（推荐）**

1. 在 Xcode 中选择项目文件
2. 选择 Target "fastv"
3. 切换到 "Package Dependencies" 标签
4. 点击 "+" 添加：`https://github.com/microsoft/onnxruntime-swift`
5. 选择最新版本并添加

**方法 B：CocoaPods**

```bash
# 在项目根目录创建 Podfile
cat > Podfile << EOF
platform :osx, '11.0'
use_frameworks!

target 'fastv' do
  pod 'onnxruntime-mobile-objc', '~> 1.15.0'
end
EOF

# 安装依赖
pod install

# 使用 .xcworkspace 打开项目
open fastv.xcworkspace
```

### 3. 启用 ONNX Runtime 实现

添加依赖后：

1. 打开 `fastv/Services/ONNXRuntimeWrapper.swift`
2. 在文件顶部添加：`import onnxruntime`
3. 参考 `ONNXRuntimeWrapper_Implementation.swift` 中的实现代码
4. 将实现代码复制到 `ONNXRuntimeWrapper.swift` 替换占位实现

详细步骤请参考：**INTEGRATION_GUIDE.md**

### 4. 验证模型文件

确保以下文件已添加到 Xcode 项目中：
- `fastv/Resources/Models/sensevoice-small/model.onnx`
- `fastv/Resources/Models/sensevoice-small/tokens.json`
- `fastv/Resources/Models/sensevoice-small/config.yaml`

如果文件未显示在项目中：
1. 右键点击 `fastv/Resources` 文件夹
2. 选择 "Add Files to fastv..."
3. 选择 `Models` 文件夹
4. 确保勾选 "Copy items if needed" 和 "Create groups"
5. 确保 "Add to targets" 中勾选了 "fastv"

### 5. 构建和运行

1. 清理构建：`Product` → `Clean Build Folder` (⇧⌘K)
2. 构建项目：`Product` → `Build` (⌘B)
3. 运行应用：`Product` → `Run` (⌘R)

## 使用说明

### 从本地文件处理视频

1. 启动应用
2. 拖拽视频文件到应用窗口，或点击"选择文件"
3. 选择处理选项：
   - ✅ 提取第一帧
   - ✅ 提取最后一帧
   - ✅ 提取音频
   - ✅ 提取文本稿（需要 ONNX Runtime）
4. 点击"开始处理"
5. 查看结果并保存

### 从在线平台下载视频

1. 在 URL 输入框中粘贴视频链接（支持抖音、快手、B站等）
2. 点击"下载"按钮
3. 等待下载完成（自动加载视频）
4. 按照上述步骤处理视频

## 技术栈

- **语言**：Swift 5.9+
- **框架**：SwiftUI, AVFoundation, Accelerate
- **平台**：macOS 11.0+
- **依赖**：ONNX Runtime（语音转文字功能）

## 模型信息

- **模型名称**：SenseVoice Small
- **模型大小**：894MB
- **支持语言**：中文、英文、日文、韩文等
- **输入格式**：16kHz 单声道 PCM 音频
- **输出格式**：文本转录结果

## 故障排除

### 模型文件未找到

- 检查文件是否在项目资源目录中
- 确认文件的 Target Membership 设置正确
- 重新添加文件到项目

### ONNX Runtime 未集成

- 参考 **INTEGRATION_GUIDE.md** 添加依赖
- 确保已启用实际实现代码
- 检查 import 语句是否正确

### 下载失败

- 检查网络连接
- 确认视频链接格式正确
- 查看控制台错误信息

## 开发状态

- ✅ 视频下载功能
- ✅ 帧提取功能
- ✅ 音频提取功能
- ✅ 音频特征提取
- ✅ Token 解码和后处理
- ⚠️ ONNX Runtime 集成（需要用户添加依赖）

## 许可证

本项目仅供学习和研究使用。

## 参考资源

- [ONNX Runtime Swift](https://github.com/microsoft/onnxruntime-swift)
- [SenseVoice 项目](https://github.com/alibaba-damo-academy/FunASR)
- [macOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/macos)

