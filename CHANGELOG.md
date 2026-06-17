# Changelog

所有版本變更記錄。

## [2.0.0-rc3] - 2026-06-17

竞品调研驱动的「四件套」打磨：易用性、准确性、稳定性、美观一锅端。

### 改进

- **隐私锚点（about + settings）**：版本信息上方和设置「通用」section 顶部都加上「语音转写在本机完成，无需联网」的绿色徽章。竞品调研反推：Wispr Flow / Typeless 都是云端，Typeless 还在「on-device」措辞上翻车；我们真的本地，要让用户看得到。5 语言 i18n。
- **波形窗口「极简模式」**：`WaveformWindowStyle` 新增 `.minimal` 一档，录音中只显示一个 8pt 的呼吸光点（随音量缩放 0.6×~1.2×），不画波形 bars。窗口尺寸缩到 24×24。适合写作 / 演示 / 录屏不被打扰的场景。状态颜色随状态切换（录音红 / 转写蓝 / AI 紫）与菜单栏徽章对齐。
- **中文 AI 优化提示词打磨**：默认 system prompt 新增三块：(1)「改口识别」专章，命中"不是 X 是 Y"/"等等重说"等模式时丢前半段保后半段；(2)「中英混合规则」明确中英文间留半角空格、专有名词保留原大小写（iPhone/macOS/GitHub 不要写成 Iphone/Macos/Github）、数字与单位间留空格；(3) 填充词列表扩展到 30+ 词（"那种""的话""然后呢""怎么说呢"等）。安全规则原封不动（反 prompt injection 那块）。
- **Onboarding 5 步精简为 2 步**：模型下载 → 完成页。语言 / 快捷键 / AI Config 全部走默认值（语言跟系统、快捷键已预设、AI 优化默认关），用户首次成功转写后再去设置自定义。竞品调研反推：SuperWhisper「15-30 分钟配置劝退」是反面教材，目标 = **默认值敢拍板**。原来的 LanguageSelectionStep / ShortcutSetupStep / AIConfigurationStep / UsageGuideStep 代码保留未删（供设置页或未来「重新引导」复用）。新增 OnboardingCompletionStep，4 行 hint 指路到设置。
- **WaveformView 录音渲染补 Group 包裹**：minimal/经典两个分支共用 `.transition(.asymmetric(...))`，编译稳定。

## [2.0.0-rc2] - 2026-06-17

### 改进

- **菜单栏状态徽章四态可视化**：用户瞥一眼菜单栏就知道当前在做什么。
  - 闲置 → ⚡️ 闪电（跟随菜单栏深浅色）
  - 录音中 → 🎤 麦克风（红）
  - 转写中 → 〰️ 波形（蓝）
  - AI 优化中 → ✨ 星花（紫）
  - 状态来源订阅 `WaveformWindowManager` 已有的状态机（recording/transcribing/aiCorrecting），无需在各处插桩。tooltip 同步显示当前活动名称，5 语言 i18n（中/英/日/韩/粤）。
- 设计动机来自竞品调研：Wispr Flow 试用后掉链子、SuperWhisper 配置复杂被劝退，状态透明度本身就是稳定性的可见证据。

## [2.0.0-rc1] - 2026-06-17

### 重大变更

- **产品线拆分**：妙打（MuseType）收敛为纯语音输入工具。邮件客户端拆分为独立产品 museMail（~/Sites/musemail），会议记录拆分为独立产品 museNote（~/Sites/musenote）。
- **砍除模块**：移除邮件、会议记录、AI Todo、AI Chat、视频工具、MicroAPP 等所有非语音输入模块的代码与界面（约 70 个源文件）。侧边栏仅保留「语音输入」。设置页移除「邮箱」标签页。
- **Dock 图标隐藏**：三个 app 统一新增「在 Dock 中隐藏图标」开关（设置 → 通用），开启后仅菜单栏常驻，运行时即时切换无需重启。i18n 覆盖中/英/日/韩/粤五种语言。
- 移除 AppleScript 邮件脚本支持（.sdef + FastVScriptingApplication）。
- 清理桥接头文件，移除 LibEtPanWrapper / LuaWrapper 引用。

## [1.4.3-rc14] - 2026-06-16

### 修复

- **打开邮件正文后仍不标已读**：`selectMessage` 会并发起 `markAsRead`（标已读）和 `loadMessageBody`（加载正文）两个任务；正文加载分支用点击瞬间捕获的旧副本（`isRead=false`）整条回写列表与 `EmailStore`，把刚标好的 `isRead=true` 覆盖回 `false`——正文已缓存时几乎必中（永远标不上），首次打开走网络时表现为「闪一下已读又变回未读」。修复：新增 `refreshVolatileFlags`，在三条正文回写分支（缓存命中 / orphan 救援 / 网络抓取）回写前，从最新副本同步 `isRead / isStarred / isSpam / isDeleted`，正文加载不再误改用户态标志位。

## [1.4.3-rc13] - 2026-06-14

### 清理

- 移除 `AIProfileEditView.saveProfile()` 里 6 行调试 `print`（保存按钮点击、编辑模式、Profile ID/Name 等），不影响功能，纯净化日志输出。

## [1.4.3-rc12] - 2026-06-14

### 修復（i18n 去重）

- 清理 `Localizable.strings` 历史遗留的重复 key：`speech.model.preload.title` / `speech.model.preload.message` 在 zh-Hans、en 两个文件中各出现两次（第 44/45 行与第 433/434 行）。按 .strings「后者生效」规则，此前 zh-Hans/en 实际显示的是晚出现的那份；现统一保留语义更完整、且与 ja/ko/yue 现存唯一一份一致的第 44/45 行版本，删除晚出现的重复项。
- 用脚本对 5 个语言文件（zh-Hans/en/ja/ko/yue）做了全量重复 key 扫描，确认除上述外无其他重复；清理后复扫均无重复。未触碰任何无关 key。

## [1.4.3-rc11] - 2026-06-14

### 修復 / 体验（AI 服务编辑 + 邮件标已读 + 翻译）

**AI 服务编辑：API Key 可见性切换**
- `AIProfileEditView` 的 API Key 输入框旁新增「小眼睛」按钮，点一下在密文（`SecureField`）与明文（`TextField`）之间切换，方便核对粘贴进去的 key 是否正确；默认仍为隐藏态。明文模式下关闭自动纠错，避免 key 被「自作聪明」改掉。

**邮件点击即时标已读**
- `selectMessage`：鼠标点击邮件视为「明确打开」→ 立刻标已读，不再受默认 3 秒延迟拖累（仅「仅手动 -1」模式保留不自动标）。列表里点击只有 `onTapGesture` 一条路径，没有方向键被动浏览会误标，所以即时是安全的。
- `markAsRead`：标读时同步乐观更新 VM 的 `messages` 列表副本，消除原本 0.5 秒 EmailStore 订阅防抖滞后——未读圆点/加粗当场消失，列表与详情页同步。
- `EmailSettingsTab` 的「自动标已读」设置文案同步对齐新行为。

