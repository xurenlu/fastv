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

    private func regenerateResponse(for message: ChatMessage) {
        Task { await viewModel.regenerateResponse(for: message) }
    }

    private func retryMessage(_ message: ChatMessage) {
        Task { await viewModel.retryMessage(message) }
    }

    var needsConfiguration: Bool {
        preferences.aiServiceProfiles.isEmpty || preferences.getDefaultProfile() == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // 配置提示横幅 - Apple 风格：克制、可操作
            if needsConfiguration {
                configBanner
            }

            // 顶部：模型选择器和参数
            toolbarSection

            Divider()

            // 消息列表
            messageListSection

            Divider()

            // 输入区域
            ChatInputView(viewModel: viewModel)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.regularMaterial)
                .disabled(needsConfiguration)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .frame(minWidth: 800, idealWidth: 900, maxWidth: 1000, minHeight: 600, idealHeight: 700, maxHeight: 800)
        }
    }

    // MARK: - Config Banner

    private var configBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)

            Text(NSLocalizedString("chat.config.required", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button(NSLocalizedString("chat.open.settings", comment: "")) {
                showSettings = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Toolbar

    private var toolbarSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if !viewModel.availableModels.isEmpty {
                    Picker(NSLocalizedString("chat.model", comment: ""), selection: Binding(
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
                    Text(NSLocalizedString("chat.no.models", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showParameters.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: showParameters ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                        Text(NSLocalizedString("chat.parameters", comment: ""))
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(needsConfiguration)

                Spacer()

                if let session = viewModel.currentSession {
                    Text(session.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            if showParameters {
                Divider()
                parametersPanel
            }
        }
    }

    private var parametersPanel: some View {
        HStack(spacing: 28) {
            parameterSlider(
                label: "温度",
                value: $preferences.chatTemperature,
                range: 0...2,
                step: 0.1,
                width: 140
            )
            parameterSlider(
                label: "Top P",
                value: $preferences.chatTopP,
                range: 0...1,
                step: 0.05,
                width: 140
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Top K")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("0=不设置", value: $preferences.chatTopK, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }
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
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    private func parameterSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
            }
            Slider(value: value, in: range, step: step)
                .frame(width: width)
        }
    }

    // MARK: - Message List

    private var messageListSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if viewModel.currentMessages.isEmpty {
                        Spacer()
                        ContentUnavailableView {
                            Text(NSLocalizedString("chat.start.conversation", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    } else {
                        ForEach(viewModel.currentMessages) { message in
                            ChatMessageView(
                                message: message,
                                modelName: message.isAIMessage ? viewModel.selectedModel : nil,
                                onRegenerate: message.isAIMessage ? { regenerateResponse(for: message) } : nil,
                                onRetry: (message.isUserMessage && message.sendError != nil) ? { retryMessage(message) } : nil
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .onChange(of: viewModel.currentMessages.count) { oldValue, newValue in
                if newValue > oldValue, let lastMessage = viewModel.currentMessages.last {
                    DispatchQueue.main.async {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.currentSessionId) { _, _ in
                if let lastMessage = viewModel.currentMessages.last {
                    DispatchQueue.main.async {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ChatWindowView(viewModel: AIChatViewModel())
}
