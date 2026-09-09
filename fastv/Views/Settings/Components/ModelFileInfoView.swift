//
//  ModelFileInfoView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

/// 模型文件信息视图
struct ModelFileInfoView: View {
    @State private var isModelDownloaded = false
    @State private var showOnboarding = false
    @State private var installedVariant: SpeechModelVariant?
    @State private var canUpgradeToFastModel = false
    @ObservedObject private var downloader = ModelDownloader.shared
    @ObservedObject private var preferences = UserPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: isModelDownloaded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(isModelDownloaded ? .green : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("模型文件状态")
                        .font(.body)

                    Text(statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isModelDownloaded {
                    Button(action: {
                        showOnboarding = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("下载模型")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if canUpgradeToFastModel {
                upgradeBanner
            } else if isModelDownloaded {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("模型文件已就绪，可以使用语音输入功能")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(downloadSizeHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            checkModelStatus()
        }
        .onChange(of: downloader.isDownloading) { oldValue, newValue in
            // 如果下载完成（从下载中变为非下载中），检查模型状态
            if oldValue && !newValue {
                checkModelStatus()
                // 如果模型已下载，关闭 onboarding sheet
                if isModelDownloaded {
                    showOnboarding = false
                }
                offerLegacyModelCleanupIfNeeded()
            }
        }
        .onChange(of: preferences.isModelDownloaded) { oldValue, newValue in
            if newValue {
                checkModelStatus()
                // 如果模型已下载，关闭 onboarding sheet
                if isModelDownloaded {
                    showOnboarding = false
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }

    /// 升级到加速版的提示条。老用户装的是 fp32 标准版，光靠新版本代码拿不到模型本身的提速。
    private var upgradeBanner: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "bolt.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("model.upgrade.available.title", comment: ""))
                    .font(.caption)
                Text(
                    String(
                        format: NSLocalizedString("model.upgrade.available.detail", comment: ""),
                        "\(SpeechModelVariant.preferred.approximateMegabytes)"
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(NSLocalizedString("model.upgrade.action", comment: "")) {
                showOnboarding = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var statusDescription: String {
        guard isModelDownloaded, let variant = installedVariant else {
            return "未下载"
        }
        return String(
            format: NSLocalizedString("model.info.current.variant", comment: ""),
            variant.displayName,
            "\(variant.approximateMegabytes)"
        )
    }

    private var downloadSizeHint: String {
        "首次使用需要下载模型文件（约 \(SpeechModelVariant.preferred.approximateMegabytes)MB）"
    }

    private func checkModelStatus() {
        // 统一使用 checkModelFilesExist() 检查，并同步 preferences.isModelDownloaded
        let modelExists = ModelDownloader.shared.checkModelFilesExist()
        isModelDownloaded = modelExists
        installedVariant = SpeechModelLocator.resolvedVariant()
        canUpgradeToFastModel = SpeechModelLocator.canUpgradeToPreferred()
        if modelExists {
            preferences.isModelDownloaded = true
        } else {
            preferences.isModelDownloaded = false
        }
    }

    /// 加速版装好之后，问用户要不要删掉旧的标准版模型（占约 894MB）。
    /// 只在两个变体同时存在时问，删除是用户点头之后才做。
    private func offerLegacyModelCleanupIfNeeded() {
        guard SpeechModelLocator.isInstalled(.preferred),
              SpeechModelLocator.isInstalled(.float32) else {
            return
        }
        let freedMegabytes = SpeechModelVariant.float32.approximateMegabytes
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("model.upgrade.cleanup.title", comment: "")
        alert.informativeText = String(
            format: NSLocalizedString("model.upgrade.cleanup.message", comment: ""),
            "\(freedMegabytes)"
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("model.upgrade.cleanup.confirm", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("model.upgrade.cleanup.keep", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            ModelDownloader.shared.removeModelFile(variant: .float32)
            checkModelStatus()
        }
    }
}
