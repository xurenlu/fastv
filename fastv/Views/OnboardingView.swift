//
//  OnboardingView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AppKit

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadStatus: String = ""
    @State private var downloadError: Error?

    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var downloader = ModelDownloader.shared

    /// v2.0.0-rc3 精简：5 步 → 2 步。
    ///
    /// 设计动机来自竞品调研：SuperWhisper 因「15-30 分钟配置劝退新用户」吃了苦头。
    /// 我们的策略 = **默认值敢拍板**：
    /// - 输入语言：默认系统语言（中文环境用 zh，其它用 auto）
    /// - 快捷键：默认值已存在（在 UserPreferences 初始化时）
    /// - AI 优化：默认关（不强求 API Key，避免没配 key 报错的首次体验崩盘）
    ///
    /// 用户首次启动只需走 2 步：模型下载 → 完成。其它配置在「设置」里随时可改。
    /// 旧的 LanguageSelectionStep / ShortcutSetupStep / AIConfigurationStep /
    /// UsageGuideStep 代码保留（未删），供未来「重新引导」或 settings 复用。
    private static let totalSteps = 2

    var body: some View {
        VStack(spacing: 0) {
            // 步骤指示器
            HStack(spacing: 8) {
                ForEach(0..<Self.totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 30)
            .padding(.bottom, 20)

            // 内容区域
            ScrollView {
                Group {
                    switch currentStep {
                    case 0:
                        ModelDownloadStep(
                            isDownloading: $isDownloading,
                            downloadProgress: $downloadProgress,
                            downloadStatus: $downloadStatus,
                            downloadError: $downloadError
                        )
                    case 1:
                        OnboardingCompletionStep()
                    default:
                        ModelDownloadStep(
                            isDownloading: $isDownloading,
                            downloadProgress: $downloadProgress,
                            downloadStatus: $downloadStatus,
                            downloadError: $downloadError
                        )
                    }
                }
                .transition(.opacity)
            }

            // 底部按钮
            HStack {
                if currentStep > 0 {
                    Button(NSLocalizedString("onboarding.previous", comment: "")) {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button(currentStep == Self.totalSteps - 1
                       ? NSLocalizedString("onboarding.complete", comment: "")
                       : NSLocalizedString("onboarding.next", comment: "")) {
                    if currentStep == Self.totalSteps - 1 {
                        // 完成引导
                        preferences.markOnboardingCompleted()
                        dismiss()
                    } else if currentStep == 0 {
                        // 从模型下载步骤进入完成页之前，异步确认模型确实在
                        Task { @MainActor in
                            let modelExists = await ModelDownloader.shared.checkModelFilesExistAsync()
                            if modelExists {
                                preferences.isModelDownloaded = true
                            }
                            withAnimation {
                                currentStep += 1
                            }
                        }
                    } else {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(currentStep == 0 && !preferences.isModelDownloaded)
            }
            .padding(20)
        }
        .frame(width: 720, height: 560)
        .onAppear {
            // 初始化识别语言设置（如果还没有选择，默认为中文）
            if preferences.voiceInputLanguage.isEmpty || preferences.voiceInputLanguage == "auto" {
                preferences.voiceInputLanguage = "zh"
            }
            
            // 初始化应用界面语言设置（如果还没有选择）
            if preferences.defaultLanguage.isEmpty {
                // 使用系统语言或默认中文
                let systemLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
                let supportedLanguage = SupportedLanguage.allCases.first { $0.rawValue == systemLanguage } ?? .chinese
                preferences.defaultLanguage = supportedLanguage.rawValue
                LocalizationManager.shared.currentLanguage = supportedLanguage.rawValue
            } else {
                // 确保LocalizationManager使用已保存的语言
                LocalizationManager.shared.currentLanguage = preferences.defaultLanguage
            }
            
            // 异步检查模型文件，避免阻塞UI
            Task { @MainActor in
                let modelExists = await ModelDownloader.shared.checkModelFilesExistAsync()
                if modelExists {
                    preferences.isModelDownloaded = true
                }
            }
        }
    }
}

// MARK: - 步骤1: 选择语言
struct LanguageSelectionStep: View {
    @ObservedObject private var preferences = UserPreferences.shared
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "globe")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            
            Text("onboarding.select.language.title")
                .font(.title)
                .fontWeight(.bold)
            
            Text("onboarding.select.language.description")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // 使用网格布局，一行排2个语言
            let languages = TranscriptLanguage.allCases.filter { $0 != .nospeech }
            let columns = [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
            
            LazyVGrid(columns: columns, spacing: 12) {
                // 显示识别语言选项（排除 nospeech）
                ForEach(languages, id: \.self) { language in
                    Button(action: {
                        preferences.voiceInputLanguage = language.rawValue
                    }) {
                        HStack {
                            Text(language.displayName)
                                .font(.body)
                            Spacer()
                            if preferences.voiceInputLanguage == language.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(preferences.voiceInputLanguage == language.rawValue ? 
                                      Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)
        }
        .padding(40)
    }
}

// MARK: - 步骤2: 设置快捷键
struct ShortcutSetupStep: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var isCapturing = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "keyboard")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            
            Text("onboarding.set.shortcut.title")
                .font(.title)
                .fontWeight(.bold)
            
            Text("onboarding.set.shortcut.description")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 8) {
                Text("current.shortcut")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 4) {
                    if preferences.voiceInputShortcutModifiers.contains(.control) {
                        Text("⌃")
                            .font(.system(size: 14, weight: .medium))
                    }
                    if preferences.voiceInputShortcutModifiers.contains(.option) {
                        Text("⌥")
                            .font(.system(size: 14, weight: .medium))
                    }
                    if preferences.voiceInputShortcutModifiers.contains(.shift) {
                        Text("⇧")
                            .font(.system(size: 14, weight: .medium))
                    }
                    if preferences.voiceInputShortcutModifiers.contains(.command) {
                        Text("⌘")
                            .font(.system(size: 14, weight: .medium))
                    }
                    
                    Text(keyCodeToString(preferences.voiceInputShortcutKeyCode))
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.gray.opacity(0.1))
                }
            }
            
            Button(action: {
                isCapturing = true
            }) {
                Text(isCapturing ? NSLocalizedString("press.to.capture.shortcut", comment: "") : NSLocalizedString("set.shortcut", comment: ""))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .sheet(isPresented: $isCapturing) {
            ShortcutCaptureSheetView(
                keyCode: Binding(
                    get: { preferences.voiceInputShortcutKeyCode },
                    set: { preferences.voiceInputShortcutKeyCode = $0 }
                ),
                modifiers: Binding(
                    get: { preferences.voiceInputShortcutModifiers },
                    set: { preferences.voiceInputShortcutModifiers = $0 }
                ),
                onDismiss: {
                    isCapturing = false
                }
            )
        }
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0xFFFF: return NSLocalizedString("key.left.control", comment: "")
        case 0x3F: return NSLocalizedString("key.fn", comment: "")
        default: return "\(NSLocalizedString("key", comment: ""))\(keyCode)"
        }
    }
}

