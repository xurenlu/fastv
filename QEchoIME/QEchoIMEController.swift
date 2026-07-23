//
//  QEchoIMEController.swift
//  QEchoIME
//
//  IMKit 输入控制器：把键盘事件喂给 librime（wubi_pinyin 五笔·拼音混打），
//  维护组字区 marked text 与系统候选窗，并承接语音上屏通道。
//

import Cocoa
import InputMethodKit

/// 进程级共享面板（由 main.swift 在启动时创建）
enum QEchoPanels {
    static var candidates: IMKCandidates?
}

@objc(QEchoIMEController)
final class QEchoIMEController: IMKInputController {

    private static let notFoundRange = NSRange(location: NSNotFound, length: NSNotFound)

    private var lastModifiers: NSEvent.ModifierFlags = []

    // MARK: - 生命周期

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        RimeEngine.shared.startIfNeeded()
        VoiceCommitServer.shared.register(activeController: self)
    }

    override func deactivateServer(_ sender: Any!) {
        // 焦点离开：把未完成的原始输入串上屏，避免内容凭空消失
        if let client = sender as? IMKTextInput & NSObjectProtocol {
            flushRawInput(to: client)
        }
        QEchoPanels.candidates?.hide()
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
            handleFlagsChanged(event)
            syncState(with: client)
            return false
        case .keyDown:
            guard !event.modifierFlags.contains(.command) else { return false }
            let flags = event.modifierFlags
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
            let handled = engine.processKey(keysym: keysym, modifiers: mask)
            syncState(with: client)
            return handled
        default:
            return false
        }
    }

    /// Shift 抬起切中英文（由 Rime ascii_composer 决定行为），只透传按下/抬起事件
    private func handleFlagsChanged(_ event: NSEvent) {
        let previous = lastModifiers
        let current = event.modifierFlags
        lastModifiers = current
        let shiftWas = previous.contains(.shift)
        let shiftNow = current.contains(.shift)
        guard shiftWas != shiftNow else { return }
        if shiftNow {
            _ = RimeEngine.shared.processKey(keysym: RimeKeyMapping.XK_Shift_L, modifiers: 0)
        } else {
            _ = RimeEngine.shared.processKey(
                keysym: RimeKeyMapping.XK_Shift_L,
                modifiers: RimeKeyMapping.shiftMask | RimeKeyMapping.releaseMask
            )
        }
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
            QEchoPanels.candidates?.hide()
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

        if let panel = QEchoPanels.candidates, !(state?.candidates.isEmpty ?? true) {
            panel.update()
            panel.show()
        } else {
            QEchoPanels.candidates?.hide()
        }
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

    // MARK: - IMKCandidates 数据源

    override func candidates(_ sender: Any!) -> [Any]! {
        RimeEngine.shared.snapshot()?.candidates.map { candidate in
            candidate.comment.isEmpty ? candidate.text : "\(candidate.text) \(candidate.comment)"
        } ?? []
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let selected = candidateString?.string,
              let state = RimeEngine.shared.snapshot() else { return }
        let index = state.candidates.firstIndex { candidate in
            selected == candidate.text
                || selected == "\(candidate.text) \(candidate.comment)"
        }
        guard let index, RimeEngine.shared.selectCandidate(onCurrentPage: index) else { return }
        if let client = client() {
            syncState(with: client)
        }
    }

    // MARK: - 系统要求提交（焦点切换 / 应用主动 commit）

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput & NSObjectProtocol else { return }
        flushRawInput(to: client)
        QEchoPanels.candidates?.hide()
    }

    // MARK: - 语音上屏（VoiceCommitServer 调用）

    /// 语音文本上屏：先落掉进行中的组字，避免 marked text 与插入内容交错
    func commitVoiceText(_ text: String) -> Bool {
        guard let client = client() else { return false }
        if RimeEngine.shared.ready, RimeEngine.shared.isComposing {
            RimeEngine.shared.clearComposition()
            clearMarkedText(of: client)
            QEchoPanels.candidates?.hide()
        }
        client.insertText(text, replacementRange: Self.notFoundRange)
        return true
    }
}
