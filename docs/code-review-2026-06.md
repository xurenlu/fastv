# fastv 代码体检报告（2026-06）

本报告由 3 路 review agent 并行扫描得出，覆盖：
1. **正确性 / 崩溃 / 数据安全**（agent #1）
2. **代码质量 / 架构健康度**（agent #2）
3. **性能 / 内存 / UX 细节**（agent #3）

扫描范围：`fastv/` 核心 Swift + `stt-api/` Python 服务。

---

## 一、状态总览

| 档位 | 数量 | 含义 | 处理策略 |
|------|------|------|----------|
| **P0** | 5 | 一定会触发崩溃 / 数据丢失 / 明显泄密 | 本轮全改 |
| **P1** | 9 | 高概率触发或后果严重 | 本轮挑 7 项改（1/2/3/4/5/6/8） |
| **P2** | 一批 | 边角 case / 长期负债 | 本轮只清死代码，其余待用户挑 |

**本轮已完成（截至清理 commit）**
- ✅ P2 死代码清理：删除 3 个 `.backup` 文件、`DiaryAIService.swift`、`DiarizationServiceManager.swift`、`AppStateManager` 空壳、`AIScenario` 4 个废枚举值（`videoAnalysis/diaryAnalysis/expenseParsing/intelGeneration`）、`ChatAIService.sendMessageLegacy`、`OllamaService.testOptimizationLegacy`。同时给 `UserPreferences` 的 `aiScenarioBindings` 解码加了「逐项容错」，避免老配置里残留已删 scenario 时整数组丢失。
- ✅ 编译验证通过。

**本轮待改**
- P0：MeetingRecordService 跨 actor 数据竞态、stt-api 上传大小限制、stt-api 模型加载锁、stt-api WS 共享 VAD、ChatAIService 明文 print 响应。
- P1：EmailService 字典加锁、ChatManager 即时落盘、SpeechTranscriber continuation 防多次 resume、流式图文文档不写回 records、录音中 1Hz duration 不写回、loadRecords 异步化、ChatWindow 流式自动追底 + parseMarkdown 节流。
- P2：架构级（EmailViewModel 3191 行拆分、Legacy 接口收敛、@MainActor 摘掉网络服务等）。

---

## 二、P0 列表（强烈建议尽快改）

### P0-1 MeetingRecordService 跨 actor 数据竞态
**位置**：`fastv/Services/MeetingRecordService.swift:80` 与 `:60`
**现象**：类是 `@MainActor`，`records` 是 `@Published`。但 `saveRecords()` 用 `saveQueue.async { try encoder.encode(self.records) }` —— 在后台队列上读 MainActor 隔离的属性；`loadRecords()` 用 `saveQueue.sync` 给 `self.records` 赋值，等于在后台写 MainActor 属性。TSan 必报，偶发 EXC_BAD_ACCESS。
**修复方向**：MainActor 上先 snapshot 出 records 数组再传进 detached Task；或把存储改成 actor。

### P0-2 stt-api 上传无大小限制 → OOM
**位置**：`stt-api/stt_api.py:228-260`
**现象**：`UploadFile.read()` 一次性读所有字节进内存；上传几 GB 文件可远程触发 OOM。
**修复方向**：
- 加 `app.add_middleware` 或上传前做 Content-Length 检查（建议 50MB）。
- 改用 `await file.read(CHUNK)` 流式落临时文件。

### P0-3 stt-api `_ensure_model` 无锁，并发首请求重复加载模型
**位置**：`stt-api/stt_api.py:73-122`
**现象**：`_model_loading` 是普通 bool，没有线程锁。两个并发首请求都看到 `_model is None` 且 `_model_loading=False`，**都进入加载分支**，各加载一遍 GB 级模型，可能撑爆显存。
**修复方向**：加 `asyncio.Lock`（或 `threading.Lock`）包住加载分支。

### P0-4 stt-api WS 多客户端共享同一份 `_vad`
**位置**：`stt-api/stt_api.py:117 / 263-276 / 306-318`
**现象**：模块级单例 `_vad` 在多个 WS 连接间共享，`_vad.vad.all_reset_detection()` 会互相清掉对方的检测状态 → 跨连接漏字 / 截断。
**修复方向**：每个 WS 连接持有自己的 `FSMNVad` 实例；PCM 直接喂 `WavFrontend`，跳过临时 wav。

### P0-5 ChatAIService 明文 print 完整 AI 响应到 stdout
**位置**：`fastv/Services/ChatAIService.swift:188-193`、`:614-624`
**现象**：任何上游响应（含 prompt 回显、可能的 token 片段、用户隐私邮件/笔记原文）都被 `print("📄 完整响应 JSON: ...")` 输出。长期 stdout 留痕 = 抓 log 即泄密。
**修复方向**：DEBUG 才打日志；统一 `Logger` + `.private` privacy；对响应体长度截断 + 关键字段（authorization/key/cookie）掩码。

---

## 三、P1 列表

### P1-1 EmailService.backgroundSyncTasks 字典裸读裸写
`fastv/Services/EmailService.swift:65 / 404 / 488 / 493-494`
`nonisolated(unsafe) backgroundSyncTasks: [UUID: Task]` 多 detached Task 与 MainActor 调用点共享，无锁。并发触发 schedule/cancel 可能崩 / 泄漏任务句柄。
**修**：换 `OSAllocatedUnfairLock` 或 actor 容器。

### P1-2 ChatManager 2 秒 debounce 才落盘，崩溃即丢消息
`fastv/Models/ChatManager.swift:24 / 198-225`
**修**：`finishStreaming` / `addMessage` 后立即 flush；UUID 解码用 guard 跳过坏 key。

