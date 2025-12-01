//
//  EmailAccountManagementView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 邮箱账号管理视图 - 符合 Apple 设计标准
struct EmailAccountManagementView: View {
    @StateObject private var viewModel = EmailAccountViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.accounts.isEmpty && !viewModel.isAddingAccount {
                    emptyStateView
                } else {
                    accountListView
                }
            }
            .navigationTitle("邮箱账号")
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
            .sheet(isPresented: Binding(
                get: { viewModel.isAddingAccount || viewModel.editingAccount != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.isAddingAccount = false
                        viewModel.cancelEditing()
                    }
                }
            )) {
                accountFormView
            }
        }
        .frame(minWidth: 640, minHeight: 480)
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
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, 8)
            
            VStack(spacing: 10) {
                Text("还没有邮箱账号")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text("添加邮箱账号以开始收发邮件")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)
            
            Button(action: {
                viewModel.startAddingAccount()
            }) {
                Label("添加账号", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    // MARK: - Account Form
    
    private var accountFormView: some View {
        NavigationStack {
            Form {
                // 基本信息部分
                Section {
                    // 邮箱服务选择
                    Picker("邮箱服务", selection: $viewModel.serviceType) {
                        ForEach(EmailServiceType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: viewModel.serviceType) { _, _ in
                        viewModel.serviceTypeChanged()
                    }
                    
                    // 邮箱地址
                    TextField("邮箱地址", text: $viewModel.emailAddress)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        #endif
                    
                    // 显示名称
                    TextField("显示名称", text: $viewModel.displayName, prompt: Text("可选"))
                    
                    // 密码
                    SecureField(
                        viewModel.editingAccount == nil ? "密码" : "密码（留空则不修改）",
                        text: $viewModel.password
                    )
                    .textContentType(.password)
                } header: {
                    Text("账号信息")
                } footer: {
                    if viewModel.serviceType != .custom {
                        Text("服务器配置已自动设置")
                            .font(.caption)
                    }
                }
                
                // 服务器配置（预设服务显示只读，自定义服务可编辑）
                if viewModel.serviceType == .custom {
                    // 自定义服务：显示可编辑的高级设置
                    Section {
                        DisclosureGroup("服务器设置", isExpanded: $viewModel.showAdvancedSettings) {
                            VStack(spacing: 16) {
                                // IMAP 设置
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("接收邮件服务器 (IMAP)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                        .textCase(.none)
                                    
                                    TextField("服务器地址", text: $viewModel.imapHost)
                                    
                                    HStack(spacing: 12) {
                                        TextField("端口", text: $viewModel.imapPort)
                                            .frame(width: 120)
                                        
                                        Picker("加密方式", selection: $viewModel.imapEncryption) {
                                            Text("无").tag(EmailEncryption.none)
                                            Text("SSL/TLS").tag(EmailEncryption.ssl)
                                            Text("STARTTLS").tag(EmailEncryption.startTLS)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                                
                                Divider()
                                    .padding(.vertical, 4)
                                
                                // SMTP 设置
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("发送邮件服务器 (SMTP)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                        .textCase(.none)
                                    
                                    TextField("服务器地址", text: $viewModel.smtpHost)
                                    
                                    HStack(spacing: 12) {
                                        TextField("端口", text: $viewModel.smtpPort)
                                            .frame(width: 120)
                                        
                                        Picker("加密方式", selection: $viewModel.smtpEncryption) {
                                            Text("无").tag(EmailEncryption.none)
                                            Text("SSL/TLS").tag(EmailEncryption.ssl)
                                            Text("STARTTLS").tag(EmailEncryption.startTLS)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    } header: {
                        Text("服务器配置")
                    }
                } else {
                    // 预设服务：显示可编辑的配置信息（编辑账号时允许自定义）
                    Section {
                        // 编辑账号时，显示高级设置开关
                        if viewModel.editingAccount != nil {
                            Toggle("自定义服务器配置", isOn: $viewModel.showAdvancedSettings)
                                .font(.subheadline)
                        }
                        
                        if viewModel.showAdvancedSettings || viewModel.editingAccount == nil {
                            DisclosureGroup("服务器设置", isExpanded: .constant(true)) {
                                VStack(spacing: 16) {
                                    // IMAP 设置
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("接收邮件服务器 (IMAP)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                            .textCase(.none)
                                        
                                        TextField("服务器地址", text: $viewModel.imapHost)
                                            .onChange(of: viewModel.imapHost) { _, _ in
                                                // 用户修改配置时，自动启用高级设置
                                                if viewModel.editingAccount != nil {
                                                    viewModel.showAdvancedSettings = true
                                                }
                                            }
                                        
                                        HStack(spacing: 12) {
                                            TextField("端口", text: $viewModel.imapPort)
                                                .frame(width: 120)
                                                .onChange(of: viewModel.imapPort) { _, _ in
                                                    if viewModel.editingAccount != nil {
                                                        viewModel.showAdvancedSettings = true
                                                    }
                                                }
                                            
                                            Picker("加密方式", selection: $viewModel.imapEncryption) {
                                                Text("无").tag(EmailEncryption.none)
                                                Text("SSL/TLS").tag(EmailEncryption.ssl)
                                                Text("STARTTLS").tag(EmailEncryption.startTLS)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .onChange(of: viewModel.imapEncryption) { _, _ in
                                                if viewModel.editingAccount != nil {
                                                    viewModel.showAdvancedSettings = true
                                                }
                                            }
                                        }
                                    }
                                    
                                    Divider()
                                        .padding(.vertical, 4)
                                    
                                    // SMTP 设置
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("发送邮件服务器 (SMTP)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                            .textCase(.none)
                                        
                                        TextField("服务器地址", text: $viewModel.smtpHost)
                                            .onChange(of: viewModel.smtpHost) { _, _ in
                                                // 用户修改配置时，自动启用高级设置
                                                if viewModel.editingAccount != nil {
                                                    viewModel.showAdvancedSettings = true
                                                }
                                            }
                                        
                                        HStack(spacing: 12) {
                                            TextField("端口", text: $viewModel.smtpPort)
                                                .frame(width: 120)
                                                .onChange(of: viewModel.smtpPort) { _, _ in
                                                    if viewModel.editingAccount != nil {
                                                        viewModel.showAdvancedSettings = true
                                                    }
                                                }
                                            
                                            Picker("加密方式", selection: $viewModel.smtpEncryption) {
                                                Text("无").tag(EmailEncryption.none)
                                                Text("SSL/TLS").tag(EmailEncryption.ssl)
                                                Text("STARTTLS").tag(EmailEncryption.startTLS)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .onChange(of: viewModel.smtpEncryption) { _, _ in
                                                if viewModel.editingAccount != nil {
                                                    viewModel.showAdvancedSettings = true
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        } else {
                            // 只读显示（添加新账号时）
                            VStack(spacing: 12) {
                                // IMAP 配置
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("接收邮件 (IMAP)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                        
                                        Text(viewModel.imapHost)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        
                                        HStack(spacing: 8) {
                                            Text("端口: \(viewModel.imapPort)")
                                            Text("•")
                                            Text(encryptionDisplayName(viewModel.imapEncryption))
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .symbolRenderingMode(.hierarchical)
                                }
                                
                                Divider()
                                
                                // SMTP 配置
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("发送邮件 (SMTP)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                        
                                        Text(viewModel.smtpHost)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        
                                        HStack(spacing: 8) {
                                            Text("端口: \(viewModel.smtpPort)")
                                            Text("•")
                                            Text(encryptionDisplayName(viewModel.smtpEncryption))
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .symbolRenderingMode(.hierarchical)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("服务器配置")
                    } footer: {
                        if viewModel.editingAccount != nil && viewModel.showAdvancedSettings {
                            Text("自定义服务器配置将覆盖预设配置")
                                .font(.caption)
                        } else if viewModel.editingAccount == nil {
                            Text("这些设置已根据您选择的邮箱服务自动配置")
                                .font(.caption)
                        }
                    }
                }
                
                // 测试连接
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
                    .disabled(viewModel.isTestingConnection || 
                             viewModel.emailAddress.isEmpty || 
                             // 编辑账号时，密码可以为空（使用已存储的密码）
                             (viewModel.password.isEmpty && viewModel.editingAccount == nil))
                    
                    if let result = viewModel.connectionTestResult {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.success ? Color.green : Color.red)
                                    .symbolRenderingMode(.hierarchical)
                                
                                Text(result.message)
                                    .foregroundStyle(result.success ? Color.primary : Color.red)
                            }
                            
                            ConnectionStagesView(stages: result.stages)
                        }
                        .font(.subheadline)
                        .padding(.top, 4)
                    }
                } header: {
                    Text("连接测试")
                } footer: {
                    if viewModel.connectionTestResult == nil {
                        Text("测试连接以确保账号配置正确")
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(viewModel.editingAccount == nil ? "添加邮箱账号" : "编辑邮箱账号")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.cancelEditing()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.editingAccount == nil ? "添加" : "保存") {
                        Task {
                            do {
                                try await viewModel.saveAccount()
                                dismiss()
                            } catch {
                                viewModel.errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(viewModel.emailAddress.isEmpty || 
                             viewModel.isTestingConnection ||
                             (viewModel.password.isEmpty && viewModel.editingAccount == nil))
                }
            }
            .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("好", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 640)
    }
}

// MARK: - Account Row

struct AccountRow: View {
    let account: EmailAccount
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // 状态指示器
            StatusIndicator(status: account.connectionStatus)
            
            // 账号信息
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    if account.isDefault {
                        Label("默认", systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                
                Text(account.emailAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 4) {
                    Text(account.serviceType.displayName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    if account.isEnabled {
                        Text("•")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        
                        Text("已启用")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            
            Spacer(minLength: 12)
            
            // 操作按钮组
            HStack(spacing: 8) {
                // 编辑按钮 - 更大更明显
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help("编辑账号")
                
                // 删除按钮
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("删除账号", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
                .help("更多操作")
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let status: ConnectionStatus
    
    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 9, height: 9)
            .overlay {
                Circle()
                    .stroke(statusColor.opacity(0.2), lineWidth: 1)
                    .frame(width: 11, height: 11)
            }
    }
    
    private var statusColor: Color {
        switch status {
        case .connected:
            return Color(red: 0.2, green: 0.78, blue: 0.35) // Apple green
        case .connecting:
            return Color(red: 1.0, green: 0.58, blue: 0.0) // Apple orange
        case .disconnected:
            return Color.secondary
        case .error:
            return Color(red: 1.0, green: 0.23, blue: 0.19) // Apple red
        }
    }
}

// MARK: - Helper Functions

private func encryptionDisplayName(_ encryption: EmailEncryption) -> String {
    switch encryption {
    case .none:
        return "无加密"
    case .ssl:
        return "SSL/TLS"
    case .startTLS:
        return "STARTTLS"
    }
}

struct ConnectionStagesView: View {
    let stages: [ConnectionTestStageResult]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(stages) { (stage: ConnectionTestStageResult) in
                ConnectionStageRow(stage: stage)
            }
        }
    }
}

struct ConnectionStageRow: View {
    let stage: ConnectionTestStageResult
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: stage.success ? "checkmark.seal.fill" : "xmark.seal.fill")
                .foregroundStyle(stage.success ? Color.green : Color.red)
                .symbolRenderingMode(.hierarchical)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(stage.detail)
                    .font(.caption)
                    .foregroundStyle(stage.success ? Color.secondary : Color.red)
            }
        }
    }
}

// MARK: - Preview

#Preview("账号列表") {
    EmailAccountManagementView()
}
