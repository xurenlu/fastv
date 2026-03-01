# 妙打 (FastV) - 智能语音输入法

妙打是一款**聚焦语音输入与语音转文字**的 macOS 应用。按住快捷键说话，实时将语音转换为文字并自动输入到当前应用的输入框中。支持多语言识别，内置 AI 优化和快速纠错，识别准确、响应快速，数据本地处理，保护隐私安全。

**能力暴露**：除 macOS 应用外，还提供 [STT API 服务](stt-api/README.md)，通过 HTTP 和 WebSocket 将语音转文字能力暴露给外部调用。

## ✨ 核心功能

### 🎤 语音输入（又快又准）

- **全局快捷键**：在其他应用的输入框中按下快捷键（默认 FN），开始语音输入
- **实时转文字**：按住快捷键说话，松开后自动将语音转换为文字并插入
- **智能分段**：检测到停顿（默认 0.8 秒）时自动分段转文字，边说边转，无需等待松开
- **双路径策略**：
  - **快路径**：停顿即转写，即时反馈
  - **准路径**：多段音频拼接后二次转写，长音频准确率更高
- **动态规划分批**：每批至少 3 段、至少 3 秒，避免过短片段，松键时优先用准路径结果替换零碎结果
- **多语言支持**：支持中文、英文、日文、韩文、粤语等多种语言识别

### 📝 会议记录

- **一键录音**：点击开始录音，自动转写会议、访谈、笔记等内容
- **实时波形**：录音时显示悬浮波形窗口，直观确认正在拾音
- **AI 整理**：支持生成摘要、提取行动项、完整整理
- **多格式导出**：支持导出为 PDF、纯文本、Markdown、HTML

### ⚡ 快速纠错

- **常用词管理**：自定义常用词替换规则
- **水词修正**：自动去除「嗯」「那个」等填充词
- **AI 优化**：可选启用 AI 文本优化（需要配置 AI 服务）

### 💬 其他功能

- **AI Chat**：多 Provider 支持（OpenAI、DashScope、智谱、MiniMax、Ollama、OpenRouter 等）
- **AI Todo**：与 macOS 提醒事项同步的智能待办
- **邮箱**：IMAP 邮件客户端

## 🚀 快速开始

### 1. 安装应用

从 [GitHub Releases](https://github.com/xurenlu/fastv/releases) 下载最新版本，或使用 Xcode 编译：

```bash
git clone https://github.com/xurenlu/fastv.git
cd fastv
open fastv.xcworkspace   # 使用 workspace（含 CocoaPods）
# 或 open fastv.xcodeproj
```

### 2. 配置权限

首次运行时，需要在系统设置中授权：

- **麦克风权限**：用于语音输入和会议录音
- **辅助功能权限**：用于全局快捷键和文本插入

### 3. 设置快捷键

1. 打开应用设置（⌘+,）
2. 在「语音输入法」部分配置快捷键（默认 FN）
3. 确保「启用语音输入法」已勾选

### 4. 开始使用

1. 打开任意应用的输入框（如备忘录、微信、浏览器等）
2. 按下设置的快捷键（默认 FN）
3. 开始说话，松开快捷键后自动转文字并插入

## 📖 使用技巧

### 智能分段转文字（又快又准）

启用「智能分段转文字」功能后：

- 检测到停顿（默认 0.8 秒）时，立即将前面的音频转文字并缓存
- 无需等待松开快捷键，实现边说边转的效果
- 累积 3 段以上时，后台自动将多段音频拼接后二次转写，准确率更高
- 松键时：若二次转写已完成，则用其替换零碎结果；否则用零碎结果，保证不卡顿
- 可在设置中调整停顿阈值（0.5～2.0 秒）

### AI 优化

配置 AI 服务后：

- 按住快捷键时同时按住 ⌃（Control）键，可启用 AI 优化
- 优化后的文本会自动去除水词、添加标点、修正错别字
- 支持多种 AI 服务：OpenAI、DashScope、Ollama、Claude、智谱、MiniMax 等

## 🔌 STT API 服务

将语音转文字能力暴露为可调用的 API，供外部系统集成：

| 接口 | 说明 |
|------|------|
| `POST /api/v1/transcribe` | 上传音频文件（MP3/WAV/M4A）转文字 |
| `WS /ws/transcribe` | 流式边说边转，停顿检测自动分段 |

详见 [stt-api/README.md](stt-api/README.md)。

```bash
cd stt-api && pip install -r requirements.txt && python stt_api.py --port 50002
```

## 🛠️ 技术架构

- **开发语言**：Swift 5.9+（macOS 应用）、Python（STT API）
- **UI 框架**：SwiftUI
- **音频处理**：AVFoundation, Accelerate
- **语音识别**：SenseVoice Small 模型（本地 ONNX 推理）
- **音频特征提取**：Kaldi Native FBank
- **平台要求**：macOS 14.6+

## 📦 依赖库

本项目使用了以下优秀的开源库，在此表示感谢：

### ONNX Runtime

- **项目地址**：https://github.com/microsoft/onnxruntime
- **授权协议**：MIT License
- **用途**：用于运行 SenseVoice 语音识别模型
- **感谢**：感谢 Microsoft 提供强大的 ONNX 运行时支持

### SenseVoice (FunASR)

- **项目地址**：https://github.com/alibaba-damo-academy/FunASR
- **授权协议**：Apache 2.0 License
- **用途**：提供多语言语音识别模型
- **感谢**：感谢阿里巴巴达摩院开源 SenseVoice 模型，使本地化语音识别成为可能

### Kaldi Native FBank

- **项目地址**：https://github.com/kaldi-asr/kaldi
- **授权协议**：Apache 2.0 License
- **用途**：音频特征提取（Mel 频谱图）
- **感谢**：感谢 Kaldi 项目提供高效的音频特征提取库

## 📄 授权协议

本项目遵循 MIT License。详见 [LICENSE](LICENSE) 文件。

## 🙏 致谢

感谢所有开源社区和开发者为本项目提供的支持：

- **Microsoft** - ONNX Runtime
- **阿里巴巴达摩院** - SenseVoice 模型
- **Kaldi 团队** - 音频特征提取库
- **Apple** - Swift 和 SwiftUI 框架

## 📚 技术文档

本项目的核心技术实现细节已记录在以下文章中：

- **[从零到一：打造一款高效的语音转文字输入法](https://83d.me/2025/11/22/voice-input-method-from-scratch)** - 详细记录了项目的技术选型、ONNX Runtime 集成、音频特征提取、标点符号支持等核心技术实现过程
- **[语音转写「又快又准」策略实现详解](docs/语音转写快准策略实现详解.md)** - 双路径并行、动态规划分批、松键合并等实现细节

## 📝 更新日志

详见 [CHANGELOG.md](CHANGELOG.md)。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📧 联系方式

- **GitHub Issues**：https://github.com/xurenlu/fastv/issues
- **技术博客**：https://83d.me/2025/11/22/voice-input-method-from-scratch

---

**注意**：本项目仅供学习和研究使用。使用第三方库时请遵守相应的授权协议。
