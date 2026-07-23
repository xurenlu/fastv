# Product Overview

> 最后更新：2026-07-23 | 当前版本：v2.4.0-rc7

## 当前设计思路

轻语（QEcho）定位为 macOS 上的低打扰语音输入工具。应用优先保持后台常驻，通过全局快捷键、悬浮波形和本地语音转写能力，把 AI 语音输入送到用户正在使用的输入场景里。

## 主要功能

- 系统输入法（实验性）：QEchoIME 作为独立 IMKit 输入法随主 App 分发，输入源菜单显示「轻语输入法」并使用 QEcho App 图标，设置页一键安装到 `~/Library/Input Methods` 并注册启用。打字由 librime 驱动，三方案可切换：五笔·拼音混打（默认）/ 纯五笔 86 / 纯拼音，设置页或输入法下拉菜单均可切换并双侧同步；`` ` `` 前缀拼音反查五笔编码、Shift 中英切换、内联组字 + 自绘候选窗（横/竖排、字体字号、浅深两套配色、圆角间距、序号编码显隐均可在设置页定制并实时预览）。候选快捷键：数字选字、空格首选、分号次选、引号三选（纯五笔）、`-`/`=` 与 `,`/`。` 翻页、Tab 轮换、回车上原始编码。动态词频（用户词库）可在设置页开关。输入法下拉菜单提供打开轻语设置、方案切换、中英/全角开关。选中轻语输入法时，语音文本经 CFMessagePort → `IMKTextInput.insertText` 走系统输入法通道上屏（失败自动回退 CGEvent / 剪贴板），插入前自动落掉进行中的组字。词典预编译随包分发（含纯五笔 prism），用户词典与设置在 `~/Library/Application Support/QEchoIME/`。
- 语音输入法：默认按住快捷键录音、松开转写并插入当前输入框；设置 → 触发方式 还可切换「按一下切换」（toggle）或「混合」（短按 = 切换、长按 ≥ 0.25s = 按住录音），覆盖长段口述与短句两类场景。
- 术语包：常错词管理新增「术语包」分栏。专有名词、产品名、技术术语在替换管线中优先生效且大小写不敏感，说「open ai」也能输出「OpenAI」。
- Power Mode（场景感知 prompt）：按前台 App / 浏览器 URL 自动切换 AI 后处理 prompt 模板。出厂内置 4 套预设（邮件正式 / Slack 简短 / IM 口语 / IDE 代码注释），用户可加自定义场景（bundleId / URL 通配 / App 名 contains 三种匹配规则 OR 组合）。AX 抽 Safari/Chrome/Arc/Brave/Edge/Firefox 当前 tab URL，1s 缓存。
- 悬浮指示器位置：除「左上 / 右上 / 左下 / 右下 / 正中下方」5 个固定位置之外，新增「跟随光标」—— 录音期间小指示器贴着输入光标移动（AX 拿 caret bounds 优先，失败兜底鼠标位置）。
- 关于窗口：独立 macOS 窗口展示轻语版本、作者主页，以及包含 GitWise、象墨等产品的 83d 系列推荐应用。
- AI 语音优化：AI 快捷键可对转写文本进行口语化清理、标点补全、错字修正和轻度结构化整理；当口述内容天然包含多个事项、条件、步骤或请求时，可整理成 2-5 条短列表。
- 中英混合术语校正：内置高置信度术语/流行技术词规则（如 `麦克 app → Mac app`、`Mac OS → macOS`、`open ai → OpenAI`、`git hub → GitHub`、`type script → TypeScript`），并通过默认 AI prompt 处理需要语境推断的产品名、技术词和流行词。
- 同 App 短上下文联想校正：AI 语音优化会读取当前焦点输入框光标前的小段文本，只在同一 App / 当前输入框内作为参考，用于修正同音或近音误识别；动态上下文放在 user message，固定规则保留在 system prompt 以提高 DeepSeek / Kimi 等模型的 cache rate。
- AI 上下文回改：识别到“修改上一句”“润色这句”“重写”等语音指令时，读取当前 text input / textarea 的内容，只回改选中文本或光标前最近一句。
- 智能分段转写：长语音输入时按停顿后台转写，松开后合并输出。
- 会议记录：支持录音、转写、摘要与导出；录音同时 AI 流式生成「图文并茂」的结构化 Markdown 文档（要点列表、表格、勾选框行动项、mermaid 思维导图）。
- AI 服务配置：支持本地 Ollama、OpenAI、Claude、Gemini、DashScope、智谱、MiniMax、OpenRouter 等多种协议；可注册多个 Provider，并按场景（语音输入优化 / 会议转写修订 / 会议摘要 / 会议图文文档 / Todo / AI 聊天）分别绑定不同模型。
- 邮件、聊天、Todo、视频工具和 MicroAPP 工具集合。

## 待完成问题

- 输入法收尾项：关于页展示第三方许可（librime BSD-3 / rime-wubi LGPL-3.0 / rime-pinyin-simp Apache-2.0 / rime-prelude LGPL-3.0，LICENSE 文件已随包）、安装后引导用户在输入法菜单选中「轻语输入法」的提示动画、候选窗样式自定义（当前用系统 IMKCandidates 默认样式）、词频重置入口、模糊音设置（拼音 z/zh 等）。
- 输入法真机回归：在 Safari / 微信 / VS Code / 终端等宿主里过一遍混打、翻页、Shift 切换、语音上屏与组字互斥；覆盖 Sonoma 上 IMKCandidates 的已知怪癖。
- 增加针对常见浏览器 textarea、原生 NSTextView、Electron 输入框的端到端回归测试。
- 为 AI 上下文回改补充更细粒度的用户提示，例如回写失败时提示当前应用不支持 Accessibility 回写。
- 梳理现有硬编码文案，逐步统一到本地化资源。
- IMAP IDLE 当前最小可用版只对默认账号 INBOX 监听，未来可扩到全部启用账号 + 用户开关；状态徽章未来加 NSPopover 详情面板（包含最近一次推送时间 / 重连次数）。
- 多选批量操作（archive / spam / delete）现在是串行 `await` 单条处理；账号内可并行化以提升大批量场景的体验。
- 邮件正文 WebView 渲染未来可加入 prefers-color-scheme 自适应深色 + 系统字体回退。
- IDLE 长连接的"最近 PUSH 间隔过长"自检（比如 12h 没有 EXISTS 也没有错误），目前没有兜底，长期跑可考虑加自检并主动 NOOP。

## 版本记录

- `2.4.0-rc7`：修设置窗左侧 tab 残留键盘焦点边框（.focusable(false)）；推荐应用抽出共享 `RecommendedAppsGrid`，关于窗口与设置页「数据与其他」共用同一精致网格（8 个 App，对齐 museterm 关于窗），替换原设置页手工硬编码的两个推荐；补齐性能/内存监控等文案本地化。
- `2.4.0-rc6`：候选个数 5–9 可选（menu/page_size）；候选窗 6 套一键预设皮肤（经典浅色/夜幕/清新绿/极简黑白/大字护眼/竖排水墨，均由现有可选项拼成，套用后可微调）；设置窗口重构为左侧竖向 tab 5 组（常用/语音输入/输入法·打字/AI 与模型/数据与其他）；移除主窗口 7 套界面皮肤，主窗固定系统默认配色。
- `2.4.0-rc5`：候选窗全面外观定制。自绘无边框 NSPanel + NSView 替代系统 IMKCandidates，支持横/竖排、候选字体与字号、序号/编码提示字号、7 色配色（浅色/深色两套独立可调 + 跟随系统深浅色）、圆角/间距/内边距、序号与编码提示显隐、点击选字。设置页「候选窗外观」区块带实时预览与一键恢复默认。外观经 qecho-ime-settings.json 即时通知 IME 重绘，不触发 Rime 重部署。`CandidateAppearanceTests` 12 例（含旧设置文件向后兼容），全套 80 测通过。
- `2.4.0-rc4`：输入源菜单图标改为单色矢量模板图 `QEchoIMETemplate.pdf`（脉冲麦克风），文件名以 Template 结尾由 macOS 自动明暗反色，替代此前糊/发黑的彩色 App icon 缩图；清理旧 tiff 残留引用。源图 `assets/brand/qecho-ime-menubar-template.svg` 随仓库。
- `2.4.0-rc3`：输入法阶段三 — 试用反馈打磨。输入源显示名「轻语输入法」+ App icon 菜单栏图标（tsInputMethodLocalizedNamesKey / tsInputMethodIconFileKey）；候选快捷键分号次选、引号三选（纯五笔），delimiter 相应避让；新增 `wubi86.schema.yaml` 纯五笔方案（prism 预编译随包）与纯拼音入口，三方案在设置页 segmented / 输入法下拉菜单切换，经 `qecho-ime-settings.json` 双侧同步；动态词频开关（custom 补丁 + IME 热重启部署）；输入法下拉菜单（设置入口经分布式通知唤起主 App / 方案 radio / 中英切换 / 全角开关）；IME 菜单 5 语种本地化。`IMESettingsTests` 8 例，含随包 custom 与生成器一致性防漂移。
- `2.4.0-rc2`：输入法阶段二 — librime 五笔·拼音混打。vendor librime 1.17.0 universal dylib 与 wubi_pinyin/pinyin_simp/prelude 方案数据（含预编译词典与三方 LICENSE）；新增 `RimeEngine`（C API 封装）、`RimeKeyMapping`（键值/光标偏移纯函数，共享单测）；`QEchoIMEController` 实现内联组字、IMKCandidates 候选窗、选字/翻页/Esc/回车、Shift 中英切换（flagsChanged → Rime ascii_composer）、语音上屏前自动清组字。冒烟验证 `wqvb`/`shuru`/`khk` 混出候选；全套 59 单测通过。
- `2.4.0-rc1`：系统输入法（实验性）阶段一。新增 QEchoIME IMKit target（英文直通薄壳 + CFMessagePort 语音上屏服务端），随主 App 嵌入分发；主 App 新增 `InputMethodBridgeService`（检测当前输入源 + 发送转写文本）与 `InputMethodInstaller`（安装 / TIS 注册 / 启用），三处语音插入调用点收敛到 `insertVoiceText` 统一入口并优先走输入法通道；设置页新增「输入法（实验性）」区块与 5 语种文案；`InputMethodBridgeContract` 契约 6 个单测，全套 46 测通过。
- `2.3.0-rc4`：关于窗口对齐 MuseTerm 的紧凑布局，推荐应用卡片使用更大的 42pt 图标，并新增 GitWise 与象墨（Xomo / VeilPic）两个入口及对应本地化文案、图标资源。
- `2.3.0-rc3`：Sparkle appcast 控制面显式固定为 `https://some.im`，避免未来误把 some.im/niuwoai 推理节点或用户自定义 API Base 当作更新源；更新 SomeIMUpdateConfiguration 契约测试，逐项断言 appcast 的 scheme、host、path 与查询参数。
- `2.3.0-rc2`：放大菜单栏闲置态品牌图标。`MenuBarIcon` 三档 PNG 裁掉过多透明边距并提高画布填充率，`StatusBarManager` 明确以 18pt 渲染品牌图标，使轻语图标与系统菜单栏图标并排时更接近同一视觉尺寸。
- `2.3.0-rc1`：集成 Sparkle 自动更新，支持启动检查和应用菜单手动检查更新；更新源统一使用 some.im 的 QEcho stable appcast。
- `2.2.0-rc7`：修正简体中文系统应用名为轻语，英文和其他非中文系统继续显示 QEcho。
- `2.2.0-rc6`：品牌升级为轻语（QEcho），应用产物输出为 `QEcho.app`，关于页推荐应用统一为 Q 系列命名。
- `2.2.0-rc5`：关于页推荐应用收口轻图（QPic / qpic），图片编辑、截图、上传分享类产品不再展示 MuseSnip / 简图。
- `2.2.0-rc4`：AI 后处理新增同 App 短上下文联想校正。优化语音时读取当前焦点输入框光标前最多 260 个 UTF-16 字符，只作为当前 App / 当前输入框参考，帮助把“保持工作去干净”这类同音误识别修成“保持工作区干净”。默认系统提示词与 Power Mode 4 个内置 prompt 同步加入“不复述上下文、不跨 App 使用历史、不引入外部事实”的约束；动态上下文放在 user message，固定规则留在 system prompt 以提升 DeepSeek / Kimi 等模型的 cache rate。

