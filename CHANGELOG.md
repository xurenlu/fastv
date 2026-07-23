# Changelog

## [2.4.0-rc11] - 2026-07-24

### Changed

- **设置窗口成为主窗口**：轻语已是系统输入法，打开 App / 点 Dock 图标现在直接显示设置窗（左侧 tab），不再有以前那个带测试输入框的旧主窗口 + 齿轮弹 sheet 结构。`ContentView` 的 WindowGroup 内容改为直接渲染 `SettingsView`（保留 XCTest 短路、`MainWindowSentinel`、引导页分支）。
- **测试输入框 / 语音输入统计 / 语音输入历史 并入「语音输入」tab**：原主窗口的三块整体搬进设置窗「语音输入」tab，位于该 tab 的各项语音设置（快捷键/触发/识别语言/分段/悬浮条/插入/权限/默认语言）之后，方便就地试用与查看统计。
- `Cmd+,` 与输入法菜单「打开轻语设置」改为把主窗口（即设置窗）拉到前面（`MainWindowPresenter.bringToFront`），不再单独 sheet 弹设置。

### Engineering

- 删除 `fastv/Views/VoiceInputView.swift`（内容已迁入 `VoiceInputTab`）与仅其使用的 `ModelDownloadBanner`；移除失效的 `Notification.Name.openSettings`。
- 版本号 `2.4.0-rc10` → `2.4.0-rc11`，build `40` → `41`；同步 4 处版本点。

## [2.4.0-rc10] - 2026-07-23

### Fixed

- **修点击 Dock 图标出现两个主窗口**：主窗口关闭走 `orderOut`（隐藏而非 close），窗口对象仍在 `NSApp.windows`；此前 `applicationShouldHandleReopen` 返回 true，SwiftUI WindowGroup 会再建一个新场景窗口，同时 helper 又调回旧窗口，导致重复。改为始终返回 false，由 `MainWindowPresenter.bringToFront()` 全权找回已有主窗口。

### Changed

- 主窗口统计区加「语音输入统计」小标题（麦克风图标），明确这些指标（字数/字每分/识别语音/识别耗时/实时率）均来自语音输入；历史区标题由「历史记录」改为「语音输入历史」。5 语种本地化。

### Engineering

- 版本号 `2.4.0-rc9` → `2.4.0-rc10`，build `39` → `40`；同步 4 处版本点。

## [2.4.0-rc9] - 2026-07-23

### Changed

- 设置窗口结构调整：
  - **移除「常用」tab**：其唯一实义项「在 Dock 中隐藏图标」开关删除（该行为保留底层默认，不再从设置暴露）；隐私说明在各 tab 顶部本已可见，空 tab 移除。
  - **「默认语言」移到「语音输入」tab**：该项只影响语音识别的默认语言，归入语音输入更合语义。
  - **「输入法·打字」提为第一个 tab 并作为默认选中项**。
- 最终左侧 5 组顺序：输入法·打字（默认）/ 语音输入 / AI 与模型 / 数据与其他 / 帮助。

### Engineering

- 删除 `GeneralTab.swift`；`SettingsView.SettingsTab` 移除 `.general`、默认值改 `.typing`；`VoiceInputTab` 追加默认语言 section；清理失效 i18n key `settings.tab.general`。
- 版本号 `2.4.0-rc8` → `2.4.0-rc9`，build `38` → `39`；同步 4 处版本点。

## [2.4.0-rc8] - 2026-07-23

### Added

