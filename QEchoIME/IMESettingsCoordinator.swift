//
//  IMESettingsCoordinator.swift
//  QEchoIME
//
//  IME 侧设置协调：读取 IME 用户目录的设置文件并应用到 RimeEngine。
//  设置文件由主 App（设置页）写入并经 CFMessagePort 通知；
//  输入法菜单切方案时本进程也会回写，保持两侧一致。
//  所有调用都在主 RunLoop。
//

import Foundation

final class IMESettingsCoordinator {
    static let shared = IMESettingsCoordinator()

    /// 最近一次已应用到引擎的设置；nil 表示进程尚未应用过
    private var applied: IMESettings?

    private init() {}

    /// 幂等应用设置：焦点激活与「设置变更」消息都会调用，无变化时零成本返回
    func applyIfNeeded() {
        let engine = RimeEngine.shared
        engine.startIfNeeded()
        guard engine.ready else { return }

        let settings = IMESettings.load()
        guard settings != applied else { return }

        // 词频开关落在 *.custom.yaml（主 App 通知前已重写），需要整体重启让 Rime 重新部署
        if let applied, applied.enableUserDict != settings.enableUserDict {
            engine.restartForConfigChange()
        }
        if engine.currentSchemaId() != settings.schemaId {
            engine.selectSchema(settings.schemaId)
        }
        applied = settings
    }

    /// 输入法菜单里切了方案：应用并回写设置文件
    func schemaChangedFromMenu(_ schema: IMESchema) {
        RimeEngine.shared.selectSchema(schema.rawValue)
        var settings = IMESettings.load()
        settings.schemaId = schema.rawValue
        do {
            try settings.write()
        } catch {
            NSLog("QEchoIME: 设置文件写入失败 \(error.localizedDescription)")
        }
        applied = settings
    }
}
