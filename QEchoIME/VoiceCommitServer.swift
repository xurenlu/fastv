//
//  VoiceCommitServer.swift
//  QEchoIME
//
//  接收主 App（轻语）经 CFMessagePort 发来的语音转写文本，
//  通过当前活跃的 IMK client 走系统输入法通道上屏（IMKTextInput.insertText）。
//  端口回调跑在主 RunLoop，无需额外加锁。
//

import Cocoa
import InputMethodKit

final class VoiceCommitServer {
    static let shared = VoiceCommitServer()

    private var port: CFMessagePort?
    private var runLoopSource: CFRunLoopSource?
    private weak var activeController: IMKInputController?

    private init() {}

    // MARK: - 活跃 client 注册（由 QEchoIMEController 在焦点切换时调用）

    func register(activeController controller: IMKInputController) {
        activeController = controller
    }

    func unregister(controller: IMKInputController) {
        if activeController === controller {
            activeController = nil
        }
    }

    // MARK: - CFMessagePort 服务端

    func start() {
        guard port == nil else { return }

        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: CFMessagePortCallBack = { _, _, data, info in
            guard let info else { return nil }
            let server = Unmanaged<VoiceCommitServer>.fromOpaque(info).takeUnretainedValue()
            let reply = server.handleMessage(data as Data?)
            guard let replyData = try? reply.encoded() else { return nil }
            return Unmanaged.passRetained(replyData as CFData)
        }

        guard let localPort = CFMessagePortCreateLocal(
            kCFAllocatorDefault,
            InputMethodBridgeContract.voiceCommitPortName as CFString,
            callback,
            &context,
            nil
        ) else {
            NSLog("QEchoIME: 语音上屏端口创建失败（端口名可能被其他进程占用）")
            return
        }

        port = localPort
        let source = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, localPort, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func handleMessage(_ data: Data?) -> VoiceCommitReply {
        guard let data else {
            return VoiceCommitReply(ok: false, reason: "empty-request")
        }
        let payload: VoiceCommitPayload
        do {
            payload = try VoiceCommitPayload.decode(data)
        } catch {
            // reason 只带错误类别，不回传用户文本
            return VoiceCommitReply(ok: false, reason: "decode-failed")
        }
        guard let controller = activeController, let client = controller.client() else {
            return VoiceCommitReply(ok: false, reason: "no-active-client")
        }
        client.insertText(
            payload.text,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
        return VoiceCommitReply(ok: true, reason: nil)
    }
}