- **设置窗口新增「帮助」tab**（左侧第 6 组），内容全面，四大块：
  - **输入法快捷键表**：数字选字、空格首选、分号次选、引号三选（纯五笔）、`-`/`,` 上一页、`=`/`。` 下一页、方向键移动、Tab 轮换、回车上原码、Esc 清空、Shift 中英切换、`` ` `` 拼音反查，每项配说明。
  - **语音输入指南**：两个语音快捷键（FN / FN+Control）、三种触发方式、AI 优化与上下文回改、术语包、Power Mode。
  - **输入法安装与排障**：安装启用步骤、列表里看不到怎么办、菜单栏图标没刷新怎么办、五笔/拼音/混打切换。
  - **常见问题 FAQ**：密码框为何不可用（Secure Input）、语音是否上传（本地处理）、需要哪些权限、为什么要注销重登、语音和打字是否同一套输入法。
- 帮助 tab 全部文案 5 语种本地化。

### Engineering

- 新增 `fastv/Views/Settings/HelpTab.swift`（`ShortcutRow` / `HelpParagraph` 复用组件）；`SettingsView.SettingsTab` 加 `.help`。
- 版本号 `2.4.0-rc7` → `2.4.0-rc8`，build `37` → `38`；同步 4 处版本点。

## [2.4.0-rc7] - 2026-07-23

### Fixed

- 设置窗口左侧 tab 点击后残留蓝色键盘焦点边框：`SidebarItem` 加 `.focusable(false)` 去除。

### Changed

- 推荐应用统一为精致网格并在两处展示：抽出共享 `RecommendedAppsGrid`（8 个 App：WillDeep / TimeBill / 轻图 / 轻阅 / GitWise / 象墨 / 轻邮 / 轻记，卡片带图标·名称·简介·跳转，链接 83d.me/products），关于窗口与设置页「数据与其他」共用同一份数据；列表与 museterm 关于窗对齐（不含轻语自身）。
- 设置页「数据与其他」原先手工硬编码的两个推荐（妙墨 / 时间帐单，SF Symbol 占位图标 + 中文硬编码 + App Store 链接）替换为上述统一网格；「性能监控 / 内存监控 / 支持与推荐 / 官方支持页」等硬编码文案补齐 5 语种本地化。

### Engineering

- 新增 `fastv/Views/RecommendedAppsView.swift`（`RecommendedApp` 枚举 + `RecommendedAppsGrid` + `RecommendedAppCard`）；`AboutView` 移除内部重复的推荐枚举/卡片改用共享网格。
- 版本号 `2.4.0-rc6` → `2.4.0-rc7`，build `36` → `37`；同步 4 处版本点。

## [2.4.0-rc6] - 2026-07-23

### Added

- **候选个数 5–9 可选**：设置页新增每页候选个数选择（`menu/page_size` 补丁 + IME 重部署），默认 5。
- **候选窗预设皮肤（一键套用）**：6 套预设，每套都由现有可选项拼成，选中即套用、之后仍可继续微调——经典浅色 / 夜幕 / 清新绿 / 极简黑白 / 大字护眼 / 竖排水墨。设置面板顶部网格点选，当前匹配的高亮。

### Changed

- **设置窗口重构为左侧竖向 tab、5 组**：常用 / 语音输入 / 输入法·打字 / AI 与模型 / 数据与其他。原「快速配置」拆分为「常用（隐私·Dock·界面语言）」「语音输入（快捷键·触发·识别语言·分段·悬浮条·插入方式·权限测试）」「输入法·打字（安装·方案·词频·候选窗·候选个数）」三组，结构更清晰。tab 标题 5 语种本地化。
- **移除主窗口 7 套界面皮肤**（淡雅雾林/水墨宣纸/科幻光栅/午夜岩蓝/极光暗夜/熔火石墨 + 系统默认）：主窗口固定使用系统默认配色，跟随系统深浅色。旧用户升级后回默认外观（UserDefaults 里遗留的皮肤键被静默忽略，无需迁移）。

### Tests

- `CandidateAppearanceTests` 扩充候选个数（钳制/补丁/旧文件兼容）与 6 套预设特征用例；`IMESettingsTests` 补丁生成器调用同步 pageSize。全套通过。

### Engineering

- `IMESettings.candidatePageSize` 可选字段（旧文件解码 nil 回落默认并钳制 5~9）；`RimePatchGenerator` 加 `pageSize` 参数写 `menu/page_size`；词频或候选个数变化才重写 custom 并触发 Rime 重部署。
- `CandidatePreset` 枚举（6 套，各自完整 CandidateAppearance）加入共享契约。
- 删除 `MainWindowSkin` 枚举，保留 `MainWindowSkinPalette.systemDefault` 常量；VoiceInputView 渲染零改动。
- 设置视图拆分：`GeneralTab` / `VoiceInputTab`（原 QuickSettingsTab 改名）/ `TypingTab`；`SettingsView` 改左侧 sidebar。
- 版本号 `2.4.0-rc5` → `2.4.0-rc6`，build `35` → `36`；同步 4 处版本点。

## [2.4.0-rc5] - 2026-07-23

### Added

- **自绘候选窗 + 全面外观定制**：抛弃系统 `IMKCandidates`（只能横竖排、无法定制字体配色），改为轻语自绘的无边框浮动 `NSPanel` + 自绘 `NSView`，跟随组字光标定位、支持点击选字。设置 → 快速配置 新增「候选窗外观」区块，带**实时预览**（可切浅色/深色预览）：
  - **排列方向**：横排 / 竖排。
  - **字体与字号**：候选字体（系统默认或 PingFang/Songti/Kaiti 等已安装中文字体）、候选字号、序号/编码提示字号。
  - **配色主题**：背景、文字、选中背景、选中文字、编码提示、序号、边框 7 个颜色，**浅色/深色两套独立可调**，可开「配色跟随系统深浅色」自动切换；内置浅色 + 深色两套默认配色。
  - **外观细节**：圆角、候选间距、内边距，以及「显示候选序号」「显示编码/拼音提示」开关。
  - 一键「恢复默认外观」。
- 外观设置经 `qecho-ime-settings.json` 落盘，改动即时通知输入法进程重绘（不触发 Rime 重新部署，调色无卡顿）。

### Tests

- 新增 `CandidateAppearanceTests` 12 例：颜色 hex 解析（6/8 位、非法输入）、往返、字号/间距钳制、外观编解码、**旧设置文件无 `candidateAppearance` 字段的向后兼容**、明暗预设区分。全套 80 测通过。

### Engineering

- 候选窗模型 `CandidateAppearance` / `CandidatePalette` / `CandidateColor` / `CandidateLayout` 加入共享契约（两 target + 单测共用，不依赖 AppKit）；`IMESettings.candidateAppearance` 为可选字段，旧文件解码为 nil 后经 `appearance` 计算属性回落默认并钳制。
- QEchoIME 新增 `CandidateWindow`（NSPanel 定位/明暗解析）、`CandidateContentView`（自绘布局与绘制，横竖排共用测量保证点击命中一致）；`main.swift` 移除 IMKCandidates。
- 版本号 `2.4.0-rc4` → `2.4.0-rc5`，build `34` → `35`；同步 4 处版本点。

## [2.4.0-rc4] - 2026-07-23

### Fixed

- 修输入源菜单图标丑/糊：此前直接把彩色 App icon 缩到 16pt 当输入法图标，小尺寸糊成一团且深色菜单栏下发黑。改为专门绘制的**单色矢量模板图** `QEchoIMETemplate.pdf`（脉冲外环 + 麦克风 + 声波竖条镂空），文件名以 `Template` 结尾，macOS 自动按明暗主题反色（与系统 CharacterPalette 的 `CVIconTemplate.pdf` 同一机制），矢量任意分辨率清晰。源图 `assets/brand/qecho-ime-menubar-template.svg` 随仓库保留可迭代。
- 移除工程中旧 `QEchoIME.tiff` 的残留资源引用，避免构建期挂空引用。

### Note

- 系统会缓存输入源图标，更新后若仍显示旧图标，需注销重新登录（或 `killall '\''com.apple.TextInputMenuAgent'\''` 后重选输入法）刷新缓存。

## [2.4.0-rc3] - 2026-07-23

### Added

- 输入法阶段三（试用反馈打磨）：
  - **显示名与图标**：输入源菜单显示「轻语输入法」（`tsInputMethodLocalizedNamesKey`，中文简/繁本地化，英文等显示 QEcho IME），菜单栏图标复用 QEcho App icon（16/32 双分辨率 tiff）。
  - **候选上屏快捷键**：分号次选（全方案）、引号三选（纯五笔）；`-`/`=` 与 `,`/`。` 翻页、Tab 轮换候选为 Rime 预设保留。混打/纯五笔方案的 `speller/delimiter` 相应调整避让。
  - **三方案可切换**：五笔·拼音混打（默认）/ 纯五笔 86（新增 `wubi86.schema.yaml`，prism 预编译随包）/ 纯拼音，设置页 segmented 选择或输入法菜单直接切换，双侧经 `qecho-ime-settings.json` 保持同步。
  - **动态词频开关**：设置页可开关用户词库（`translator/enable_user_dict` custom 补丁 + IME 进程热重启部署），默认开启、越打越顺手。
  - **输入法下拉菜单**（结构参考主流中文输入法）：打开轻语设置… / 三方案 radio / 中英切换 / 全角符号开关；「打开轻语设置」经分布式通知唤起主 App 设置窗口（通知不携带任何用户数据）。
- 主 App ⇄ IME 桥接扩展：CFMessagePort 增加「设置变更」控制消息（messageID 2），IME 收到后重读设置并按需重启 Rime 部署；`RimePatchGenerator` 统一生成用户目录 custom 补丁，与随包默认文件同源防漂移。

### Tests

- 新增 `IMESettingsTests` 8 例：设置模型编解码/回退、三方案 schema id 对齐、补丁生成器（delimiter 避让、次三选绑定、词频开关）、随包 custom 文件与生成器一致性。

### Engineering

- `RimeEngine` 增加 `select_schema` / `get_current_schema` / `get_option` / `set_option` 与配置变更整体重启（glog setup 进程内单次守卫）；rime_deployer 离线预编译三方案（`wubi86.prism.bin` 等）随包，用户侧零部署等待。
- 版本号 `2.4.0-rc2` → `2.4.0-rc3`，build `32` → `33`；同步 Xcode、Info.plist 与 STT API 响应版本。

## [2.4.0-rc2] - 2026-07-23

### Added

- 输入法阶段二：QEchoIME 接入 librime，支持**五笔·拼音混打**（`wubi_pinyin` 方案，五笔 86 码与全拼同一输入串混出候选，`` ` `` 前缀拼音反查带五笔编码提示）。组字区内联 preedit（下划线 marked text）、系统单列候选窗（IMKCandidates）、翻页/方向键/数字选字/Esc 清空/回车上原文，Shift 中英切换由 Rime ascii_composer 处理。
- 语音上屏与打字融合：语音文本插入前自动落掉进行中的组字，避免 marked text 交错。
- Vendor librime 1.17.0 官方预编译 universal dylib（`ThirdParty/librime/`，BSD-3-Clause）与 Rime 方案数据（`QEchoIME/RimeData/`：rime-wubi LGPL-3.0、rime-pinyin-simp Apache-2.0、rime-prelude LGPL-3.0，均以独立数据文件随包分发并附 LICENSE）。词典预编译产物随包分发，首次启用无需等待长时间部署；用户词典与日志位于 `~/Library/Application Support/QEchoIME/`。

