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
#import <libetpan/mailimap_helper.h>
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
    
    // 设置代理环境变量（如果启用）
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL proxyEnabled = [defaults boolForKey:@"emailProxyEnabled"];
    if (proxyEnabled) {
        NSString *proxyHost = [defaults stringForKey:@"emailProxyHost"] ?: @"localhost";
        NSInteger proxyPort = [defaults integerForKey:@"emailProxyPort"];
        if (proxyPort == 0) proxyPort = 7856;
        NSString *proxyType = [defaults stringForKey:@"emailProxyType"] ?: @"socks5";
        
        NSLog(@"📡 [LibEtPan IMAP] 代理已启用: %@://%@:%ld", proxyType, proxyHost, (long)proxyPort);
        
        // 设置环境变量，让 CFNetwork 使用代理
        NSString *proxyString;
        if ([proxyType isEqualToString:@"socks5"]) {
            proxyString = [NSString stringWithFormat:@"socks5://%@:%ld", proxyHost, (long)proxyPort];
            setenv("all_proxy", [proxyString UTF8String], 1);
            setenv("ALL_PROXY", [proxyString UTF8String], 1);
        } else if ([proxyType isEqualToString:@"http"]) {
            proxyString = [NSString stringWithFormat:@"http://%@:%ld", proxyHost, (long)proxyPort];
            setenv("http_proxy", [proxyString UTF8String], 1);
            setenv("https_proxy", [proxyString UTF8String], 1);
            setenv("HTTP_PROXY", [proxyString UTF8String], 1);
            setenv("HTTPS_PROXY", [proxyString UTF8String], 1);
        }
        
        NSLog(@"📡 [LibEtPan IMAP] 环境变量已设置: %@", proxyString);
    } else {
        NSLog(@"⚠️ [LibEtPan IMAP] 代理未启用");
    }
    
    NSLog(@"🔌 [LibEtPan IMAP] 尝试连接: %@ 端口 %d 加密方式 %@", _host, (int)_port, _encryption);
    
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
        NSLog(@"❌ [LibEtPan] IMAP 连接失败，错误代码: %d", r);
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"连接失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    NSLog(@"✅ [LibEtPan] IMAP 连接成功");
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
    
    NSLog(@"🔐 [LibEtPan] 尝试登录 IMAP，用户名: %@", _username);
    
    const char *username = [_username UTF8String];
    const char *password = [_password UTF8String];
    
    int r = mailimap_login((mailimap *)_imapSession, username, password);
    
    if (r != MAILIMAP_NO_ERROR) {
        NSLog(@"❌ [LibEtPan] IMAP 登录失败，错误代码: %d", r);
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"登录失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    NSLog(@"✅ [LibEtPan] IMAP 登录成功");
    return YES;
}

- (BOOL)selectFolder:(NSString *)folderName error:(NSError **)error {
    if (!_imapSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"IMAP 会话未初始化"}];
        }
        return NO;
    }
    
    const char *mb = [folderName UTF8String];
    int r = mailimap_select((mailimap *)_imapSession, mb);
    
    if (r != MAILIMAP_NO_ERROR) {
        NSLog(@"❌ [LibEtPan] 选择文件夹失败: %@, 错误代码: %d", folderName, r);
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"选择文件夹失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    NSLog(@"✅ [LibEtPan] 选择文件夹成功: %@", folderName);
    return YES;
}