- `2.2.0-rc3`：AI 后处理新增中英混合与流行术语校正。内置规则增量加入 `麦克 app → Mac app`、`麦克 OS / Mac OS → macOS`、`open ai → OpenAI`、`git hub → GitHub`、`type script → TypeScript`、`swift ui → SwiftUI`、`vs code → VS Code`、`k8s → Kubernetes` 等高置信度替换；默认系统提示词和 Power Mode 4 个内置 prompt 同步加入“只在语境明确时修正，不确定时保留原文”的 AI 约束。常错词正则边界改为适配中文上下文的 ASCII 边界，并新增对应单测。

- `2.2.0-rc2`：关于窗口刷新为独立 700×500 macOS 窗口，移植 MuseTerm 的布局结构与推荐应用网格，但内容替换为轻语自己的语音输入定位、隐私承诺、版本信息和作者主页入口。新增企鹅动画帧、推荐应用图标资源，并补齐中 / 英 / 日 / 韩 / 粤 5 语种 About 本地化文案。

- `2.2.0-rc1`：AI 语音输入提示词新增输入法级别的轻度结构化整理。默认 prompt 在多事项、条件、步骤、问题或请求场景可整理成 2-5 条短列表，同时明确不强行列表化单句闲聊、不新增原文没有的信息。Power Mode 邮件 / Slack / IM 预设同步增强，IDE 预设仅对多项 TODO、步骤或条件允许多行 `// - ` 注释列表。旧出厂默认 prompt 与仍未修改的内置预设会温和迁移，用户自定义模板保持不动。

