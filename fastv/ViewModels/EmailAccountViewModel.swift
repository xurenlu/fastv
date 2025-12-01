//
//  EmailAccountViewModel.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 账号管理视图模型
@MainActor
class EmailAccountViewModel: ObservableObject {
    @Published var accounts: [EmailAccount] = []
    @Published var isAddingAccount = false
    @Published var editingAccount: EmailAccount?
    
    // 添加/编辑表单
    @Published var emailAddress: String = ""
    @Published var displayName: String = ""
    @Published var password: String = ""
    @Published var serviceType: EmailServiceType = .gmail
    
    // 高级设置
    @Published var showAdvancedSettings = false
    @Published var imapHost: String = ""
    @Published var imapPort: String = "993"
    @Published var imapEncryption: EmailEncryption = .ssl
    @Published var smtpHost: String = ""
    @Published var smtpPort: String = "587"
    @Published var smtpEncryption: EmailEncryption = .startTLS
    
    // 状态
    @Published var isTestingConnection = false
    @Published var connectionTestResult: ConnectionTestResult?
    @Published var errorMessage: String?
    
    private let emailStore = EmailStore.shared
    @Published private(set) var emailService = EmailService.shared
    
    init() {
        loadAccounts()
        // 初始化时自动填充默认服务（Gmail）的配置
        serviceTypeChanged()
    }
    
    /// 加载账号列表
    func loadAccounts() {
        accounts = emailStore.accounts
    }
    
    /// 开始添加账号
    func startAddingAccount() {
        resetForm()
        isAddingAccount = true
        editingAccount = nil
    }
    
    /// 开始编辑账号
    func startEditingAccount(_ account: EmailAccount) {
        // 确保使用最新的账号数据（从 EmailStore 重新获取）
        // 这样可以确保获取到保存后的最新配置
        let latestAccount = emailStore.getAccount(id: account.id) ?? account
        
        editingAccount = latestAccount
        isAddingAccount = false
        
        emailAddress = latestAccount.emailAddress
        displayName = latestAccount.displayName
        serviceType = latestAccount.serviceType
        
        // 编辑账号时，总是使用账号中保存的实际配置（而不是预设配置）
        // 这样用户可以看到和编辑他们之前自定义的配置
        imapHost = latestAccount.imapHost
        imapPort = String(latestAccount.imapPort)
        imapEncryption = latestAccount.imapEncryption
        
        smtpHost = latestAccount.smtpHost
        smtpPort = String(latestAccount.smtpPort)
        smtpEncryption = latestAccount.smtpEncryption
        
        // 检查账号的配置是否与预设配置不同，如果不同则自动展开高级设置
        let hasCustomConfig = {
            if let imapConfig = latestAccount.serviceType.imapConfig {
                if latestAccount.imapHost != imapConfig.host ||
                   latestAccount.imapPort != imapConfig.port ||
                   latestAccount.imapEncryption != imapConfig.encryption {
                    print("📝 [EmailAccountViewModel] 检测到自定义 IMAP 配置")
                    return true
                }
            }
            if let smtpConfig = latestAccount.serviceType.smtpConfig {
                if latestAccount.smtpHost != smtpConfig.host ||
                   latestAccount.smtpPort != smtpConfig.port ||
                   latestAccount.smtpEncryption != smtpConfig.encryption {
                    print("📝 [EmailAccountViewModel] 检测到自定义 SMTP 配置: \(latestAccount.smtpHost):\(latestAccount.smtpPort) \(latestAccount.smtpEncryption.rawValue) vs 预设: \(smtpConfig.host):\(smtpConfig.port) \(smtpConfig.encryption.rawValue)")
                    return true
                }
            }
            return latestAccount.serviceType == .custom
        }()
        
        print("📝 [EmailAccountViewModel] 编辑账号: \(latestAccount.emailAddress), hasCustomConfig: \(hasCustomConfig), showAdvancedSettings: \(hasCustomConfig)")
        showAdvancedSettings = hasCustomConfig
        
        // 密码需要从Keychain获取，但这里不显示
        password = ""
    }
    