### Tests

- 新增 `RimeKeyMappingTests` 7 例：macOS 键码/字符 → X11 keysym 映射、修饰键掩码、UTF-8→UTF-16 光标偏移（含 emoji 与非法偏移兜底）。全套 59 测通过。

### Engineering

- `RimeEngine`（librime C API Swift 封装：traits/session/process_key/context/commit）、`RimeKeyMapping`（纯函数映射，musetype 与 QEchoIME 共享编译）；`scripts/add_ime_target.rb` 扩展 dylib 链接/嵌入、bridging header、RimeData 资源（仍幂等）。
- `.gitignore` 对 `QEchoIME/RimeData/build/` 预编译词典加白名单（vendor 数据非构建产物）。
- 版本号 `2.4.0-rc1` → `2.4.0-rc2`，build `31` → `32`；同步 Xcode、Info.plist 与 STT API 响应版本。

## [2.4.0-rc1] - 2026-07-23

### Added

- 系统输入法（实验性）第一阶段：新增 `QEchoIME` IMKit 输入法 target，产物随主 App 嵌入分发（`Contents/Resources/QEchoIME.app`）。设置 → 快速配置 新增「输入法（实验性）」区块，一键安装到 `~/Library/Input Methods` 并注册、启用输入源（TIS API）。
- 语音上屏新增系统输入法通道：当用户选中「轻语」输入法时，转写文本经 CFMessagePort 发给输入法进程，由 `IMKTextInput.insertText` 走系统正规通道提交，比 CGEvent 模拟按键 / 剪贴板粘贴更可靠；输入法未选中或发送失败时自动回退原有插入方式。
- 主 App 与输入法进程的桥接契约 `InputMethodBridgeContract`（端口名、输入源 ID、带版本号的 JSON 载荷/回执），配套 6 个单元测试（编解码往返、版本兼容、输入源 ID 判定）。

### Engineering

- 本阶段打字为直通模式（行为等同 ABC 键盘）；拼音·五笔混打将基于 librime + `wubi_pinyin` 方案在后续版本实现。
- 三处语音插入调用点收敛到统一入口 `insertVoiceText`。
- 新增 `scripts/add_ime_target.rb`（幂等）：向 Xcode 工程注入 QEchoIME target、共享契约文件、目标依赖与嵌入 phase。
- 版本号 `2.3.0-rc4` → `2.4.0-rc1`，build `30` → `31`；同步 Xcode、Info.plist 与 STT API 响应版本。

## [2.3.0-rc4] - 2026-07-22

### Changed

- 关于窗口对齐 MuseTerm 的紧凑布局：头部改为动画图标、应用名、版本号、简介与 83d 作者主页链接，推荐应用卡片同步使用 42pt 图标与更高卡片行距。
- 推荐应用新增 GitWise 与象墨（Xomo / VeilPic），并补齐中、英、日、韩、粤本地化文案和图标资源。

### Engineering

- 版本号 `2.3.0-rc3` → `2.3.0-rc4`，build `29` → `30`；同步 Xcode、Info.plist 与 STT API 响应版本。

## [2.3.0-rc3] - 2026-07-21

### Fixed

- Sparkle appcast 控制面显式固定为 `https://some.im`，避免未来误把 some.im/niuwoai 推理节点或用户自定义 API Base 当作更新源。

### Tests

- 更新 SomeIMUpdateConfiguration 契约测试，逐项断言 appcast 的 scheme、host、path 与 app_id/platform/channel 查询参数。

### Changed

- 版本号 `2.3.0-rc2` → `2.3.0-rc3`，build `28` → `29`。

所有版本變更記錄。

## [2.3.0-rc2] - 2026-07-20

### 修复

- 放大菜单栏闲置态品牌图标：裁掉 `MenuBarIcon` 资源中过多的透明边距，并让 `StatusBarManager` 以 18pt 渲染品牌图标，改善与系统菜单栏图标并排时偏小的问题。

### 工程

- 版本号 `2.3.0-rc1` → `2.3.0-rc2`，build `27` → `28`；同步 Xcode、Info.plist 与 STT API 响应版本。

## [2.3.0-rc1] - 2026-07-20

### 新增

- 集成 Sparkle 自动更新，支持启动检查和应用菜单手动检查更新。
- 更新源统一使用 some.im 的 QEcho stable appcast：`https://some.im/api/v1/appcast/qecho/macos/stable.xml`。

### 测试

- 新增更新地址配置测试，并通过 CocoaPods workspace 的 macOS 13.7 Debug 构建。

### 工程

- 版本号 `2.2.0-rc8` → `2.3.0-rc1`，build `26` → `27`；同步 Xcode、Info.plist 与 STT API 响应版本。

## [2.2.0-rc8] - 2026-07-09

### 修复

- **官方支持页链接切换到 QEcho 英文 slug**：设置页的官方支持入口从旧 typecho 地址改为 `https://83d.me/products/qecho`。

### 工程

- 版本号 `2.2.0-rc7` → `2.2.0-rc8`；同步 `fastv.xcodeproj/project.pbxproj`、`fastv/Info.plist`、`stt-api/stt_api.py`。

## [2.2.0-rc7] - 2026-07-09

### 修复

- **简体中文系统应用名恢复为轻语**：修正 `zh-Hans` 本地化中的 `app.name`，确保中文系统显示轻语，英文和其他非中文系统显示 QEcho。