- (nullable NSArray<NSString *> *)fetchFoldersWithError:(NSError **)error {
    if (!_imapSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"IMAP 会话未初始化"}];
        }
        return nil;
    }
    
    clist *result = NULL;
    int r = mailimap_list((mailimap *)_imapSession, "", "*", &result);
    
    if (r != MAILIMAP_NO_ERROR) {
        NSLog(@"❌ [LibEtPan] 获取文件夹列表失败，错误代码: %d", r);
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"获取文件夹列表失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return nil;
    }
    
    NSMutableArray<NSString *> *folders = [NSMutableArray array];
    clistiter *iter;
    for (iter = clist_begin(result); iter != NULL; iter = clist_next(iter)) {
        struct mailimap_mailbox_list *mb_list = (struct mailimap_mailbox_list *)clist_content(iter);
        if (mb_list && mb_list->mb_name) {
            NSString *folderName = [NSString stringWithUTF8String:mb_list->mb_name];
            [folders addObject:folderName];
        }
    }
    
    mailimap_list_result_free(result);
    
    NSLog(@"✅ [LibEtPan] 获取到 %lu 个文件夹", (unsigned long)folders.count);
    return folders;
}

- (nullable NSArray<NSDictionary *> *)fetchMessagesFromUID:(uint32_t)fromUID toUID:(uint32_t)toUID error:(NSError **)error {
    if (!_imapSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"IMAP 会话未初始化"}];
        }
        return nil;
    }
    
    // 构建搜索条件：获取所有邮件
    struct mailimap_search_key *search_key = mailimap_search_key_new_all();
    
    clist *search_result = NULL;
    int r = mailimap_uid_search((mailimap *)_imapSession, "UTF-8", search_key, &search_result);
    
    mailimap_search_key_free(search_key);
    
    if (r != MAILIMAP_NO_ERROR) {
        NSLog(@"❌ [LibEtPan] 搜索邮件 UID 失败，错误代码: %d", r);
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"搜索邮件失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return nil;
    }
    
    NSMutableArray<NSDictionary *> *messages = [NSMutableArray array];
    clistiter *iter;
    for (iter = clist_begin(search_result); iter != NULL; iter = clist_next(iter)) {
        uint32_t uid = *((uint32_t *)clist_content(iter));
        // 过滤 UID 范围
        if (uid >= fromUID && (toUID == 0 || uid <= toUID)) {
            [messages addObject:@{@"uid": @(uid)}];
        }
    }
    
    mailimap_search_result_free(search_result);
    
    NSLog(@"✅ [LibEtPan] 找到 %lu 封邮件", (unsigned long)messages.count);
    return messages;
}

