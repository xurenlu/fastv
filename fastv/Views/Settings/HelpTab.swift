//
//  HelpTab.swift
//  fastv
//
//  设置 - 帮助：输入法快捷键表、语音输入指南、安装排障、常见问题。
//  内容与实际实现保持一致；文案走 i18n。
//

import SwiftUI

struct HelpTab: View {
    var body: some View {
        Form {
            shortcutsSection
            voiceGuideSection
            troubleshootSection
            faqSection
            updateSection
            aboutLinkSection
        }
        .formStyle(.grouped)
    }

    // MARK: - 输入法快捷键表

    private var shortcutsSection: some View {
        Section {
            ShortcutRow(keys: "1 – 9", descKey: "help.sc.digits")
            ShortcutRow(keys: "Space", descKey: "help.sc.space")
            ShortcutRow(keys: ";", descKey: "help.sc.semicolon")
            ShortcutRow(keys: "'", descKey: "help.sc.apostrophe")
            ShortcutRow(keys: "-  /  ,", descKey: "help.sc.pageUp")
            ShortcutRow(keys: "=  /  .", descKey: "help.sc.pageDown")
            ShortcutRow(keys: "↑ ↓", descKey: "help.sc.arrows")
            ShortcutRow(keys: "Tab", descKey: "help.sc.tab")
            ShortcutRow(keys: "Return", descKey: "help.sc.return")
            ShortcutRow(keys: "Esc", descKey: "help.sc.esc")
            ShortcutRow(keys: "Shift", descKey: "help.sc.shift")
            ShortcutRow(keys: "`", descKey: "help.sc.backtick")
        } header: {
            Text(NSLocalizedString("help.section.shortcuts", comment: ""))
        } footer: {
            Text(NSLocalizedString("help.shortcuts.footer", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 语音输入指南

    private var voiceGuideSection: some View {
        Section {
            HelpParagraph(titleKey: "help.voice.keys.title", bodyKey: "help.voice.keys.body")
            HelpParagraph(titleKey: "help.voice.trigger.title", bodyKey: "help.voice.trigger.body")
            HelpParagraph(titleKey: "help.voice.ai.title", bodyKey: "help.voice.ai.body")
            HelpParagraph(titleKey: "help.voice.terms.title", bodyKey: "help.voice.terms.body")
            HelpParagraph(titleKey: "help.voice.power.title", bodyKey: "help.voice.power.body")
        } header: {
            Text(NSLocalizedString("help.section.voice", comment: ""))
        }
    }

    // MARK: - 输入法安装 / 排障

    private var troubleshootSection: some View {
        Section {
            HelpParagraph(titleKey: "help.install.steps.title", bodyKey: "help.install.steps.body")
            HelpParagraph(titleKey: "help.install.notShown.title", bodyKey: "help.install.notShown.body")
            HelpParagraph(titleKey: "help.install.icon.title", bodyKey: "help.install.icon.body")
            HelpParagraph(titleKey: "help.install.schemes.title", bodyKey: "help.install.schemes.body")
        } header: {
            Text(NSLocalizedString("help.section.install", comment: ""))
        }
    }

    // MARK: - 常见问题

    private var faqSection: some View {
        Section {
            HelpParagraph(titleKey: "help.faq.password.title", bodyKey: "help.faq.password.body")
            HelpParagraph(titleKey: "help.faq.privacy.title", bodyKey: "help.faq.privacy.body")
            HelpParagraph(titleKey: "help.faq.permission.title", bodyKey: "help.faq.permission.body")
            HelpParagraph(titleKey: "help.faq.relogin.title", bodyKey: "help.faq.relogin.body")
            HelpParagraph(titleKey: "help.faq.voiceVsType.title", bodyKey: "help.faq.voiceVsType.body")
        } header: {
            Text(NSLocalizedString("help.section.faq", comment: ""))
        }
    }

    // MARK: - 版本与更新

    private var updateSection: some View {
        Section {
            HStack {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(NSLocalizedString("help.update.current", comment: ""))
                Spacer()
                Text(appVersionText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                SomeIMUpdateController.shared.checkForUpdates()
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
                    Text(NSLocalizedString("help.update.check", comment: ""))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text(NSLocalizedString("help.section.update", comment: ""))
        }
    }

    private var appVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "v\(short) (\(build))"
    }

    // MARK: - 支持链接

    private var aboutLinkSection: some View {
        Section {
            Link(destination: URL(string: "https://83d.me/products/qecho")!) {
                HStack {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.blue)
                    Text(NSLocalizedString("support.official.page", comment: ""))
                    Spacer()
                    Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(.secondary)
                }
            }
            Link(destination: URL(string: "https://83d.me")!) {
                HStack {
                    Image(systemName: "link").foregroundStyle(.blue)
                    Text(NSLocalizedString("about.author_homepage", comment: ""))
                    Spacer()
                    Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(NSLocalizedString("help.section.more", comment: ""))
        }
    }
}

// MARK: - 复用小组件

/// 快捷键表格行：左侧按键、右侧说明
private struct ShortcutRow: View {
    let keys: String
    let descKey: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(keys)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .frame(width: 84, alignment: .leading)
                .foregroundStyle(.primary)
            Text(NSLocalizedString(descKey, comment: ""))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }
}

/// 帮助段落：小标题 + 正文
private struct HelpParagraph: View {
    let titleKey: String
    let bodyKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString(titleKey, comment: ""))
                .font(.callout.weight(.semibold))
            Text(NSLocalizedString(bodyKey, comment: ""))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    HelpTab()
}