### 工程

- 版本号 `2.2.0-rc6` → `2.2.0-rc7`；同步 `fastv.xcodeproj/project.pbxproj`、`fastv/Info.plist`、`stt-api/stt_api.py`。

## [2.2.0-rc6] - 2026-07-08

### 变更

- **品牌升级为轻语 / QEcho**：应用展示名、产物名和关于页推荐卡片统一到轻语（QEcho），输出 App 改为 `QEcho.app`。
- **关于页推荐应用改用 Q 系列命名**：推荐网格更新为 QMailMate / QPic / QNote / QMarkView / QTerm 等新英文名与对应中文名，图片类推荐继续只保留轻图。

### 工程

- 版本号 `2.2.0-rc5` → `2.2.0-rc6`；同步 `fastv.xcodeproj/project.pbxproj`、`fastv/Info.plist`、`stt-api/stt_api.py`。

## [2.2.0-rc5] - 2026-07-08

### 修复

- **关于页推荐应用收口轻图**：推荐网格中的图片编辑、截图、上传分享类产品只保留轻图（QPic / qpic），移除已停用的 MuseSnip / 简图推荐，并更新轻图卡片文案。

### 工程

- 版本号 `2.2.0-rc4` → `2.2.0-rc5`；同步 `fastv.xcodeproj/project.pbxproj`、`fastv/Info.plist`、`stt-api/stt_api.py` 与 README 版本。

## [2.2.0-rc4] - 2026-07-08

### 新增

- **同 App 短上下文联想校正**：AI 语音优化时会读取当前焦点输入框光标前最多 260 个 UTF-16 字符，作为“同一 App 短上下文”随本次语音一起发送给模型，用于修正同音/近音误识别。例如在编程语境中，`保持工作去干净` 可根据前文修正为 `保持工作区干净`。
- 默认 AI 系统提示词新增“同一 App 短上下文联想校正”章节，要求模型只把短上下文当作当前 App 当前输入框的参考，不复述、不续写、不跨 App 使用历史、不引入外部事实。
- Power Mode 的邮件 / Slack / IM / IDE 内置 prompt 同步加入同 App 短上下文规则，并对未修改过的出厂模板做温和迁移。

### 变更

- 为提高 DeepSeek / Kimi 等模型的 cache rate，固定规则继续放在 system prompt；每次不同的短上下文放在 user message 中，避免动态上下文污染可缓存的 system 前缀。
- AI 请求的 user message 在存在短上下文时使用稳定结构：`同一 App 短上下文` + `本次语音转写`，让模型明确只输出本次语音的优化结果。

### 测试

- 扩展 ContextProfile 测试，覆盖默认系统提示词、4 个内置场景 prompt 是否包含短上下文规则，以及短上下文是否只截取光标前有限文本。

### 工程

- 版本号 `2.2.0-rc3` → `2.2.0-rc4`（同一 minor 预发布中的 AI 后处理增强，递增 rc 号）。
- 同步 `fastv.xcodeproj/project.pbxproj` 6 处 `MARKETING_VERSION`、`fastv/Info.plist` 的 `CFBundleShortVersionString`，以及 `stt-api/stt_api.py` 的 `API_VERSION`。

## [2.2.0-rc3] - 2026-07-08

### 新增

- **中英混合术语自动校正**：内置一组高置信度术语/流行技术词规则，覆盖 `麦克 app → Mac app`、`麦克 OS / Mac OS → macOS`、`open ai → OpenAI`、`chat gpt → ChatGPT`、`git hub → GitHub`、`type script → TypeScript`、`swift ui → SwiftUI`、`vs code → VS Code`、`k8s / k 8 s → Kubernetes` 等常见语音误听。
- 默认 AI 系统提示词新增“中英混合与流行术语校正”章节，要求 AI 只在高置信度、语境明确时修正产品名、技术词和流行词，不确定时保留原文，避免臆造。
- Power Mode 的邮件 / Slack / IM / IDE 内置 prompt 同步加入中英混合术语校正规则，并对未修改过的出厂模板做温和迁移。

### 变更

- 常错词正则边界从单纯 `\b` 调整为更适合中文上下文的 ASCII 边界，确保“我想做一个麦克 app”这种夹在中文句子里的短语也能命中，同时避免把英文词误替换到更长单词内部。
- 内置纠错规则初始化升级到 v3；已初始化过 v2 的用户会增量加入新规则，不覆盖用户自定义规则，也不重置已存在内置规则的开关状态。

### 测试

- 新增中英混合术语测试，覆盖 `麦克 app`、`麦克系统`、`open ai`、`git hub`、`type script` 的内置替换。
- 扩展 ContextProfile 测试，覆盖默认提示词与 4 个内置场景 prompt 是否包含中英混合术语校正规则。

### 工程

- 版本号 `2.2.0-rc2` → `2.2.0-rc3`（同一 minor 预发布中的 AI 后处理增强，递增 rc 号）。
- 同步 `fastv.xcodeproj/project.pbxproj` 6 处 `MARKETING_VERSION`、`fastv/Info.plist` 的 `CFBundleShortVersionString`，以及 `stt-api/stt_api.py` 的 `API_VERSION`。

## [2.2.0-rc2] - 2026-07-07

### 新增

- **关于窗口刷新**：借用 MuseTerm 的 About 窗口结构，改为独立 700×500 macOS 窗口，加入左侧企鹅动画、版本信息、作者主页入口、隐私承诺卡片和 83d 系列推荐应用网格。
- 新增 About 窗口所需的企鹅动画帧与推荐应用图标资源，并补齐中 / 英 / 日 / 韩 / 粤 5 语种本地化文案。

### 变更

- 设置 → 数据与其他 → 关于 从原先的 sheet 弹层改为独立窗口打开，窗口内容改为妙打自己的语音输入定位与隐私说明，不复用 MuseTerm 的产品介绍文案。

### 工程

- 版本号 `2.2.0-rc1` → `2.2.0-rc2`（同一 minor 预发布中的界面增强，递增 rc 号）。
- 同步 `fastv.xcodeproj/project.pbxproj` 6 处 `MARKETING_VERSION`、`fastv/Info.plist` 的 `CFBundleShortVersionString`，以及 `stt-api/stt_api.py` 的 `API_VERSION`。

## [2.2.0-rc1] - 2026-07-07

### 新增

- **AI 语音输入轻度结构化整理**：默认 AI 优化提示词新增“输入法级别”的结构化规则。当原文天然包含多个事项、条件、步骤、问题或请求时，可以整理成 2-5 条短列表；单句闲聊不强行列表化，且不新增原文没有的信息。
- **Power Mode 预设同步增强**：邮件、Slack、IM 内置 prompt 均加入轻度结构化边界；IDE / 代码编辑器预设仅在多项 TODO、步骤或条件场景允许输出多行 `// - ` 列表注释，避免破坏默认单行注释体验。

