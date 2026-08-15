//
//  QEchoIMEController.swift
//  QechoIME
//
//  IMKit 输入控制器：把键盘事件喂给 librime（wubi_pinyin 五笔·拼音混打），
//  维护组字区 marked text 与自绘候选窗，并承接语音上屏通道。
//

import Cocoa
import InputMethodKit

/// 进程级共享面板（由 main.swift 在启动时创建）
enum QechoPanels {
    static var candidateWindow: CandidateWindow?
}

@objc(QechoIMEController)
final class QechoIMEController: IMKInputController {

    private static let notFoundRange = NSRange(location: NSNotFound, length: NSNotFound)

    private var lastModifiers: NSEvent.ModifierFlags = []
    private var shiftUsedAsModifier = false

    // MARK: - 生命周期

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        RimeEngine.shared.startIfNeeded()
        IMESettingsCoordinator.shared.applyIfNeeded()
        lastModifiers = []
        shiftUsedAsModifier = false
        VoiceCommitServer.shared.register(activeController: self)
        // 候选窗点击选字回调绑定到当前 controller
        QechoPanels.candidateWindow?.onSelect = { [weak self] index in
            self?.selectCandidateByClick(index)
        }
    }

    override func deactivateServer(_ sender: Any!) {
        // 焦点离开：把未完成的原始输入串上屏，避免内容凭空消失
        if let client = sender as? IMKTextInput & NSObjectProtocol {
            flushRawInput(to: client)
        }
        CandidateLearningStore.shared.flush()
        QechoPanels.candidateWindow?.hide()
        VoiceCommitServer.shared.unregister(controller: self)
        super.deactivateServer(sender)
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    // MARK: - 按键处理

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput & NSObjectProtocol else { return false }
        let engine = RimeEngine.shared
        engine.startIfNeeded()
        guard engine.ready else { return false } // 引擎不可用时英文直通

        switch event.type {
        case .flagsChanged:
            let handled = handleFlagsChanged(event, client: client)
            syncState(with: client)
            return handled
        case .keyDown:
            let flags = event.modifierFlags
            if flags.contains(.shift) {
                shiftUsedAsModifier = true
            }
            guard !flags.contains(.command) else { return false }
            let characters = flags.contains(.control)
                ? event.charactersIgnoringModifiers
                : event.characters
            guard let keysym = RimeKeyMapping.keysym(macKeyCode: event.keyCode, characters: characters) else {
                return false
            }
            let mask = RimeKeyMapping.modifierMask(
                shift: flags.contains(.shift),
                control: flags.contains(.control),
                option: flags.contains(.option),
                command: false,
                capsLock: flags.contains(.capsLock)
            )
            let candidateState = engine.snapshot()
            let rawInput = engine.rawInput()
            let handled = engine.processKey(keysym: keysym, modifiers: mask)
            if handled,
               let candidateState,
               let selectedIndex = RimeKeyMapping.selectedCandidateIndex(
                    for: keysym,
                    highlightedIndex: candidateState.highlightedIndex,
                    candidateCount: candidateState.candidates.count,
                    apostropheSelectsThird: engine.currentSchemaId() == IMESchema.wubi.rawValue
               ) {
                recordCandidateSelection(
                    state: candidateState,
                    rawInput: rawInput,
                    selectedIndex: selectedIndex,
                    source: .keyboard
                )
            }
            syncState(with: client)
            return handled
        default:
            return false
        }
    }

    /// 独立 Shift：有汉字候选时上屏原始英文且保持中文；否则交给 Rime 切中英文。
    private func handleFlagsChanged(
        _ event: NSEvent,
        client: IMKTextInput & NSObjectProtocol
    ) -> Bool {
        let previous = lastModifiers
        let current = event.modifierFlags
        lastModifiers = current
        let shiftWas = previous.contains(.shift)
        let shiftNow = current.contains(.shift)
        guard shiftWas != shiftNow else { return false }
        if shiftNow {
            shiftUsedAsModifier = false
            return false
        }

        defer { shiftUsedAsModifier = false }
        guard !shiftUsedAsModifier else { return false }

        let engine = RimeEngine.shared
        let candidates = engine.snapshot()?.candidates.map(\.text) ?? []
        if RimeKeyMapping.shouldCommitRawInputOnStandaloneShift(
            isASCIIMode: engine.option("ascii_mode"),
            candidates: candidates
        ) {
            guard let rawInput = engine.takeRawInput(), !rawInput.isEmpty else { return false }
            client.insertText(rawInput, replacementRange: Self.notFoundRange)
            return true
        }

        _ = engine.processKey(keysym: RimeKeyMapping.XK_Shift_L, modifiers: 0)
        _ = engine.processKey(
            keysym: RimeKeyMapping.XK_Shift_L,
            modifiers: RimeKeyMapping.shiftMask | RimeKeyMapping.releaseMask
        )
        return false
    }

    // MARK: - 状态同步（上屏 + 组字区 + 候选窗）

    private func syncState(with client: IMKTextInput & NSObjectProtocol) {
        let engine = RimeEngine.shared
        if let commit = engine.consumeCommit(), !commit.isEmpty {
            client.insertText(commit, replacementRange: Self.notFoundRange)
        }

        let state = engine.snapshot()
        let preedit = state?.preedit ?? ""
        guard !preedit.isEmpty else {
            clearMarkedText(of: client)
            QechoPanels.candidateWindow?.hide()
            return
        }

        let marked = NSAttributedString(
            string: preedit,
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
        )
        let cursor = RimeKeyMapping.utf16Offset(fromUTF8Offset: state?.cursorUTF8 ?? 0, in: preedit)
        client.setMarkedText(
            marked,
            selectionRange: NSRange(location: cursor, length: 0),
            replacementRange: Self.notFoundRange
        )

        updateCandidateWindow(state: state, client: client)
    }

    /// 用自绘候选窗渲染当前候选，跟随组字光标定位
    private func updateCandidateWindow(
        state: RimeEngine.CompositionState?,
        client: IMKTextInput & NSObjectProtocol
    ) {
        guard let window = QechoPanels.candidateWindow else { return }
        guard let state, !state.candidates.isEmpty else {
            window.hide()
            return
        }
        let items = state.candidates.map { CandidateItem(text: $0.text, comment: $0.comment) }
        window.update(
            items: items,
            highlightedIndex: state.highlightedIndex,
            appearance: IMESettingsCoordinator.shared.currentAppearance,
            near: caretScreenRect(client: client)
        )
    }

    /// 取组字区首字符的屏幕矩形；宿主不支持时回退鼠标位置
    private func caretScreenRect(client: IMKTextInput & NSObjectProtocol) -> NSRect {
        var lineRect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        if lineRect.width > 0 || lineRect.height > 0 {
            return lineRect
        }
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x, y: mouse.y, width: 1, height: 16)
    }

    /// 候选窗点击选字：当前页内序号 index
    private func selectCandidateByClick(_ index: Int) {
        let engine = RimeEngine.shared
        let candidateState = engine.snapshot()
        let rawInput = engine.rawInput()
        guard engine.selectCandidate(onCurrentPage: index) else { return }
        if let candidateState {
            recordCandidateSelection(
                state: candidateState,
                rawInput: rawInput,
                selectedIndex: index,
                source: .mouse
            )
        }
        if let client = client() {
            syncState(with: client)
        }
    }

    private func recordCandidateSelection(
        state: RimeEngine.CompositionState,
        rawInput: String,
        selectedIndex: Int,
        source: CandidateSelectionSource
    ) {
        guard state.candidates.indices.contains(selectedIndex) else { return }
        CandidateLearningStore.shared.recordSelection(
            schemaId: RimeEngine.shared.currentSchemaId() ?? IMESchema.mixed.rawValue,
            inputCode: rawInput,
            candidates: state.candidates.map(\.text),
            selectedIndex: selectedIndex,
            pageNumber: state.pageNumber,
            dynamicRankingEnabled: IMESettingsCoordinator.shared.currentUserDictEnabled,
            source: source
        )
    }

    private func clearMarkedText(of client: IMKTextInput & NSObjectProtocol) {
        client.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: Self.notFoundRange
        )
    }

    private func flushRawInput(to client: IMKTextInput & NSObjectProtocol) {
        if let raw = RimeEngine.shared.takeRawInput(), !raw.isEmpty {
            client.insertText(raw, replacementRange: Self.notFoundRange)
        }
        clearMarkedText(of: client)
    }

    // MARK: - 系统要求提交（焦点切换 / 应用主动 commit）

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput & NSObjectProtocol else { return }
        flushRawInput(to: client)
        QechoPanels.candidateWindow?.hide()
    }

    // MARK: - 输入法菜单（菜单栏输入源下拉，结构参考主流中文输入法）

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "Qecho")

        let settingsItem = NSMenuItem(
            title: Self.localized("ime.menu.openSettings"),
            action: #selector(openMainAppSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let currentSchema = RimeEngine.shared.currentSchemaId()
        for schema in IMESchema.allCases {
            let item = NSMenuItem(
                title: Self.localized(schema.displayNameKey),
                action: #selector(selectSchemaFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = schema.rawValue
            item.state = schema.rawValue == currentSchema ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let asciiOn = RimeEngine.shared.option("ascii_mode")
        let asciiItem = NSMenuItem(
            title: Self.localized(asciiOn ? "ime.menu.switchToChinese" : "ime.menu.switchToEnglish"),
            action: #selector(toggleAsciiMode(_:)),
            keyEquivalent: ""
        )
        asciiItem.target = self
        menu.addItem(asciiItem)

        let fullShapeItem = NSMenuItem(
            title: Self.localized("ime.menu.fullShape"),
            action: #selector(toggleFullShape(_:)),
            keyEquivalent: ""
        )
        fullShapeItem.target = self
        fullShapeItem.state = RimeEngine.shared.option("full_shape") ? .on : .off
        menu.addItem(fullShapeItem)

        return menu
    }

    @objc private func openMainAppSettings(_ sender: Any?) {
        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(
            withBundleIdentifier: InputMethodBridgeContract.mainAppBundleID
        ) {
            workspace.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
        let post = {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(InputMethodBridgeContract.openSettingsDistributedNotification),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
        post()
        // 主 App 冷启动时首个通知可能赶不上观察者注册，延迟补发一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: post)
    }

    @objc private func selectSchemaFromMenu(_ sender: Any?) {
        guard let rawValue = Self.menuItem(from: sender)?.representedObject as? String,
              let schema = IMESchema(rawValue: rawValue) else { return }
        IMESettingsCoordinator.shared.schemaChangedFromMenu(schema)
        if let client = client() {
            syncState(with: client)
        }
    }

    @objc private func toggleAsciiMode(_ sender: Any?) {
        let engine = RimeEngine.shared
        engine.setOption("ascii_mode", value: !engine.option("ascii_mode"))
    }

    @objc private func toggleFullShape(_ sender: Any?) {
        let engine = RimeEngine.shared
        engine.setOption("full_shape", value: !engine.option("full_shape"))
    }

    /// IMKit 菜单动作的 sender 可能是 NSMenuItem，也可能是带 IMKCommandMenuItem 的字典
    private static func menuItem(from sender: Any?) -> NSMenuItem? {
        if let item = sender as? NSMenuItem {
            return item
        }
        if let info = sender as? [String: Any] {
            return info["IMKCommandMenuItem"] as? NSMenuItem
        }
        return nil
    }

    private static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    // MARK: - 语音上屏（VoiceCommitServer 调用）

    /// 语音文本上屏：先落掉进行中的组字，避免 marked text 与插入内容交错
    func commitVoiceText(_ text: String) -> Bool {
        guard let client = client() else { return false }
        if RimeEngine.shared.ready, RimeEngine.shared.isComposing {
            RimeEngine.shared.clearComposition()
            clearMarkedText(of: client)
            QechoPanels.candidateWindow?.hide()
        }
        client.insertText(text, replacementRange: Self.notFoundRange)
        return true
    }
}
