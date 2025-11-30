//
//  LibEtPanWrapper.m
//  fastv
//
//  Objective-C wrapper for LibEtPan C API
//

#import "LibEtPanWrapper.h"

// 使用系统路径格式导入 LibEtPan 头文件
// 注意：需要在 Xcode 的 Header Search Paths 中添加：$(SRCROOT)/ThirdParty/libetpan/include（递归）
#import <libetpan/mailimap.h>
#import <libetpan/mailsmtp.h>
#import <libetpan/mailmime.h>

// Forward declaration for Swift types
@class EmailAccount;

@implementation LibEtPanIMAPSession {
    void *_imapSession; // mailimap *
    NSString *_host;
    NSInteger _port;
    NSString *_encryption;
    NSString *_username;
    NSString *_password;
}

- (instancetype)initWithHost:(NSString *)host
                         port:(NSInteger)port
                   encryption:(NSString *)encryption
                     username:(NSString *)username
                     password:(NSString *)password {
    self = [super init];
    if (self) {
        _host = host;
        _port = port;
        _encryption = encryption;
        _username = username;
        _password = password;
        _imapSession = mailimap_new(0, NULL);
        if (!_imapSession) {
            return nil;
        }
    }
    return self;
}

- (BOOL)connectWithError:(NSError **)error {
    if (!_imapSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"IMAP 会话未初始化"}];
        }
        return NO;
    }
    
    int r;
    const char *host = [_host UTF8String];
    uint16_t port = (uint16_t)_port;
    
    // 根据加密方式选择连接方法
    if ([_encryption isEqualToString:@"ssl"]) {
        r = mailimap_ssl_connect((mailimap *)_imapSession, host, port);
    } else if ([_encryption isEqualToString:@"startTLS"]) {
        r = mailimap_socket_connect((mailimap *)_imapSession, host, port);
        if (r == MAILIMAP_NO_ERROR) {
            r = mailimap_socket_starttls((mailimap *)_imapSession);
        }
    } else {
        // 无加密
        r = mailimap_socket_connect((mailimap *)_imapSession, host, port);
    }
    
    if (r != MAILIMAP_NO_ERROR && r != MAILIMAP_NO_ERROR_NON_AUTHENTICATED) {
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"连接失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)loginWithError:(NSError **)error {
    if (!_imapSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"IMAP 会话未初始化"}];
        }
        return NO;
    }
    
    const char *username = [_username UTF8String];
    const char *password = [_password UTF8String];
    
    int r = mailimap_login((mailimap *)_imapSession, username, password);
    
    if (r != MAILIMAP_NO_ERROR) {
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"登录失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)selectFolder:(NSString *)folderName error:(NSError **)error {
    // TODO: 实现选择文件夹
    if (error) {
        *error = [NSError errorWithDomain:@"LibEtPanError" 
                                     code:-1 
                                 userInfo:@{NSLocalizedDescriptionKey: @"未实现"}];
    }
    return NO;
}

- (nullable NSArray<NSString *> *)fetchFoldersWithError:(NSError **)error {
    // TODO: 实现获取文件夹列表
    if (error) {
        *error = [NSError errorWithDomain:@"LibEtPanError" 
                                     code:-1 
                                 userInfo:@{NSLocalizedDescriptionKey: @"未实现"}];
    }
    return nil;
}

- (nullable NSArray<NSDictionary *> *)fetchMessagesFromUID:(uint32_t)fromUID toUID:(uint32_t)toUID error:(NSError **)error {
    // TODO: 实现获取邮件列表
    if (error) {
        *error = [NSError errorWithDomain:@"LibEtPanError" 
                                     code:-1 
                                 userInfo:@{NSLocalizedDescriptionKey: @"未实现"}];
    }
    return nil;
}

- (nullable NSDictionary<NSString *, id> *)fetchMessageHeadersWithUID:(uint32_t)uid error:(NSError **)error {
    // TODO: 实现获取邮件头
    if (error) {
        *error = [NSError errorWithDomain:@"LibEtPanError" 
                                     code:-1 
                                 userInfo:@{NSLocalizedDescriptionKey: @"未实现"}];
    }
    return nil;
}