### 变更

- 默认系统提示词抽成 `UserPreferences.defaultAISystemPrompt` 单一来源，设置页“恢复默认”和首次启动共用同一份 prompt。
- 对仍保持旧出厂文案的默认系统提示词与内置 Power Mode 预设做一次温和迁移；用户自定义过的 prompt 不会被覆盖。

### 测试

- 新增 `ContextProfileMatchingTests.builtInPromptsIncludeLightStructure`，覆盖默认提示词与内置场景预设的轻度结构化规则。

### 工程

- 版本号 `2.1.1-rc2` → `2.2.0-rc1`（功能增强，递增 minor 预发布版本）。
- 同步 `fastv.xcodeproj/project.pbxproj` 6 处 `MARKETING_VERSION`、`fastv/Info.plist` 的 `CFBundleShortVersionString`，以及 `stt-api/stt_api.py` 的 `API_VERSION`。

## [2.1.1-rc2] - 2026-06-26

### 修复

- **清理已废弃邮件链路残留的 libetpan 链接**：当前主线已在 v2.0.0 收敛为纯语音输入工具，源码中不再包含 `EmailService.swift` / `LibEtPanWrapper.m` 等邮件调用层，但 Xcode 工程仍把 `libetpan.a` 及其 CFNetwork/Security/zlib/sasl/iconv/resolv 依赖链进 app target，并保留 `ThirdParty/libetpan/include/**` 头文件搜索路径。移除这些残留工程配置，避免旧构建或误链接路径继续把 `mailstream_cfstream.c:912` 的 CFStream 同步等待暴露到运行时诊断里。
- 处理策略保持在调用/工程层：不修改第三方 `mailstream_cfstream.c` 的 RunLoop 等待逻辑；如果后续恢复邮件功能，IMAP/SMTP 阻塞 I/O 仍应放在 `.utility` QoS，而不是 `.userInitiated`。

### 工程

- 版本号 `2.1.1-rc1` → `2.1.1-rc2`（bugfix，仅递增 rc 号）。
- 同步 `fastv.xcodeproj/project.pbxproj` 6 处 `MARKETING_VERSION`、`fastv/Info.plist` 的 `CFBundleShortVersionString`，以及 `stt-api/stt_api.py` 的 `API_VERSION`。

## [2.1.1-rc1] - 2026-06-21

### 修复

- **菜单栏图标与 AppIcon 品牌不一致**：闲置态原本是 SF Symbol `bolt.fill`
  闪电，与 rc5 上线的 MuseType 脉冲麦克风 AppIcon 视觉脱节。新增
  [`fastv/Assets.xcassets/MenuBarIcon.imageset/`](fastv/Assets.xcassets/MenuBarIcon.imageset/Contents.json)
  含 1x/2x/3x 三档 PNG（取自 `assets/brand/png/musetype-logo-pulse-mic-{16,32,64}.png`），
  在 Contents.json 标 `template-rendering-intent: template` 让系统跟随菜单栏明暗自动取色。
  `StatusBarManager.applyActivity(_:to:)` 仅闲置态切到 `MenuBarIcon`，
  录音/转写/AI 优化三个功能态保留 SF Symbol（红 mic / 蓝 waveform / 紫 sparkles），
  品牌图标与状态指示职责分明。
- **系统托盘「显示妙打」失效**：用户红 × 关闭主窗口后，SwiftUI 在
  `.accessory` 激活模式下会销毁 `WindowGroup` 的窗口对象，`NSApp.windows`
  里只剩 `NSStatusBarWindow`（状态栏 status item 自己的容器）；
  `StatusBarManager.showMainWindow` 与 `applicationShouldHandleReopen` 之前
  都是直接取 `windows.first` + `makeKeyAndOrderFront(nil)`，刚好误打到那个
  状态栏窗口上，控制台报
  `makeKeyWindow ... canBecomeKeyWindow returned NO` 警告，主窗口当然
  也不会出现。
- 新增 [`fastv/Views/MainWindowSentinel.swift`](fastv/Views/MainWindowSentinel.swift)：
  - `MainWindowSentinel` 挂在 [`fastv/ContentView.swift`](fastv/ContentView.swift)
    的 `.background`，第一次出现就给主窗口打 identifier
    `museTypeMainContentWindow`，并把红色关闭按钮的 `target` / `action`
    重定向到 `MainWindowCloseInterceptor.hideMainWindow(_:)`（执行
    `orderOut(nil)` 而非真正 close），让窗口对象常驻 `NSApp.windows`。
  - `MainWindowPresenter.bringToFront()` 是新加的统一恢复链：
    activate App → identifier 命中 → 退一步过滤 NSStatusBarWindow /
    borderless 的真内容窗口 → 兜底切 `.regular` 激活策略让 SwiftUI 有机会
    重建场景（用户偏好「隐藏 Dock 图标」的话，等窗口出来后再切回
    `.accessory`）。
- [`fastv/Services/StatusBarManager.swift`](fastv/Services/StatusBarManager.swift)
  的 `showMainWindow(_:)` 与 [`fastv/fastvApp.swift`](fastv/fastvApp.swift)
  的 `applicationShouldHandleReopen(_:hasVisibleWindows:)` 改为统一走
  `MainWindowPresenter.bringToFront()`。
- 注：不替换 SwiftUI 内部 NSWindowDelegate（避免破坏框架内部观察），
  因此 Cmd+W 仍会让 SwiftUI 走真 close 路径；此时由
  `MainWindowPresenter.bringToFront()` 的兜底重激活分支兜住，最差情况会有
  Dock 图标短暂闪现。

### 工程

- 版本号 `2.1.0` → `2.1.1-rc1`（bugfix，递增补丁版本号）。
- 同步 `fastv.xcodeproj/project.pbxproj` 6 处 `MARKETING_VERSION` 与
  `fastv/Info.plist` 的 `CFBundleShortVersionString`。

## [2.1.0] - 2026-06-21

竞品调研驱动的「四件套」补齐汇总版。从 `2.0.0-rc14` 起步，经 rc1 → rc6
6 个 rc 拼齐后定版。对照 VoiceInk / Superwhisper / TypeWhisper / Wispr Flow /
VocaMac 五家头部产品，把妙打从「本地 + 菜单栏 + 多语种」推进到了「上下文
感知 + AI 模板路由 + 术语包 + 跟随光标」同档。

### 本轮汇总

- **rc1 — 热键三模式 + 术语包**：[HotkeyTriggerStateMachine](fastv/Services/HotkeyTriggerStateMachine.swift) 把
  物理按键 press/release 翻译为有效录音 start/stop，FN/Control/普通键三条
  检测路径统一走 dispatchRaw*；CorrectionCategory 新增 `.terminology` 分类，
  替换管线中优先生效且大小写不敏感。