**邮件翻译可单独配 AI**
- 新增独立的 `emailTranslate`（邮件翻译）AI 场景，加入 `activeScenarios`，可在「AI 场景映射」里为翻译单独指定服务/模型；未绑定时回退默认 Profile，再回退旧版兼容配置。
- `EmailAIService.translate()` 由硬编码的 `.aiChat` 改为走 `.emailTranslate` 场景——翻译终于不再被迫和「AI 聊天」共用一套配置。

**国际化（i18n）**
- `AIServiceManagementView`（含编辑表单、测试连接的全部错误文案）此前 26+ 处硬编码中文全部接入 `NSLocalizedString`；测试结果成败判断从 `contains("成功")` 字符串匹配改为独立布尔 `testSucceeded`，避免翻译后判断失效。
- `AIScenario` 的 `displayName` / `sceneDescription` 全部 i18n。
- 5 个语言（zh-Hans/en/ja/ko/yue）各补齐 69 条新 key，格式符（`%@`/`%d`/`%.1f`）跨语言对齐。

## [1.4.3-rc9] - 2026-06-09

### 修復（改名遗留 + 邮件标已读真正落地）

用户反馈窗体标题还显示「row1」、点开邮件还是不被标已读。这两个都是历史欠账，这一轮一次性了断。

#### 改名 row1 → MuseType / 若一智能助手 → 妙打

不是 Debug / Release 差异，是 5 个 `Localizable.strings` 里英文 / 简体中文 / 日文的 `app.name` 还停留在旧名字（ko / yue 早就改成 `妙打` 了）。[`AppDelegate.setWindowTitle()`](fastv/fastvApp.swift:478) 把所有 NSWindow.title 设成 `NSLocalizedString("app.name")`，英文系统下窗体就被刷成「row1」。`pbxproj` 里 `INFOPLIST_KEY_CFBundleDisplayName` 也还是「若一智能助手」，菜单栏 / Dock 同步漂着。

- **5 个 `Localizable.strings` 全口径替换**（app.name + onboarding.welcome + welcome.title + 三段权限引导文案，共 6 处/语种）：
  - en: `row1` → `MuseType`
  - zh-Hans: `若一智能助手` → `妙打`
  - ja: `智響（ちきょう / Chikyō）` → `妙打`
  - ko / yue: 已是 `妙打`，不动
- **5 个 `InfoPlist.strings` 的 `CFBundleDisplayName`** 全部对齐（en → MuseType；zh-Hans / ja / ko / yue → 妙打）。
- **[`project.pbxproj`](fastv.xcodeproj/project.pbxproj:568) 4 处**：`INFOPLIST_KEY_CFBundleDisplayName` + 三段 `NSAppleEventsUsageDescription` / `NSMicrophoneUsageDescription` / `NSRemindersFullAccessUsageDescription` 里的「若一智能助手」一次替成「妙打」。
- **`PRODUCT_NAME` 和 `PRODUCT_BUNDLE_IDENTIFIER` 故意不动**：改 `PRODUCT_NAME` 会换 `.app` 文件名、code-sign 路径；改 bundle id 会让用户已授权的辅助功能 / 麦克风 / 提醒事项权限全部失效，TCC 数据库会把应用当新装的。展示层全部跟着 `CFBundleDisplayName` 与 `app.name` 走，已经够。
- 验证：`xcodebuild` 后 `plutil -p row1.app/Contents/Info.plist | grep Display` → `CFBundleDisplayName => "妙打"` 实锤。

#### 邮件 markAsRead 改成乐观更新（点开真的会变已读）

rc7 只堵了本地虚拟文件夹这一支路，但 [ViewModel.markAsRead](fastv/ViewModels/EmailViewModel.swift:1860) 老逻辑还是服务端权威：
```
do { try await emailService.markAsRead(...) ; updated.isRead = true; updateMessage(updated) }
catch { errorMessage = ... }
```
只要 IMAP 因为任何原因（网络瞬断 / 文件夹名 modified-UTF-7 编码差异 / 服务端 LIMIT / 限流）抛错，`do/catch` 把异常吞了，**本地 `isRead=true` 写库这一行永远走不到**，UI 看上去就是「点了等 3 秒还是红点」。

改成本地优先 + 服务端 best-effort：
1. **先本地**：从 EmailStore 拿最新副本（保留正文缓存），把 `isRead=true` 写进 DB —— UI 立刻看到红点变灰。
2. **再服务端**：异步走 IMAP STORE \Seen；失败只 `print` 日志，**不撤销本地状态、不把异常塞进 errorMessage 横幅**。
3. **下次 sync 兜底**：[`EmailStore.addMessages:327`](fastv/Models/EmailStore.swift:327) 的 OR-merge 逻辑 `updated.isRead = message.isRead ? message.isRead : existing.isRead` 已经天然站在本地读态这边 —— 服务端真说未读时，OR 合并到 `existing=true`，本地读态不会回落。

## [1.4.3-rc8] - 2026-06-09

### 修復 & 增強（邮件签名编辑器三连：塞不下、点击没反应、样式不够好看）

用户反馈截图里签名编辑窗体内容溢出，必须滚动才能看到底部「保存」「设为默认」；可用变量芯片是死的，点击不会插入；样式不够丰富。

- **布局重构 — 把"塞不下"压成"清爽够用"**。[`EmailSignatureEditorView.swift`](fastv/Views/EmailSignature/EmailSignatureEditorView.swift) 整段重写：丢掉 `Form` 改 `ScrollView + VStack`，名称 / HTML / 默认 / 预览四个控件挤进两行；可用变量从两列 6 行的稀疏卡片换成 `LazyVGrid(adaptive: 130-200)` 的紧凑芯片（每行 4-5 个）；原本 4 行 footer 提示文案折叠到 `DisclosureGroup("变量替换规则")`，默认收起；TextEditor 高度 250 → `minHeight: 180, idealHeight: 220, maxHeight: 320` 自适应。窗体 `minHeight` 从 600 降到 520，正常显示器一屏装得下、低分屏也不爆。
- **变量芯片点击即插入光标位置**。引入 [`SignatureEditorController`](fastv/Views/EmailSignature/EmailSignatureEditorView.swift:18) + [`SignatureTextEditor`](fastv/Views/EmailSignature/EmailSignatureEditorView.swift:42) — NSViewRepresentable 包 NSTextView，controller 持弱引用 textView 暴露 `insert(_ fragment:)`。点击芯片走 `tv.shouldChangeText` → `replaceCharacters(in: selectedRange, with:)` → `didChangeText`，可走 Undo；光标自动推到插入末尾，并 `scrollRangeToVisible` 拉回可视区。NSTextView 尚未挂载时（视图首帧）兜底走 `content += token`。鼠标 hover 芯片显示 `help` 提示「点击把 {{name}} 插入光标位置 — 发件人显示名称」。
- **HTML 编辑用等宽字体**。`isHtml = true` 时 SignatureTextEditor 切到 `monospacedSystemFont(ofSize: 12)`，对齐邮件 HTML 标签视觉；纯文本切回 `systemFont(ofSize: 13)`。

### 新增（精致样式 ×6 — 内置签名样式从 11 套扩到 17 套）