- (nullable NSData *)fetchMessageBodyWithUID:(uint32_t)uid error:(NSError **)error {
    // TODO: 实现获取邮件正文
    if (error) {
        *error = [NSError errorWithDomain:@"LibEtPanError" 
                                     code:-1 
                                 userInfo:@{NSLocalizedDescriptionKey: @"未实现"}];
    }
    return nil;
}

- (BOOL)markAsReadWithUID:(uint32_t)uid error:(NSError **)error {
    // TODO: 实现标记为已读
    if (error) {
        *error = [NSError errorWithDomain:@"LibEtPanError" 
                                     code:-1 
                                 userInfo:@{NSLocalizedDescriptionKey: @"未实现"}];
    }
    return NO;
}

- (void)disconnect {
    if (_imapSession) {
        mailimap_free((mailimap *)_imapSession);
        _imapSession = NULL;
    }
}

- (void *)imapSession {
    return _imapSession;
}

- (void)dealloc {
    [self disconnect];
}

@end

@implementation LibEtPanSMTPSession {
    void *_smtpSession; // mailsmtp *
    NSString *_host;
    NSInteger _port;
    NSString *_encryption;
    NSString *_username;
    NSString *_password;
}

- (instancetype)initWithHost:(NSString *)host
                         port:(NSInteger)port
                   encryption:(NSString *)encryption
                     username:(NSString *)username
                     password:(NSString *)password {
    self = [super init];
    if (self) {
        _host = host;
        _port = port;
        _encryption = encryption;
        _username = username;
        _password = password;
        _smtpSession = mailsmtp_new(0, NULL);
        if (!_smtpSession) {
            return nil;
        }
    }
    return self;
}

- (BOOL)connectWithError:(NSError **)error {
    if (!_smtpSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"SMTP 会话未初始化"}];
        }
        return NO;
    }
    
    int r;
    const char *host = [_host UTF8String];
    uint16_t port = (uint16_t)_port;
    
    if ([_encryption isEqualToString:@"ssl"]) {
        r = mailsmtp_ssl_connect((mailsmtp *)_smtpSession, host, port);
    } else if ([_encryption isEqualToString:@"startTLS"]) {
        r = mailsmtp_socket_connect((mailsmtp *)_smtpSession, host, port);
        if (r == MAILSMTP_NO_ERROR) {
            r = mailsmtp_socket_starttls((mailsmtp *)_smtpSession);
        }
    } else {
        // 无加密
        r = mailsmtp_socket_connect((mailsmtp *)_smtpSession, host, port);
    }
    
    if (r != MAILSMTP_NO_ERROR) {
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"连接失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)loginWithError:(NSError **)error {
    if (!_smtpSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"SMTP 会话未初始化"}];
        }
        return NO;
    }
    
    // TODO: 实现 SMTP 认证
    // LibEtPan 的 SMTP 认证需要额外的 SASL 库支持
    // 暂时返回成功，后续完善
    // const char *username = [_username UTF8String];
    // const char *password = [_password UTF8String];
    // int r = mailsmtp_auth((mailsmtp *)_smtpSession, username, password);
    int r = MAILSMTP_NO_ERROR;
    
    if (r != MAILSMTP_NO_ERROR) {
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"登录失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)sendMessageTo:(NSArray<NSString *> *)to
                    cc:(nullable NSArray<NSString *> *)cc
                   bcc:(nullable NSArray<NSString *> *)bcc
                subject:(NSString *)subject
                   body:(NSString *)body
              htmlBody:(nullable NSString *)htmlBody
            attachments:(nullable NSArray<NSData *> *)attachments
            readReceipt:(BOOL)readReceipt
                  error:(NSError **)error {
    // TODO: 实现发送邮件
    if (error) {
        *error = [NSError errorWithDomain:@"LibEtPanError" 
                                     code:-1 
                                 userInfo:@{NSLocalizedDescriptionKey: @"未实现"}];
    }
    return NO;
}

- (void)disconnect {
    if (_smtpSession) {
        mailsmtp_free((mailsmtp *)_smtpSession);
        _smtpSession = NULL;
    }
}

- (void *)smtpSession {
    return _smtpSession;
}

- (void)dealloc {
    [self disconnect];
}

@end
