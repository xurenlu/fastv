//
//  AIScenarioMappingView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

/// AI 场景映射视图
struct AIScenarioMappingView: View {
    @ObservedObject var preferences = UserPreferences.shared
    
    var body: some View {
        Form {
            ForEach(AIScenario.allCases, id: \.self) { scenario in
                ScenarioMappingRowView(scenario: scenario)
            }
        }
        .formStyle(.grouped)
    }
}

/// 场景映射行视图
struct ScenarioMappingRowView: View {
    @ObservedObject var preferences = UserPreferences.shared
    let scenario: AIScenario
    
    @State private var selectedProfileId: UUID?
    @State private var modelOverride: String = ""
    @State private var timeoutOverride: Double?
    @State private var useDefault = true
    
    var currentBinding: AIScenarioBinding? {
        preferences.aiScenarioBindings.first { $0.scenario == scenario }
    }
    
    var selectedProfile: AIServiceProfile? {
        if let profileId = selectedProfileId {
            return preferences.getProfile(id: profileId)
        }
        return preferences.getDefaultProfile()
    }
    
    var body: some View {
        Section {
            Toggle("使用默认配置", isOn: $useDefault)
                .onChange(of: useDefault) { oldValue, newValue in
                    if newValue {
                        // 使用默认，删除绑定
                        preferences.deleteScenarioBinding(for: scenario)
                        selectedProfileId = nil
                        modelOverride = ""
                        timeoutOverride = nil
                    } else {
                        // 不使用默认，创建绑定
                        if let defaultProfile = preferences.getDefaultProfile() {
                            selectedProfileId = defaultProfile.id
                            let binding = AIScenarioBinding(
                                scenario: scenario,
                                profileId: defaultProfile.id
                            )
                            preferences.saveScenarioBinding(binding)
                        }
                    }
                }
            
            if !useDefault {
                // Profile 选择
                Picker("AI 服务", selection: Binding(
                    get: { selectedProfileId ?? UUID() },
                    set: { newId in
                        selectedProfileId = newId
                        updateBinding()
                    }
                )) {
                    Text("未选择").tag(UUID())
                    ForEach(preferences.aiServiceProfiles) { profile in
                        HStack {
                            if profile.isDefault {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                            }
                            Text(profile.name)
                        }
                        .tag(profile.id)
                    }
                }
                
                // 模型覆盖
                if let profile = selectedProfile {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("模型（留空使用服务默认）")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        TextField("例如：\(profile.defaultModel)", text: $modelOverride)
                            .onChange(of: modelOverride) { oldValue, newValue in
                                updateBinding()
                            }
                        
                        // 推荐模型快捷选择
                        if !profile.protocolType.recommendedModels.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Button(action: {
                                        modelOverride = ""
                                        updateBinding()
                                    }) {
                                        Text("使用默认")
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(modelOverride.isEmpty ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                                            )
                                            .foregroundStyle(modelOverride.isEmpty ? .blue : .primary)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    ForEach(profile.protocolType.recommendedModels, id: \.self) { model in
                                        Button(action: {
                                            modelOverride = model
                                            updateBinding()
                                        }) {
                                            Text(model)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(modelOverride == model ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                                                )
                                                .foregroundStyle(modelOverride == model ? .blue : .primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    // 超时覆盖
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("超时时间（留空使用服务默认）")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let timeout = timeoutOverride {
                                Text("\(String(format: "%.1f", timeout)) 秒")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(String(format: "%.1f", profile.timeout)) 秒（默认）")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { timeoutOverride ?? profile.timeout },
                                    set: { newValue in
                                        if abs(newValue - profile.timeout) < 0.1 {
                                            timeoutOverride = nil
                                        } else {
                                            timeoutOverride = newValue
                                        }
                                        updateBinding()
                                    }
                                ),
                                in: 2.0...60.0,
                                step: 0.5
                            )
                            
                            Button(action: {
                                timeoutOverride = nil
                                updateBinding()
                            }) {
                                Text("重置")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .disabled(timeoutOverride == nil)
                        }
                    }
                }
            }
        } header: {
            Text(scenario.displayName)
        } footer: {
            if useDefault {
                if let defaultProfile = preferences.getDefaultProfile() {
                    Text("当前使用默认配置：\(defaultProfile.name) (\(defaultProfile.defaultModel))")
                } else {
                    Text("当前使用默认配置")
                }
            } else if let profile = selectedProfile {
                let model = modelOverride.isEmpty ? profile.defaultModel : modelOverride
                let timeout = timeoutOverride ?? profile.timeout
                Text("使用配置：\(profile.name)，模型：\(model)，超时：\(String(format: "%.1f", timeout))秒")
            }
        }
        .onAppear {
            loadBinding()
        }
    }
    
    private func loadBinding() {
        if let binding = currentBinding {
            useDefault = false
            selectedProfileId = binding.profileId
            modelOverride = binding.modelOverride ?? ""
            timeoutOverride = binding.timeoutOverride
        } else {
            useDefault = true
            selectedProfileId = preferences.getDefaultProfile()?.id
            modelOverride = ""
            timeoutOverride = nil
        }
    }
    
    private func updateBinding() {
        guard !useDefault, let profileId = selectedProfileId else {
            return
        }
        
        let binding = AIScenarioBinding(
            scenario: scenario,
            profileId: profileId,
            modelOverride: modelOverride.isEmpty ? nil : modelOverride,
            timeoutOverride: timeoutOverride
        )
        preferences.saveScenarioBinding(binding)
    }
}