- **rc2 — 收敛遗留废测试清理**：删 `EmailRemoteImageBlocking` /
  `EmailTranslateStrip` 两个文件 + `MeetingRichDoc` 前 6 例引用已删 API 的用例，
  `fastvTests` 目录不再有 `#if false` 屏蔽段。
- **rc3 — 修测试 runner SwiftUI 兼容崩溃**：[ContentView](fastv/ContentView.swift) +
  [fastvApp](fastv/fastvApp.swift) 加 `isRunningUnderXCTest` 早 return，
  XCTest host 跳过状态栏 / 快捷键 / 麦克风 / 模型预热等重副作用，恢复 macOS 26
  下整套单测执行能力。
- **rc4 — Power Mode 上下文感知 prompt**：[AppContextResolver](fastv/Services/AppContextResolver.swift)
  + [ContextProfile](fastv/Models/ContextProfile.swift) + [ContextProfileManager](fastv/Models/ContextProfileManager.swift)
  + [ContextProfileEditorView](fastv/Views/ContextProfileEditorView.swift)。
  按前台 App / 浏览器 URL 切换 AI 后处理 prompt 模板；出厂 4 内置预设
  （邮件正式 / Slack / IM 口语 / IDE 代码）；MatchRule 三态 + glob `*`。
- **rc5 — MuseType 品牌图标统一**：`AppIcon.appiconset` + `assets/brand/`
  + DMG `.VolumeIcon.icns`。
- **rc6 — 光标旁悬浮指示器**：[CursorPositionLocator](fastv/Services/CursorPositionLocator.swift)
  AX 优先链拿 caret bounds（失败兜底鼠标位置），[WaveformWindowManager](fastv/Views/WaveformView.swift)
  followCursorTimer 50ms 重定位。

### 测试规模

`scripts/run_unit_tests.sh` 全套 41 个测试通过，含 6 个 suite：
HotkeyTriggerStateMachine、TerminologyCorrection、ContextProfileMatching、
CursorPositionLocator、MeetingRichDoc（残留 4 例）、fastvTests。

### 工程

- 版本号 `2.1.0-rc6` → `2.1.0`（定版，全部 6 个 rc 已落地）。
- 后续 Batch 4「语音指令编辑」（"删掉这句"/"换行"/"加粗"）单独立项，不在
  2.1.0 范围内。

## [2.1.0-rc6] - 2026-06-21

竞品调研第三批：**光标旁悬浮指示器（Follow Cursor）**。对标 VocaMac /
VoiceInk「悬浮在输入光标旁的小指示器」体验，让用户视线不必离开输入框去看
菜单栏徽章。

### 新增

- [`fastv/Models/WaveformWindowPosition.swift`](fastv/Models/WaveformWindowPosition.swift)
  新增 `.followCursor` case 与 `isFollowingCursor` helper；`displayName` 改用
  `NSLocalizedString(_:value:comment:)`，保持中文兜底的同时打开 5 语种 i18n 通道。
- [`fastv/Services/CursorPositionLocator.swift`](fastv/Services/CursorPositionLocator.swift)：
  AX 优先链 — `AXFocusedUIElement` → `AXSelectedTextRange` →
  `AXBoundsForRangeParameterizedAttribute` 拿 caret bounds，Quartz/AppKit 坐标系
  正确翻转；失败回退 focused element 自身 frame；再失败回退 `NSEvent.mouseLocation`。
  `clampedRect(origin:size:into:margin:)` 是纯函数，已加单测覆盖多屏 / 负坐标 /
  屏幕比窗口窄等边界。
- [`fastv/Views/WaveformView.swift`](fastv/Views/WaveformView.swift):
  `WaveformWindowManager` 加 `followCursorTimer`（50ms 间隔），仅在
  `waveformWindowPosition == .followCursor` 时启动，`hide()` / `cleanup()` 立即
  销毁。origin 没变就跳过 `setFrameOrigin`，避免无谓的 layout。
  `calculateWindowFrame()` 的 switch 加 `.followCursor` 分支，首次显示就落到光标旁。
- [`fastv/Views/Settings/QuickSettingsTab.swift`](fastv/Views/Settings/QuickSettingsTab.swift)：
  现有 position picker 通过 `ForEach(allCases)` 自动新增「跟随光标」选项；选中后
  下方多一行 hint 解释 AX 权限要求。
- 5 语种 i18n（en / zh-Hans / ja / ko / yue）补齐 6 个位置 displayName + 1 个
  followCursor hint，共 7 × 5 = 35 个 key。

### 测试

- 新增 [`fastvTests/CursorPositionLocatorTests.swift`](fastvTests/CursorPositionLocatorTests.swift) 6 例：
  锚点在屏内 → 原样；右溢出 / 左下溢出 → clamp 到 margin；屏幕小于窗口 → 居中；
  副屏负坐标空间；enum 暴露面校验。

### 工程

- 版本号 `2.1.0-rc5` → `2.1.0-rc6`（功能新增，递增 rc 号）。

## [2.1.0-rc5] - 2026-06-21

### 改进

- **应用与 DMG 图标统一为 MuseType 新品牌**：替换 `AppIcon.appiconset` 全尺寸图标为脉冲麦克风 Logo；新增 `assets/brand/musetype-dmg-volume.icns`，`create_dmg.sh` 与 `package_for_distribution.sh` 在创建 DMG 时写入 `.VolumeIcon.icns` 并设置卷标自定义图标。
- **品牌资产入库**：保留 MuseType / 妙打图形标、深浅色版本、中英文组合字标，以及常用 PNG 尺寸导出，后续官网、文档和安装包可复用同一套资产。

### 工程

- 版本号 `2.1.0-rc4` → `2.1.0-rc5`，同步 STT API `X-API-Version`。

## [2.1.0-rc4] - 2026-06-21

竞品调研第二批：**Power Mode（上下文感知 prompt 模板）**。对标
VoiceInk Power Mode / Superwhisper Custom Mode / Wispr Flow Writing Styles。

### 新增

- **上下文解析层** [`fastv/Services/AppContextResolver.swift`](fastv/Services/AppContextResolver.swift)：
  从 `NSWorkspace.frontmostApplication` 拿 bundleId / appName，对受支持的浏览器
  （Safari / Chrome / Arc / Brave / Edge / Firefox）走 AX `AXWebArea` 抽当前 tab URL；
  1s TTL 缓存避免每次录音都重复 AX 调用；未授权 AX 静默回退到无 URL。
- **Profile 模型** [`fastv/Models/ContextProfile.swift`](fastv/Models/ContextProfile.swift)：
  `MatchRule` 三态枚举（`bundleId` / `urlPattern` / `appNameContains`），自带
  `precedence`（100/50/10）与 `globMatch`（`*` 通配，正则字符严格转义）；
  `ContextProfile` 内含 `matchScore` 与 `renderedPrompt`（替换 `{transcript}` / `{appName}` /
  `{browserURL}` 占位符，缺失值清空字面占位符避免泄漏到最终 prompt）。
