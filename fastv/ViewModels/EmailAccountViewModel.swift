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
        editingAccount = account
        isAddingAccount = false
        
        emailAddress = account.emailAddress
        displayName = account.displayName
        serviceType = account.serviceType
        
        // 如果服务类型是自定义，自动展开高级设置
        if account.serviceType == .custom {
            showAdvancedSettings = true
        } else {
            showAdvancedSettings = false
        }
        
        // 如果服务类型有预设配置，使用预设配置；否则使用账号中保存的配置
        if let imapConfig = account.serviceType.imapConfig {
            imapHost = imapConfig.host
            imapPort = String(imapConfig.port)
            imapEncryption = imapConfig.encryption
        } else {
            imapHost = account.imapHost
            imapPort = String(account.imapPort)
            imapEncryption = account.imapEncryption
        }
        
        if let smtpConfig = account.serviceType.smtpConfig {
            smtpHost = smtpConfig.host
            smtpPort = String(smtpConfig.port)
            smtpEncryption = smtpConfig.encryption
        } else {
            smtpHost = account.smtpHost
            smtpPort = String(account.smtpPort)
            smtpEncryption = account.smtpEncryption
        }
        
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
            // 如果服务类型是预设的且没有打开高级设置，使用预设配置
            // 如果打开了高级设置或服务类型是自定义，使用表单中的配置
            if let imapConfig = serviceType.imapConfig, !showAdvancedSettings {
                account.imapHost = imapConfig.host
                account.imapPort = imapConfig.port
                account.imapEncryption = imapConfig.encryption
            } else {
                account.imapHost = imapHost
                account.imapPort = Int(imapPort) ?? 993
                account.imapEncryption = imapEncryption
            }
            
            if let smtpConfig = serviceType.smtpConfig, !showAdvancedSettings {
                account.smtpHost = smtpConfig.host
                account.smtpPort = smtpConfig.port
                account.smtpEncryption = smtpConfig.encryption
            } else {
                account.smtpHost = smtpHost
                account.smtpPort = Int(smtpPort) ?? 587
                account.smtpEncryption = smtpEncryption
            }
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
            try await emailStore.updateAccount(account)
        } else {
            try await emailStore.addAccount(account)
        }
        
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
            connectionTestResult = ConnectionTestResult(success: false, message: "密码不能为空")
            errorMessage = "密码不能为空"
            isTestingConnection = false
            return
        }
        
        do {
            let success = try await emailService.testConnection(account: testAccount, password: testPassword)
            connectionTestResult = ConnectionTestResult(success: success, message: success ? "连接成功" : "连接失败")
        } catch {
            connectionTestResult = ConnectionTestResult(success: false, message: error.localizedDescription)
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
}

