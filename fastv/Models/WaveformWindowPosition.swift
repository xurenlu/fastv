//
//  WaveformWindowPosition.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

/// 波形窗口位置
enum WaveformWindowPosition: String, CaseIterable {
    case topLeft = "topLeft"
    case topRight = "topRight"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"
    case bottomCenter = "bottomCenter"
    /// 跟随光标（AX 优先取 caret 位置，失败兜底鼠标位置）
    case followCursor = "followCursor"

    /// 显示名称（i18n 键由 QuickSettingsTab 转换；这里保留中文兜底）
    var displayName: String {
        switch self {
        case .topLeft:
            return NSLocalizedString("waveform.position.topLeft", value: "左上角", comment: "")
        case .topRight:
            return NSLocalizedString("waveform.position.topRight", value: "右上角", comment: "")
        case .bottomLeft:
            return NSLocalizedString("waveform.position.bottomLeft", value: "左下角", comment: "")
        case .bottomRight:
            return NSLocalizedString("waveform.position.bottomRight", value: "右下角", comment: "")
        case .bottomCenter:
            return NSLocalizedString("waveform.position.bottomCenter", value: "正中间下方", comment: "")
        case .followCursor:
            return NSLocalizedString("waveform.position.followCursor", value: "跟随光标", comment: "")
        }
    }

    /// 是否为「跟随光标」动态位置（需在 show 后启动跟踪 timer）
    var isFollowingCursor: Bool { self == .followCursor }
}

