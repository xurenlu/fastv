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
    @State private var aiConfigHasAPIKey = false // 跟踪AI配置步骤是否有API Key
    
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var downloader = ModelDownloader.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // 步骤指示器
            HStack(spacing: 8) {
                ForEach(0..<5) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
            
            // 内容区域
            Group {
                switch currentStep {
                case 0:
                    LanguageSelectionStep()
                case 1:
                    ShortcutSetupStep()
                case 2:
                    ModelDownloadStep(
                        isDownloading: $isDownloading,
                        downloadProgress: $downloadProgress,
                        downloadStatus: $downloadStatus,
                        downloadError: $downloadError
                    )
                case 3:
                    AIConfigurationStep(onAPIKeyChanged: { hasAPIKey in
                        aiConfigHasAPIKey = hasAPIKey
                    })
                case 4:
                    UsageGuideStep()
                default:
                    LanguageSelectionStep()
                }
            }
            .transition(.opacity)
            
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
                
                // AI配置步骤（步骤3）的特殊按钮逻辑
                if currentStep == 3 {
                    // 跳过按钮
                    Button(NSLocalizedString("onboarding.skip", comment: "")) {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    // 完成或下一步按钮
                    Button(aiConfigHasAPIKey ? NSLocalizedString("onboarding.complete", comment: "") : NSLocalizedString("onboarding.next", comment: "")) {
                        if aiConfigHasAPIKey {
                            // 如果已配置API Key，直接完成引导
                            preferences.markOnboardingCompleted()
                            dismiss()
                        } else {
                            // 否则进入下一步
                            withAnimation {
                                currentStep += 1
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    // 其他步骤的按钮逻辑
                    Button(currentStep == 4 ? NSLocalizedString("onboarding.complete", comment: "") : NSLocalizedString("onboarding.next", comment: "")) {
                        if currentStep == 4 {
                            // 完成引导
                            preferences.markOnboardingCompleted()
                            dismiss()
                        } else if currentStep == 2 {
                            // 从模型下载步骤进入下一步时，异步检查模型是否已下载
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
                    .disabled(currentStep == 2 && !preferences.isModelDownloaded)
                }
            }
            .padding(20)
        }
        .frame(width: 720, height: 600)
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
            
            if preferences.enableVoiceInput {
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
                    set: { 
                        preferences.voiceInputShortcutModifiers = $0
                        preferences.enableVoiceInput = true
                    }
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
    
    // 阿里云API Key申请链接
    private let aliyunAPIKeyURL = "https://bailian.console.aliyun.com/?accounttraceid=ecf52b9459854c13be278b89515acd5ekwwf&tab=model#/api-key"
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            
            Text(NSLocalizedString("onboarding.ai.config.title", comment: ""))
                .font(.title)
                .fontWeight(.bold)
            
            Text(NSLocalizedString("onboarding.ai.config.description", comment: ""))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
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
                
                // 显示主要服务选项
                VStack(spacing: 8) {
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
                        
                        // 申请链接按钮（仅阿里云显示）
                        if selectedProtocolType == .dashScope {
                            Button(action: {
                                if let url = URL(string: aliyunAPIKeyURL) {
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
        .padding(40)
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
            HStack {
                Text(protocolType.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                
                if isRecommended {
                    Text(NSLocalizedString("onboarding.ai.config.recommended", comment: ""))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(Color.orange.opacity(0.2))
                        }
                        .foregroundStyle(.orange)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
            }
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

#Preview {
    OnboardingView()
}