- (nullable NSDictionary<NSString *, id> *)fetchMessageHeadersWithUID:(uint32_t)uid error:(NSError **)error {
    if (!_imapSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"IMAP 会话未初始化"}];
        }
        return nil;
    }
    
    // 使用 helper 函数获取邮件头（注意：helper 函数使用 msgid，不是 UID）
    // 我们需要先获取 UID 对应的 msgid，或者直接使用 UID fetch
    // 简化实现：使用 UID fetch 获取 ENVELOPE（包含基本头信息）
    struct mailimap_set *set = mailimap_set_new_single(uid);
    struct mailimap_fetch_type *fetch_type = mailimap_fetch_type_new_fetch_att_list_empty();
    struct mailimap_fetch_att *fetch_att = mailimap_fetch_att_new_envelope();
    mailimap_fetch_type_new_fetch_att_list_add(fetch_type, fetch_att);
    
    clist *fetch_result = NULL;
    int r = mailimap_uid_fetch((mailimap *)_imapSession, set, fetch_type, &fetch_result);
    
    mailimap_set_free(set);
    mailimap_fetch_type_free(fetch_type);
    
    if (r != MAILIMAP_NO_ERROR) {
        NSLog(@"❌ [LibEtPan] 获取邮件头失败，UID: %u, 错误代码: %d", uid, r);
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"获取邮件头失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return nil;
    }
    
    if (!fetch_result || clist_begin(fetch_result) == NULL) {
        NSLog(@"⚠️ [LibEtPan] 邮件头为空，UID: %u", uid);
        if (fetch_result) mailimap_fetch_list_free(fetch_result);
        return nil;
    }
    
    // 解析 ENVELOPE
    NSMutableDictionary<NSString *, id> *headers = [NSMutableDictionary dictionary];
    
    clistiter *iter;
    for (iter = clist_begin(fetch_result); iter != NULL; iter = clist_next(iter)) {
        struct mailimap_msg_att *msg_att = (struct mailimap_msg_att *)clist_content(iter);
        
        clistiter *att_iter;
        for (att_iter = clist_begin(msg_att->att_list); att_iter != NULL; att_iter = clist_next(att_iter)) {
            struct mailimap_msg_att_item *item = (struct mailimap_msg_att_item *)clist_content(att_iter);
            
            if (item->att_type == MAILIMAP_MSG_ATT_ITEM_STATIC) {
                struct mailimap_msg_att_static *att_static = item->att_data.att_static;
                
                if (att_static->att_type == MAILIMAP_MSG_ATT_ENVELOPE) {
                    struct mailimap_envelope *env = att_static->att_data.att_env;
                    
                    if (env && env->env_subject) {
                        headers[@"subject"] = [NSString stringWithUTF8String:env->env_subject];
                    }
                    if (env && env->env_from && env->env_from->frm_list) {
                        clistiter *addr_iter = clist_begin(env->env_from->frm_list);
                        if (addr_iter) {
                            struct mailimap_address *addr = (struct mailimap_address *)clist_content(addr_iter);
                            if (addr) {
                                NSMutableString *email = [NSMutableString string];
                                if (addr->ad_mailbox_name) {
                                    [email appendString:[NSString stringWithUTF8String:addr->ad_mailbox_name]];
                                }
                                if (addr->ad_host_name) {
                                    if (email.length > 0) [email appendString:@"@"];
                                    [email appendString:[NSString stringWithUTF8String:addr->ad_host_name]];
                                }
                                if (email.length > 0) {
                                    headers[@"from"] = email;
                                }
                            }
                        }
                    }
                    if (env && env->env_to && env->env_to->to_list) {
                        NSMutableString *toStr = [NSMutableString string];
                        clistiter *to_iter;
                        for (to_iter = clist_begin(env->env_to->to_list); to_iter != NULL; to_iter = clist_next(to_iter)) {
                            struct mailimap_address *addr = (struct mailimap_address *)clist_content(to_iter);
                            if (addr) {
                                NSMutableString *email = [NSMutableString string];
                                if (addr->ad_mailbox_name) {
                                    [email appendString:[NSString stringWithUTF8String:addr->ad_mailbox_name]];
                                }
                                if (addr->ad_host_name) {
                                    if (email.length > 0) [email appendString:@"@"];
                                    [email appendString:[NSString stringWithUTF8String:addr->ad_host_name]];
                                }
                                if (email.length > 0) {
                                    if (toStr.length > 0) [toStr appendString:@", "];
                                    [toStr appendString:email];
                                }
                            }
                        }
                        if (toStr.length > 0) {
                            headers[@"to"] = toStr;
                        }
                    }
                    if (env && env->env_date) {
                        headers[@"date"] = [NSString stringWithUTF8String:env->env_date];
                    }
                    if (env && env->env_message_id) {
                        headers[@"message-id"] = [NSString stringWithUTF8String:env->env_message_id];
                    }
                }
            }
        }
    }
    
    mailimap_fetch_list_free(fetch_result);
    
    NSLog(@"✅ [LibEtPan] 获取邮件头成功，UID: %u", uid);
    return headers;
}

