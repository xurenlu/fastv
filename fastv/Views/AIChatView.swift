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
            // 左侧：会话列表
            ChatSessionListView(viewModel: viewModel)
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
            
            // 右侧：聊天窗口
            if viewModel.currentSessionId != nil {
                ChatWindowView(viewModel: viewModel)
            } else {
                // 空状态：提示创建新会话
                ContentUnavailableView {
                    Label {
                        Text("开始新对话")
                            .font(.system(size: 20, weight: .semibold))
                    } icon: {
                        Image(systemName: "message.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                } description: {
                    VStack(spacing: 8) {
                        Text("点击左侧的"+"按钮创建新会话")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        
                        Button(action: {
                            viewModel.createNewSession()
                        }) {
                            Label("创建新会话", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("AI Chat")
    }
}

#Preview {
    AIChatView()
}

