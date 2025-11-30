# MailCore2 集成指南

## 为什么选择 MailCore2

1. ✅ **不需要 OAuth**：直接使用 IMAP/SMTP 协议，不需要去 Google/Microsoft 申请
2. ✅ **功能完整**：支持 IMAP、SMTP、POP3 所有协议
3. ✅ **成熟稳定**：被很多邮件客户端使用
4. ✅ **支持所有邮件服务**：Gmail、Outlook、企业邮箱等

## 集成步骤

### 1. 下载 MailCore2 源码

```bash
cd /Users/rocky/Sites/fastv
git clone https://github.com/MailCore/mailcore2.git
cd mailcore2
```

### 2. 编译静态库

MailCore2 提供了 Xcode 项目，可以直接编译：

```bash
# 打开 Xcode 项目
open build-mac/mailcore2.xcodeproj

# 或者使用 CMake
mkdir build && cd build
cmake ..
make
```

### 3. 添加到项目

1. 在 Xcode 中，将编译好的静态库（.a 文件）添加到项目
2. 添加头文件搜索路径
3. 链接必要的框架：
   - Security.framework
   - libresolv.dylib
   - libsasl2.dylib

### 4. 创建桥接头文件

创建 `fastv-Bridging-Header.h`：

```objc
#import <MailCore/MailCore.h>
```

在项目设置中配置：
- Build Settings → Swift Compiler - General → Objective-C Bridging Header
- 设置为：`fastv/fastv-Bridging-Header.h`

### 5. 在 EmailService 中使用

```swift
import Foundation

class EmailService {
    // MailCore2 的 Objective-C API
    func connectIMAP(account: EmailAccount) {
        let session = MCOIMAPSession()
        session.hostname = account.imapHost
        session.port = UInt32(account.imapPort)
        session.username = account.emailAddress
        // 密码从 Keychain 获取
        session.password = EmailCredentialStore.shared.getPassword(accountId: account.id)
        
        // 设置加密方式
        switch account.imapEncryption {
        case .ssl:
            session.connectionType = .TLS
        case .startTLS:
            session.connectionType = .startTLS
        case .none:
            session.connectionType = .clear
        }
        
        // 连接测试
        session.checkAccountOperation { error in
            if let error = error {
                print("连接失败: \(error)")
            } else {
                print("连接成功")
            }
        }
    }
}
```

## 依赖库

MailCore2 依赖以下库（通常系统自带）：
- libresolv（DNS 解析）
- libsasl2（SASL 认证）
- Security.framework（Keychain）

## 常见问题

### Q: 编译失败怎么办？
A: 确保安装了所有依赖，可能需要安装 OpenSSL：
```bash
brew install openssl
```

### Q: 链接错误？
A: 检查是否添加了所有必要的框架和库

### Q: Swift 调用 Objective-C API？
A: MailCore2 提供 Objective-C API，Swift 可以直接调用，只需要桥接头文件

## 参考资源

- MailCore2 GitHub: https://github.com/MailCore/mailcore2
- MailCore2 文档: http://libmailcore.com/api/
- 示例代码: https://github.com/MailCore/mailcore2/tree/master/example

## 下一步

1. 下载并编译 MailCore2
2. 集成到项目
3. 更新 EmailService 使用 MailCore2 API
4. 测试连接和邮件收发

