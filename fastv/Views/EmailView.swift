//
//  EmailView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 邮箱主视图
struct EmailView: View {
    @StateObject private var viewModel = EmailViewModel()
    @State private var showAccountManagement = false
    
    var body: some View {
        HSplitView {
            // 左侧：文件夹列表
            folderListView
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)
            
            // 中间：邮件列表
            messageListView
                .frame(minWidth: 300, idealWidth: 400)
            
            // 右侧：邮件详情
            if let message = viewModel.selectedMessage {
                messageDetailView(message: message)
                    .frame(minWidth: 400, idealWidth: 500)
            } else {
                emptyDetailView
                    .frame(minWidth: 400, idealWidth: 500)
            }
        }
        .navigationTitle("邮箱")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showAccountManagement = true
                }) {
                    Label("账号管理", systemImage: "person.crop.circle.badge.plus")
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    if let account = viewModel.currentAccount {
                        Task {
                            await viewModel.syncAccount(account)
                        }
                    }
                }) {
                    Label("同步", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .sheet(isPresented: $showAccountManagement) {
            EmailAccountManagementView()
        }
    }
    
    // MARK: - Folder List
    
    private var folderListView: some View {
        VStack(spacing: 0) {
            // 账号选择器
            if !viewModel.accounts.isEmpty {
                Picker("账号", selection: Binding(
                    get: { viewModel.selectedAccountId ?? UUID() },
                    set: { id in
                        if let account = viewModel.accounts.first(where: { $0.id == id }) {
                            viewModel.selectAccount(account)
                        }
                    }
                )) {
                    ForEach(viewModel.accounts) { account in
                        Text(account.displayName).tag(account.id)
                    }
                }
                .pickerStyle(.menu)
                .padding()
            }
            
            Divider()
            
            // 文件夹列表
            List(selection: $viewModel.selectedFolderId) {
                ForEach(viewModel.folders) { folder in
                    FolderRow(folder: folder)
                        .tag(folder.id)
                }
            }
            .listStyle(.sidebar)
        }
    }
    
    // MARK: - Message List
    
    private var messageListView: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索邮件", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 邮件列表
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.messages.isEmpty {
                emptyMessageListView
            } else {
                List(selection: $viewModel.selectedMessageId) {
                    ForEach(viewModel.searchText.isEmpty ? viewModel.messages : viewModel.searchMessages(query: viewModel.searchText)) { message in
                        MessageRow(message: message, showAttachments: viewModel.showAttachments)
                            .tag(message.id)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private var emptyMessageListView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("没有邮件")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            if viewModel.selectedFolderId == nil {
                Text("请选择一个文件夹")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Message Detail
    
    private func messageDetailView(message: EmailMessage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 邮件头部
                messageHeader(message: message)
                
                Divider()
                
                // 邮件正文
                if let htmlBody = message.htmlBody, !htmlBody.isEmpty {
                    // HTML渲染（简化版，实际应该使用WebView）
                    Text(message.textBody ?? message.preview)
                        .textSelection(.enabled)
                } else {
                    Text(message.textBody ?? message.preview)
                        .textSelection(.enabled)
                }
                
                // 附件列表
                if !message.attachments.isEmpty && viewModel.showAttachments {
                    Divider()
                    attachmentsView(attachments: message.attachments)
                }
            }
            .padding()
        }
    }
    
    private func messageHeader(message: EmailMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                EmailAvatarView(email: message.from.email)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.from.name ?? message.from.email)
                        .font(.headline)
                    
                    Text(message.from.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(message.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(message.subject)
                .font(.title3)
                .fontWeight(.semibold)
        }
    }
    
    private func attachmentsView(attachments: [EmailAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("附件")
                .font(.headline)
            
            ForEach(attachments) { attachment in
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                    Text(attachment.filename)
                    Spacer()
                    Text(attachment.sizeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("选择一封邮件查看详情")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let folder: EmailFolder
    
    var body: some View {
        HStack {
            Image(systemName: folder.type.icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(folder.name)
            
            Spacer()
            
            if folder.unreadCount > 0 {
                Text("\(folder.unreadCount)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: EmailMessage
    let showAttachments: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            EmailAvatarView(email: message.from.email, size: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.from.name ?? message.from.email)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(message.date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(message.subject)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(message.isRead ? .secondary : .primary)
                
                Text(message.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                if showAttachments && message.hasAttachments {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                        Text("\(message.attachments.count) 个附件")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(message.isRead ? 0.7 : 1.0)
    }
}

#Preview {
    EmailView()
}