    /// 取消编辑
    func cancelEditing() {
        resetForm()
        isAddingAccount = false
        editingAccount = nil
    }
    
    /// 保存账号
    func saveAccount() async throws {
        // 验证输入
        guard !emailAddress.isEmpty else {
            throw EmailServiceError.invalidConfiguration("邮箱地址不能为空")
        }
        
        guard !password.isEmpty || editingAccount != nil else {
            throw EmailServiceError.invalidConfiguration("密码不能为空")
        }
        
        // 构建账号
        var account: EmailAccount
        
        if let editing = editingAccount {
            // 更新现有账号
            account = editing
            account.emailAddress = emailAddress
            account.displayName = displayName.isEmpty ? emailAddress : displayName
            account.serviceType = serviceType
            
            // 更新服务器配置
            // 简化逻辑：直接使用表单中的配置，不管开关状态
            // 用户看到什么就保存什么
            account.imapHost = imapHost
            account.imapPort = Int(imapPort) ?? 993
            account.imapEncryption = imapEncryption
            
            account.smtpHost = smtpHost
            account.smtpPort = Int(smtpPort) ?? 587
            account.smtpEncryption = smtpEncryption
            
            print("💾 [EmailAccountViewModel] 保存配置 - SMTP: \(smtpHost):\(smtpPort) \(smtpEncryption.rawValue)")
        } else {
            // 创建新账号
            if let imapConfig = serviceType.imapConfig {
                account = EmailAccount(
                    emailAddress: emailAddress,
                    displayName: displayName.isEmpty ? emailAddress : displayName,
                    serviceType: serviceType,
                    imapHost: imapConfig.host,
                    imapPort: imapConfig.port,
                    imapEncryption: imapConfig.encryption,
                    smtpHost: serviceType.smtpConfig?.host ?? "",
                    smtpPort: serviceType.smtpConfig?.port ?? 587,
                    smtpEncryption: serviceType.smtpConfig?.encryption ?? .startTLS
                )
            } else {
                account = EmailAccount(
                    emailAddress: emailAddress,
                    displayName: displayName.isEmpty ? emailAddress : displayName,
                    serviceType: .custom,
                    imapHost: imapHost,
                    imapPort: Int(imapPort) ?? 993,
                    imapEncryption: imapEncryption,
                    smtpHost: smtpHost,
                    smtpPort: Int(smtpPort) ?? 587,
                    smtpEncryption: smtpEncryption
                )
            }
            
            // 如果是第一个账号，设为默认
            if accounts.isEmpty {
                account.isDefault = true
            }
        }
        
        // 保存密码到Keychain
        if !password.isEmpty {
            try EmailCredentialStore.shared.savePassword(accountId: account.id, password: password)
        }
        
        // 保存账号
        if editingAccount != nil {
            print("💾 [EmailAccountViewModel] 保存账号更新: \(account.emailAddress)")
            print("💾 [EmailAccountViewModel] SMTP配置: \(account.smtpHost):\(account.smtpPort) \(account.smtpEncryption.rawValue)")
            try await emailStore.updateAccount(account)
            // updateAccount 内部已经调用了 loadAccounts()，但我们需要等待它完成
            // 然后重新加载 ViewModel 的账号列表
            await Task.yield() // 让出执行权，确保 EmailStore 的异步操作完成
        } else {
            try await emailStore.addAccount(account)
            await Task.yield()
        }
        
        // 重新加载账号列表，确保获取最新数据
        loadAccounts()
        
        resetForm()
        isAddingAccount = false
        editingAccount = nil
    }
    
    /// 删除账号
    func deleteAccount(_ account: EmailAccount) async throws {
        try await emailStore.deleteAccount(account)
        loadAccounts()
    }
    
