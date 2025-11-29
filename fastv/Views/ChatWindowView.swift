//
//  ChatWindowView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

struct ChatWindowView: View {
    @ObservedObject var viewModel: AIChatViewModel
    
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var showSettings = false
    @State private var showParameters = false
    
    var needsConfiguration: Bool {
        preferences.aiAPIEndpoint.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 配置提示横幅
            if needsConfiguration {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("请先在设置中配置 API Endpoint（API Key 可选，某些本地 API 如 Ollama 不需要）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("打开设置") {
                        showSettings = true
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                
                Divider()
            }
            
            // 顶部：模型选择器和参数设置
            VStack(spacing: 0) {
                HStack {
                    if !viewModel.availableModels.isEmpty {
                        Picker("模型", selection: Binding(
                            get: { viewModel.selectedModel },
                            set: { viewModel.changeModel($0) }
                        )) {
                            ForEach(viewModel.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                        .disabled(needsConfiguration)
                    } else {
                        Text("无可用模型")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // 参数设置按钮
                    Button(action: {
                        withAnimation {
                            showParameters.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showParameters ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                            Text("参数")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(needsConfiguration)
                    
                    Spacer()
                    
                    if let session = viewModel.currentSession {
                        Text(session.title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                
                // 参数设置面板
                if showParameters {
                    VStack(spacing: 0) {
                        Divider()
                        
                        HStack(spacing: 24) {
                            // Temperature
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("温度")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.2f", preferences.chatTemperature))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40, alignment: .trailing)
                                }
                                Slider(value: $preferences.chatTemperature, in: 0...2, step: 0.1)
                                    .frame(width: 140)
                            }
                            
                            // Top P
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Top P")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.2f", preferences.chatTopP))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40, alignment: .trailing)
                                }
                                Slider(value: $preferences.chatTopP, in: 0...1, step: 0.05)
                                    .frame(width: 140)
                            }
                            
                            // Top K
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Top K")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("0=不设置", value: $preferences.chatTopK, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                            }
                            
                            // Max Tokens
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Max Tokens")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $preferences.chatMaxTokens, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                }
            }
            
            Divider()
            
            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.currentMessages.isEmpty {
                            Spacer()
                            ContentUnavailableView {
                                Text("开始对话")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        } else {
                            ForEach(viewModel.currentMessages) { message in
                                ChatMessageView(
                                    message: message,
                                    modelName: message.isAIMessage ? viewModel.selectedModel : nil
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: viewModel.currentMessages.count) { oldValue, newValue in
                    // 新消息时滚动到底部
                    if let lastMessage = viewModel.currentMessages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // 输入区域
            ChatInputView(viewModel: viewModel)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
                .disabled(needsConfiguration)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .frame(minWidth: 800, idealWidth: 900, maxWidth: 1000, minHeight: 600, idealHeight: 700, maxHeight: 800)
        }
    }
}

#Preview {
    ChatWindowView(viewModel: AIChatViewModel())
}

