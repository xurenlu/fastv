//
//  GeneralTab.swift
//  fastv
//
//  设置 - 常用：隐私说明、Dock 图标、界面语言。
//

import SwiftUI

struct GeneralTab: View {
    @ObservedObject var preferences = UserPreferences.shared

    var body: some View {
        Form {
            Section {
                // 隐私锚点：让用户在每天最常去的设置入口也能看到「本地处理」承诺。
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                    Text(NSLocalizedString("settings.privacy.local.processing", comment: ""))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                Toggle(NSLocalizedString("hide.dock.icon", comment: ""), isOn: $preferences.hideDockIcon)
                Text(NSLocalizedString("hide.dock.icon.description", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(NSLocalizedString("settings.section.general", comment: ""))
            }

            // 界面语言
            Section {
                Picker(NSLocalizedString("default.language", comment: ""), selection: Binding(
                    get: { preferences.defaultLanguage },
                    set: { newValue in
                        preferences.defaultLanguage = newValue
                        LocalizationManager.shared.currentLanguage = newValue
                    }
                )) {
                    ForEach(SupportedLanguage.allCases, id: \.self) { language in
                        Text(language.nativeName).tag(language.rawValue)
                    }
                }
            } header: {
                Text(NSLocalizedString("language", comment: ""))
            } footer: {
                Text(NSLocalizedString("language.description", comment: ""))
            }
        }
        .formStyle(.grouped)
    }
}
