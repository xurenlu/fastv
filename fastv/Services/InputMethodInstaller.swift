//
//  InputMethodInstaller.swift
//  fastv
//
//  把随主 App 分发的 QechoIME.app 安装到 ~/Library/Input Methods，
//  并通过 TIS 注册、启用输入源。选中输入源仍由用户在系统输入法菜单完成。
//

import AppKit
import Carbon
import Combine

@MainActor
final class InputMethodInstaller: ObservableObject {
    enum InstallState: Equatable {
        /// 构建产物里没有嵌入 QechoIME.app（打包问题）
        case embeddedMissing
        case notInstalled
        case installedDisabled
        case enabled
    }

    static let shared = InputMethodInstaller()

    @Published private(set) var state: InstallState = .notInstalled
    @Published private(set) var lastError: String?

    private init() {
        refresh()
    }

    var embeddedIMEURL: URL? {
        Bundle.main.url(forResource: "QechoIME", withExtension: "app")
    }

    var installedIMEURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/QechoIME.app", isDirectory: true)
    }

    func refresh() {
        guard embeddedIMEURL != nil else {
            state = .embeddedMissing
            return
        }
        guard FileManager.default.fileExists(atPath: installedIMEURL.path) else {
            state = .notInstalled
            return
        }
        if let source = findInputSource(), isEnabled(source) {
            state = .enabled
        } else {
            state = .installedDisabled
        }
    }

    /// 安装（或更新）并启用输入法。覆盖 ~/Library/Input Methods 里旧版 QechoIME.app 属预期升级行为。
    func installAndEnable() {
        lastError = nil
        guard let embedded = embeddedIMEURL else {
            state = .embeddedMissing
            return
        }
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: installedIMEURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            terminateRunningIME()
            if fileManager.fileExists(atPath: installedIMEURL.path) {
                try fileManager.removeItem(at: installedIMEURL)
            }
            try fileManager.copyItem(at: embedded, to: installedIMEURL)

            let registerStatus = TISRegisterInputSource(installedIMEURL as CFURL)
            guard registerStatus == noErr else {
                throw installError("TISRegisterInputSource", registerStatus)
            }
            guard let source = findInputSource() else {
                throw installError("TISCreateInputSourceList", -1)
            }
            let enableStatus = TISEnableInputSource(source)
            guard enableStatus == noErr else {
                throw installError("TISEnableInputSource", enableStatus)
            }
            refresh()
        } catch {
            lastError = error.localizedDescription
            refresh()
        }
    }

    // MARK: - Private

    private func terminateRunningIME() {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: InputMethodBridgeContract.inputMethodBundleID)
            .forEach { $0.terminate() }
    }

    private func findInputSource() -> TISInputSource? {
        let properties = [
            kTISPropertyInputSourceID as String: InputMethodBridgeContract.inputSourceID
        ] as CFDictionary
        // includeAllInstalled = true：未启用的输入源也要能找到
        guard let unmanagedList = TISCreateInputSourceList(properties, true) else {
            return nil
        }
        let list = unmanagedList.takeRetainedValue() as NSArray
        guard list.count > 0 else { return nil }
        return (list[0] as! TISInputSource)
    }

    private func isEnabled(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    private func installError(_ api: String, _ status: OSStatus) -> NSError {
        NSError(
            domain: "InputMethodInstaller",
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "\(api) failed (status \(status))"]
        )
    }
}
