//
//  main.swift
//  QechoIME
//
//  轻语输入法进程入口：注册 IMKServer 并启动语音上屏监听。
//  本进程由系统在用户选中输入源时拉起，保持轻量，不加载语音模型。
//

import Cocoa
import InputMethodKit

guard let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
      let bundleIdentifier = Bundle.main.bundleIdentifier else {
    // 输入法进程缺少连接配置属于打包错误，无法恢复
    fatalError("QechoIME: Info.plist 缺少 InputMethodConnectionName 或 bundle identifier")
}

// IMKServer 必须持有到进程退出，系统经它路由键盘事件
let server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier)
guard let server else {
    fatalError("QechoIME: IMKServer 创建失败（连接名 \(connectionName)）")
}

// 自绘候选窗（替代系统 IMKCandidates），支持横/竖排、配色、字体、序号等外观定制
QechoPanels.candidateWindow = CandidateWindow()

VoiceCommitServer.shared.start()

NSApplication.shared.run()