// MARK: - 步骤3: 下载模型
struct ModelDownloadStep: View {
    @Binding var isDownloading: Bool
    @Binding var downloadProgress: Double
    @Binding var downloadStatus: String
    @Binding var downloadError: Error?
    
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var downloader = ModelDownloader.shared
    @State private var isEditingURL = false
    @State private var editedURL: String = ""
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            
            Text("onboarding.download.model.title")
                .font(.title)
                .fontWeight(.bold)
            
            Text("onboarding.download.model.description")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // 显示模型大小提示
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("onboarding.model.size.warning")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.1))
            }
            
            // 显示其他文件说明
            Text("onboarding.model.other.files")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            // 下载地址显示和编辑
            VStack(spacing: 12) {
                if isEditingURL {
                    VStack(spacing: 12) {
                        TextField(NSLocalizedString("model.download.url.placeholder", comment: ""), text: $editedURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                        
                        HStack(spacing: 12) {
                            Button(NSLocalizedString("cancel", comment: "")) {
                                isEditingURL = false
                                editedURL = preferences.modelDownloadURL
                            }
                            .buttonStyle(.bordered)
                            
                            Button(NSLocalizedString("save", comment: "")) {
                                preferences.modelDownloadURL = editedURL
                                isEditingURL = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 8) {
                        HStack {
                            Text(NSLocalizedString("model.download.url.label", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Button(action: {
                                editedURL = preferences.modelDownloadURL
                                isEditingURL = true
                            }) {
                                Text(NSLocalizedString("model.download.edit.url", comment: ""))
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                        
                        Text(preferences.modelDownloadURL)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.gray.opacity(0.1))
                            }
                    }
                    .padding(.horizontal, 20)
                }
            }
            
            if downloader.isDownloading {
                VStack(spacing: 16) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                    
                    VStack(spacing: 8) {
                        Text(downloader.downloadStatus)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        if !downloader.downloadSpeed.isEmpty {
                            Text(downloader.downloadSpeed)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.horizontal, 40)
            } else {
                // 使用状态变量管理模型检查，避免在视图渲染时阻塞
                ModelDownloadStatusContentView(
                    isDownloading: $isDownloading,
                    downloadProgress: $downloadProgress,
                    downloadStatus: $downloadStatus,
                    downloadError: $downloadError,
                    onStartDownload: {
                        Task {
                            await startDownload()
                        }
                    }
                )
            }
            
            if let error = downloadError {
                Text(String(format: NSLocalizedString("model.download.error", comment: ""), error.localizedDescription))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(40)
    }
    
    private func startDownload() async {
        isDownloading = true
        downloadError = nil
        
        do {
            try await downloader.downloadModel(baseURL: preferences.modelDownloadURL) { progress, status, speed in
                downloadProgress = progress
                downloadStatus = status
                // speed 已经在 downloader.downloadSpeed 中更新了
            }
            // 下载完成后，同步状态
            if ModelDownloader.shared.checkModelFilesExist() {
                preferences.isModelDownloaded = true
            }
        } catch {
            downloadError = error
        }
        
        isDownloading = false
    }
}

// MARK: - 步骤4: AI配置
struct AIConfigurationStep: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var selectedProtocolType: AIProtocolType = .dashScope
    @State private var apiKey: String = ""
    @State private var hasConfigured: Bool = false
    
    var onAPIKeyChanged: ((Bool) -> Void)?
    
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            
            Text(NSLocalizedString("onboarding.ai.config.title", comment: ""))
                .font(.title)
                .fontWeight(.bold)
            
            // AI优化好处说明
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.orange)
                    Text(NSLocalizedString("onboarding.ai.config.benefit", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.1))
            }
            .padding(.horizontal, 40)
            
            // 服务选择器
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("onboarding.ai.config.select.service", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                // 横向图标按钮
                HStack(spacing: 16) {
                    // 阿里云 DashScope (推荐)
                    ServiceOptionButton(
                        protocolType: .dashScope,
                        isSelected: selectedProtocolType == .dashScope,
                        isRecommended: true,
                        onSelect: {
                            selectedProtocolType = .dashScope
                        }
                    )
                    
                    // 其他服务选项
                    ServiceOptionButton(
                        protocolType: .ollama,
                        isSelected: selectedProtocolType == .ollama,
                        isRecommended: false,
                        onSelect: {
                            selectedProtocolType = .ollama
                        }
                    )
                    
                    ServiceOptionButton(
                        protocolType: .openAI,
                        isSelected: selectedProtocolType == .openAI,
                        isRecommended: false,
                        onSelect: {
                            selectedProtocolType = .openAI
                        }
                    )
                }
            }
            .padding(.horizontal, 40)
            
            // API Key 输入区域
            if selectedProtocolType.requiresAPIKey {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(NSLocalizedString("onboarding.ai.config.api.key", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        // 申请链接按钮（有专属申请页的服务显示）
                        if let apiKeyURL = selectedProtocolType.apiKeyApplicationURL {
                            Button(action: {
                                if let url = URL(string: apiKeyURL) {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                        .font(.caption)
                                    Text(NSLocalizedString("onboarding.ai.config.apply.link", comment: ""))
                                        .font(.caption)
                                }
                                .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    SecureField(
                        NSLocalizedString("onboarding.ai.config.api.key.placeholder", comment: ""),
                        text: $apiKey
                    )
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { oldValue, newValue in
                        // 当API Key输入时，自动保存配置
                        if !newValue.isEmpty {
                            saveAIConfiguration()
                        }
                        // 通知父视图API Key状态变化
                        onAPIKeyChanged?(!newValue.isEmpty)
                    }
                }
                .padding(.horizontal, 40)
            }
            
            // 跳过提示
            Text(NSLocalizedString("onboarding.ai.config.skip.hint", comment: ""))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 20)
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
        .onAppear {
            // 检查是否已有配置
            if let defaultProfile = preferences.getDefaultProfile(),
               !defaultProfile.apiKey.isEmpty {
                selectedProtocolType = defaultProfile.protocolType
                apiKey = defaultProfile.apiKey
                hasConfigured = true
                onAPIKeyChanged?(true)
            } else {
                // 如果没有配置，检查当前选择的服务是否需要API Key
                // 如果选择的是Ollama（不需要API Key），也认为已配置
                if !selectedProtocolType.requiresAPIKey {
                    onAPIKeyChanged?(true)
                } else {
                    onAPIKeyChanged?(!apiKey.isEmpty)
                }
            }
        }
        .onChange(of: selectedProtocolType) { oldValue, newValue in
            // 当切换服务类型时，如果新服务不需要API Key，自动保存配置并通知父视图已配置
            if !newValue.requiresAPIKey {
                // 自动保存Ollama配置
                saveAIConfigurationForOllama()
                onAPIKeyChanged?(true)
            } else if !apiKey.isEmpty {
                onAPIKeyChanged?(true)
            } else {
                onAPIKeyChanged?(false)
            }
        }
    }
    
    private func saveAIConfigurationForOllama() {
        // 为Ollama保存配置（不需要API Key）
        let ollamaType = AIProtocolType.ollama
        let existingProfile = preferences.aiServiceProfiles.first { profile in
            profile.protocolType == ollamaType
        }
        
        let profile: AIServiceProfile
        if let existing = existingProfile {
            profile = AIServiceProfile(
                id: existing.id,
                name: existing.name,
                protocolType: ollamaType,
                endpoint: ollamaType.defaultEndpoint ?? "",
                apiKey: "",
                defaultModel: ollamaType.recommendedModels.first ?? "",
                timeout: 5.0,
                isDefault: true,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
        } else {
            profile = AIServiceProfile(
                name: ollamaType.displayName,
                protocolType: ollamaType,
                endpoint: ollamaType.defaultEndpoint ?? "",
                apiKey: "",
                defaultModel: ollamaType.recommendedModels.first ?? "",
                timeout: 5.0,
                isDefault: true
            )
        }
        
        preferences.saveProfile(profile)
        preferences.setDefaultProfile(profile)
        preferences.enableAIOptimization = true
        hasConfigured = true
    }
    
    private func saveAIConfiguration() {
        guard !apiKey.isEmpty else { return }
        
        // 查找是否已存在相同协议的profile
        let existingProfile = preferences.aiServiceProfiles.first { profile in
            profile.protocolType == selectedProtocolType
        }
        
        let profile: AIServiceProfile
        if let existing = existingProfile {
            // 更新现有profile
            profile = AIServiceProfile(
                id: existing.id,
                name: existing.name,
                protocolType: selectedProtocolType,
                endpoint: selectedProtocolType.defaultEndpoint ?? "",
                apiKey: apiKey,
                defaultModel: selectedProtocolType.recommendedModels.first ?? "",
                timeout: selectedProtocolType == .ollama ? 5.0 : 30.0,
                isDefault: true, // 设为默认
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
        } else {
            // 创建新profile
            profile = AIServiceProfile(
                name: selectedProtocolType.displayName,
                protocolType: selectedProtocolType,
                endpoint: selectedProtocolType.defaultEndpoint ?? "",
                apiKey: apiKey,
                defaultModel: selectedProtocolType.recommendedModels.first ?? "",
                timeout: selectedProtocolType == .ollama ? 5.0 : 30.0,
                isDefault: true
            )
        }
        
        // 保存profile
        preferences.saveProfile(profile)
        
        // 设置为默认profile
        preferences.setDefaultProfile(profile)
        
        // 自动启用AI优化
        preferences.enableAIOptimization = true
        
        hasConfigured = true
    }
}

// MARK: - 服务选项按钮
struct ServiceOptionButton: View {
    let protocolType: AIProtocolType
    let isSelected: Bool
    let isRecommended: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                ZStack {
                    // 图标背景
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
                        .frame(width: 56, height: 56)
                    
                    // 图标
                    Image(systemName: protocolType.iconName)
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    
                    // 选中标记
                    if isSelected {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.tint)
                                    .background {
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 18, height: 18)
                                    }
                            }
                        }
                        .frame(width: 56, height: 56)
                    }
                    
                    // 推荐标记
                    if isRecommended {
                        VStack {
                            HStack {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                                    .padding(4)
                                    .background {
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 18, height: 18)
                                    }
                                Spacer()
                            }
                            Spacer()
                        }
                        .frame(width: 56, height: 56)
                    }
                }
                
                // 服务名称
                Text(protocolType.displayName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 步骤5: 使用引导
struct UsageGuideStep: View {
    @ObservedObject private var preferences = UserPreferences.shared
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            
            Text(NSLocalizedString("onboarding.usage.guide.title", comment: ""))
                .font(.title)
                .fontWeight(.bold)
            
            Text(NSLocalizedString("onboarding.usage.guide.description", comment: ""))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // 重要提示：可以在其他APP中使用
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    
                    Text(NSLocalizedString("onboarding.usage.guide.highlight", comment: ""))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.1))
                }
            }
            .padding(.horizontal, 40)
            
            // 根据用户选择的识别语言显示相应提示
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(usageHintText)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        
                        // 显示快捷键提示
                        HStack(spacing: 6) {
                            Text(NSLocalizedString("press.shortcut.to.start", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 4) {
                                if preferences.voiceInputShortcutModifiers.contains(.control) {
                                    Text("⌃")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                if preferences.voiceInputShortcutModifiers.contains(.option) {
                                    Text("⌥")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                if preferences.voiceInputShortcutModifiers.contains(.shift) {
                                    Text("⇧")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                if preferences.voiceInputShortcutModifiers.contains(.command) {
                                    Text("⌘")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                
                                Text(keyCodeToString(preferences.voiceInputShortcutKeyCode))
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.secondary.opacity(0.1))
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.1))
                }
            }
            .padding(.horizontal, 40)
        }
        .padding(40)
    }
    
    private var usageHintText: String {
        switch preferences.voiceInputLanguage {
        case "zh":
            return NSLocalizedString("onboarding.usage.guide.chinese", comment: "")
        case "en":
            return NSLocalizedString("onboarding.usage.guide.english", comment: "")
        case "yue":
            return NSLocalizedString("onboarding.usage.guide.cantonese", comment: "")
        case "ja":
            return NSLocalizedString("onboarding.usage.guide.japanese", comment: "")
        case "ko":
            return NSLocalizedString("onboarding.usage.guide.korean", comment: "")
        case "auto":
            return NSLocalizedString("onboarding.usage.guide.auto", comment: "")
        default:
            return NSLocalizedString("onboarding.usage.guide.auto", comment: "")
        }
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0xFFFF: return NSLocalizedString("key.left.control", comment: "")
        case 0x3F: return NSLocalizedString("key.fn", comment: "")
        case 0x09: return "V"
        case 0x31: return NSLocalizedString("key.space", comment: "")
        default: return "\(NSLocalizedString("key", comment: ""))\(keyCode)"
        }
    }
}

