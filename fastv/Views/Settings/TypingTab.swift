//
//  TypingTab.swift
//  fastv
//
//  设置 - 输入法·打字：系统输入法安装/方案/词频、候选窗外观与候选个数。
//

import SwiftUI

struct TypingTab: View {
    var body: some View {
        Form {
            // 系统输入法（安装 / 方案 / 词频 / 快捷键说明）
            InputMethodSettingsSection()

            // 候选窗外观（预设皮肤 / 候选个数 / 方向 / 字体 / 配色 / 细节）
            CandidateAppearanceView()
        }
        .formStyle(.grouped)
    }
}
