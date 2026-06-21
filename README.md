# 妙打 MuseType — macOS 上的「光标即输入框」语音输入工具

妙打是一款定位极简的 macOS 语音输入工具：**按住快捷键说话 → 松开转写 → 直接落到当前输入框**。完全本地识别，菜单栏常驻、零打扰；可选接 AI 后处理做去口水词、加标点、按场景换语气。

> v2.0.0 起，妙打收敛为**纯语音输入工具**；邮箱、视频、Todo 等历史产品线已不在主线。
>
> 当前版本：**v2.1.0**（hotfix `v2.1.1-rc1` 已发）。最近一轮按 VoiceInk / Superwhisper / TypeWhisper / Wispr Flow / VocaMac 做了竞品调研，补齐了**热键三模式 / 术语包 / Power Mode / 跟随光标**四件套。

## ✨ 核心功能

### 🎤 语音输入（本地、低延迟）
- **全局快捷键**：默认 `⌥ + V` 触发普通语音输入；`FN + ⌃` 触发「语音 + AI 校正」
- **触发方式三选**（v2.1.0 新增）：
  - `按住录音 Push-to-Talk`（默认，按下开始、松开结束）
  - `按一下切换 Toggle`（按一次开/再按一次关，适合长段口述）
  - `混合 Hybrid`（短按 = 切换、长按 ≥ 0.25s = 按住录音）