// MARK: - 快捷键捕获 Sheet 视图
struct ShortcutCaptureSheetView: View {
    @Binding var keyCode: UInt16
    @Binding var modifiers: NSEvent.ModifierFlags
    var onDismiss: () -> Void
    @State private var isCapturing = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 说明文字
                VStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    
                    Text("shortcut.capture.title")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("shortcut.capture.description")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // 快捷键捕获视图
                ShortcutCaptureView(
                    keyCode: $keyCode,
                    modifiers: $modifiers
                )
                .padding(.horizontal, 40)
                
                Spacer()
                
                // 底部按钮
                HStack(spacing: 12) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button(NSLocalizedString("onboarding.complete", comment: "")) {
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
            }
            .frame(width: 500, height: 400)
        }
    }
}

// MARK: - 模型下载状态内容视图（异步检查，避免阻塞UI）
struct ModelDownloadStatusContentView: View {
    @Binding var isDownloading: Bool
    @Binding var downloadProgress: Double
    @Binding var downloadStatus: String
    @Binding var downloadError: Error?
    let onStartDownload: () -> Void
    
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var modelExists: Bool? = nil
    @State private var isChecking: Bool = false
    
    var body: some View {
        Group {
            if isChecking {
                // 检查中
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding()
            } else if modelExists == true {
                // 模型已存在
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("onboarding.model.ready")
                        .font(.body)
                }
            } else {
                // 模型不存在，显示下载按钮
                Button(action: onStartDownload) {
                    Text("onboarding.start.download")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .task {
            // 视图出现时异步检查模型文件
            await checkModelAsync()
        }
    }
    
    private func checkModelAsync() async {
        isChecking = true
        defer { isChecking = false }
        
        let exists = await ModelDownloader.shared.checkModelFilesExistAsync()
        await MainActor.run {
            modelExists = exists
            if exists {
                preferences.isModelDownloaded = true
            }
        }
    }
}

// MARK: - 步骤2: 完成页
//
// v2.0.0-rc3 新增。代替原来的 5 步流程末页 UsageGuideStep。
// 内容只做三件事：1) 庆祝 2) 一句话说明默认行为 3) 指路到设置去自定义。
// 不再罗列"如何使用"——用户自己按住快捷键说一句话就知道了。
struct OnboardingCompletionStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)

            Text(NSLocalizedString("onboarding.complete.title", comment: ""))
                .font(.title)
                .fontWeight(.bold)

            Text(NSLocalizedString("onboarding.complete.subtitle", comment: ""))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text(NSLocalizedString("onboarding.complete.hint.shortcut", comment: ""))
                        .font(.callout)
                }
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text(NSLocalizedString("onboarding.complete.hint.language", comment: ""))
                        .font(.callout)
                }
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text(NSLocalizedString("onboarding.complete.hint.ai", comment: ""))
                        .font(.callout)
                }
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                        .frame(width: 20)
                    Text(NSLocalizedString("onboarding.complete.hint.privacy", comment: ""))
                        .font(.callout)
                }
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.08))
            }
            .padding(.horizontal, 40)
        }
        .padding(40)
    }
}

#Preview {
    OnboardingView()
}