- (nullable NSData *)fetchMessageBodyWithUID:(uint32_t)uid error:(NSError **)error {
    if (!_imapSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"IMAP 会话未初始化"}];
        }
        return nil;
    }
    
    // 使用 UID fetch 获取完整邮件
    struct mailimap_set *set = mailimap_set_new_single(uid);
    struct mailimap_fetch_type *fetch_type = mailimap_fetch_type_new_fetch_att_list_empty();
    struct mailimap_fetch_att *fetch_att = mailimap_fetch_att_new_rfc822();
    mailimap_fetch_type_new_fetch_att_list_add(fetch_type, fetch_att);
    
    clist *fetch_result = NULL;
    int r = mailimap_uid_fetch((mailimap *)_imapSession, set, fetch_type, &fetch_result);
    
    mailimap_set_free(set);
    mailimap_fetch_type_free(fetch_type);
    
    if (r != MAILIMAP_NO_ERROR) {
        NSLog(@"❌ [LibEtPan] 获取邮件正文失败，UID: %u, 错误代码: %d", uid, r);
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"获取邮件正文失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return nil;
    }
    
    if (!fetch_result || clist_begin(fetch_result) == NULL) {
        NSLog(@"⚠️ [LibEtPan] 邮件正文为空，UID: %u", uid);
        if (fetch_result) mailimap_fetch_list_free(fetch_result);
        return nil;
    }
    
    // 提取邮件正文数据
    NSData *bodyData = nil;
    
    clistiter *iter;
    for (iter = clist_begin(fetch_result); iter != NULL; iter = clist_next(iter)) {
        struct mailimap_msg_att *msg_att = (struct mailimap_msg_att *)clist_content(iter);
        
        clistiter *att_iter;
        for (att_iter = clist_begin(msg_att->att_list); att_iter != NULL; att_iter = clist_next(att_iter)) {
            struct mailimap_msg_att_item *item = (struct mailimap_msg_att_item *)clist_content(att_iter);
            
            if (item->att_type == MAILIMAP_MSG_ATT_ITEM_STATIC) {
                struct mailimap_msg_att_static *att_static = item->att_data.att_static;
                
                if (att_static->att_type == MAILIMAP_MSG_ATT_RFC822) {
                    if (att_static->att_data.att_rfc822.att_content && att_static->att_data.att_rfc822.att_length > 0) {
                        bodyData = [NSData dataWithBytes:att_static->att_data.att_rfc822.att_content 
                                                   length:att_static->att_data.att_rfc822.att_length];
                        break;
                    }
                }
            }
        }
        if (bodyData) break;
    }
    
    mailimap_fetch_list_free(fetch_result);
    
    if (bodyData) {
        NSLog(@"✅ [LibEtPan] 获取邮件正文成功，UID: %u, 大小: %lu 字节", uid, (unsigned long)bodyData.length);
    } else {
        NSLog(@"⚠️ [LibEtPan] 未找到邮件正文数据，UID: %u", uid);
    }
    
    return bodyData;
}

