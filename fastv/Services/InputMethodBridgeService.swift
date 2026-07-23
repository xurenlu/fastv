//
//  InputMethodBridgeService.swift
//  fastv
//
//  语音文本经系统输入法通道上屏：当用户当前选中的输入源是轻语输入法（QEchoIME）时，
//  把转写文本经 CFMessagePort 发给输入法进程，由 IMKTextInput.insertText 提交，
//  比 CGEvent 模拟按键 / 剪贴板粘贴更可靠。发送失败时调用方回退传统插入方式。
//

import Foundation
import Carbon

final class InputMethodBridgeService {
    static let shared = InputMethodBridgeService()

    /// 等待 IME 回执的超时（秒）。IME 侧 insertText 是同步快速操作，0.5s 足够。
    private static let sendTimeout: CFTimeInterval = 0.5

    private init() {}

    /// 当前系统选中的键盘输入源是否为轻语输入法
    var isQEchoInputSourceSelected: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return false
        }
        let id = Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
        return InputMethodBridgeContract.isQEchoInputSource(id: id)
    }

    /// 尝试经输入法通道上屏；返回 false 时调用方应回退到 CGEvent / 剪贴板方案
    func commitViaInputMethod(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        guard let remotePort = CFMessagePortCreateRemote(
            kCFAllocatorDefault,
            InputMethodBridgeContract.voiceCommitPortName as CFString
        ) else {
            print("ℹ️ [InputMethodBridge] 输入法进程未在监听，回退传统插入")
            return false
        }
        defer { CFMessagePortInvalidate(remotePort) }

        let requestData: Data
        do {
            requestData = try VoiceCommitPayload(text: text).encoded()
        } catch {
            print("⚠️ [InputMethodBridge] 载荷编码失败: \(error)")
            return false
        }

        var rawReply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            remotePort,
            1,
            requestData as CFData,
            Self.sendTimeout,
            Self.sendTimeout,
            CFRunLoopMode.defaultMode.rawValue,
            &rawReply
        )
        guard status == kCFMessagePortSuccess,
              let replyData = rawReply?.takeRetainedValue() as Data? else {
            print("⚠️ [InputMethodBridge] 发送失败或超时 status=\(status)")
            return false
        }
        guard let reply = try? VoiceCommitReply.decode(replyData) else {
            print("⚠️ [InputMethodBridge] 回执解析失败")
            return false
        }
        if !reply.ok {
            print("⚠️ [InputMethodBridge] 输入法侧未接受上屏: \(reply.reason ?? "unknown")")
        }
        return reply.ok
    }
}