[`EmailSignatureTemplates.swift`](fastv/Services/EmailSignatureTemplates.swift) 新增「精致样式」分组：

- **品牌卡片** (`brand_card`)：圆角浅灰底 + 品牌紫名称，产品 / 设计岗常用质感。
- **左色条** (`accent_bar`)：左侧 6px 红色圆角条 + 22px 大字号名片，名字一眼被看到。
- **暖色线条** (`warm_accent`)：橙红渐变 80px 下划线 + 斜体职位，文创 / 自由职业风。
- **渐变玻璃** (`gradient_glass`)：浅紫淡蓝 135° 渐变背景卡片 + 12px 圆角，现代轻盈。
- **蒙德里安** (`mondrian`)：蓝白色块分割 + 底部明黄条，强平面设计感。
- **黑白胶囊** (`mono_chip`)：黑白胶囊化芯片 (border-radius: 999px) 排版联系方式，极简高级。

[`SignatureTemplatePickerView`](fastv/Views/EmailSignature/SignatureTemplatePickerView.swift:23) 新增「精致样式」分类，左侧栏可直接点进去看缩略图预览。

## [1.4.3-rc7] - 2026-06-09

### 修復（本地「已发送(本地)」文件夹被无差别走 IMAP，触发 NON_EXISTANT_FOLDER 错码 33）

截图里反复出现的 `[LibEtPan] 选择文件夹失败：已发送(本地)，错误代码：33` + `[EmailService] 断开 IMAP 连接 (syncMessages)` + `nw_socket_handle_socket_event ... Connection reset by peer` + `[EmailViewModel] 后台同步失败：已发送(本地) - connectionFailed("选择文件夹失败...")`，根因是后台同步循环把**所有**文件夹喂给 `imap.selectFolder`，但「已发送(本地)」(`path = "__LocalSent__"`) 是个仅存在于本地数据库的虚拟文件夹，用来兜 SMTP 发出的本机副本——服务端根本没这个 mailbox，libetpan 立刻回 NON_EXISTANT_FOLDER。同条链路下，用户点开本地已发送邮件后，3 秒延迟标已读触发 `markAsRead` → `imap.selectFolder` → 同样炸 33 → ViewModel 的 `do { try await emailService.markAsRead(...) } catch { ... }` 把异常吞到 `catch`，**第 1886 行 `updated.isRead = true` 永远跑不到**，UI 一直显示未读。

- **[`EmailFolder`](fastv/Models/EmailFolder.swift:91) 新增 `isLocal` 计算属性**：以稳定 key `path == kLocalSentFolderPath` 判定，不走可被国际化的 `name`。
- **`EmailService` 所有 IMAP 入口对本地文件夹短路**：
  - [`syncMessages`](fastv/Services/EmailService.swift:298) 直接返回 `[]`（后台同步循环跳过它）。
  - [`markAsRead`](fastv/Services/EmailService.swift:833) 直接 `return`（让 ViewModel 继续完成本地 isRead 写库）。
  - [`deleteMessage`](fastv/Services/EmailService.swift:867) / [`toggleStar`](fastv/Services/EmailService.swift:903) 直接 `return`，本地删/星标交给 `EmailStore`。
  - [`moveMessage`](fastv/Services/EmailService.swift:1068) 源端或目标端任一为本地时跳过 IMAP COPY/EXPUNGE。
  - [`fetchMessageBody`](fastv/Services/EmailService.swift:542) / [`fetchRawMessage`](fastv/Services/EmailService.swift:649) / [`downloadAttachment`](fastv/Services/EmailService.swift:975) 抛 `invalidConfiguration("本地文件夹的邮件没有服务端...可拉取")`，提示明确而不是挂死 / 撞 33。
  - [`searchMessages`](fastv/Services/EmailService.swift:696) 返回 `[]`（关键词过滤交给本地）。
- **[`EmailViewModel.startBackgroundSyncTask`](fastv/ViewModels/EmailViewModel.swift:479) 循环顶部加 `if folder.isLocal { continue }`**：在进入 `loadMessages` / `syncMessages` 之前就过滤掉本地文件夹，省一次 IMAP 建连、把日志噪音压下去。Service 层的兜底仍然保留，是双保险。

效果：截图里那一坨 LibEtPan + nw_socket 反复刷的告警归零；点开本地已发送邮件后 3 秒会被正确标已读（IMAP no-op，本地 DB 落 `isRead = true`）。

## [1.4.3-rc6] - 2026-06-09

### 修復（QoS 优先级反转告警）

Xcode runtime 反复刷 `mailstream_cfstream.c:912 [Internal] Thread running at User-initiated quality-of-service class waiting on a lower QoS thread running at Default quality-of-service class.` —— libetpan 的 CFStream 同步等 runloop，而 runloop 跑在 Default QoS 线程上；我们却把 IMAP/SMTP 工作线程钉到了 UserInitiated，于是高优先级线程等低优先级线程，OS 抛优先级反转告警。

- **降级 IMAP/SMTP 工作线程的 QoS 到 Utility**。[`LibEtPanWrapper.m:25`](fastv/Services/LibEtPanWrapper.m:25) 的 `ensureUserInitiatedQoS` 函数体由 `QOS_CLASS_USER_INITIATED` 改为 `QOS_CLASS_UTILITY`（函数名保留，所有 23 个调用点不必动）。
- **EmailService.swift 中 16 处 `Task.detached(priority: .userInitiated)` 全部降到 `.utility`**：fetchFolders / syncMessages / fetchMessageBody / fetchRawMessage / searchMessages / fetchFolders / markAsRead / deleteMessage / toggleStar / downloadAttachment（两路）/ moveMessage / SMTP createSession / SMTP sendMessage 等全部统一。已是 `.background` 的 [`scheduleBackgroundSync`](fastv/Services/EmailService.swift:441) 保持不动。
- 按 Apple QoS 指南，邮件 I/O 这种"用户能感知但不会盯着看"的后台任务本来就该是 utility；userInitiated 留给真正的"用户点了某个按钮、必须立刻给反馈"的同步任务。优化后 IMAP 取信、SMTP 发信的体感延迟没有变化（瓶颈是网络往返），但 Console 不再被告警刷屏，CFStream runloop 与调用线程 QoS 对齐。

## [1.4.3-rc5] - 2026-06-09

### 修復（邮件正文「找不到文件夹」死胡同）

rc4 把找不到 folder 的 case 从「无声卡 loading」改成了「显示失败 + 重试按钮」，但点重试只是再走一次 `loadMessageBody`，对真正悬挂的 `folder_id` 没用——失败提示让用户"刷新文件夹列表"，按钮却没刷新，文案和行为对不齐。这一轮把两个口子一并补了：

