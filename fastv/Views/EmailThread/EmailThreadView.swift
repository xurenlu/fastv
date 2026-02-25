//
//  EmailThreadView.swift
//  fastv
//
//  Created for Email Thread View
//

import SwiftUI

/// 邮件线程列表视图
struct EmailThreadView: View {
    @ObservedObject var viewModel: EmailViewModel
    @State private var selectedThreadId: UUID?
    
    var body: some View {
        List(selection: $selectedThreadId) {
            ForEach(viewModel.threads) { thread in
                ThreadRow(thread: thread, viewModel: viewModel)
                    .tag(thread.id)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selectedThreadId) { _, newValue in
            if let threadId = newValue {
                viewModel.selectThread(threadId)
            }
        }
    }
}

/// 线程行视图
struct ThreadRow: View {
    let thread: EmailThread
    @ObservedObject var viewModel: EmailViewModel
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(thread.subject ?? "无主题")
                    .font(.headline)
                    .lineLimit(1)
                
                Text(thread.participantEmails.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label("\(thread.messageCount)", systemImage: "envelope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if thread.unreadCount > 0 {
                        Label("\(thread.unreadCount) 未读", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            Spacer()
            
            Text(formatDate(thread.lastMessageDate))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// 线程详情视图
struct EmailThreadDetailView: View {
    let thread: EmailThread
    @ObservedObject var viewModel: EmailViewModel
    @State private var messages: [EmailMessage] = []
    @State private var isLoading = false
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(messages) { message in
                    ThreadMessageView(message: message, viewModel: viewModel)
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
        .task {
            await loadMessages()
        }
    }
    
    private func loadMessages() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            messages = try await EmailThreadService.shared.getMessagesInThread(thread.id)
            // 按日期排序
            messages.sort { $0.date < $1.date }
        } catch {
            print("❌ [EmailThreadDetailView] 加载线程消息失败: \(error)")
        }
    }
}

/// 线程中的单条消息视图
struct ThreadMessageView: View {
    let message: EmailMessage
    @ObservedObject var viewModel: EmailViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.from.displayName)
                    .font(.headline)
                
                Text(message.from.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(formatDate(message.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if !message.subject.isEmpty {
                Text(message.subject)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if let textBody = message.textBody, !textBody.isEmpty {
                Text(String(textBody.prefix(200)))
                    .font(.body)
                    .lineLimit(3)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