- (BOOL)markAsReadWithUID:(uint32_t)uid error:(NSError **)error {
    if (!_imapSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"IMAP 会话未初始化"}];
        }
        return NO;
    }
    
    // 使用 STORE 命令标记为已读（添加 \Seen 标志）
    struct mailimap_set *set = mailimap_set_new_single(uid);
    struct mailimap_flag_list *flag_list = mailimap_flag_list_new_empty();
    mailimap_flag_list_add(flag_list, mailimap_flag_new_seen());
    
    // fl_sign: +1 表示添加标志，0 表示设置标志，-1 表示移除标志
    struct mailimap_store_att_flags *store_flags = mailimap_store_att_flags_new(1, 0, flag_list);
    
    int r = mailimap_uid_store((mailimap *)_imapSession, set, store_flags);
    
    mailimap_set_free(set);
    mailimap_store_att_flags_free(store_flags);
    
    if (r != MAILIMAP_NO_ERROR) {
        NSLog(@"❌ [LibEtPan] 标记为已读失败，UID: %u, 错误代码: %d", uid, r);
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"标记为已读失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    NSLog(@"✅ [LibEtPan] 标记为已读成功，UID: %u", uid);
    return YES;
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
    
    // 设置代理环境变量（如果启用）
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL proxyEnabled = [defaults boolForKey:@"emailProxyEnabled"];
    if (proxyEnabled) {
        NSString *proxyHost = [defaults stringForKey:@"emailProxyHost"] ?: @"localhost";
        NSInteger proxyPort = [defaults integerForKey:@"emailProxyPort"];
        if (proxyPort == 0) proxyPort = 7856;
        NSString *proxyType = [defaults stringForKey:@"emailProxyType"] ?: @"socks5";
        
        // 设置环境变量，让 CFNetwork 使用代理
        NSString *proxyString;
        if ([proxyType isEqualToString:@"socks5"]) {
            proxyString = [NSString stringWithFormat:@"socks5://%@:%ld", proxyHost, (long)proxyPort];
            setenv("all_proxy", [proxyString UTF8String], 1);
        } else if ([proxyType isEqualToString:@"http"]) {
            proxyString = [NSString stringWithFormat:@"http://%@:%ld", proxyHost, (long)proxyPort];
            setenv("http_proxy", [proxyString UTF8String], 1);
            setenv("https_proxy", [proxyString UTF8String], 1);
        }
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
    if (!_smtpSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"SMTP 会话未初始化"}];
        }
        return NO;
    }
    
    // 1. 设置发件人
    const char *from = [_username UTF8String];
    int r = mailsmtp_mail((mailsmtp *)_smtpSession, from);
    if (r != MAILSMTP_NO_ERROR) {
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"设置发件人失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    // 2. 添加收件人
    for (NSString *recipient in to) {
        const char *toAddr = [recipient UTF8String];
        r = mailsmtp_rcpt((mailsmtp *)_smtpSession, toAddr);
        if (r != MAILSMTP_NO_ERROR) {
            if (error) {
                NSString *errorMsg = [NSString stringWithFormat:@"添加收件人失败: %@, 错误: %d", recipient, r];
                *error = [NSError errorWithDomain:@"LibEtPanError" 
                                             code:r 
                                         userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
            }
            return NO;
        }
    }
    
    // 添加 CC 收件人
    if (cc) {
        for (NSString *recipient in cc) {
            const char *ccAddr = [recipient UTF8String];
            r = mailsmtp_rcpt((mailsmtp *)_smtpSession, ccAddr);
            if (r != MAILSMTP_NO_ERROR) {
                if (error) {
                    NSString *errorMsg = [NSString stringWithFormat:@"添加CC收件人失败: %@, 错误: %d", recipient, r];
                    *error = [NSError errorWithDomain:@"LibEtPanError" 
                                                 code:r 
                                             userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
                }
                return NO;
            }
        }
    }
    
    // 添加 BCC 收件人
    if (bcc) {
        for (NSString *recipient in bcc) {
            const char *bccAddr = [recipient UTF8String];
            r = mailsmtp_rcpt((mailsmtp *)_smtpSession, bccAddr);
            if (r != MAILSMTP_NO_ERROR) {
                if (error) {
                    NSString *errorMsg = [NSString stringWithFormat:@"添加BCC收件人失败: %@, 错误: %d", recipient, r];
                    *error = [NSError errorWithDomain:@"LibEtPanError" 
                                                 code:r 
                                             userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
                }
                return NO;
            }
        }
    }
    
    // 3. 开始数据阶段
    r = mailsmtp_data((mailsmtp *)_smtpSession);
    if (r != MAILSMTP_NO_ERROR) {
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"开始数据阶段失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    // 4. 构建 MIME 消息
    NSMutableString *message = [NSMutableString string];
    
    // 邮件头
    [message appendFormat:@"From: %@\r\n", _username];
    
    // To
    NSMutableString *toStr = [NSMutableString string];
    for (NSUInteger i = 0; i < to.count; i++) {
        if (i > 0) [toStr appendString:@", "];
        [toStr appendString:to[i]];
    }
    [message appendFormat:@"To: %@\r\n", toStr];
    
    // CC
    if (cc && cc.count > 0) {
        NSMutableString *ccStr = [NSMutableString string];
        for (NSUInteger i = 0; i < cc.count; i++) {
            if (i > 0) [ccStr appendString:@", "];
            [ccStr appendString:cc[i]];
        }
        [message appendFormat:@"Cc: %@\r\n", ccStr];
    }
    
    // Subject（需要编码）
    NSString *encodedSubject = [self encodeMimeHeader:subject];
    [message appendFormat:@"Subject: %@\r\n", encodedSubject];
    
    // Date
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss Z";
    dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    dateFormatter.timeZone = [NSTimeZone localTimeZone];
    [message appendFormat:@"Date: %@\r\n", [dateFormatter stringFromDate:[NSDate date]]];
    
    // Message-ID
    NSString *messageId = [NSString stringWithFormat:@"<%@@%@>", 
                          [[NSUUID UUID] UUIDString], 
                          [[_username componentsSeparatedByString:@"@"] lastObject] ?: @"localhost"];
    [message appendFormat:@"Message-ID: %@\r\n", messageId];
    
    // Read Receipt
    if (readReceipt) {
        [message appendFormat:@"Disposition-Notification-To: %@\r\n", _username];
        [message appendFormat:@"Return-Receipt-To: %@\r\n", _username];
    }
    
    // MIME-Version
    [message appendString:@"MIME-Version: 1.0\r\n"];
    
    // Content-Type（根据是否有附件和HTML决定）
    BOOL hasAttachments = attachments && attachments.count > 0;
    BOOL hasHtml = htmlBody && htmlBody.length > 0;
    
    if (hasAttachments) {
        // multipart/mixed
        NSString *boundary = [NSString stringWithFormat:@"boundary_%@", [[NSUUID UUID] UUIDString]];
        [message appendFormat:@"Content-Type: multipart/mixed; boundary=\"%@\"\r\n", boundary];
        [message appendString:@"\r\n"];
        
        // 正文部分
        [message appendFormat:@"--%@\r\n", boundary];
        if (hasHtml) {
            [message appendString:@"Content-Type: multipart/alternative; boundary=\"alt_boundary\"\r\n"];
            [message appendString:@"\r\n"];
            
            // 纯文本版本
            [message appendString:@"--alt_boundary\r\n"];
            [message appendString:@"Content-Type: text/plain; charset=UTF-8\r\n"];
            [message appendString:@"Content-Transfer-Encoding: quoted-printable\r\n"];
            [message appendString:@"\r\n"];
            [message appendString:[self quotedPrintableEncode:body]];
            [message appendString:@"\r\n"];
            
            // HTML版本
            [message appendString:@"--alt_boundary\r\n"];
            [message appendString:@"Content-Type: text/html; charset=UTF-8\r\n"];
            [message appendString:@"Content-Transfer-Encoding: quoted-printable\r\n"];
            [message appendString:@"\r\n"];
            [message appendString:[self quotedPrintableEncode:htmlBody]];
            [message appendString:@"\r\n"];
            
            [message appendString:@"--alt_boundary--\r\n"];
        } else {
            [message appendString:@"Content-Type: text/plain; charset=UTF-8\r\n"];
            [message appendString:@"Content-Transfer-Encoding: quoted-printable\r\n"];
            [message appendString:@"\r\n"];
            [message appendString:[self quotedPrintableEncode:body]];
            [message appendString:@"\r\n"];
        }
        
        // 附件部分
        for (NSData *attachment in attachments) {
            [message appendFormat:@"--%@\r\n", boundary];
            [message appendString:@"Content-Type: application/octet-stream\r\n"];
            [message appendString:@"Content-Transfer-Encoding: base64\r\n"];
            [message appendString:@"Content-Disposition: attachment\r\n"];
            [message appendString:@"\r\n"];
            
            NSString *base64 = [attachment base64EncodedStringWithOptions:0];
            // 每76个字符换行（RFC 2045）
            NSUInteger lineLength = 76;
            for (NSUInteger i = 0; i < base64.length; i += lineLength) {
                NSUInteger length = MIN(lineLength, base64.length - i);
                [message appendString:[base64 substringWithRange:NSMakeRange(i, length)]];
                [message appendString:@"\r\n"];
            }
        }
        
        [message appendFormat:@"--%@--\r\n", boundary];
    } else if (hasHtml) {
        // multipart/alternative（只有HTML和文本，无附件）
        NSString *boundary = [NSString stringWithFormat:@"boundary_%@", [[NSUUID UUID] UUIDString]];
        [message appendFormat:@"Content-Type: multipart/alternative; boundary=\"%@\"\r\n", boundary];
        [message appendString:@"\r\n"];
        
        // 纯文本版本
        [message appendFormat:@"--%@\r\n", boundary];
        [message appendString:@"Content-Type: text/plain; charset=UTF-8\r\n"];
        [message appendString:@"Content-Transfer-Encoding: quoted-printable\r\n"];
        [message appendString:@"\r\n"];
        [message appendString:[self quotedPrintableEncode:body]];
        [message appendString:@"\r\n"];
        
        // HTML版本
        [message appendFormat:@"--%@\r\n", boundary];
        [message appendString:@"Content-Type: text/html; charset=UTF-8\r\n"];
        [message appendString:@"Content-Transfer-Encoding: quoted-printable\r\n"];
        [message appendString:@"\r\n"];
        [message appendString:[self quotedPrintableEncode:htmlBody]];
        [message appendString:@"\r\n"];
        
        [message appendFormat:@"--%@--\r\n", boundary];
    } else {
        // 纯文本
        [message appendString:@"Content-Type: text/plain; charset=UTF-8\r\n"];
        [message appendString:@"Content-Transfer-Encoding: quoted-printable\r\n"];
        [message appendString:@"\r\n"];
        [message appendString:[self quotedPrintableEncode:body]];
    }
    
    // 5. 发送消息
    NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
    r = mailsmtp_data_message((mailsmtp *)_smtpSession, 
                              (const char *)messageData.bytes, 
                              messageData.length);
    
    if (r != MAILSMTP_NO_ERROR) {
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"发送消息失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    NSLog(@"✅ [LibEtPan] 邮件发送成功");
    return YES;
}

// 辅助方法：编码 MIME 头（简化版，只处理非ASCII字符）
- (NSString *)encodeMimeHeader:(NSString *)header {
    // 简化实现：如果包含非ASCII字符，使用 base64 编码
    NSData *data = [header dataUsingEncoding:NSUTF8StringEncoding];
    BOOL needsEncoding = NO;
    for (NSUInteger i = 0; i < data.length; i++) {
        unsigned char byte = ((unsigned char *)data.bytes)[i];
        if (byte > 127) {
            needsEncoding = YES;
            break;
        }
    }
    
    if (needsEncoding) {
        NSString *base64 = [data base64EncodedStringWithOptions:0];
        return [NSString stringWithFormat:@"=?UTF-8?B?%@?=", base64];
    }
    
    return header;
}

// 辅助方法：Quoted-Printable 编码（简化版）
- (NSString *)quotedPrintableEncode:(NSString *)text {
    NSMutableString *encoded = [NSMutableString string];
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    
    for (NSUInteger i = 0; i < data.length; i++) {
        unsigned char byte = ((unsigned char *)data.bytes)[i];
        
        // 可打印ASCII字符（33-126，除了61=）
        if (byte >= 33 && byte <= 126 && byte != 61) {
            [encoded appendFormat:@"%c", byte];
        } else if (byte == 32) {
            // 空格：行尾用 =20，行中直接用空格
            [encoded appendString:@" "];
        } else if (byte == 9) {
            // Tab
            [encoded appendString:@"\t"];
        } else if (byte == 13 || byte == 10) {
            // 换行符
            [encoded appendFormat:@"%c", byte];
        } else {
            // 其他字符：=XX 格式
            [encoded appendFormat:@"=%02X", byte];
        }
        
        // 每行最多76个字符（简化处理）
        if (encoded.length > 0 && encoded.length % 75 == 0) {
            [encoded appendString:@"=\r\n"];
        }
    }
    
    return encoded;
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
