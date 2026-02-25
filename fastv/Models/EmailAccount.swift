//
//  EmailAccount.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 预设邮箱服务类型
enum EmailServiceType: String, Codable, CaseIterable {
    case gmail = "Gmail"
    case outlook = "Outlook/Hotmail"
    case aliyun = "阿里云企业邮箱"
    case tencent = "腾讯企业邮箱"
    case custom = "自定义"
    
    var displayName: String {
        return rawValue
    }
    
    /// 获取预设的IMAP配置
    var imapConfig: (host: String, port: Int, encryption: EmailEncryption)? {
        switch self {
        case .gmail:
            return ("imap.gmail.com", 993, .ssl)
        case .outlook:
            return ("outlook.office365.com", 993, .ssl)
        case .aliyun:
            return ("imap.mxhichina.com", 993, .ssl)
        case .tencent:
            return ("imap.exmail.qq.com", 993, .ssl)
        case .custom:
            return nil
        }
    }
    
    /// 获取预设的SMTP配置
    /// 注意：Gmail 使用 SSL 直连（端口 465）更稳定，STARTTLS（端口 587）在某些网络环境下可能失败
    var smtpConfig: (host: String, port: Int, encryption: EmailEncryption)? {
        switch self {
        case .gmail:
            return ("smtp.gmail.com", 465, .ssl)  // 使用 SSL 直连，比 STARTTLS 更稳定
        case .outlook:
            return ("smtp.office365.com", 587, .startTLS)
        case .aliyun:
            return ("smtp.mxhichina.com", 465, .ssl)
        case .tencent:
            return ("smtp.exmail.qq.com", 465, .ssl)
        case .custom:
            return nil
        }
    }
}

/// 邮件加密方式
enum EmailEncryption: String, Codable {
    case none = "none"
    case ssl = "ssl"
    case startTLS = "startTLS"
}

/// 邮箱账号模型
struct EmailAccount: Identifiable, Codable {
    let id: UUID
    var emailAddress: String
    var displayName: String
    var serviceType: EmailServiceType
    
    // IMAP配置
    var imapHost: String
    var imapPort: Int
    var imapEncryption: EmailEncryption
    
    // SMTP配置
    var smtpHost: String
    var smtpPort: Int
    var smtpEncryption: EmailEncryption
    
    // 状态
    var isEnabled: Bool
    var isDefault: Bool
    var lastSyncDate: Date?
    var connectionStatus: ConnectionStatus
    
    var createdAt: Date
    var updatedAt: Date
    
    // 密码不存储在模型中，使用Keychain
    // 这里只存储密码的Keychain标识符
    var passwordKeychainIdentifier: String?
    
    init(
        id: UUID = UUID(),
        emailAddress: String,
        displayName: String = "",
        serviceType: EmailServiceType = .custom,
        imapHost: String = "",
        imapPort: Int = 993,
        imapEncryption: EmailEncryption = .ssl,
        smtpHost: String = "",
        smtpPort: Int = 587,
        smtpEncryption: EmailEncryption = .startTLS,
        isEnabled: Bool = true,
        isDefault: Bool = false,
        lastSyncDate: Date? = nil,
        connectionStatus: ConnectionStatus = .disconnected,
        passwordKeychainIdentifier: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        applyServiceDefaults: Bool = true
    ) {
        self.id = id
        self.emailAddress = emailAddress
        self.displayName = displayName.isEmpty ? emailAddress : displayName
        self.serviceType = serviceType
        
        // 如果允许且是预设服务，使用预设配置
        if applyServiceDefaults, let imapConfig = serviceType.imapConfig {
            self.imapHost = imapConfig.host
            self.imapPort = imapConfig.port
            self.imapEncryption = imapConfig.encryption
        } else {
            self.imapHost = imapHost
            self.imapPort = imapPort
            self.imapEncryption = imapEncryption
        }
        
        if applyServiceDefaults, let smtpConfig = serviceType.smtpConfig {
            self.smtpHost = smtpConfig.host
            self.smtpPort = smtpConfig.port
            self.smtpEncryption = smtpConfig.encryption
        } else {
            self.smtpHost = smtpHost
            self.smtpPort = smtpPort
            self.smtpEncryption = smtpEncryption
        }
        
        self.isEnabled = isEnabled
        self.isDefault = isDefault
        self.lastSyncDate = lastSyncDate
        self.connectionStatus = connectionStatus
        self.passwordKeychainIdentifier = passwordKeychainIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 连接状态
enum ConnectionStatus: String, Codable {
    case connected = "connected"
    case connecting = "connecting"
    case disconnected = "disconnected"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .connected:
            return "已连接"
        case .connecting:
            return "连接中"
        case .disconnected:
            return "未连接"
        case .error:
            return "连接错误"
        }
    }
}

