# ONNX Runtime 完整集成指南

## 快速开始

本项目已实现完整的语音转文字功能框架，只需添加 ONNX Runtime 依赖即可使用。

## 步骤 1：添加 ONNX Runtime 依赖

### 方法 A：Swift Package Manager（推荐）

1. 打开 Xcode，选择项目文件 `fastv.xcodeproj`
2. 选择 Target "fastv"
3. 切换到 **"Package Dependencies"** 标签页
4. 点击 **"+"** 按钮
5. 在搜索框中输入：
   ```
   https://github.com/microsoft/onnxruntime-swift
   ```
6. 选择最新版本（建议 1.15.0 或更高）
7. 点击 **"Add Package"**
8. 确保 "fastv" target 被选中，点击 **"Add Package"**

> 当前项目不支持 CocoaPods。请勿创建 `Podfile` 或切换到 `.xcworkspace`；仓库内 ONNX Runtime C API 是当前受控实现。

## 步骤 2：启用 ONNX Runtime 实现

1. 打开 `fastv/Services/ONNXRuntimeWrapper.swift`
2. 找到文件开头的 `#if false`
3. 将其改为 `#if true` 或直接删除条件编译
4. 删除或注释掉 `#else` 部分的占位实现

## 步骤 3：验证模型文件

确保以下文件已添加到 Xcode 项目中：
- `fastv/Resources/Models/sensevoice-small/model.onnx`
- `fastv/Resources/Models/sensevoice-small/tokens.json`
- `fastv/Resources/Models/sensevoice-small/config.yaml`

**检查方法：**
1. 在 Xcode 项目导航器中找到这些文件
2. 选择文件，查看右侧的 "File Inspector"
3. 确保 "Target Membership" 中勾选了 "fastv"

如果文件未显示在项目中：
1. 右键点击 `fastv/Resources` 文件夹
2. 选择 "Add Files to fastv..."
3. 选择 `Models` 文件夹
4. 确保勾选 "Copy items if needed" 和 "Create groups"
5. 确保 "Add to targets" 中勾选了 "fastv"

## 步骤 4：构建和测试

1. 清理构建文件夹：`Product` → `Clean Build Folder` (⇧⌘K)
2. 构建项目：`Product` → `Build` (⌘B)
3. 运行应用：`Product` → `Run` (⌘R)

## 测试语音转文字功能

1. 启动应用
2. 选择一个包含音频的视频文件（或从链接下载）
3. 在"处理选项"中：
   - ✅ 勾选"提取音频"
   - ✅ 勾选"提取文本稿"
4. 点击"开始处理"
5. 处理完成后，在结果卡片中查看转录的文本

## 故障排除

### 错误：模型文件未找到

**解决方案：**
- 检查模型文件是否在项目资源目录中
- 确认文件的 Target Membership 设置正确
- 尝试重新添加文件到项目

### 错误：无法导入 onnxruntime

**解决方案：**
- 确认已正确添加 Swift Package 依赖
- 清理构建文件夹后重新构建
- 检查 Xcode 版本是否支持（需要 Xcode 12+）

### 错误：会话创建失败

**解决方案：**
- 检查模型文件路径是否正确
- 确认模型文件未损坏（文件大小应为约 894MB）
- 查看控制台输出的详细错误信息

### 错误：输入输出名称不匹配

**解决方案：**
- SenseVoice 模型的输入名称可能是 `speech`，输出名称可能是 `text`
- 如果不同，需要修改 `ONNXRuntimeWrapper.swift` 中的输入输出名称
- 可以使用 ONNX 模型查看工具检查模型的输入输出名称

### 性能优化建议

1. **使用 CoreML 加速**（macOS）：
   - 在 `ONNXRuntimeWrapper.swift` 的 `loadModel` 方法中取消注释：
   ```swift
   try sessionOptions.appendExecutionProviderCoreML()
   ```

2. **批量处理**：
   - 对于多个音频文件，可以复用同一个会话实例

3. **内存管理**：
   - 长时间运行的应用，建议定期释放会话并重新加载

## 技术细节

### 模型信息
- **模型类型**：SenseVoice Small
- **输入格式**：Mel 频谱特征 [batch, sequence_length, 80]
- **输出格式**：Token IDs (Int64)
- **采样率**：16kHz
- **特征维度**：80 Mel bands

### 处理流程
1. 音频预处理：转换为 16kHz 单声道 PCM
2. 特征提取：Mel 频谱图（80 维，25ms 帧长，10ms 帧移）
3. LFR 处理：低帧率特征（m=7, n=6）
4. 模型推理：ONNX Runtime
5. Token 解码：使用 tokens.json 映射
6. 后处理：CTC 去重、文本规范化

## 参考资源

- [ONNX Runtime Swift 文档](https://github.com/microsoft/onnxruntime-swift)
- [ONNX Runtime 官方文档](https://onnxruntime.ai/)
- [SenseVoice 项目](https://github.com/alibaba-damo-academy/FunASR)

## 支持

如遇到问题，请检查：
1. Xcode 控制台的错误信息
2. 模型文件完整性
3. 依赖版本兼容性
4. 系统要求（macOS 11.0+）