- `2.1.1-rc2`：清理主线工程里已废弃邮件链路留下的 `libetpan.a` 及其 CFNetwork/Security/zlib/sasl/iconv/resolv 依赖链接项和 `ThirdParty/libetpan/include/**` 头文件搜索路径。当前源码不再包含邮件调用层，继续链接 libetpan 只会增加旧构建/误链接触发 `mailstream_cfstream.c:912` QoS 优先级反转诊断的机会；第三方 libetpan 源码保持不改，后续如恢复邮件功能，应继续把 IMAP/SMTP 阻塞 I/O 放在 `.utility` QoS。

- `2.1.0`：定版。竞品调研驱动的「四件套」补齐，覆盖 rc1 → rc6 全部已 ship 能力：热键三模式 + 术语包（rc1）、SwiftUI 测试 host 修复（rc3）、Power Mode 上下文 prompt 模板（rc4）、QEcho 品牌图标（rc5）、光标旁悬浮指示器（rc6）。全套 41 个单测通过。Batch 4「语音指令编辑」单独立项。
- `2.1.0-rc6`：竞品调研第三批 — **光标旁悬浮指示器（Follow Cursor）**。`WaveformWindowPosition` 新增 `.followCursor` 枚举；`Services/CursorPositionLocator.swift` AX 优先链（`AXFocusedUIElement` → `AXSelectedTextRange` → `AXBoundsForRangeParameterizedAttribute` 拿 caret bounds，失败回退 focused element frame，再失败回退 `NSEvent.mouseLocation`）；`WaveformWindowManager` 加 50ms `followCursorTimer`，仅 followCursor 模式启动、hide / cleanup 即销毁。新增 `CursorPositionLocatorTests` 6 例（clamp 数学 + 多屏 + 负坐标）。5 语种 i18n 补齐 6 个位置 displayName + 1 个 hint。
- `2.1.0-rc5`：应用与 DMG 图标统一到 QEcho 新品牌。`AppIcon.appiconset` 全尺寸替换为脉冲麦克风 Logo；新增 `assets/brand/musetype-dmg-volume.icns`，打包脚本创建 DMG 时写入 `.VolumeIcon.icns` 并设置卷标自定义图标；品牌资产目录保留深浅色图形标、中英文组合字标与 PNG 尺寸导出。
- `2.1.0-rc4`：竞品调研第二批 — **Power Mode（上下文感知 prompt 模板）**。新增 `AppContextResolver`（NSWorkspace.frontmost + AX 抽浏览器 URL，1s 缓存）、`ContextProfile` / `MatchRule` 模型（bundleId 100 / urlPattern 50 / appNameContains 10 三档优先级 + `*` 通配）、`ContextProfileManager`（UserDefaults 持久化 + 出厂 4 内置预设：邮件 / Slack / IM / IDE）。`fastvApp.swift` 两个 polish 调用点注入 `resolveSystemPrompt(...)`，未启用 / 未命中走默认 `aiSystemPrompt`。设置 → AI 与模型 新增 Power Mode section 与 `ContextProfileEditorView` 编辑面板。5 语种 i18n。
- `2.1.0-rc2`：清理 v2.0.0-rc1 产品收敛后遗留的 3 个废测试。`EmailRemoteImageBlockingTests.swift` 与 `EmailTranslateStripTests.swift` 整文件删除（引用已不存在的 `EmailBodyWebViewRepresentable.stripRemoteImageSources` / `EmailViewModel.stripHTMLTagsForTranslate`），`MeetingRichDocTests.swift` 顶部 6 个引用已删 `decideRichDocTrigger` 的用例删除，保留下方 Markdown / `AIScenario` 4 个仍然有效的用例。`fastvTests` 目录里不再有 `#if false` 临时屏蔽段。
- `2.1.0-rc1`：竞品调研驱动的首批补齐。
  - **触发方式三模式**：原 push-to-talk 之外新增 toggle（按一下开/再按一下关）与 hybrid（短按切换 / 长按 ≥ 0.25s 退化为 PTT）。引入独立 `HotkeyTriggerStateMachine`（`fastv/Services/HotkeyTriggerStateMachine.swift`），把"物理按键 press/release"翻译为"有效录音 start/stop"，FN / Control / 普通键三条检测路径统一走 `dispatchRawPress` / `dispatchRawRelease`。设置 → 语音输入与快捷键 segmented 实时切换，5 语种 i18n。默认仍为 `pushToTalk` 与历史版本一致。
  - **术语包**：`CorrectionCategory` 加 `.terminology`；`CommonMistakeManager.applyCorrections` 中术语条目优先于一般错字（`getSortedMistakes` 排序时 terminology 在前），且大小写不敏感（regex `.caseInsensitive`）。`CommonMistakeManagementView` 顶部新增「错字纠正 / 术语包」分段，添加对话框在术语模式下自动写 `.terminology` 分类。5 语种 i18n。
  - 新增单测：`HotkeyTriggerStateMachineTests`（三模式状态机）、`TerminologyCorrectionTests`（术语优先 + 大小写命中）。
