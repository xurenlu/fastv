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
            // 工具栏：新建会话 - Apple 风格
            HStack(spacing: 0) {
                Button(action: { viewModel.createNewSession() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                        Text(NSLocalizedString("chat.new.session", comment: ""))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.regularMaterial)

            Divider()

            // 会话列表
            if chatManager.sessions.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label {
                        Text(NSLocalizedString("chat.empty.sessions", comment: ""))
                            .font(.system(size: 15, weight: .medium))
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(chatManager.sessions) { session in
                            ChatSessionRow(
                                session: session,
                                isSelected: viewModel.currentSessionId == session.id,
                                onSelect: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        viewModel.selectSession(session)
                                    }
                                },
                                onDelete: { viewModel.deleteSession(session) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

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

                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .symbolRenderingMode(.hierarchical)
                        Text(session.formattedShortDate)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }

                    if session.messageCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .symbolRenderingMode(.hierarchical)
                            Text("\(session.messageCount)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()
                }
            }

            Spacer()

            if isHovered {
                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.red.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .alert(NSLocalizedString("chat.delete.session", comment: ""), isPresented: $showDeleteConfirmation) {
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("delete", comment: ""), role: .destructive) {
                onDelete()
            }
        } message: {
            Text(NSLocalizedString("chat.delete.session.confirm", comment: ""))
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        if isHovered {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }
}

#Preview {
    ChatSessionListView(viewModel: AIChatViewModel())
}
