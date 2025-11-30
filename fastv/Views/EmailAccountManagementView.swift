//
//  EmailAccountManagementView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 账号管理视图
struct EmailAccountManagementView: View {
    @StateObject private var viewModel = EmailAccountViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 账号列表
                if viewModel.accounts.isEmpty && !viewModel.isAddingAccount {
                    emptyStateView
                } else {
                    accountListView
                }
            }
            .navigationTitle("邮箱账号管理")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        viewModel.startAddingAccount()
                    }) {
                        Label("添加账号", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.isAddingAccount) {
                accountFormView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    // MARK: - Account List
    
    private var accountListView: some View {
        List {
            ForEach(viewModel.accounts) { account in
                AccountRow(account: account) {
                    viewModel.startEditingAccount(account)
                } onDelete: {
                    Task {
                        try? await viewModel.deleteAccount(account)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("还没有添加邮箱账号")
                .font(.headline)
            
            Text("点击右上角的"+"按钮添加第一个账号")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(action: {
                viewModel.startAddingAccount()
            }) {
                Label("添加账号", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Account Form
    
    private var accountFormView: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    Picker("邮箱服务", selection: $viewModel.serviceType) {
                        ForEach(EmailServiceType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: viewModel.serviceType) { _, _ in
                        viewModel.serviceTypeChanged()
                    }
                    
                    TextField("邮箱地址", text: $viewModel.emailAddress)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                    
                    TextField("显示名称（可选）", text: $viewModel.displayName)
                    
                    SecureField("密码", text: $viewModel.password)
                        .textContentType(.password)
                }
                
                Section {
                    DisclosureGroup("高级设置", isExpanded: $viewModel.showAdvancedSettings) {
                        TextField("IMAP服务器", text: $viewModel.imapHost)
                        TextField("IMAP端口", text: $viewModel.imapPort)
                        Picker("IMAP加密", selection: $viewModel.imapEncryption) {
                            Text("无").tag(EmailEncryption.none)
                            Text("SSL").tag(EmailEncryption.ssl)
                            Text("STARTTLS").tag(EmailEncryption.startTLS)
                        }
                        
                        TextField("SMTP服务器", text: $viewModel.smtpHost)
                        TextField("SMTP端口", text: $viewModel.smtpPort)
                        Picker("SMTP加密", selection: $viewModel.smtpEncryption) {
                            Text("无").tag(EmailEncryption.none)
                            Text("SSL").tag(EmailEncryption.ssl)
                            Text("STARTTLS").tag(EmailEncryption.startTLS)
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        Task {
                            await viewModel.testConnection()
                        }
                    }) {
                        HStack {
                            if viewModel.isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "network")
                            }
                            Text("测试连接")
                        }
                    }
                    .disabled(viewModel.isTestingConnection || viewModel.emailAddress.isEmpty || viewModel.password.isEmpty)
                    
                    if let result = viewModel.connectionTestResult {
                        HStack {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.success ? .green : .red)
                            Text(result.message)
                                .foregroundStyle(result.success ? .green : .red)
                        }
                    }
                }
            }
            .navigationTitle(viewModel.editingAccount == nil ? "添加账号" : "编辑账号")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.cancelEditing()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            do {
                                try await viewModel.saveAccount()
                                dismiss()
                            } catch {
                                viewModel.errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(viewModel.emailAddress.isEmpty || viewModel.password.isEmpty)
                }
            }
            .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("确定") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}

// MARK: - Account Row

struct AccountRow: View {
    let account: EmailAccount
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.displayName)
                    .font(.headline)
                
                Text(account.emailAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    StatusIndicator(status: account.connectionStatus)
                    Text(account.serviceType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if account.isDefault {
                Label("默认", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            
            Menu {
                Button(action: onEdit) {
                    Label("编辑", systemImage: "pencil")
                }
                
                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct StatusIndicator: View {
    let status: ConnectionStatus
    
    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }
    
    private var statusColor: Color {
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }
}

#Preview {
    EmailAccountManagementView()
}

