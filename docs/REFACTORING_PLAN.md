# FastV 项目重构方案：聚焦语音输入与 STT 能力暴露

## 一、新项目定位

**核心定义**：聚焦提供语音输入功能，并将语音识别成文字的能力暴露为可调用的 API。

- **语音输入**：macOS 全局快捷键语音输入，边说边转（停顿检测）
- **能力暴露**：HTTP API 接受外部音频文件，WebSocket 支持流式边说边转

## 二、拟移除功能清单

### 高优先级移除（与核心无关）

| 功能 | 涉及文件/模块 | 说明 |
|------|---------------|------|
| 视频下载 | VideoDownloader.swift | 依赖第三方 RapidAPI，与 STT 无关 |
| MicroApp 系统 | MicroAppManager, MicroAppBridge, MicroAppHostView, examples/ | 60+ 示例，复杂度高 |
| Lua 引擎 | LuaEngine.swift | 未启用 |
| 健康助理 | HealthAssistantView, HealthKitService, FoodRecognitionService, CalorieCalculator | 饮食/运动/健康指标 |
| 支出管理 | ExpenseView, ExpenseViewModel, ReceiptVisionService | 收据识别、支出记录 |
| 日记功能 | DiaryView, DiaryStore | 可合并到语音备忘录 |
| 情报功能 | IntelView, IntelStore | 定位不明确 |

### 中优先级移除（可后续处理）

| 功能 | 说明 |
|------|------|
| 视频工具（除音频转文字外） | 格式转换、压缩、裁剪、水印、卡通化等 14 项 |
| 邮件功能 | Gmail/IMAP 完整邮件客户端 |
| 已废弃 DiarizationServiceManager | 说话人分离改为独立部署 |

### 保留功能

| 功能 | 说明 |
|------|------|
| 语音输入法 | 全局快捷键、实时转文字、智能分段 |
| 语音备忘录 | 快速笔记、AI 优化 |
| 会议记录 | 自动检测、分段转文字、AI 总结 |
| 快速纠错 | 常用词、水词修正、AI 优化 |
| 视频工具-音频转文字 | 与 STT 核心相关 |
| AI 服务配置 | 文本优化依赖 |
| 说话人分离 | 独立 Python 服务，可选 |

## 三、新增：STT API 服务

新建 `stt-api/` 目录，提供：

### 1. HTTP 接口 `POST /api/v1/transcribe`

- **输入**：音频文件（MP3、WAV、M4A 等）
- **输出**：JSON `{ "text": "转录文本", "language": "zh", ... }`
- **实现**：sensevoice-onnx + pydub 预处理

### 2. WebSocket 接口 `WS /ws/transcribe`

- **输入**：客户端持续发送音频二进制流（PCM 16kHz 单声道）
- **输出**：检测到停顿时，服务端推送 `{ "type": "segment", "text": "..." }`
- **实现**：VAD 停顿检测 + 分段转录，边说边转

## 四、实施顺序建议

1. **Phase 1**：创建 STT API 服务（HTTP + WebSocket）
2. **Phase 2**：精简 macOS 应用，移除高优先级无关功能
3. **Phase 3**：更新 README、文档，统一版本号与 CHANGELOG