- **重试按钮顺手刷新文件夹列表**。[`retryLoadMessageBody`](fastv/ViewModels/EmailViewModel.swift:1611) 在调用 `loadMessageBody` 之前先 `await loadFolders(account:, backgroundRefresh: true)`，让按钮实际行为对上提示文案。覆盖"本地 folder 缓存还没拉到"这类时序问题，用户不必再手动去侧栏找刷新入口。
- **同 accountId、同 messageId 的副本救援**。Gmail / 企业邮箱常见同一封邮件在 INBOX + `[Gmail]/All Mail` 各一份；若用户当前点开的这份 `folder_id` 已被 SQLite `ON DELETE SET NULL` 清空（[EmailDatabase.swift:119](fastv/Services/EmailDatabase.swift:119)），但另一份还在有效文件夹里、且已缓存了正文，[`loadMessageBody`](fastv/ViewModels/EmailViewModel.swift:1702) 现在会在 folder 解析失败之后扫一遍 `EmailStore.messages` 找同 messageId 副本，借用其 `textBody` / `htmlBody` / `attachments` / `containsRemoteResources` 字段直接渲染——不必发起 IMAP 请求，也不必依赖再次同步修复 orphan 状态。
  - 副本的 `folderId` 故意**不抄**，保留原 row 的 orphan 状态。下一次正常 sync 会自然把 `folder_id` 重新落对，避免在这里硬塞一个可能不准的 folder。
  - 只在同 `accountId` 范围内匹配，避免误把别人账号的同 messageId 邮件正文塞过来。

### 未触及（已纳入后续计划）

- 在 `email_messages` 表上加冗余 `folder_path` 列，让 folder_id 悬挂时能按 path 反查（需要 schema 迁移，单独排）。
- `EmailStore.addFolder` 对 IMAP modified UTF-7 / 大小写差异的 path 归一化（重写去重逻辑，单独排）。

## [1.4.3-rc4] - 2026-06-09

### 修復
- 邮件正文「正在加载正文...」永远转圈的 bug。两条独立的卡死路径都堵掉：
  1. **「所有邮件」聚合视图下找不到 folder 静默 return**。聚合查询用 `MIN(id)` picked 出来的那条 row，其 `folderId` 可能指向 ViewModel.folders 缓存里还没有的文件夹（跨账号副本 / 启动竞态 / 空文件夹分组）。原来直接 `return` 不写状态，UI 永远停在 loading。现改为：先去 `EmailStore.accounts` 全量文件夹兜底再找一遍；找不到才把失败信息写入 `bodyLoadFailures`，让 UI 显示失败 + 重试按钮。
  2. **`fetchMessageBody` 无超时控制**。每次现抓正文都新建一条 IMAP 连接（connect+login+select+fetch+disconnect），全程交给 LibEtPan 阻塞 socket；网络慢 / 服务端限流时，await 会一直挂着。现用 `withThrowingTaskGroup` 套 45s 超时，超时抛 `EmailServiceError.timedOut`。LibEtPan socket 不能真正 cancel，但 ViewModel 这一侧能提前拿到错误把 UI 切到「加载失败 → 重试」。
- 新增 [`EmailViewModel.bodyLoadFailures`](fastv/ViewModels/EmailViewModel.swift:84) + [`retryLoadMessageBody`](fastv/ViewModels/EmailViewModel.swift:1607)：每封邮件一个独立失败态，不再吞到全局 `errorMessage` 横幅里遮住正文区。
- [`EmailView`](fastv/Views/EmailView.swift:749) 的「正在加载正文...」区块改造为：失败时显示橙色三角 + 错误原因 + 「重试」按钮，点击直接重跑 `loadMessageBody`。

## [1.4.3-rc3] - 2026-06-06

### 修復
- 邮件翻译把 CSS 当正文翻译的 bug：用户点"翻译为中文"后，正文区出现 "body {width: 600px;margin: 0 auto;}" / "table {border-collapse: collapse;}" 一大段 CSS。根因是 `stripHTMLTagsForTranslate` 只剥 `<tag>` 本身，**`<style>` / `<script>` 标签之间的内容文本被原样留下喂给 AI**。
- 修复 [`stripHTMLTagsForTranslate`](fastv/ViewModels/EmailViewModel+Translate.swift:240)：先把 `<style>...</style>`、`<script>...</script>`、`<head>...</head>`、`<noscript>...</noscript>`、HTML 注释、`<!DOCTYPE>`、`<?xml?>`、Outlook 条件注释 整段（含内容）一并删掉，再剥剩余标签。
- 顺手加固：数字字符引用 `&#1234;` / `&#x4e2d;` 还原为 Unicode 字符；多余空格压缩；每行首尾 trim；`</tr>`/`</h5>`/`</h6>` 也算块级换行。

### 测试
- 新增 [`fastvTests/EmailTranslateStripTests.swift`](fastvTests/EmailTranslateStripTests.swift)：14 个用例覆盖 `<style>` / `<script>` / `<head>` / 注释 / DOCTYPE / `<noscript>` / 数字字符引用 / 段落保留 / 空白压缩。**14/14 全过**。
- 全套测试 36 → 50，TEST SUCCEEDED。

## [1.4.3-rc2] - 2026-06-06

### 修復（隱私拦截覆盖扩展 — 之前的正则只挡了 60% 场景）

自查时给 stripRemoteImageSources 写单测，**第一次跑 13/21 失败**，逼出一堆之前没覆盖到的远程加载点位。这一轮全部补齐：

- **`<img>` 兼容性**：无引号 `<img src=http://x>` 之前漏过；现在多走一条无引号正则。大小写不敏感、单引号、双引号、protocol-relative `//` 全部覆盖。
- **`<picture><source srcset>`**：响应式图片在主流邮件客户端越来越常见，之前完全漏过。
- **`<input type="image" src=...>`**：会发 GET 请求，常用于追踪点击 / 表单内嵌追踪。
- **`<video poster>`**：海报图同样外链请求。
- **`<iframe src>` / `<embed src>` / `<object data>`**：极少邮件用但能加载整个外部文档，必须挡。
- **`<link rel="stylesheet" href=...>`**：远程 CSS 会被 WebKit 加载，且 CSS 内可链 url() 触发二次跟踪。
- **inline `background:url(...)` 短写法**：之前只挡 `background-image:url(...)`，newsletter 用 `background:url(http://t.com/pixel.gif)` 这种短写法整一片。
- **`<style>` 标签内 `@import url(http://...)` 与 `url(http://...)`**：用单独的标签内正则替换为 `url(about:blank)` / `/* fastv-blocked @import */`，CSS 引擎不再发请求。
- **早退**：HTML 里没有 `http` 或 `//` 时直接返回原文，大邮件不白跑 8 个正则。

### 测试
- 新增 [`fastvTests/EmailRemoteImageBlockingTests.swift`](fastvTests/EmailRemoteImageBlockingTests.swift)：21 个用例覆盖上述所有挡 / 不挡场景，断言用"是否还有 live remote request 形态"的正则判定，避免误把 `data-original-src="http..."` 误判为漏挡。**21/21 全过**。
- 一次跑 36 个测试（fastvTests + MeetingRichDocTests + EmailRemoteImageBlockingTests），TEST SUCCEEDED。

### 修復（延迟标读 / IDLE 状态边界）

- `EmailViewModel.selectAccount` 切账号时也取消 `pendingMarkAsReadTask`，防止切走后用旧账号 ID 把邮件标读（之前只在 selectFolder 里做了取消）。
- `EmailIdleService.stop(accountId:)` 把 `statuses[accountId]` 一并清掉 + 广播一次 `.stopped`，让 `EmailViewModel.idleStatusByAccount` 同步去除已删账号的徽章残留。

