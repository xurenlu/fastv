//
//  AIServiceManagementView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

/// AI 服务管理视图
struct AIServiceManagementView: View {
    @ObservedObject var preferences = UserPreferences.shared
    @State private var selectedProfile: AIServiceProfile?
    @State private var editingProfile: AIServiceProfile?
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var profileToDelete: AIServiceProfile?
    @State private var testResult: String?
    @State private var isTesting = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题区域
            VStack(alignment: .leading, spacing: 4) {
                Text("AI 服务配置")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("管理您的 AI 服务配置，为不同场景选择不同的服务")
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
                        Label("暂无 AI 服务配置", systemImage: "server.rack")
                            .font(.headline)
                        Text("点击下方按钮添加第一个 AI 服务")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(preferences.aiServiceProfiles) { profile in
                        ProfileRowView(
                            profile: profile,
                            isSelected: selectedProfile?.id == profile.id,
                            onSelect: { selectedProfile = profile },
                            onEdit: {
                                editingProfile = profile
                                showEditSheet = true
                            },
                            onDelete: {
                                profileToDelete = profile
                                showDeleteAlert = true
                            },
                            onSetDefault: {
                                preferences.setDefaultProfile(profile)
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
                        Image(systemName: testResult.contains("成功") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(testResult.contains("成功") ? .green : .red)
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
                        Label("添加服务", systemImage: "plus.circle.fill")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    if let selectedProfile = selectedProfile {
                        Button(action: {
                            editingProfile = selectedProfile
                            showEditSheet = true
                        }) {
                            Label("编辑", systemImage: "pencil")
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
                                Label("测试连接", systemImage: "network")
                                    .frame(minWidth: 80)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isTesting)
                        
                        Button(action: {
                            let newProfile = AIServiceProfile(
                                id: UUID(),
                                name: selectedProfile.name + " (副本)",
                                protocolType: selectedProfile.protocolType,
                                endpoint: selectedProfile.endpoint,
                                apiKey: selectedProfile.apiKey,
                                defaultModel: selectedProfile.defaultModel,
                                timeout: selectedProfile.timeout
                            )
                            preferences.saveProfile(newProfile)
                        }) {
                            Label("复制", systemImage: "doc.on.doc")
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
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {
                profileToDelete = nil
            }
            Button("删除", role: .destructive) {
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
                Text("确定要删除「\(profile.name)」吗？此操作无法撤销。")
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
                // DashScope 需要特殊的 content 格式
                let testMessages: [[String: Any]]
                if profile.protocolType == .dashScope {
                    testMessages = [["role": "user", "content": [["text": "test"]]]]
                } else {
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
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                await MainActor.run {
                    if let httpResponse = response as? HTTPURLResponse {
                        print("🔍 [测试连接] 状态码: \(httpResponse.statusCode)")
                        if httpResponse.statusCode == 200 {
                            testResult = "✅ 连接成功"
                        } else if httpResponse.statusCode == 400 {
                            // 尝试解析错误信息
                            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let message = errorJson["message"] as? String {
                                testResult = "❌ 请求参数错误（400）: \(message)"
                            } else {
                                testResult = "❌ 请求参数错误（400）"
                            }
                        } else if httpResponse.statusCode == 401 {
                            testResult = "❌ 认证失败（401）: API Key 可能无效"
                        } else if httpResponse.statusCode == 403 {
                            testResult = "❌ 访问被拒绝（403）: API Key 可能无权限"
                        } else if httpResponse.statusCode == 404 {
                            testResult = "❌ 端点不存在（404）: 请检查 API Endpoint 配置"
                        } else if httpResponse.statusCode >= 500 {
                            testResult = "❌ 服务器错误（\(httpResponse.statusCode)）"
                        } else {
                            testResult = "❌ 连接失败（状态码: \(httpResponse.statusCode)）"
                        }
                    } else {
                        testResult = "❌ 连接失败：无效响应"
                    }
                    isTesting = false
                }
            } catch let error as URLError {
                await MainActor.run {
                    switch error.code {
                    case .timedOut:
                        testResult = "❌ 连接超时：请检查网络或端点地址"
                    case .cannotFindHost, .cannotConnectToHost:
                        testResult = "❌ 无法连接到服务器：请检查端点地址"
                    case .networkConnectionLost:
                        testResult = "❌ 网络连接中断"
                    default:
                        testResult = "❌ 网络错误：\(error.localizedDescription)"
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ 连接失败：\(error.localizedDescription)"
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
                        Label("设为默认", systemImage: "star")
                    }
                }
                Button(action: onEdit) {
                    Label("编辑", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
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
        switch type {
        case .openAI:
            return "brain.head.profile"
        case .azureOpenAI:
            return "cloud.fill"
        case .dashScope:
            return "cloud.sun.fill"
        case .ollama:
            return "server.rack"
        case .claude:
            return "sparkles"
        case .someIM:
            return "network"
        case .gemini:
            return "star.circle.fill"
        case .custom:
            return "gearshape.fill"
        }
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
    @State private var defaultModel: String
    @State private var timeout: Double
    
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
            _timeout = State(initialValue: 30.0)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("服务名称", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    Picker("协议类型", selection: $protocolType) {
                        ForEach(AIProtocolType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: protocolType) { oldValue, newValue in
                        // 当协议类型改变时，更新 endpoint 和 model
                        if endpoint.isEmpty || endpoint == oldValue.defaultEndpoint {
                            endpoint = newValue.defaultEndpoint ?? ""
                        }
                        if defaultModel.isEmpty || !newValue.recommendedModels.contains(defaultModel) {
                            defaultModel = newValue.recommendedModels.first ?? ""
                        }
                    }
                } header: {
                    Text("基本信息")
                        .font(.headline)
                        .padding(.top, 8)
                } footer: {
                    Text("为这个服务配置起一个易于识别的名称")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section {
                    if protocolType.endpointEditable {
                        TextField("API Endpoint", text: $endpoint, prompt: Text("https://api.example.com/v1"))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        HStack {
                            Text("API Endpoint")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(endpoint.isEmpty ? (protocolType.defaultEndpoint ?? "") : endpoint)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                    
                    if protocolType.requiresAPIKey {
                        SecureField("API Key", text: $apiKey, prompt: Text("输入您的 API Key"))
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    TextField("默认模型", text: $defaultModel, prompt: Text("选择或输入模型名称"))
                        .textFieldStyle(.roundedBorder)
                    
                    // 推荐模型快捷选择
                    if !protocolType.recommendedModels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("推荐模型")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(protocolType.recommendedModels, id: \.self) { model in
                                        Button(action: {
                                            defaultModel = model
                                        }) {
                                            Text(model)
                                                .font(.caption)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule()
                                                        .fill(defaultModel == model ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                                )
                                                .foregroundStyle(defaultModel == model ? Color.accentColor : .primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("超时时间")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(String(format: "%.1f", timeout)) 秒")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $timeout, in: 2.0...60.0, step: 0.5)
                    }
                } header: {
                    Text("连接配置")
                        .font(.headline)
                        .padding(.top, 8)
                } footer: {
                    if protocolType == .someIM {
                        Text("Some.IM 使用固定的 API Endpoint，只需填写 API Key。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if protocolType == .gemini {
                        Text("Gemini 默认使用官方 Endpoint，可以自定义修改。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("配置 API 连接参数，确保服务可以正常访问。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 20)
            .navigationTitle(profile == nil ? "添加 AI 服务" : "编辑 AI 服务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let effectiveEndpoint = protocolType.endpointEditable ? endpoint : (protocolType.defaultEndpoint ?? "")
                        let profileId = profile?.id ?? UUID()
                        
                        print("🔍 [AIProfileEditView] 保存按钮点击")
                        print("  - 是编辑模式: \(profile != nil)")
                        print("  - Profile ID: \(profileId)")
                        print("  - 原始 Profile ID: \(profile?.id.uuidString ?? "无")")
                        
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
                        
                        print("  - 新 Profile ID: \(newProfile.id)")
                        print("  - Profile Name: \(newProfile.name)")
                        
                        onSave(newProfile)
                    }
                    .disabled(name.isEmpty || (protocolType.requiresAPIKey && apiKey.isEmpty))
                    .keyboardShortcut(.defaultAction)
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
}