- `2.0.0-rc14`：CTC 去重改为标准保守流程。启用时先合并连续重复帧，再移除 blank token，尽量保留「谢谢」「我看看」「100」等 blank 分隔的正常重复；设置页文案改为实验性保守去重，并补充单测覆盖叠词与连续数字。
- `2.0.0-rc13`：设置窗口底部移除版本号 footer，避免版本号压在底部分隔线上；版本信息保留在「数据与其他」→「关于」弹窗中。
- `2.0.0-rc12`：语音输入法作为唯一主功能固定启用。设置页移除「启用语音输入法」开关，历史版本保存过关闭状态的用户升级后会自动恢复启用，快捷键注册不再依赖该旧开关。
- `2.0.0-rc11`：主窗口默认皮肤改为「淡雅雾林」。未设置过界面皮肤的新用户默认进入该风格，已手动选择过皮肤的用户保持原选择不变。
- `2.0.0-rc10`：修主窗口启动被语音模型预加载拖慢的问题。主窗口先显示并完成快捷键初始化，ONNX 语音模型延后 1.5 秒静默预热；启动预热优先级从 `.userInitiated` 降为 `.utility`，按下语音快捷键时仍保留即时预热路径。
- `2.0.0-rc9`：主窗口新增界面皮肤选择器，提供系统默认、淡雅雾林、水墨宣纸、科幻光栅、午夜岩蓝、极光暗夜、熔火石墨 7 套风格；主窗口背景、输入区、统计卡片、历史列表即时换肤。深色风格使用专门的浅色文字 token，并补齐中 / 英 / 日 / 韩 / 粤 5 语言文案。
- `2.0.0-rc8`：工程身份收尾到 `musetype`。Xcode app target、共享 scheme、test plan、CocoaPods target、测试宿主路径、`PRODUCT_NAME`、主 Bundle ID、构建/打包脚本产物名统一迁移，编译产物改为 `musetype.app` / `musetype.dmg`；单测导入同步为 `@testable import musetype`。
- `2.0.0-rc7`：回滚 rc6 的 ONNX `IntraOp=1` 实验。`ONNXRuntimeWrapper.numThreads` 恢复 `max(4, activeProcessorCount)`，删 `intraOpNumThreads` 常量。rc5 关掉的二次拼接保留。
- `2.0.0-rc6`：实验性把 ONNX `SetIntraOpNumThreads` 从 `max(4, activeProcessorCount)` 改为 `1`，验证「多 ONNX 推理互抢线程」假设。注意 IntraOp 控制单次推理内部并行，不是 session 并发，理论上单次推理时间会数倍上升。常量 `ONNXRuntimeWrapper.intraOpNumThreads` 提到类顶部方便一行回滚。
- `2.0.0-rc5`：关掉 AI 模式下的「二次拼接转写」。原机制在录音中累计 ≥3 段后会把音频合并再跑一遍 ONNX 提准，但它和前台分段转写抢 ONNX session，让分段感觉变慢；AI 模式本来就有 AI Polish 文本兜底，边际收益不值这个 CPU。新增 `enableBatchRefinementTranscription = false` 编译开关 short-circuit 掉触发点，相关代码（scheduleBatchRefinementTranscription / runBatchRefinementTranscription / partitionSegmentsForBatchRefinement）保留以备 A/B 或回滚。普通快捷键走实时插入分支，本就不触发，不受影响。
- `2.0.0-rc4`：去掉主窗口左右分栏。轻语收敛为纯语音输入工具后，左侧 160pt 的「功能」侧栏只剩 `voiceInput` 一个孤零零的入口，视觉负担大于信息密度。`ContentView` 直接渲染 `VoiceInputView` + 齿轮 toolbar + 设置 sheet，主窗口 minSize 720×520 → 560×520，删除 `SidebarItem` / `SidebarItemRow` 以及 `HSplitView` 结构。
- `1.4.3-rc9`：改名遗留收尾 + 邮件点开真正变已读。(1) 5 个 `Localizable.strings`（en/zh-Hans/ja/ko/yue）的 `app.name` 与所有 `onboarding.welcome` / `welcome.title` / 权限引导文案，外加 5 个 `InfoPlist.strings` 的 `CFBundleDisplayName`，外加 `pbxproj` 里 `INFOPLIST_KEY_CFBundleDisplayName` + 三段权限描述，一次性全部统一为 `QEcho`（en）/ `轻语`（zh-Hans/ja/ko/yue）。当时为避免 TCC 权限失效暂未改工程身份；`2.0.0-rc8` 已完成工程身份迁移。(2) `EmailViewModel.markAsRead` 改成乐观更新：先把 isRead=true 写进 EmailStore（UI 立即变已读），再异步走 IMAP STORE \Seen，IMAP 失败只记日志不回滚本地，依赖 `EmailStore.addMessages` 的 `isRead = server ? server : existing` OR-merge 兜底保住本地读态。
- `1.4.3-rc8`：邮件签名编辑器三连改造：(1) 布局从 `Form` 重构为 `ScrollView + VStack`，可用变量从两列稀疏卡片改为 `LazyVGrid` adaptive 紧凑芯片，4 行 footer 折叠到 `DisclosureGroup`，窗体 `minHeight` 600 → 520；(2) 引入 `SignatureEditorController` + 自定义 `SignatureTextEditor`(NSViewRepresentable 包 NSTextView)，变量芯片点击走 `replaceCharacters(in: selectedRange, with:)` 插入到光标位置，支持 Undo，光标自动推到插入末尾；(3) 内置签名样式从 11 套扩到 17 套，新增「精致样式」分组（品牌卡片 / 左色条 / 暖色线条 / 渐变玻璃 / 蒙德里安 / 黑白胶囊）。HTML 编辑时 NSTextView 用等宽字体。
- `1.4.3-rc7`：修「已发送(本地)」虚拟文件夹被后台同步无差别 IMAP `selectFolder` 触发 NON_EXISTANT_FOLDER（错码 33）的告警刷屏，连带修「点开本地已发送邮件不被标已读」（IMAP 抛错导致 ViewModel.markAsRead 走 catch 分支，本地 `isRead = true` 写库被跳过）。`EmailFolder` 加 `isLocal` 计算属性（以 `path == "__LocalSent__"` 判定）；`EmailService` 全部 IMAP 入口（sync/markAsRead/delete/star/move/fetchBody/fetchRaw/downloadAttachment/search）对本地文件夹短路；`EmailViewModel.startBackgroundSyncTask` 循环顶部 `if folder.isLocal { continue }` 双保险。
- `1.4.3-rc6`：消掉 Xcode runtime 的 `mailstream_cfstream.c:912` 优先级反转告警。libetpan CFStream runloop 跑在 Default QoS，调用线程被钉到 UserInitiated 时会触发 "User-initiated waiting on a lower QoS thread"。`LibEtPanWrapper.m` 的 `ensureUserInitiatedQoS` 函数体改为 `QOS_CLASS_UTILITY`；`EmailService.swift` 中 16 处包 IMAP/SMTP 同步调用的 `Task.detached(priority: .userInitiated)` 全部降为 `.utility`（已存在的 `.background` 后台同步保持不动）。
- `1.4.3-rc5`：rc4 的「正文加载失败 + 重试按钮」收尾。重试按钮先 `loadFolders` 再 `loadMessageBody`，按钮行为对得上文案；`loadMessageBody` 在 folder 解析失败后扫 `EmailStore.messages` 找同账号同 messageId 的副本借用正文（覆盖 Gmail INBOX + All Mail 双份场景），避免 `folder_id` 被 `ON DELETE SET NULL` 清空后整封邮件死锁。
- `1.4.3-rc4`：修邮件正文「正在加载正文...」永远转圈的 bug — 两条卡死路径同时堵：(1)「所有邮件」聚合视图 picked 到 ViewModel.folders 没缓存的文件夹时，原本静默 return 不写状态，现在先到 `EmailStore.accounts` 全量文件夹兜底再找，找不到才写失败态；(2) `fetchMessageBody` 加 45s 超时（`withThrowingTaskGroup` + 计时子任务），超时抛 `EmailServiceError.timedOut`。新增 `bodyLoadFailures` 字典与 `retryLoadMessageBody`，UI 失败态展示橙色三角 + 错误原因 + 重试按钮。
- `1.4.3-rc3`：修翻译时 CSS 被当正文翻译的 bug — `<style>` / `<script>` / `<head>` / 注释 / DOCTYPE 标签整段（含内容）剥离；数字字符引用还原；空白压缩。新增 14 个翻译剥离单测。
- `1.4.3-rc2`：自查 + 单测 + 补漏。给 stripRemoteImageSources 写 21 个单测一次跑挂 13 个，逼出隐私拦截的覆盖盲区，补：无引号 src / `<picture><source>` / `<input type=image>` / `<video poster>` / `<iframe>` / `<embed>` / `<object>` / `<link rel=stylesheet>` / `background:url 短写法` / `<style>` 内 `@import` 与 url(http) 全部挡掉；早退优化（无 http 直接返回）。延迟标读边界补全（selectAccount 取消）；IDLE statuses 删账号时清。
- `1.4.3-rc1`：邮件隐私加固两件套。延迟标已读（默认 3 秒，可调 1/3/5/10/立即/仅手动），换邮件自动取消，杜绝键盘浏览时一路误标；真正挡远程图片 + 追踪像素 —— 注入 HTML 前把外链 `<img src>` / `srcset` 改名为 `data-original-src`，WebKit 不再发起请求，1x1 透明追踪像素失效；其余图片显示"🖼 图片已被隐私保护挡住"占位框，点"显示图片"重新注入后图片正常加载。
- `1.4.2-rc4`：修「所有邮件」启动几秒后列表突然只剩 2 封的 bug。aggregator 改走 DB 直查（新增 `EmailStore.fetchAggregateMessagesFromDatabase`），列表与侧栏数字同源，IMAP 同步 / IDLE 推送 / 后台任务怎么折腾内存 dict 都不会再让列表变少。
- `1.4.2-rc3`：修「所有邮件」侧栏数字与列表不一致（14 vs 2）—— `showAllMessages` 现在先调 `EmailStore.loadAllFoldersForAggregateView` 把账号下所有非 spam/trash/drafts 文件夹从 DB 并发加载进内存，再 aggregator；顺带刷新各 folder 的 message 数缓存。主菜单侧边栏 tab 的 icon 左 padding 从 6 → 14，紫色选中竖条与 icon 之间留出视觉呼吸感。
- `1.4.2-rc2`：复审本轮 IDLE / 附件 / 移动改动并修 P0/P1。IDLE 取消路径补 DONE 再 disconnect；onNewMessage 改 NotificationCenter（修跨 actor 数据竞争 + 多 VM 兼容）；服务器不支持 IDLE 时停止 runLoop 不反复重连；spam / restore 合并到 moveMessageInMemory 单次写库；移动保留 uid；MIME 解析跳过 preamble / epilogue；附件解码降级到 isoLatin1 + 文件名白名单安全化；大邮件截断时附件元信息走全量解析。同时把 UI 推到"酷炫"档：邮件详情 hero header 渐变玻璃卡片、列表行选中竖条 + 蓝点 + chip 角标、toolbar IDLE 状态徽章带呼吸光晕。
- `1.4.2-rc1`：邮件 IMAP IDLE 长连接（默认账号 INBOX 收到新邮件立即推送刷新，25 分钟续期 + 异常指数退避重连）；附件按 MIME part 真实下载（IMAP `BODY.PEEK[<part>]`，按 `Content-Transfer-Encoding` 解码，老数据有 filename 匹配回退）；邮件归档 / 移动 / 标记垃圾 / 取消垃圾后立即从源文件夹移除并加入目标文件夹（新增 `EmailStore.moveMessageInMemory`），不再等下次同步。
- `1.4.1-rc1`：邮件 IMAP 操作真实现（标星 / 取消标星 / 删除 / 移动走 LibEtPan 真命令，含 COPY+EXPUNGE 模拟 MOVE 与中文文件夹 Modified UTF-7 编码）；新增搜索 / 加载 generation 序列号校验，旧任务不再覆盖新文件夹/新搜索词的 UI 结果；新增超大邮件正文保护（>10MB 截断 + UI 提示横幅）；EmailViewModel 按 AIPolish / Translate / Compose 三段拆为 extension 文件，主文件 3302 → 2443 行脱离 CLAUDE.md 3000 红线。
- `1.4.0-rc4`：邮件可靠性加固。`EmailService.backgroundSyncTasks` 全部访问改走带 NSLock 的 helper（修复多账号并发同步可能崩溃 / 泄漏 Task 句柄的隐患）；删除账号时同步取消该账号的后台同步任务；AI 翻译 / 排版优化的取消路径不再覆写已切回的原文缓存；`sendMessage` 与正文合并日志去除收件人 / 主题 / 附件名等明文敏感信息。
- `1.4.0-rc3`：邮件详情新增 AI 翻译按钮（点一次译为中文，再点切回原文，译文按消息 id 缓存）；新增 docs/code-review-2026-06.md 体检报告；清理 5 处死代码 + 4 个废枚举 + 3 个 .backup 文件，并加固 aiScenarioBindings 解码容错。
- `1.4.0-rc2`：修复工具栏齿轮设置按钮的焦点圈外观问题（`.focusable(false)`）。
- `1.4.0-rc1`：会议记录新增「实时图文文档」面板，录音过程中 AI 流式输出结构化 Markdown，支持表格、勾选框、mermaid 思维导图；AI 设置新增「会议转写修订」与「会议图文文档」两个独立场景，可分别绑定不同 provider / 模型；统一新增流式（SSE）调用能力，覆盖 OpenAI 兼容、Claude、Gemini、DashScope、Ollama 等协议。
- `1.3.0-rc6`：优化语音输入响应速度，快捷键按下即预热识别模型，降低录音缓冲延迟，并复用 token 映射减少每次转写的固定开销。
- `1.3.0-rc5`：修复单元测试宿主退出时 ONNX 语音模型预加载仍在后台初始化导致的崩溃提示，并为启动预加载增加防重入保护。
- `1.3.0-rc4`：修复内存监控阈值误判与后台持久化并发隐患，同步测试 target 版本配置，提升长期运行稳定性。
- `1.3.0-rc3`：新增共享测试 scheme、test plan 和命令行单测脚本，并补齐测试 target 依赖搜索路径，让单元测试可在命令行/CI 稳定发现、构建和执行。
- `1.3.0-rc2`：补充语音回改核心规则测试，并收敛语音输入相关日志中的用户文本输出。
- `1.3.0-rc1`：新增 AI 上下文回改最近一句，支持按标点和换行识别回改范围。
