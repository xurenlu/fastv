//
//  AIServiceManagementView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI
import AppKit

/// AI 服务管理视图
struct AIServiceManagementView: View {
    @ObservedObject var preferences = UserPreferences.shared
    @State private var selectedProfile: AIServiceProfile?
    @State private var editingProfile: AIServiceProfile?
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var profileToDelete: AIServiceProfile?
    @State private var testResult: String?
    @State private var testSucceeded = false
    @State private var isTesting = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题区域
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("ai.service.title", comment: "AI 服务配置"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(NSLocalizedString("ai.service.subtitle", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider()
                .padding(.horizontal, 24)
            
            // 内容区域
            if preferences.aiServiceProfiles.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    ContentUnavailableView {
                        Label(NSLocalizedString("ai.service.empty.title", comment: ""), systemImage: "server.rack")
                            .font(.headline)
                        Text(NSLocalizedString("ai.service.empty.subtitle", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(preferences.aiServiceProfiles) { profile in
                        let capturedProfile = profile
                        ProfileRowView(
                            profile: profile,
                            isSelected: selectedProfile?.id == profile.id,
                            onSelect: { selectedProfile = capturedProfile },
                            onEdit: {
                                editingProfile = capturedProfile
                                showEditSheet = true
                            },
                            onDelete: {
                                profileToDelete = capturedProfile
                                showDeleteAlert = true
                            },
                            onSetDefault: {
                                preferences.setDefaultProfile(capturedProfile)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            
            Divider()
                .padding(.horizontal, 24)
            
            // 操作按钮区域
            VStack(spacing: 12) {
                // 测试结果
                if let testResult = testResult {
                    HStack(spacing: 8) {
                        Image(systemName: testSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(testSucceeded ? .green : .red)
                            .font(.caption)
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                }
                
                // 按钮组
                HStack(spacing: 12) {
                    Button(action: {
                        editingProfile = nil
                        showEditSheet = true
                    }) {
                        Label(NSLocalizedString("ai.service.add", comment: ""), systemImage: "plus.circle.fill")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    if let selectedProfile = selectedProfile {
                        Button(action: {
                            editingProfile = selectedProfile
                            showEditSheet = true
                        }) {
                            Label(NSLocalizedString("ai.common.edit", comment: ""), systemImage: "pencil")
                                .frame(minWidth: 80)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        
                        Button(action: {
                            testConnection(for: selectedProfile)
                        }) {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(minWidth: 80)
                            } else {
                                Label(NSLocalizedString("ai.service.test", comment: ""), systemImage: "network")
                                    .frame(minWidth: 80)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isTesting)
                        
                        Button(action: {
                            let newProfile = AIServiceProfile(
                                id: UUID(),
                                name: selectedProfile.name + NSLocalizedString("ai.service.copy.suffix", comment: " (副本)"),
                                protocolType: selectedProfile.protocolType,
                                endpoint: selectedProfile.endpoint,
                                apiKey: selectedProfile.apiKey,
                                defaultModel: selectedProfile.defaultModel,
                                timeout: selectedProfile.timeout
                            )
                            preferences.saveProfile(newProfile)
                        }) {
                            Label(NSLocalizedString("ai.service.duplicate", comment: ""), systemImage: "doc.on.doc")
                                .frame(minWidth: 80)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showEditSheet, onDismiss: {
            // 清理状态
            editingProfile = nil
        }) {
            if let editingProfile = editingProfile {
                AIProfileEditView(
                    profile: editingProfile,
                    onSave: { profile in
                        // 先关闭 sheet，再保存，避免重复触发
                        showEditSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            preferences.saveProfile(profile)
                        }
                    },
                    onCancel: {
                        showEditSheet = false
                    }
                )
            } else {
                AIProfileEditView(
                    profile: nil,
                    onSave: { profile in
                        // 先关闭 sheet，再保存，避免重复触发
                        showEditSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            preferences.saveProfile(profile)
                        }
                    },
                    onCancel: {
                        showEditSheet = false
                    }
                )
            }
        }
        .alert(NSLocalizedString("ai.service.delete.confirm.title", comment: ""), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("ai.common.cancel", comment: ""), role: .cancel) {
                profileToDelete = nil
            }
            Button(NSLocalizedString("ai.common.delete", comment: ""), role: .destructive) {
                if let profile = profileToDelete {
                    preferences.deleteProfile(profile)
                    if selectedProfile?.id == profile.id {
                        selectedProfile = nil
                    }
                    profileToDelete = nil
                }
            }
        } message: {
            if let profile = profileToDelete {
                Text(String(format: NSLocalizedString("ai.service.delete.confirm.message", comment: ""), profile.name))
            }
        }
        .onAppear {
            if selectedProfile == nil {
                selectedProfile = preferences.getDefaultProfile()
            }
        }
    }
    
    private func testConnection(for profile: AIServiceProfile) {
        isTesting = true
        testResult = nil
        testSucceeded = false
        
        Task {
            do {
                let adapter = AIServiceAdapter.shared
                let url = try adapter.buildAPIURL(for: profile, useChatCompletions: true, model: profile.defaultModel)
                print("🔍 [测试连接] URL: \(url.absoluteString)")
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                
                let headers = adapter.buildRequestHeaders(for: profile)
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
                print("🔍 [测试连接] Headers: \(headers.keys)")
                
                // 构建测试请求体
                // DashScope 兼容模式使用 OpenAI 格式，原生模式使用特殊格式
                let endpoint = profile.effectiveEndpoint.lowercased()
                let usesDashScopeCompatibleMode = endpoint.contains("compatible-mode") || endpoint.contains("/chat/completions")
                
                let testMessages: [[String: Any]]
                if profile.protocolType == .dashScope && !usesDashScopeCompatibleMode {
                    // DashScope 原生格式：content 为数组
                    testMessages = [["role": "user", "content": [["text": "test"]]]]
                } else {
                    // OpenAI 兼容格式（包括 DashScope 兼容模式）：content 为字符串
                    testMessages = [["role": "user", "content": "test"]]
                }
                
                let testBody = adapter.buildRequestBody(
                    for: profile,
                    messages: testMessages,
                    model: profile.defaultModel,
                    temperature: 0.1,
                    maxTokens: 10
                )
                
                request.httpBody = try JSONSerialization.data(withJSONObject: testBody)
                request.timeoutInterval = 10
                
                // 打印请求体用于调试
                if let bodyData = request.httpBody,
                   let bodyString = String(data: bodyData, encoding: .utf8) {
                    print("🔍 [测试连接] 请求体: \(bodyString)")
                }
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                await MainActor.run {
                    if let httpResponse = response as? HTTPURLResponse {
                        print("🔍 [测试连接] 状态码: \(httpResponse.statusCode)")
                        if httpResponse.statusCode == 200 {
                            testSucceeded = true
                            testResult = NSLocalizedString("ai.service.test.success", comment: "")
                        } else if httpResponse.statusCode == 400 {
                            // 尝试解析错误信息
                            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                // 打印完整的错误响应用于调试
                                if let errorData = try? JSONSerialization.data(withJSONObject: errorJson, options: .prettyPrinted),
                                   let errorString = String(data: errorData, encoding: .utf8) {
                                    print("🔍 [测试连接] 错误响应: \(errorString)")
                                }
                                
                                // 尝试提取错误消息
                                var errorMessage = ""
                                if let message = errorJson["message"] as? String {
                                    errorMessage = message
                                } else if let error = errorJson["error"] as? [String: Any],
                                          let message = error["message"] as? String {
                                    errorMessage = message
                                } else if let error = errorJson["error"] as? String {
                                    errorMessage = error
                                }
                                
                                if !errorMessage.isEmpty {
                                    testResult = String(format: NSLocalizedString("ai.service.test.error.400.detail", comment: ""), errorMessage)
                                } else {
                                    testResult = NSLocalizedString("ai.service.test.error.400", comment: "")
                                }
                            } else if let errorString = String(data: data, encoding: .utf8) {
                                print("🔍 [测试连接] 错误响应（文本）: \(errorString)")
                                testResult = String(format: NSLocalizedString("ai.service.test.error.400.detail", comment: ""), errorString)
                            } else {
                                testResult = NSLocalizedString("ai.service.test.error.400", comment: "")
                            }
                        } else if httpResponse.statusCode == 401 {
                            testResult = NSLocalizedString("ai.service.test.error.401", comment: "")
                        } else if httpResponse.statusCode == 403 {
                            testResult = NSLocalizedString("ai.service.test.error.403", comment: "")
                        } else if httpResponse.statusCode == 404 {
                            testResult = NSLocalizedString("ai.service.test.error.404", comment: "")
                        } else if httpResponse.statusCode >= 500 {
                            testResult = String(format: NSLocalizedString("ai.service.test.error.500", comment: ""), httpResponse.statusCode)
                        } else {
                            testResult = String(format: NSLocalizedString("ai.service.test.error.status", comment: ""), httpResponse.statusCode)
                        }
                    } else {
                        testResult = NSLocalizedString("ai.service.test.error.invalid_response", comment: "")
                    }
                    isTesting = false
                }
            } catch let error as URLError {
                await MainActor.run {
                    switch error.code {
                    case .timedOut:
                        testResult = NSLocalizedString("ai.service.test.error.timeout", comment: "")
                    case .cannotFindHost, .cannotConnectToHost:
                        testResult = NSLocalizedString("ai.service.test.error.cannot_connect", comment: "")
                    case .networkConnectionLost:
                        testResult = NSLocalizedString("ai.service.test.error.connection_lost", comment: "")
                    default:
                        testResult = String(format: NSLocalizedString("ai.service.test.error.network", comment: ""), error.localizedDescription)
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = String(format: NSLocalizedString("ai.service.test.error.generic", comment: ""), error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}

/// Profile 行视图
struct ProfileRowView: View {
    let profile: AIServiceProfile
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSetDefault: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    // 选中指示器
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .frame(width: 3, height: 40)
                    
                    // 默认标识
                    if profile.isDefault {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 14))
                            .symbolEffect(.bounce, value: profile.isDefault)
                    }
                    
                    // 协议图标
                    Image(systemName: protocolIcon(for: profile.protocolType))
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))
                        .frame(width: 24)
                    
                    // 信息区域
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        
                        HStack(spacing: 8) {
                            Text(profile.protocolType.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.1))
                                )
                            
                            if !profile.defaultModel.isEmpty {
                                Text(profile.defaultModel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // 操作菜单
            Menu {
                if !profile.isDefault {
                    Button(action: onSetDefault) {
                        Label(NSLocalizedString("ai.service.set_default", comment: ""), systemImage: "star")
                    }
                }
                Button(action: onEdit) {
                    Label(NSLocalizedString("ai.common.edit", comment: ""), systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label(NSLocalizedString("ai.common.delete", comment: ""), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
    }
    
    private func protocolIcon(for type: AIProtocolType) -> String {
        return type.iconName
    }
}

/// AI Profile 编辑视图
struct AIProfileEditView: View {
    let profile: AIServiceProfile?
    let onSave: (AIServiceProfile) -> Void
    let onCancel: () -> Void
    
    @State private var name: String
    @State private var protocolType: AIProtocolType
    @State private var endpoint: String
    @State private var apiKey: String
    @State private var isAPIKeyVisible = false
    @State private var defaultModel: String
    @State private var timeout: Double
    
    // Ollama 模型列表相关
    @State private var downloadedModels: [OllamaModelInfo] = []
    @State private var availableLibraryModels: [OllamaModelInfo] = []
    @State private var isFetchingModels = false
    @State private var fetchingError: String?
    @State private var downloadingModel: String?
    @State private var downloadProgress: (status: String, completed: Int64, total: Int64) = ("", 0, 0)
    
    init(profile: AIServiceProfile?, onSave: @escaping (AIServiceProfile) -> Void, onCancel: @escaping () -> Void) {
        self.profile = profile
        self.onSave = onSave
        self.onCancel = onCancel
        
        if let profile = profile {
            _name = State(initialValue: profile.name)
            _protocolType = State(initialValue: profile.protocolType)
            _endpoint = State(initialValue: profile.endpoint)
            _apiKey = State(initialValue: profile.apiKey)
            _defaultModel = State(initialValue: profile.defaultModel)
            _timeout = State(initialValue: profile.timeout)
        } else {
            _name = State(initialValue: "")
            _protocolType = State(initialValue: .ollama)
            _endpoint = State(initialValue: "")
            _apiKey = State(initialValue: "")
            _defaultModel = State(initialValue: "")
            _timeout = State(initialValue: AIProtocolType.ollama.defaultTimeout)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                connectionConfigSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 20)
            .navigationTitle(profile == nil ? NSLocalizedString("ai.service.add.title", comment: "") : NSLocalizedString("ai.service.edit.title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("ai.common.cancel", comment: ""), action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            // 初始化默认值
            if endpoint.isEmpty {
                endpoint = protocolType.defaultEndpoint ?? ""
            }
            if defaultModel.isEmpty {
                defaultModel = protocolType.recommendedModels.first ?? ""
            }
        }
    }
    
    // MARK: - 基本信息 Section
    @ViewBuilder
    private var basicInfoSection: some View {
                Section {
                    TextField(NSLocalizedString("ai.service.name", comment: ""), text: $name)
                        .textFieldStyle(.roundedBorder)

                    Picker(NSLocalizedString("ai.service.protocol", comment: ""), selection: $protocolType) {
                        ForEach(AIProtocolType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: protocolType) { oldValue, newValue in
                        // 当协议类型改变时，更新 endpoint、model 和超时
                        if endpoint.isEmpty || endpoint == oldValue.defaultEndpoint {
                            endpoint = newValue.defaultEndpoint ?? ""
                        }
                        if defaultModel.isEmpty || !newValue.recommendedModels.contains(defaultModel) {
                            defaultModel = newValue.recommendedModels.first ?? ""
                        }
                        // 如果超时还是旧协议的默认值，自动更新为新协议的默认值
                        if timeout == oldValue.defaultTimeout {
                            timeout = newValue.defaultTimeout
                        }
                    }
                } header: {
                    Text(NSLocalizedString("ai.service.section.basic", comment: ""))
                        .font(.headline)
                        .padding(.top, 8)
                } footer: {
                    Text(NSLocalizedString("ai.service.section.basic.footer", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
        }
                }
                
    // MARK: - 连接配置 Section
    @ViewBuilder
    private var connectionConfigSection: some View {
                Section {
            endpointField
            apiKeyField
            if protocolType == .ollama {
                ollamaModelSection
            } else {
                modelField
                recommendedModelsView
            }
            timeoutSlider
        } header: {
            Text(NSLocalizedString("ai.service.section.connection", comment: ""))
                .font(.headline)
                .padding(.top, 8)
        } footer: {
            connectionFooterText
        }
    }
    
    // MARK: - Endpoint 字段
    @ViewBuilder
    private var endpointField: some View {
                    if protocolType.endpointEditable {
                        TextField(NSLocalizedString("ai.service.endpoint", comment: "API Endpoint"), text: $endpoint, prompt: Text(verbatim: "https://api.example.com/v1"))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        HStack {
                            Text(NSLocalizedString("ai.service.endpoint", comment: "API Endpoint"))
                                .foregroundStyle(.primary)
                            Spacer()
                let displayEndpoint = endpoint.isEmpty ? (protocolType.defaultEndpoint ?? "") : endpoint
                Text(displayEndpoint)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .textSelection(.enabled)
            }
                        }
                    }
                    
    // MARK: - API Key 字段
    @ViewBuilder
    private var apiKeyField: some View {
                    if protocolType.requiresAPIKey {
                        HStack(spacing: 8) {
                            Group {
                                if isAPIKeyVisible {
                                    TextField(NSLocalizedString("ai.service.apikey", comment: "API Key"), text: $apiKey, prompt: Text(NSLocalizedString("ai.service.apikey.prompt", comment: "")))
                                        .autocorrectionDisabled()
                                } else {
                                    SecureField(NSLocalizedString("ai.service.apikey", comment: "API Key"), text: $apiKey, prompt: Text(NSLocalizedString("ai.service.apikey.prompt", comment: "")))
                                }
                            }
                            .textFieldStyle(.roundedBorder)

                            // 小眼睛：切换 API Key 明文/密文显示
                            Button(action: { isAPIKeyVisible.toggle() }) {
                                Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(isAPIKeyVisible ? NSLocalizedString("ai.service.apikey.hide", comment: "") : NSLocalizedString("ai.service.apikey.show", comment: ""))
                        }

                        // 申请链接按钮（部分服务显示）
                        if let apiKeyURL = protocolType.apiKeyApplicationURL {
                            Button(action: { openURL(apiKeyURL) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                        .font(.caption)
                                    Text(NSLocalizedString("ai.service.apply_apikey", comment: ""))
                                        .font(.caption)
                                }
                                .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Ollama 模型选择（已下载 + 可下载 + 下载）
    @ViewBuilder
    private var ollamaModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(NSLocalizedString("ai.model.name", comment: ""), text: $defaultModel, prompt: Text(NSLocalizedString("ai.model.example", comment: "")))
                .textFieldStyle(.roundedBorder)
            
            Button(action: fetchOllamaModels) {
                HStack(spacing: 6) {
                    if isFetchingModels {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(NSLocalizedString("ai.fetch.models", comment: ""))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isFetchingModels || endpoint.isEmpty)
            .help(NSLocalizedString("ai.fetch.models.help", comment: ""))
            
            if let error = fetchingError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            // 已下载的模型
            if !downloadedModels.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("ai.ollama.models.downloaded", comment: "已下载"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(downloadedModels) { model in
                                ollamaModelChip(model: model, isDownloaded: true)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            
            // 可下载的模型
            if !availableLibraryModels.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("ai.ollama.models.available", comment: "可下载"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableLibraryModels) { model in
                                ollamaLibraryModelChip(model: model)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            
            // 下载进度
            if let downloading = downloadingModel {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("\(downloading): \(downloadProgress.status)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if downloadProgress.total > 0 {
                        Text("\(formatBytes(downloadProgress.completed)) / \(formatBytes(downloadProgress.total))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func ollamaModelChip(model: OllamaModelInfo, isDownloaded: Bool) -> some View {
        let isSelected = defaultModel == model.name
        Button(action: { defaultModel = model.name }) {
            HStack(spacing: 4) {
                Text(model.name)
                    .font(.caption)
                Text("(\(model.formattedSize))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func ollamaLibraryModelChip(model: OllamaModelInfo) -> some View {
        let isSelected = defaultModel == model.name
        let isDownloading = downloadingModel == model.name
        HStack(spacing: 4) {
            Button(action: { defaultModel = model.name }) {
                HStack(spacing: 4) {
                    Text(model.name)
                        .font(.caption)
                    if let param = model.parameterSize {
                        Text("(\(param))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text("· \(model.formattedSize)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08))
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)
            
            Button(action: { pullOllamaModel(model.name) }) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isDownloading ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isDownloading || downloadingModel != nil)
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }
    
    private func fetchOllamaModels() {
        isFetchingModels = true
        fetchingError = nil
        Task {
            do {
                let models = try await OllamaService.shared.fetchModelsWithDetails(
                    endpoint: effectiveEndpoint,
                    apiToken: apiKey.isEmpty ? nil : apiKey
                )
                let downloadedNames = Set(models.map { $0.name.lowercased() })
                let available = OllamaLibrary.availableModels(excludingDownloaded: downloadedNames)
                await MainActor.run {
                    downloadedModels = models
                    availableLibraryModels = available
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    fetchingError = error.localizedDescription
                    isFetchingModels = false
                }
            }
        }
    }
    
    private var effectiveEndpoint: String {
        let e = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !e.isEmpty { return e }
        return protocolType.defaultEndpoint ?? "http://127.0.0.1:11434"
    }
    
    private func pullOllamaModel(_ model: String) {
        guard downloadingModel == nil else { return }
        downloadingModel = model
        downloadProgress = ("", 0, 0)
        Task {
            do {
                try await OllamaService.shared.pullModel(
                    endpoint: effectiveEndpoint,
                    model: model,
                    apiToken: apiKey.isEmpty ? nil : apiKey
                ) { status, completed, total in
                    downloadProgress = (status, completed, total)
                }
                await MainActor.run {
                    downloadingModel = nil
                    defaultModel = model
                    fetchOllamaModels() // 刷新列表
                }
            } catch {
                await MainActor.run {
                    downloadingModel = nil
                    fetchingError = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - 模型字段
    @ViewBuilder
    private var modelField: some View {
                    TextField(NSLocalizedString("ai.model.default", comment: ""), text: $defaultModel, prompt: Text(NSLocalizedString("ai.model.default.prompt", comment: "")))
                        .textFieldStyle(.roundedBorder)
    }
                    
    // MARK: - 推荐模型选择
    @ViewBuilder
    private var recommendedModelsView: some View {
                    if !protocolType.recommendedModels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("ai.model.recommended", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(protocolType.recommendedModels, id: \.self) { model in
                            modelButton(for: model)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
    
    @ViewBuilder
    private func modelButton(for model: String) -> some View {
        let isSelected = defaultModel == model
                                        Button(action: {
                                            defaultModel = model
                                        }) {
                                            Text(model)
                                                .font(.caption)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                        }
                                        .buttonStyle(.plain)
                    }
                    
    // MARK: - 超时时间滑块
    @ViewBuilder
    private var timeoutSlider: some View {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(NSLocalizedString("ai.service.timeout", comment: ""))
                                .foregroundStyle(.primary)
                            Spacer()
                Text(String(format: NSLocalizedString("ai.service.timeout.format", comment: "%.1f 秒"), timeout))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $timeout, in: 2.0...180.0, step: 0.5)
                        if protocolType != .ollama {
                            Text(NSLocalizedString("ai.service.timeout.hint", comment: ""))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
    }
    
    // MARK: - Footer 文本
    @ViewBuilder
    private var connectionFooterText: some View {
                    if protocolType == .someIM {
                        Text(NSLocalizedString("ai.service.footer.someim", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if protocolType == .gemini {
                        Text(NSLocalizedString("ai.service.footer.gemini", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(NSLocalizedString("ai.service.footer.default", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
    
    // MARK: - 保存按钮
    @ViewBuilder
    private var saveButton: some View {
        Button(NSLocalizedString("ai.common.save", comment: ""), action: saveProfile)
            .disabled(name.isEmpty || (protocolType.requiresAPIKey && apiKey.isEmpty))
            .keyboardShortcut(.defaultAction)
                }
    
    private func saveProfile() {
                        let effectiveEndpoint = protocolType.endpointEditable ? endpoint : (protocolType.defaultEndpoint ?? "")
                        let profileId = profile?.id ?? UUID()

                        let newProfile = AIServiceProfile(
                            id: profileId,
                            name: name.isEmpty ? protocolType.displayName : name,
                            protocolType: protocolType,
                            endpoint: effectiveEndpoint,
                            apiKey: apiKey,
                            defaultModel: defaultModel,
                            timeout: timeout,
                            isDefault: profile?.isDefault ?? false,
                            createdAt: profile?.createdAt ?? Date(),
                            updatedAt: Date()
                        )

                        onSave(newProfile)
    }
}

