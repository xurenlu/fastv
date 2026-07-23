//
//  RecommendedAppsView.swift
//  fastv
//
//  作者其他 App 的推荐网格，关于窗口与设置页「数据与其他」共用同一份数据与卡片。
//  列表与 museterm 的关于窗对齐（museterm 推荐里的轻语自身不收录），另加 GitWise 与象墨。
//

import SwiftUI

/// 推荐 App 条目（rawValue 用于 i18n key 前缀与图标资源名匹配）
enum RecommendedApp: String, CaseIterable, Identifiable {
    case willDeep
    case timeBill
    case museUploader
    case markReader
    case gitWise
    case veilPic
    case museMail
    case museMate

    var id: String { rawValue }

    var nameKey: String { "about.app.\(rawValue).name" }
    var summaryKey: String { "about.app.\(rawValue).summary" }

    var iconAssetName: String {
        switch self {
        case .willDeep: return "AboutAppWillDeepIcon"
        case .timeBill: return "AboutAppTimeBillIcon"
        case .museUploader: return "AboutAppMuseUploaderIcon"
        case .markReader: return "AboutAppMarkReaderIcon"
        case .gitWise: return "AboutAppGitWiseIcon"
        case .veilPic: return "AboutAppVeilPicIcon"
        case .museMail: return "AboutAppMuseMailIcon"
        case .museMate: return "AboutAppMuseMateIcon"
        }
    }

    var productURL: URL {
        let slug: String
        switch self {
        case .willDeep: slug = "veilwriter"
        case .timeBill: slug = "timebill"
        case .museUploader: slug = "qpic"
        case .markReader: slug = "qmarkview"
        case .gitWise: slug = "gitwise"
        case .veilPic: slug = "qpic"
        case .museMail: slug = "qmailmate"
        case .museMate: slug = "qnote"
        }
        return URL(string: "https://83d.me/products/\(slug)")!
    }
}

/// 推荐 App 网格（自适应列宽），关于窗与设置页共用
struct RecommendedAppsGrid: View {
    private let columns = [GridItem(.adaptive(minimum: 156), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(RecommendedApp.allCases) { app in
                RecommendedAppCard(app: app)
            }
        }
    }
}

/// 单个推荐 App 卡片
struct RecommendedAppCard: View {
    let app: RecommendedApp

    var body: some View {
        Link(destination: app.productURL) {
            HStack(alignment: .center, spacing: 10) {
                Image(app.iconAssetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString(app.nameKey, comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(NSLocalizedString(app.summaryKey, comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.44), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