## [1.4.3-rc1] - 2026-06-06

### 新增（隐私加固）

- **延迟标已读**：邮箱设置新增"自动标已读"选项，默认 **3 秒** 后才标已读。期间换邮件 / 切文件夹会自动取消上一个延迟任务，避免键盘上下浏览时一路把整封收件箱误标读。可选档位：立即 / 1 / 3 / 5 / 10 秒 / 仅手动。
  - 旧行为（选中即标）仍可选（"立即"档），UI 会标出"⚠️ 服务器 `\\Seen` 标志会同步更新，无法撤销"提醒。
  - "仅手动"档位下，邮件永远不会被自动标已读，需要用户主动操作。
  - 实现：`UserPreferences.emailMarkAsReadDelaySeconds` 默认 3；`EmailViewModel.selectMessage` 把原来的 `Task { await markAsRead }` 换成可取消的 `pendingMarkAsReadTask`，回调里二次确认 `selectedMessageId == target.id` 才真的标。

- **真正挡远程图片 + 追踪像素**：之前的实现只是 CSS `img { display: none }`，WebKit 仍会发起 HTTP 请求 → newsletter / marketing 邮件里的 1x1 透明 gif 追踪像素照样能让发件人拿到 IP + UA + 打开时间。
  - 现在在 `EmailBodyWebView.injectEmailStyles` 注入前，先把外链 `<img src="http(s)://…">` / `srcset` 改名为 `data-original-src` / `data-original-srcset`；同时清掉 inline `style` 里的 `background-image: url(http…)`。WebKit 看到没有 src 的 `<img>` 就根本不发请求。
  - 内嵌 `cid:` 与 `data:image/…` 图保留不动（不会触发外链）。
  - CSS 给"有 data-original-src 的图"加占位框："🖼 图片已被隐私保护挡住"；尺寸为 1x1 / 0x0 的（标准追踪像素特征）直接 `display: none`，连占位框都没有。
  - 用户点"显示图片"切换后，HTML 会被重新注入，这次 src/srcset 不再被剥，图片正常加载。

## [1.4.2-rc4] - 2026-06-06

### 修復
- 「所有郵件」視圖列表開機幾秒後突然只剩 2 封：根因是 aggregator 完全依賴 `EmailStore.messages` 內存 dict，而 IMAP 同步 / IDLE 推送 / `loadMessages` 的 early-return + 整體替換行為，會在啟動後幾秒讓 `messages[folderId]` 變回"只有最近一封"的瞬間狀態，aggregator 跑時就算出 2 封。
- 新增 [`EmailStore.fetchAggregateMessagesFromDatabase(accountId:limit:)`](fastv/Models/EmailStore.swift:712)：用一條 SQL 從 `email_messages` 表按 `message_id` 去重直接撈出最近 N 封（與側欄 `getTotalMessageCountAsync` 同源），不再依賴內存。
- [`EmailViewModel.updateMessagesForAllFolders`](fastv/ViewModels/EmailViewModel.swift:694) 現在走 DB 直查路徑：列表 = 側欄數字 = DB 數據源同一份，IMAP 同步 / IDLE / 後台任務怎麼折騰內存 dict 都不會再讓列表變短。
- 順便：`showAllMessages` 不再預先調 `loadAllFoldersForAggregateView`（rc3 引入但已不必要），減少啟動時的並發 DB 讀。

## [1.4.2-rc3] - 2026-06-05

### 修復
- 郵箱「所有郵件」視圖計數 14 但只列出 2 條的不一致：之前 `showAllMessages` 只 aggregator `emailStore.messages[folderId]` 內存 dict，沒主動把賬號下其它文件夾從數據庫加載到內存，於是側欄按 DB 全量去重 = 14、列表按已加載文件夾合併 = 2。
- 新增 `EmailStore.loadAllFoldersForAggregateView(accountId:)`：並發加載當前賬號所有非 spam/trash/drafts 的文件夾（並發度 4，內部 early return 跳過已緩存）。`showAllMessages` 先確保所有 folder 都進內存再 aggregator，計數和列表終於對得上。
- 副作用紅利：每個 folder 的 `loadMessages` 會順帶刷新 `FolderMessageCountCache`，所以"INBOX 2"那種小數字若 DB 裡其實是 4 / 5，也會在切到「所有郵件」後自動修正。

### 細節
- 主菜單側邊欄 tab（語音輸入 / 會議記錄 / Todo / AI Chat / 郵箱）的 icon 左 padding 從 6 拉到 14，紫色選中竪條（leading 4 + 寬 3）與 icon 之間留出 ~7pt 視覺呼吸感，避免兩者貼在一起。HStack 內部 icon-text 間距同步從 8 微調到 10。

## [1.4.2-rc2] - 2026-06-05

### 修復（IDLE 並發 / 安全）
- IDLE 取消路徑現在會先發 `DONE` 再 `disconnect`，避免服務器把連接半掛到 ~29 分鐘超時、SSL 不優雅關閉招風控（rc1 引入的問題）。
- `EmailIdleService.onNewMessage` 從 `nonisolated(unsafe) var` 閉包改為 `NotificationCenter` 通知。修復跨 actor 數據競爭，並讓未來多 ViewModel / 多窗口都能各自訂閱，互不覆蓋。
- 服務器不支持 IDLE 時 `runLoop` 直接停止 + 標記 `.unsupported`，不再每 10-15 分鐘反復 connect / login 招風控。重連退避上限收緊到 6 次（5 → 320s，封頂 300s）。
- `EmailIdleService.IdleStatus` 暴露 5 種狀態（idle / connecting / reconnecting / unsupported / stopped），通過 `EmailViewModel.idleStatusByAccount` 公開給 UI。`EmailViewModel.deinit` 也補上 NotificationCenter 觀察者移除，避免長生命週期 retain cycle。

### 修復（spam / archive 一致性）
- `EmailStore.moveMessageInMemory` 新增 `mutate` 閉包參數：`markAsSpam` / `restoreFromSpam` 現在在**一次**寫庫裡完成跨文件夾移動 + `isSpam` 翻轉，進程被殺也不會留下"已挪文件夾但 isSpam 未變"的中間狀態。
- 跨文件夾移動不再把 `uid` 置 nil（保留舊 UID）：移動後 30 秒內用戶再對該郵件做 `toggleStar` / `markAsRead` 不會莫名其妙報"UID 不存在"。
- `moveMessageInMemory` 在改完 dict 後額外 `objectWillChange.send()`，確保訂閱 messages 全集的"所有郵件視圖"立即重排。