    /// 测试连接
    func testConnection() async {
        isTestingConnection = true
        errorMessage = nil
        connectionTestResult = nil
        
        // 构建临时账号用于测试
        let testAccount: EmailAccount
        if let imapConfig = serviceType.imapConfig {
            testAccount = EmailAccount(
                emailAddress: emailAddress,
                displayName: displayName,
                serviceType: serviceType,
                imapHost: imapConfig.host,
                imapPort: imapConfig.port,
                imapEncryption: imapConfig.encryption,
                smtpHost: serviceType.smtpConfig?.host ?? "",
                smtpPort: serviceType.smtpConfig?.port ?? 587,
                smtpEncryption: serviceType.smtpConfig?.encryption ?? .startTLS
            )
        } else {
            testAccount = EmailAccount(
                emailAddress: emailAddress,
                displayName: displayName,
                serviceType: .custom,
                imapHost: imapHost,
                imapPort: Int(imapPort) ?? 993,
                imapEncryption: imapEncryption,
                smtpHost: smtpHost,
                smtpPort: Int(smtpPort) ?? 587,
                smtpEncryption: smtpEncryption
            )
        }
        
        // 确定使用的密码
        // 如果密码为空且正在编辑账号，则从 Keychain 获取已存储的密码
        var testPassword = password
        if testPassword.isEmpty, let editing = editingAccount {
            // 尝试从 Keychain 获取已存储的密码
            if let storedPassword = try? EmailCredentialStore.shared.getPassword(accountId: editing.id) {
                testPassword = storedPassword
            }
        }
        
        // 验证密码
        guard !testPassword.isEmpty else {
            connectionTestResult = ConnectionTestResult(success: false, message: "密码不能为空", stages: [])
            errorMessage = "密码不能为空"
            isTestingConnection = false
            return
        }
        
        do {
            let report = try await emailService.testConnection(account: testAccount, password: testPassword)
            let stages = report.stages.map {
                ConnectionTestStageResult(
                    id: UUID(),
                    name: $0.name,
                    success: $0.success,
                    detail: $0.detail
                )
            }
            let success = report.isSuccess
            let message = success ? "IMAP 与 SMTP 均已通过" : "连接失败，请查看详细阶段信息"
            connectionTestResult = ConnectionTestResult(success: success, message: message, stages: stages)
        } catch {
            connectionTestResult = ConnectionTestResult(
                success: false,
                message: error.localizedDescription,
                stages: []
            )
            errorMessage = error.localizedDescription
        }
        
        isTestingConnection = false
    }
    
    /// 服务类型改变时更新配置
    func serviceTypeChanged() {
        if let imapConfig = serviceType.imapConfig {
            imapHost = imapConfig.host
            imapPort = String(imapConfig.port)
            imapEncryption = imapConfig.encryption
            // 预设服务时，如果之前是自定义，关闭高级设置
            if serviceType != .custom {
                showAdvancedSettings = false
            }
        } else {
            // 自定义服务时，自动展开高级设置
            showAdvancedSettings = true
        }
        
        if let smtpConfig = serviceType.smtpConfig {
            smtpHost = smtpConfig.host
            smtpPort = String(smtpConfig.port)
            smtpEncryption = smtpConfig.encryption
        }
    }
    
    /// 重置表单
    private func resetForm() {
        emailAddress = ""
        displayName = ""
        password = ""
        serviceType = .gmail
        showAdvancedSettings = false
        connectionTestResult = nil
        errorMessage = nil
        // 重置后自动填充默认服务的配置
        serviceTypeChanged()
    }
}

/// 连接测试结果
struct ConnectionTestResult {
    let success: Bool
    let message: String
    let stages: [ConnectionTestStageResult]
}

struct ConnectionTestStageResult: Identifiable {
    let id: UUID
    let name: String
    let success: Bool
    let detail: String
}