### P1-3 SpeechTranscriber continuation 可能被多次 resume → trap
`fastv/Services/SpeechTranscriber.swift:596-627`
`audio.conversion` queue 上的 `requestMediaDataWhenReady` 重复调度时，continuation.resume 可能被并发多次调用，触发 Swift trap。
**修**：用 `resumed` 标志 + 锁保护，确保只 resume 一次。

### P1-4 流式图文文档每 token 写回 records → 卡 UI
`fastv/Services/MeetingRichDocPipeline.swift:188`、`fastv/Views/MeetingRecordView.swift:705`
每个 token chunk 都 mutate `records[index].richDocumentMarkdown` → 整个 records publish → 左侧列表 diff + 右侧主线程 parseMarkdown 重跑。录音中卡顿源头。
**修**：流式累积放 pipeline 自己的 `@Published streamingText`；UI 优先订阅它；定稿才 commit 到 record。`MeetingRecordView` 渲染用 `@State elements + .task(id:)` 异步解析 + 节流到 150ms。

### P1-5 录音中 1Hz duration 写回 records 引发列表全量 diff
`fastv/Services/MeetingRecordService.swift:354`、`fastv/Views/MeetingRecordView.swift:19`
1 Hz `records[index].duration` 触发 `@Published records` → LazyVStack 整列每秒 diff；`filteredRecords` 是裸 computed，每次 body 求值都重算。
**修**：录音中时长用单独 `@Published recordingDuration` 仅给当前行展示；`filteredRecords` 改 `@State` 由 `onChange(of: service.records / searchText)` 维护。

### P1-6 MeetingRecordService.loadRecords 启动主线程同步 IO
`fastv/Services/MeetingRecordService.swift:60`
init 里 `saveQueue.sync` 等磁盘读 + JSONDecode。
**修**：init 给 `records = []`；async 加载完再 publish。

### P1-7 saveRecords 每 15s 全量 pretty JSON 覆写
`fastv/Services/MeetingRecordService.swift:80`
**修**：取消 prettyPrinted；按节流（≥30s）落盘；或拆单条文件。

### P1-8 ChatWindow 流式不会自动追底 + Markdown 不节流
`fastv/Views/ChatWindowView.swift:265`、`fastv/Views/ChatMessageView.swift:143`
`onChange(of: count)` 只在新增消息时滚动，token 累加不滚；同时 parseMarkdown 每 token 重跑。
**修**：加 `onChange(of: lastMessage.content)` debounce 100ms scrollTo bottom；parseMarkdown 节流到 150ms。

### P1-9 多处错误只 print 不冒泡 UI
`fastv/Services/MeetingRecordService.swift:204,338,397`、`fastv/fastvApp.swift:1132,1313,1359`
转写失败 / AI 失败 / Token 过期等，用户只看到悬浮窗消失不知道为什么。
**修**：统一 `errorMessage` / Toast / NSAlert。

---

## 四、P2 列表（待你挑）

### 架构 / 重构
- **EmailViewModel.swift 3191 行（超 CLAUDE.md 3000 红线）** — 71 个方法 / 39 个 `@Published`，应按 MARK 拆出 `EmailReplyViewModel` / `EmailComposeViewModel` / `EmailAIPolishViewModel`。
- `EmailView.swift` 1910 行 — 内嵌 `FolderRow / MessageRow / MessageHeadersView / DeleteConfirmationView` 6 个 View 可外拆。
- `EmailStore.swift` 1481 行 — 拆 `EmailFolderStore / EmailMessagePager / EmailMigrator`。
- `fastvApp.swift` 1379 行 — 6 个 setup 块按职责拆 extension 文件。
- `OllamaService.swift` 1364 行 — 拆「测试 / 模型管理 / 文本生成 / 多模态」。

### Legacy 收敛
- `ChatAIService.generateSummary / generateTitle` 拿到 profile 后**完全没用 adapter，直接转 Legacy**——新接口形同空壳。应改成基于 adapter 的单一实现，然后删 Legacy 兄弟。
- `OllamaService` 的 `optimizeTranscript → optimizeTranscriptLegacy` 等 4 对 Legacy 转发链。
- `ChatAIService / OllamaService / AIServiceAdapter` 整类 `@MainActor` 不合理 —— 网络/JSON 解析为主，应改 actor / 普通 class。

### 性能小项
- `VoiceInputService` 10MB PCM 上限 → 长录音末尾整段重转写无法成功；应落盘 PCM 分段。
- `MeetingRecordService.currentTranscriptSegments` `joined("")` 每 15s O(n²) → 维护 `accumulatedText`。
- `UserPreferences` 80+ `@Published willSet` 同步 JSONEncoder + UserDefaults。
- `VoiceInputView` 历史记录裸 VStack → LazyVStack。
- `ForEach(elements.enumerated(), id: \.offset)` 流式时不能复用行 → 用 element 的稳定 id。
- `TextCorrectionManager` 主线程同步写 10k 条 UserDefaults。

### UX 小项
- 录音中切到其他记录后看不到当前录音进度 → 加返回浮条。
- mermaid 渲染失败的兜底提示。
- `ContentView` 5 个 case 重复 toolbar 块可抽 `ToolbarContent`。

---

## 五、修复顺序建议

1. **稳定性优先**（本轮已确认要改）：P0 全部 + P1-1/2/3 — 这些是已知会崩或丢数据。
2. **新功能体验**（本轮已确认要改）：P1-4/5/6/8 — 实时图文文档与 chat 流式的实际卡顿源。
3. **架构债**（后续单独排）：EmailViewModel 拆分、Legacy 收敛、@MainActor 摘除。
4. **小项**（随手或单独排）：UX 兜底、错误提示统一、VoiceInput 落盘 PCM。

---

更新记录：
- 2026-06-03：首版，3 路 review 汇总；同步完成 P2 死代码清理。