- **智能分段**：检测到停顿（默认 0.8s）自动分段转写，边说边输出
- **多语言**：中文 / 英文 / 日文 / 韩文 / 粤语，本地 [SenseVoice-Small](https://github.com/alibaba-damo-academy/FunASR) ONNX 推理
- **菜单栏常驻**：四态徽章（闲置 / 录音 / 转写 / AI 优化），可选「跟随光标」悬浮指示器

### 🧠 术语包（v2.1.0 新增）
专有名词、产品名、技术术语优先生效且**大小写不敏感**。说「open ai」也能输出「OpenAI」，说「k8s」直接拼成「Kubernetes」。

### 🎯 Power Mode — 上下文感知 prompt（v2.1.0 新增）
按**前台 App / 浏览器 URL**自动切换 AI 后处理 prompt 模板。出厂内置 4 套预设：

| 场景 | 触发条件 | 效果 |
|---|---|---|
| 邮件正式 | Mail / Outlook / Spark / `*mail.google.com/*` | 加敬语、拆段、书面化 |
| Slack | slackmacgap / `*.slack.com/*` | 简短、加 - 项目符号 / 代码块 |
| IM 口语 | 微信 / Discord / Telegram / WhatsApp | 保留语气、不硬塞书面语 |
| 代码 / IDE | Xcode / VS Code / Cursor / JetBrains | 默认 `// ` 开头的英文注释 |

支持自定义场景，三种匹配规则（bundleId / URL 通配 / App 名 contains）任意组合。

### 🤖 AI 后处理（可选）
按 `FN + ⌃`（或自定义热键）走 AI 优化路径：去口水词、补标点、修错别字、按场景调语气。

**支持的 AI Provider**：Ollama（本地）、OpenAI、Claude、Gemini、DashScope、智谱、MiniMax（国内/国际）、OpenRouter、Some.IM，以及任意 OpenAI 兼容中转站。

## 🚀 快速开始

### 1. 安装
从 [GitHub Releases](https://github.com/xurenlu/fastv/releases) 下载，或从源码编译：

```bash
git clone https://github.com/xurenlu/fastv.git
cd fastv
pod install
open fastv.xcworkspace
```

### 2. 授权
首次启动需要在系统设置里授权：
- **麦克风** — 录音
- **辅助功能** — 全局快捷键监听 + Power Mode 抽前台 App / 浏览器 URL + 跟随光标取 caret

### 3. 使用
1. 在任意 App 的输入框点一下（让光标进去）
2. 按下默认快捷键 `⌥ + V` 开始说话
3. 松开 → 文字自动落到光标位置

想用 AI 校正：按 `FN + ⌃` 即可。可在「设置 → 语音输入与快捷键」里改成 toggle / hybrid 模式。

## 🎛️ 设置入口

| 入口 | 功能 |
|---|---|
| 快速配置 | 快捷键、触发方式、识别语言、悬浮指示器（位置 / 跟随光标 / 样式 / 颜色） |
| AI 与模型 | AI Provider 配置、场景映射、**Power Mode**（场景 Profile 编辑）、纠错规则管理（含术语包） |
| 数据与其他 | 历史记录、模型下载、关于 |

## 🔌 STT API（独立子项目）

把语音转文字能力暴露成 HTTP / WebSocket 接口，供外部系统集成：

```bash
cd stt-api && pip install -r requirements.txt && python stt_api.py --port 50002
```

详见 [stt-api/README.md](stt-api/README.md)。

## 🛠️ 技术栈

| 层 | 技术 |
|---|---|
| 平台 | macOS 14.6+（开发 / 测试在 macOS 26） |
| 语言 | Swift 5.9+，部分 Python（STT API） |
| UI | SwiftUI + AppKit 桥接（菜单栏、全局热键、悬浮窗口） |
| 音频 | AVFoundation、Accelerate |
| ASR | [SenseVoice-Small](https://github.com/alibaba-damo-academy/FunASR) ONNX，本地推理 |
| 特征提取 | [Kaldi Native FBank](https://github.com/kaldi-asr/kaldi) |
| 上下文 | NSWorkspace + AX（前台 App / 浏览器 URL / 文本 caret） |

### 关键文件速查
- `fastv/Services/GlobalShortcutMonitor.swift` + `fastv/Services/HotkeyTriggerStateMachine.swift` — 全局快捷键监听 + 三模式触发状态机
- `fastv/Services/AppContextResolver.swift` + `fastv/Models/ContextProfileManager.swift` — Power Mode 上下文路由
- `fastv/Models/CommonMistakeManager.swift` — 术语包 + 错字纠正管线
- `fastv/Views/WaveformView.swift` + `fastv/Services/CursorPositionLocator.swift` — 悬浮指示器 + 跟随光标
- `fastv/Services/OllamaService.swift` + `fastv/Services/AIServiceAdapter.swift` — AI Provider 适配层
- `fastv/Services/SpeechTranscriber.swift` — SenseVoice ONNX 推理入口

## 📦 测试

```bash
bash scripts/run_unit_tests.sh
```

当前共 **41 个单测 / 6 个 suite**，覆盖：热键状态机、术语包优先级与大小写命中、ContextProfile 匹配优先级与占位符渲染、CursorPositionLocator clamp 数学、AIScenario 与 Markdown 解析等。

## 🧩 依赖与致谢

- [Microsoft ONNX Runtime](https://github.com/microsoft/onnxruntime) — MIT，本地 ONNX 推理
- [SenseVoice (FunASR)](https://github.com/alibaba-damo-academy/FunASR) — Apache 2.0，多语种 ASR 模型
- [Kaldi Native FBank](https://github.com/kaldi-asr/kaldi) — Apache 2.0，音频特征提取
- Apple Swift / SwiftUI / Accessibility

## 📚 相关文章 / 文档

- [从零到一：打造一款高效的语音转文字输入法](https://83d.me/2025/11/22/voice-input-method-from-scratch) — 技术选型、ONNX 集成、特征提取、标点支持
- [语音转写「又快又准」策略实现详解](docs/语音转写快准策略实现详解.md) — 双路径并行 / 动态规划分批 / 松键合并
- [CHANGELOG.md](CHANGELOG.md) — 全部版本变更
- [product-overview.md](product-overview.md) — 设计思路 + 功能清单 + 未完成项

## 🗺️ Roadmap（短期）

- **Batch 4 — 语音指令编辑**（计划中）：在现有「修改 / 润色 / 重写最近一句」基础上扩展「删掉这句 / 换行 / 加粗这段 / 撤销」等编辑指令，对标 Wispr Flow Command Mode

## 📄 协议

MIT。详见 [LICENSE](LICENSE)。

## 🤝 反馈

- Issues：https://github.com/xurenlu/fastv/issues
- 博客：https://83d.me

---

**项目身份说明**：仓库名仍是 `fastv`（向后兼容历史链接）；应用产品名与 Bundle 已迁移到 **MuseType / 妙打**（v2.0.0-rc8 起）。
