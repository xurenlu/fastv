//
//  InputMethodSettingsSection.swift
//  fastv
//
//  「输入法（实验性）」设置区块：安装 / 启用 QechoIME 系统输入法。
//

import SwiftUI

struct InputMethodSettingsSection: View {
    @ObservedObject private var installer = InputMethodInstaller.shared
    @ObservedObject private var imeSettings = InputMethodSettingsStore.shared

    var body: some View {
        Section {
            HStack {
                Text(NSLocalizedString("ime.status.label", comment: ""))
                Spacer()
                Text(statusText)
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 8) {
                Button(buttonTitle) {
                    installer.installAndEnable()
                }
                .disabled(installer.state == .embeddedMissing)

                Button(NSLocalizedString("ime.refresh", comment: "")) {
                    installer.refresh()
                    imeSettings.reload()
                }
            }

            if let error = installer.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text(NSLocalizedString("ime.shortcuts.hint", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(NSLocalizedString("ime.section", comment: ""))
        } footer: {
            Text(NSLocalizedString("ime.hint", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            imeSettings.reload()
        }
    }

    private var statusText: String {
        switch installer.state {
        case .embeddedMissing:
            return NSLocalizedString("ime.status.embeddedMissing", comment: "")
        case .notInstalled:
            return NSLocalizedString("ime.status.notInstalled", comment: "")
        case .installedDisabled:
            return NSLocalizedString("ime.status.installedDisabled", comment: "")
        case .enabled:
            return NSLocalizedString("ime.status.enabled", comment: "")
        }
    }

    private var statusColor: Color {
        switch installer.state {
        case .enabled:
            return .green
        case .installedDisabled:
            return .orange
        case .notInstalled, .embeddedMissing:
            return .secondary
        }
    }

    private var buttonTitle: String {
        switch installer.state {
        case .notInstalled, .embeddedMissing:
            return NSLocalizedString("ime.install.button", comment: "")
        case .installedDisabled, .enabled:
            return NSLocalizedString("ime.reinstall.button", comment: "")
        }
    }
}