### 修復（附件 / MIME 解析）
- `parseAttachments` / `parseMultipart` 統一通過新 helper `splitMultipartSegments` 切分，**跳過 boundary 之前的 preamble 與 closing 之後的 epilogue**，避免郵件以 "This is a MIME message..." 開頭時 partPath 整體偏 1、`BODY[2]` 抓到 part 1。
- 子 part 拆 header/body 時兼容 `\n\n` 與 `\r\n\r\n` 雙分隔。
- `decodePartBytes`：encoding 比對前 trim + lowercase，base64 / quoted-printable 解碼字節流時 ASCII 解不出來自動降級到 `isoLatin1`（base64 子集兼容）；空 data / 未知 encoding 安全回退原數據；未知 encoding 打一條 warning 日誌。
- `makeAttachmentFileURL` 文件名安全策略升級：取最後一個路徑分量 → 替換控制字符 / 文件系統保留符（`:"?*<>|`）為 `_` → 拒絕以 `.` 開頭 → utf-8 長度封頂 240 字節 + UUID 前綴，挡 `../`、隱藏文件、超長文件名等異常輸入。
- 超大郵件正文截斷時（>10MB），`parseAttachments` 仍走**全量** data 掃描，避免附件元信息丟失。

### 新增（界面酷炫）
- 郵件詳情頂部 hero header 重做：發件人郵箱稳定 hash 出主題色，配 `LinearGradient + ultraThinMaterial` 玻璃質感卡片；頭像帶白邊陰影；主題下方 chip 行展示星標 / 未讀 / 已回復 / 重要 / 緊急 / 含附件等狀態徽章。
- 郵件列表行重做：選中時左側 accent 竖條 + 卡片底色；未讀時細竖條 + 蓝點角標 + 極淡 accent 底；hover 加柔和灰底；星標小角標貼在頭像右下；AI 摘要前綴 `sparkles` 圖標；附件 / 優先級 chip 角標。
- 工具欄新增 `IdleStatusBadge`：8pt 小圓點 + 呼吸光暈動畫表達 IDLE 連接狀態。綠色 = 在 IDLE / 藍 = 建連 / 橙 = 重連 / 灰 = 不支持 / 灰白 = 未啟用，hover 出 tooltip 文案。

## [1.4.2-rc1] - 2026-06-05

### 新增（IMAP IDLE push）
- 郵件：新增 `EmailIdleService`，為默認啟用的賬號 INBOX 維持一條獨立的 IMAP IDLE 長連接。服務器有新郵件到達（untagged EXISTS）時，立即喚醒 `EmailViewModel.handleIdleNotification` 拉一次收件箱，無需依賴定時輪詢。
- 細節：每 25 分鐘自動 `idle_done` → `idle` 續期；poll 粒度 1 秒便於響應 Task 取消；異常按指數退避重連（封頂 5 分鐘）；單賬號最多一條 IDLE Task，切賬號 / 刪賬號 / `applicationWillTerminate` 都會清理。
- 服務器不支持 IDLE 時靜默跳過，不打擾用戶。
- ViewModel 端 30 秒節流，避免 EXISTS 抖動連續刷 INBOX。
- `LibEtPanIMAPSession` 對應暴露 `hasIdleCapability` / `idleWithError:` / `idleDoneWithError:` / `idleFd` / `noopWithError:` 五個方法。

### 新增（附件按 MIME part 真實下載）
- 解析正文時順帶掃描 MIME 結構，把附件的 IMAP body section path（`"2"` / `"1.2"`）、`Content-Transfer-Encoding`、`charset`、`filename`、`Content-ID` 寫進 `EmailMessage.attachments`。
- `EmailService.downloadAttachment` 改用 `BODY.PEEK[<partPath>]` 只抓目標 part 的字節，再按 base64 / quoted-printable 解碼後寫入臨時目錄；不再取整封郵件再切附件。
- 老附件無 partPath 時退回"拉全文 + filename 匹配"路徑兜底，保證歷史郵件可下載。
- 文件名做安全處理（去掉 `/\\`，前置 UUID 前綴防覆蓋）。
- `LibEtPanIMAPSession` 新增 `fetchMessagePartWithUID:partPath:`；`EmailContentDecoder` 新增 `parseAttachments` 與 `decodePartBytes`。
- DB schema 升級：`email_attachments` 表新增 `part_path` / `encoding` / `charset` 三列，自動 migrate。

### 改進
- 郵件移動 / 歸檔 / 標記垃圾 / 取消垃圾 後立即從源文件夾的內存與 store 中移除該郵件，並寫入目標文件夾；不再依賴下次同步刷新源文件夾。
- 新增 `EmailStore.moveMessageInMemory(_:from:to:)`，跨文件夾移動內存 dict + DB row 一次完成；自動刷新側欄 `FolderMessageCountCache`。
- `EmailViewModel.markAsSpam` / `restoreFromSpam` 改為先 IMAP 操作、再 `moveMessageInMemory` 跨文件夾挪 + 翻轉 isSpam 落盤，避免之前"標記成功但邮件仍躺在原 inbox 列表"的視覺 bug。

## [1.4.1-rc1] - 2026-06-05

### 新增（IMAP 真實現）
- 郵件：`EmailService.toggleStar` / `deleteMessage` / `moveMessage` 從原來的"本地佔位"切到真實 IMAP 命令：分別走 `UID STORE +/-FLAGS (\Flagged)`、`UID STORE +FLAGS (\Deleted) + EXPUNGE`、`UID COPY → STORE +FLAGS (\Deleted) → EXPUNGE`。源/目標相同的 move 自動短路為 no-op，避免誤刪。
- `LibEtPanIMAPSession` 對應新增 `markAsUnreadWithUID:` / `addFlaggedWithUID:` / `removeFlaggedWithUID:` / `deleteAndExpungeWithUID:` / `moveMessageWithUID:toFolder:` 五個能力，並通用化為內部 `storeFlagWithUID:flag:sign:action:error:` helper。目標文件夾名稱包含中文時自動 Modified UTF-7 編碼。

### 改進
- `EmailViewModel.toggleStar` 改為"服務端先行"：先讓 IMAP 翻轉 `\Flagged` 成功，再翻轉本地並落盤，避免乐观更新與服務端不一致。
- 邮件搜索任务：新增 `searchGeneration` 序列号。用户连打字时，旧 task 即使在网络层完成也不再覆盖最新的 `searchResults`。
- 邮件加载任务：`loadMessagesAsync` 入口快照 `loadGeneration + selectedAccountId + selectedFolderId`，结果回写 UI 前校验三者一致；切账号/文件夹后旧任务的数据库写入照常落盘，但不再覆盖新文件夹的 UI。
- 超大邮件正文保护：`EmailService.fetchMessageBody` 新增 `maxBodyBytes = 10MB` 阈值，超阈值时只解析前 10MB；`EmailBodyContent` 新增 `wasTruncated` / `originalSize` 字段。邮件详情页通过新的 `truncatedBodyBanner` 提示"正文过长，已截断显示"，并指引用户用「保存为 .eml」导出原件。