- **路由器** [`fastv/Models/ContextProfileManager.swift`](fastv/Models/ContextProfileManager.swift)：
  `@MainActor ObservableObject`，UserDefaults 持久化 `contextProfiles_v1`；
  `match(_:)` 取最高 precedence 命中的 profile；`resolveSystemPrompt(...)` 在未启用
  Power Mode / 未命中 / 模板为空时回退到 `UserPreferences.aiSystemPrompt`。出厂内置 4 预设：
  - 邮件（Apple Mail / Outlook / Spark / Gmail / Outlook Web） → 正式书面语；
  - Slack（slackmacgap + *.slack.com/*） → 简短英式 Slack 风格；
  - IM / 微信 / Discord / Telegram / WhatsApp / 腾讯会议 → 保留口语；
  - IDE（Xcode / VS Code / Cursor / JetBrains） → 英文代码注释风格。
- **AI 后处理接入** [`fastv/fastvApp.swift`](fastv/fastvApp.swift) 的两个
  `OllamaService.optimizeTranscript` 调用前各插一段
  `AppContextResolver.shared.resolve()` + `ContextProfileManager.shared.resolveSystemPrompt(...)`，
  在不改 `OllamaService` API 的前提下把 prompt 路由进 polish 管线。
- **设置 UI**：
  - [`fastv/Views/Settings/AIModelSettingsTab.swift`](fastv/Views/Settings/AIModelSettingsTab.swift)
    在「场景映射」section 之后新增 **Power Mode** section，含启用 Toggle + 入口；
  - [`fastv/Views/ContextProfileEditorView.swift`](fastv/Views/ContextProfileEditorView.swift)
    HSplitView 左列表右详情，可加规则 / 改 prompt 模板 / 删除自定义 profile / 还原内置。
- **5 语种 i18n** 全套（en / zh-Hans / ja / ko / yue）。

### 测试

- 新增 [`fastvTests/ContextProfileMatchingTests.swift`](fastvTests/ContextProfileMatchingTests.swift) 9 例：
  覆盖 MatchRule 三态、glob 正则转义、ContextProfile.matchScore + renderedPrompt
  占位符、ContextProfileManager.match 优先级、enablePowerMode 开关、resolveSystemPrompt
  fallback 路径。

### 工程

- 版本号 `2.1.0-rc3` → `2.1.0-rc4`（功能新增，按既定 rc 节奏递增）。

## [2.1.0-rc3] - 2026-06-21

`xcodebuild test -scheme musetype` 编译能过但测试 runner 在 bootstrap 时
SIGSEGV（`InitialAllocationPool` → `ContentView.body.getter` → AttributeGraph），
HotkeyTriggerStateMachine 与 TerminologyCorrection 两个新测试套件因此根本跑不起来。
本版仅修复该 runner 启动崩溃，不动业务代码。

### 修复

- 在 [`fastv/ContentView.swift`](fastv/ContentView.swift) 引入全局 `isRunningUnderXCTest`
  标志（检测 `XCTestConfigurationFilePath` / `XCInjectBundleInto` 环境变量及
  `XCTestCase` 类是否存在），测试态下 `body` 直接返回 1×1 的 `Color.clear`，
  绕开 `OnboardingView` / `VoiceInputView` 这条会在 macOS 26 SwiftUI 下崩
  AttributeGraph 的真实主界面渲染路径。
- 在 [`fastv/fastvApp.swift`](fastv/fastvApp.swift) 同步给 `AppDelegate`
  （`applicationWillFinishLaunching` / `applicationDidFinishLaunching` /
  `applicationWillTerminate`）与 `WindowGroup` 的 `onAppear` 都加上同样的测试态
  早 return，避免 XCTest host 阶段触发状态栏、全局快捷键、麦克风权限弹窗、
  模型预热等重副作用，让 unit test 进程拿到一个尽量"安静"的 host。
- 影响范围：仅在 `XCTestConfigurationFilePath` 等环境变量存在时生效，正常 app
  启动路径完全不变。

### 工程

- 版本号 `2.1.0-rc2` → `2.1.0-rc3`（bugfix，仅递增 rc 号）。
- 顺手把 `fastv.xcodeproj/project.pbxproj` 里 6 处 `MARKETING_VERSION` 一并同步
  到 `2.1.0-rc3`，跟前端版本号保持一致。

## [2.1.0-rc2] - 2026-06-21

清理 v2.0.0-rc1 产品收敛后遗留的废测试，让 `fastvTests` target 恢复无屏蔽编译。

### 修复

- 删除 [`fastvTests/EmailRemoteImageBlockingTests.swift`](fastvTests/EmailRemoteImageBlockingTests.swift) 与 [`fastvTests/EmailTranslateStripTests.swift`](fastvTests/EmailTranslateStripTests.swift)：两文件分别引用已随邮件管线一并删除的 `EmailBodyWebViewRepresentable.stripRemoteImageSources` 与 `EmailViewModel.stripHTMLTagsForTranslate`，2.1.0-rc1 临时整文件 `#if false` 包裹绕过编译失败，现确认妙打不再恢复邮件功能，直接删除。
- 清理 [`fastvTests/MeetingRichDocTests.swift`](fastvTests/MeetingRichDocTests.swift) 顶部 6 个 `#if false` 包裹的 `decideRichDocTrigger` 用例（依赖随 `MeetingRichDocPipeline.swift` 一并删掉的 `RichDocTriggerInput` / `RichDocTriggerConfig`），保留下方 Markdown 解析与 `AIScenario` 4 个仍然有效的用例。
- 至此 `fastvTests` 目录里不再有任何 `#if false` 临时屏蔽段。

### 工程

- 版本号 `2.1.0-rc1` → `2.1.0-rc2`（bugfix，仅递增 rc 号）。

## [2.1.0-rc1] - 2026-06-21

竞品调研驱动的首批补齐：补上头部产品（VoiceInk / Superwhisper / TypeWhisper / Wispr Flow）已经把战场推到的两个入场门槛 —— **多触发模式** 与 **术语包**。

### 新增

- **热键触发模式可选**：设置 → 语音输入与快捷键 新增「触发方式」分段控件，提供
  - `按住录音`（Push-to-Talk）：v1 行为，按下即录、松开即停，适合短句。
  - `按一下切换`（Toggle）：按一次开始、再按一次停止，适合长段口述，手指无需一直按住。
  - `混合`（Hybrid）：短按 = 切换；按住超过 0.25 秒 = 按住录音。两种习惯一键兼顾。
  - 实现层引入独立的 `HotkeyTriggerStateMachine`（`fastv/Services/HotkeyTriggerStateMachine.swift`），把"原始按键 press/release"翻译成"有效录音 start/stop"，与 NSEvent 解耦便于单测；FN / Control / 普通键三条按键检测路径统一走 `dispatchRawPress` / `dispatchRawRelease` 分派。
- **术语包（专有名词）**：常错词管理顶部新增「错字纠正 / 术语包」分段；术语条目在替换管线中享受两项特殊待遇：
  - 优先于一般错字纠正生效（`getSortedMistakes` 排序 terminology 在前）；
  - 大小写不敏感匹配（正则使用 `.caseInsensitive`，"open ai" / "OPEN AI" 都能命中 "OpenAI"）。
  - `CorrectionCategory` 增加 `.terminology` 值，`addOrUpdate` 增加 `category` 参数；
  - 5 语种 i18n（en / zh-Hans / ja / ko / yue）。

### 工程

- 版本号从 `2.0.0-rc14` 升至 `2.1.0-rc1`（按用户全局规则，功能新增升次版本）。
- 新增单测 `fastvTests/HotkeyTriggerStateMachineTests.swift`（覆盖三模式状态机）与 `fastvTests/TerminologyCorrectionTests.swift`（覆盖术语优先 + 大小写命中）。

## [2.0.0-rc14] - 2026-06-21

### 改进

- **CTC 去重改为标准保守流程**：启用 CTC 去重时先合并连续重复帧，再移除 blank token，避免过去“先删 blank 再合并”把「谢谢」「我看看」「100」等 blank 分隔的正常重复误压掉；设置页文案同步改为实验性保守去重，并补充单测覆盖叠词与连续数字。

## [2.0.0-rc13] - 2026-06-21

### 改进

- **设置窗口底部移除版本号 footer**：版本号不再显示在设置页底部分隔线上，避免视觉上压线；版本信息保留在「数据与其他」→「关于」弹窗中。

## [2.0.0-rc12] - 2026-06-21

### 改进

- **语音输入法不再提供关闭开关**：设置页移除「启用语音输入法」开关，语音输入作为应用唯一主功能始终启用；历史版本保存过关闭状态的用户升级后也会自动恢复启用，快捷键注册不再受该旧开关影响。

## [2.0.0-rc11] - 2026-06-21

### 改进

- **主窗口默认皮肤改为淡雅雾林**：未设置过界面皮肤的新用户默认进入「淡雅雾林」风格；已手动选择过皮肤的用户保持原选择不变。

## [2.0.0-rc10] - 2026-06-21

### 修复

- **主窗口启动不再被语音模型预加载挡住**：启动时先展示主窗口并完成快捷键初始化，再延后 1.5 秒静默预热 ONNX 语音模型；移除启动阶段覆盖主窗口的模型预加载展示层。
- **降低启动预热资源优先级**：启动预加载从 `.userInitiated` 降为 `.utility`，减少 894MB 模型加载对首屏响应的抢占；按下语音快捷键时仍保留即时预热路径。

## [2.0.0-rc9] - 2026-06-21

### 新增

- **主窗口界面皮肤**：设置 → 通用新增「界面皮肤」卡片选择器，提供系统默认、淡雅雾林、水墨宣纸、科幻光栅、午夜岩蓝、极光暗夜、熔火石墨 7 套风格；主窗口背景、输入区、统计卡片、历史列表会即时跟随切换。
- **深色皮肤浅色文字体系**：科幻光栅、午夜岩蓝、极光暗夜、熔火石墨使用专门的浅色标题 / 正文 / 辅助文字 token，暗色背景下保持可读对比；界面皮肤文案补齐中 / 英 / 日 / 韩 / 粤 5 语言。

## [2.0.0-rc8] - 2026-06-18

### 清理

- **工程身份收尾到 musetype**：Xcode app target、共享 scheme、test plan、CocoaPods target、测试宿主路径、`PRODUCT_NAME`、构建/打包脚本产物名统一从 `row1` 迁到 `musetype`，编译产物改为 `musetype.app` / `musetype.dmg`。
- **Bundle ID 与测试导入同步**：主 app Bundle ID 改为 `com.17push.musetype`，`fastvTests` 的 `@testable import` 改为 `musetype`，避免新模块名下单测继续找旧模块。

## [2.0.0-rc7] - 2026-06-18

### 回滚

- **回滚 rc6 的 ONNX IntraOp=1 实验**：用户决定不实测直接回滚。`ONNXRuntimeWrapper.swift` 的 `numThreads` 恢复为 `max(4, ProcessInfo.processInfo.activeProcessorCount)`，删掉 `intraOpNumThreads` 常量。rc5 关掉的「二次拼接转写」保留（那条不影响单段推理速度）。

## [2.0.0-rc6] - 2026-06-18

### 改进

- **实验：ONNX IntraOp 线程数砍到 1**：用户假设「多个 ONNX 推理互抢线程导致识别慢」，让 `SetIntraOpNumThreads` 从 `max(4, activeProcessorCount)` 改为 `1`，作为 A/B 对照。注意 IntraOp 控制的是「单次推理内部的多核并行」，不是 session 并发；理论上设为 1 会让单次推理变慢数倍。常量提到 `ONNXRuntimeWrapper.intraOpNumThreads` 顶部，方便实测后一行回滚。

## [2.0.0-rc5] - 2026-06-18

### 改进

- **关掉「二次拼接转写」，AI 模式响应更快**：原机制（[fastvApp.swift:163-213](fastv/fastvApp.swift:163)）在 AI 快捷键模式下会把多段音频合并后再跑一遍 ONNX，目的是「长音频准确率更高」，松键时若已完成则替换零碎结果。代价是 AI 模式录音期间持续抢 ONNX session，让前台分段转写变慢；而 AI 模式下文本侧已有 AI Polish 兜底，二次 ASR 的边际收益很小。新增 `enableBatchRefinementTranscription` 编译期开关（默认 `false`），`performIncrementalSegmentTranscription` 的 `else if` 分支被 short-circuit；`scheduleBatchRefinementTranscription` / `runBatchRefinementTranscription` / `partitionSegmentsForBatchRefinement` 代码保留，方便后续 A/B 或回滚。普通快捷键路径本来就走实时插入分支，不受影响。

## [2.0.0-rc4] - 2026-06-18

### 改进

- **主窗口拍扁，去掉左右分栏**：妙打 v2.0 后只剩「语音输入」一个一级入口，左侧 160pt 的功能侧栏（含「功能」标题、`SidebarItem` 列表、`SidebarItemRow` 选中竖条）完全成了视觉负担。`ContentView` 直接渲染 `VoiceInputView`，齿轮按钮与设置 sheet 上提到根视图。删掉 `SidebarItem` / `SidebarItemRow` 及 `HSplitView` 结构，主窗口 minSize 从 720×520 收到 560×520，给纯语音工具应有的窄长身段。

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
