//
//  QEchoIMEController.swift
//  QEchoIME
//
//  IMKit 输入控制器。当前阶段为「薄壳」：
//  - 打字直通（行为等同 ABC 键盘），拼音·五笔混打在 librime 接入阶段实现
//  - 维护「当前活跃 client」注册，供语音上屏通道使用
//

import Cocoa
import InputMethodKit

@objc(QEchoIMEController)
final class QEchoIMEController: IMKInputController {

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        VoiceCommitServer.shared.register(activeController: self)
    }

    override func deactivateServer(_ sender: Any!) {
        VoiceCommitServer.shared.unregister(controller: self)
        super.deactivateServer(sender)
    }

    /// 返回 false 让 IMK 把按键原样交给宿主应用（英文直通）。
    /// librime 接入后，这里改为把按键喂给引擎并维护组字区 / 候选窗。
    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        return false
    }
}