### 架構
- 拆分 `EmailViewModel.swift`（從 3302 行 → 2443 行，脫離 CLAUDE.md 的 3000 行紅線）：
  - 新增 `EmailViewModel+AIPolish.swift`（160 行）：`aiPolishComposeDraft` / `aiPolishReplyDraft`。
  - 新增 `EmailViewModel+Translate.swift`（258 行）：AI HTML 排版優化、邮件正文翻译、正文截断 banner helpers、`stripHTMLTagsForTranslate`。
  - 新增 `EmailViewModel+Compose.swift`（566 行）：初始化回复 / 撰写草稿、附件管理、`sendCompose` / `sendReply` 與兩個發送便利方法、"已發送(本地)"保存、發送系統通知、`splitReplyBody`。
  - 主 `EmailViewModel.swift` 內幾個 `private let` 依賴（emailStore/emailService/emailAIService 等）以及 `optimizationTasks` / `translationTasks` 改为 internal，以便同模块 extension 文件访问；不影响外部 API。

## [1.4.0-rc4] - 2026-06-05

### 修復
- 郵件後台同步：修復 `EmailService.backgroundSyncTasks` 字典在 `scheduleBackgroundSync` / `cancelBackgroundSync` / `cleanupAllSessions` 三個調用點仍然裸讀裸寫的問題（上一版本已加 NSLock 但調用點沒有走鎖封裝），多賬號 / 多文件夾並發同步可能崩潰或泄漏 Task 句柄。現在所有訪問統一走 `setBackgroundSyncTask` / `cancelBackgroundSyncTask` / `snapshotBackgroundSyncAccountIds` 三個帶鎖 helper。
- 郵件賬號刪除：`EmailStore.deleteAccount` 現在會先調用 `EmailService.cleanupAccount` 取消該賬號的後台同步 Task，避免賬號刪除後仍有後台任務嘗試訪問已刪除賬號的數據庫行。
- 郵件 AI 翻譯 / HTML 排版優化：用戶取消後再讓網絡請求返回時，不再覆寫 `optimizedHTMLCache` / `translatedBodyCache`，並把 `CancellationError` / `NSURLErrorCancelled` 識別為取消而非"翻譯失敗"提示，避免一閃而過的紅色錯誤條。

### 隱私
- `EmailService.sendMessage` 不再在 stdout 打印收件人 / 抄送 / 密送 / 主題 / 附件文件名等明文敏感信息，只輸出條數和長度等指標；`EmailViewModel` 邮件正文合並日志也改為僅輸出 id + 字符數，避免 log 抓取即泄密。

## [1.4.0-rc3] - 2026-06-03

### 新增
- 郵件：詳情頁工具欄新增「AI 翻譯為中文」按鈕（`character.bubble`）。點擊把正文翻譯成中文並以譯文視圖展示，再次點擊或頂部「顯示原文」可切回原文；同一封郵件的翻譯結果按 message.id 緩存，避免重複調用。
- 翻譯 prompt 嚴格要求**只譯不改寫**、保留原段落結構、URL/郵箱/代碼/專有名詞不翻譯；走現有 `.aiChat` 場景配置。

### 文檔
- 新增 `docs/code-review-2026-06.md`：三路 review agent 對 fastv 倉庫的 P0/P1/P2 體檢報告（含已修復項與待辦項）。

### 清理
- 刪除 `DiaryAIService.swift`、`DiarizationServiceManager.swift`、`AppStateManager` 空殼單例、`ChatAIService.sendMessageLegacy`、`OllamaService.testOptimizationLegacy` 共 5 處死代碼；同時刪除 `AIScenario` 中 4 個零引用枚舉值（videoAnalysis/diaryAnalysis/expenseParsing/intelGeneration）與 3 個 `.backup` 殘留文件。
- `UserPreferences.aiScenarioBindings` 解碼改為「逐項容錯」：單條 binding 損壞不再導致整數組丟失。

## [1.4.0-rc2] - 2026-06-03

### 修復
- 設置：頂部工具欄的齒輪設置按鈕不再參與 Tab 焦點，避免出現紫色虛線聚焦圈影響觀感。

## [1.4.0-rc1] - 2026-06-03

