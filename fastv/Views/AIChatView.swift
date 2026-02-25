//
//  AIChatView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

struct AIChatView: View {
    @StateObject private var viewModel = AIChatViewModel()
    @ObservedObject private var chatManager = ChatManager.shared

    var body: some View {
        HSplitView {
            // 左侧：会话列表 - Apple 风格侧边栏
            ChatSessionListView(viewModel: viewModel)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            // 右侧：聊天窗口
            if viewModel.currentSessionId != nil {
                ChatWindowView(viewModel: viewModel)
            } else {
                // 空状态：优雅的引导
                ContentUnavailableView {
                    Label {
                        Text(NSLocalizedString("chat.start.conversation", comment: ""))
                            .font(.title2.weight(.semibold))
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                } description: {
                    VStack(spacing: 12) {
                        Text(NSLocalizedString("chat.click.to.create", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: { viewModel.createNewSession() }) {
                            Label(NSLocalizedString("chat.create.new.session", comment: ""), systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(NSLocalizedString("ai.chat", comment: "AI Chat"))
    }
}

#Preview {
    AIChatView()
}
