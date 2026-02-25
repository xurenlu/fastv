//
//  ChatSessionListView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

struct ChatSessionListView: View {
    @ObservedObject var viewModel: AIChatViewModel
    @ObservedObject private var chatManager = ChatManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏：新建会话按钮
            HStack(spacing: 0) {
                Button(action: {
                    viewModel.createNewSession()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("新建会话")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                Rectangle()
                    .fill(.regularMaterial)
            }
            
            Divider()
            
            // 会话列表
            if chatManager.sessions.isEmpty {
                Spacer()
                ContentUnavailableView {
                    VStack(spacing: 8) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("暂无会话")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(chatManager.sessions) { session in
                            ChatSessionRow(
                                session: session,
                                isSelected: viewModel.currentSessionId == session.id,
                                onSelect: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        viewModel.selectSession(session)
                                    }
                                },
                                onDelete: {
                                    viewModel.deleteSession(session)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ChatSessionRow: View {
    let session: ChatSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        HStack(spacing: 8) {
            // 显示模式
            VStack(alignment: .leading, spacing: 6) {
                Text(session.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .primary)
                
                // 优先显示总结，如果没有总结则显示最后一条消息预览
                if let summary = session.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                } else if let preview = session.lastMessagePreview {
                    Text(preview)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .foregroundStyle(.tertiary)
                }
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(session.formattedShortDate)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    
                    if session.messageCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text("\(session.messageCount)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            // 操作按钮（只保留删除按钮）
            HStack(spacing: 6) {
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(width: 24, height: 24)
                        .background {
                            Circle()
                                .fill(Color.red.opacity(0.1))
                        }
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1.0 : 0.0)
                .allowsHitTesting(isHovered)
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.secondary.opacity(0.08) : Color.clear))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isSelected ? 1.0 : (isHovered ? 1.01 : 1.0))
        .shadow(color: isSelected ? Color.accentColor.opacity(0.1) : .clear, radius: 4, x: 0, y: 2)
        .alert("删除会话", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("确定要删除这个会话吗？此操作无法撤销。")
        }
    }
}

#Preview {
    ChatSessionListView(viewModel: AIChatViewModel())
}