### 新增
- 會議記錄：新增「實時圖文文檔」面板。錄音同時 AI 流式生成結構化 Markdown，自動提煉小節、要點列表、表格、勾選框行動項，並能輸出 mermaid 思維導圖 / 流程圖。觸發策略為段落驅動 + 停頓節流（默認累計 200 字或停頓 12 秒）。
- AI 設置：新增「會議轉寫修訂」與「會議圖文文檔」兩個獨立場景，可分別綁定不同 Provider / Model / Timeout（推薦：轉寫修訂用輕量本地模型，圖文文檔用更強的雲端模型）。
- Markdown 渲染：新增 ```mermaid 代碼塊識別與渲染，支持思維導圖、流程圖、序列圖。

### 改進
- `AIServiceAdapter` 統一新增流式（SSE）能力，覆蓋 OpenAI 兼容 / DashScope / Claude / Gemini / Ollama；`ChatAIService.sendMessageStream` 提供 `AsyncThrowingStream<String, Error>` 統一接口。
- 會議記錄詳情頁改為「圖文文檔 / 全文 / AI 整理」三 Tab，避免長頁面信息擠壓。

### 版本
- 同步 macOS app、測試 target 與 STT API 版本到 `1.4.0-rc1`。

## [1.3.0-rc6] - 2026-05-25

### 改進
- 語音輸入：按下快捷鍵時立即預熱語音識別模型，讓模型加載與用戶說話時間重疊，降低鬆手後首次識別等待。
- 語音輸入：降低非藍牙麥克風錄音 tap 緩衝時長，提升拾音、波形與停頓檢測響應速度；藍牙設備保留更大的穩定性緩衝。
- 語音轉寫：進程內復用 SenseVoice token 映射，避免每次識別重讀 `tokens.json`。

### 版本
- 同步 macOS app、測試 target 與 STT API 版本到 `1.3.0-rc6`。

## [1.3.0-rc5] - 2026-05-24

### 修復
- 測試穩定性：在 XCTest 宿主環境跳過啟動時 ONNX 語音模型預加載，避免單元測試結束時後台 `CreateSession` 與 XCTest 退出析構競態導致 macOS 誤報崩潰。
- 長期運行：為語音模型啟動預加載增加防重入保護，避免重複觸發多個後台加載任務。

## [1.3.0-rc4] - 2026-05-24

### 修復
- 長期運行：修復內存監控閾值單位判斷錯誤，避免 100MB 級別內存使用被誤報為 6GB 危險狀態。
- 長期運行：調整內存監控定時器與持久化邏輯，減少 MainActor 狀態在後台隊列被直接讀取的並發風險。
- 長期運行：清理窗口委託方法與啟動窗口標題監聽中的編譯警告，降低後續 Swift 版本升級風險。
- 工程配置：同步 app、單元測試與 UI 測試 target 版本號到 `1.3.0-rc4`，並修正 UI 測試目標名為 `row1`。

## [1.3.0-rc3] - 2026-05-24

### 改進
- 測試工程：新增共享 `row1` scheme 與 `row1.xctestplan`，默認只運行 `fastvTests`，避免命令行/CI 被未配置完整的 UI 測試目標阻塞。
- 测试工程：新增 `scripts/run_unit_tests.sh`，在同一个 DerivedData 下先构建 CocoaPods 的 GRDB 与 `Pods-row1`，再执行 `row1` 单元测试，减少命令行/CI 对本机缓存和 workspace 状态的依赖。
- 测试工程：补齐 `fastvTests` 的 test host、模块导入、搜索路径与版本配置，确保命令行测试能解析 `row1`、GRDB 与 ONNX 依赖。

## [1.3.0-rc2] - 2026-05-24

### 改進
- 語音輸入：將最近一句識別與文本替換邏輯抽為純文本分析器，便於單元測試與後續維護。
- 隱私：語音輸入、文本插入與 AI 優化相關日志不再輸出用戶輸入/剪貼板文本片段，改為輸出長度與狀態信息。

### 測試
- 補充語音回改核心規則單元測試，覆蓋中文標點、換行、emoji UTF-16 邊界、文本替換與回改指令識別。

## [1.3.0-rc1] - 2026-05-24

### 新增
- 語音輸入：新增 AI 上下文回改能力。使用 AI 快捷鍵說出「修改上一句」「潤色這句」「重寫」等指令時，會讀取當前輸入框內容，優先回改選中文本，否則只回改游標前最近一句。
- 設置：新增「AI 回改最近一句」開關，可控制上下文回改能力。

### 改進
- 語音輸入：最近一句截取支持中文/英文標點與換行邊界，降低誤改整段 text input / textarea 的風險。
- 語音輸入：直接鍵盤輸入相關設置改為多語言文案。

## [1.2.9-rc1] - 2026-03-01

### 新增
- 會議記錄：錄音時顯示波形懸浮窗，直觀確認正在拾音

### 修復
- 主菜單：用 HSplitView 替代 NavigationSplitView，側邊欄固定不折疊，解決 macOS 狀態恢復導致菜單消失的問題
- 會議記錄：修復短於 15 秒錄音內容全部丟失的問題（停止時對完整音頻做轉寫）

### 改進
- 會議記錄：頁面佈局重構，左側錄音控制+記錄列表，右側詳情，UI 更清晰
- 主菜單：側邊欄選中樣式優化，左側豎條+淡背景，去除焦點環

## [1.2.8-rc1] - 2026-02-25

### 修復
- 語音轉寫：修復智能分段動態規劃在恰好 3 段時 `Range requires lowerBound <= upperBound` 崩潰問題

## [1.2.8] - 2026-02-25

### 新增
- AI Chat：支持在聊天中切换 Provider（服务商），可同时选择 Provider 和 Model
- AI Chat：新增智谱 AI、MiniMax（国内/国际）到默认 Provider 列表
- AI Chat：多 Provider 下的图片/附件支持（DashScope qwen-vl、智谱 glm-4v、OpenAI gpt-4o 等）

### 改進
- AI Chat：Provider 与 Model 双选择器，切换 Provider 时自动加载对应模型列表
- AI Chat：图片/附件支持按 Provider 和模型动态判断（支持视觉的模型可上传图片）

## [1.2.7] - 2026-02-16

### 修復
- AI 服務：修復 DashScope（Qwen）等雲端 API 因超時設置不足導致「請求超時」的問題
- AI 服務：根據協議類型自動設置合理的默認超時（本地 5 秒，雲端 API 60 秒）

### 改進
- AI 服務：超時設置滑塊範圍從 2~60 秒擴展為 2~180 秒，支持長對話和複雜任務
- AI 服務：切換協議類型時自動更新推薦超時值
- AI 服務：超時滑塊下方新增雲端 API 推薦提示

## [1.2.6] - 2026-02-16

### 新增
- AI Chat：AI 回復下方新增「重新生成」按鈕（hover 顯示），點擊可讓 AI 重新生成回復
- AI Chat：發送失敗的消息旁感嘆號可點擊，觸發重試發送（避免重複消息）
- AI 服務：新增 OpenRouter 協議類型，支持 OpenRouter 等中轉站
- AI 服務：自定義協議類型更名為「自定義（中轉站）」，支持任意 OpenAI 兼容接口

### 改進
- AI Chat：模型列表改為根據當前 AI 服務 Profile 動態加載，支持自定義模型名
- 設置：AI 服務配置說明更新，提及 OpenRouter 及自定義中轉站支持

## [1.2.5] - 2026-02-16

### 修復
- 郵件箱數量顯示不一致的問題：修復了“所有邮件”和各文件夹显示的邮件总数不准确的问题。
- 郵件過濾邏輯：在計算總數和顯示列表時，現在會正確排除已刪除和垃圾郵件（除非是在對應的回收站或垃圾郵件文件夾中）。
- 跨文件夾去重：優化了“所有邮件”視圖的郵件計數邏輯，避免跨文件夾重複計算。

## [1.2.4] - 2026-02-16

### 新增
- 郵件去重服務（EmailDeduplicationService）
- 語音模型預加載管理（SpeechModelPreloadManager、SpeechTranscriptionModel）
- 語音模型預加載啟動畫面（SpeechModelPreloadSplashView）

### 改進
- 郵件相關：EmailStore、EmailViewModel、EmailView、EmailDatabase 功能增強
- 郵件設置標籤頁擴展（EmailSettingsTab）
- 郵件自動回覆調度、圖片顯示偏好
- 語音轉寫服務（SpeechTranscriber）優化
- 郵件正文 WebView、儀表板視圖改進
- 多語言本地化更新（en、ja、ko、yue、zh-Hans）

## [1.0.9] - 2026-02-02

### 新增
- 支援雙快捷鍵模式：
  - 主快捷鍵（默認 FN）：純語音輸入，直接識別文字
  - AI 校正快捷鍵（默認 FN+Control）：語音輸入後自動進行 AI 文本優化
- 在設置界面中可分別配置兩個快捷鍵
- 根據快捷鍵類型自動決定是否進行 AI 校正（無需額外開關）
- 如果 AI 服務未配置，即使按 AI 校正快捷鍵也會跳過 AI 處理
- 快捷鍵捕獲支持組合鍵（如先按 Control 再按 FN）
- 添加「恢復默認快捷鍵」按鈕
- 捕獲過程中實時顯示當前按住的修飾鍵

### 變更
- AI 優化不再依賴「啟用 AI 優化」開關，改為根據快捷鍵類型決定
- 優化快捷鍵監聽邏輯，支援同時監聽兩個快捷鍵

## [1.0.7] - 2026-02-02

### 修復
- 修復語音輸入服務嚴重的內存泄漏問題（緩衝區無限增長導致 58GB+ 內存佔用）
- 添加音頻緩衝區大小限制（50MB），超出後自動移除舊數據
- 修復回調閉包未清空導致的循環引用問題
- 為 VoiceInputService 和 MeetingRecordViewModel 添加 deinit 資源清理
- 修復 View 消失時未清理錄音資源的問題
- 修復 VideoCartoonizerService 缺少 Combine import 的編譯錯誤

### 新增
- 添加 `forceCleanup()` 方法用於強制清理音頻資源

## [1.0.6] - 2026-01-XX

### 新增
- 合併錄音功能並優化實時轉寫
- 為會議記錄詳情頁面添加關閉按鈕
- 添加在線視頻下載功能並實現視頻工具獨立窗口

### 修復
- 修復編譯錯誤和文字水印功能優化
- 優化水印功能：添加實時預覽、拖動調整位置和大小、修復界面卡頓問題
