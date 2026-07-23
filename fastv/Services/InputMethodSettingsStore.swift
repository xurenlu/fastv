//
//  InputMethodSettingsStore.swift
//  fastv
//
//  主 App 侧的 IME 设置管理：读写 IME 用户目录的设置文件与 Rime custom 补丁，
//  变更后经 CFMessagePort 通知输入法进程即时生效（未运行则下次拉起时生效）。
//

import Combine
import Foundation

@MainActor
final class InputMethodSettingsStore: ObservableObject {
    static let shared = InputMethodSettingsStore()

    @Published private(set) var settings: IMESettings

    private init() {
        settings = IMESettings.load()
    }

    /// 设置页出现时刷新（输入法菜单可能改过方案）
    func reload() {
        settings = IMESettings.load()
    }

    func setSchema(_ schema: IMESchema) {
        var updated = settings
        updated.schemaId = schema.rawValue
        persist(updated)
    }

    func setUserDictEnabled(_ enabled: Bool) {
        var updated = settings
        updated.enableUserDict = enabled
        persist(updated)
    }

    /// 候选窗外观整体更新（设置面板绑定用）
    func setAppearance(_ appearance: CandidateAppearance) {
        var updated = settings
        updated.candidateAppearance = appearance
        persist(updated)
    }

    /// 恢复候选窗外观默认值
    func resetAppearance() {
        setAppearance(.default)
    }

    /// 每页候选个数（5~9）
    func setPageSize(_ size: Int) {
        var updated = settings
        updated.candidatePageSize = min(max(size, IMESettings.pageSizeRange.lowerBound),
                                        IMESettings.pageSizeRange.upperBound)
        persist(updated)
    }

    private func persist(_ updated: IMESettings) {
        guard updated != settings else { return }
        // 词频开关或候选个数变化都要重写 custom 补丁并触发 Rime 重部署（外观/方案变更不涉及）
        let patchChanged = updated.enableUserDict != settings.enableUserDict
            || updated.pageSize != settings.pageSize
        do {
            // 先写补丁再写设置文件：IME 收到通知重启部署时补丁必须已就位
            if patchChanged {
                try writeCustomPatches(enableUserDict: updated.enableUserDict, pageSize: updated.pageSize)
            }
            try updated.write()
        } catch {
            print("⚠️ [InputMethodSettings] 设置写入失败: \(error.localizedDescription)")
            return
        }
        settings = updated
        InputMethodBridgeService.shared.notifySettingsChanged()
    }

    private func writeCustomPatches(enableUserDict: Bool, pageSize: Int) throws {
        let directory = InputMethodBridgeContract.imeUserDataDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (fileName, content) in RimePatchGenerator.userCustomFiles(
            enableUserDict: enableUserDict, pageSize: pageSize
        ) {
            try content.write(
                to: directory.appendingPathComponent(fileName),
                atomically: true,
                encoding: .utf8
            )
        }
    }
}
