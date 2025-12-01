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
#import <libetpan/mailsmtp_types.h>
#import <libetpan/mailmime.h>
#import <pthread/qos.h>

// Forward declaration for Swift types
@class EmailAccount;

/// 设置当前线程的 QoS 为 User Initiated，避免优先级反转
/// LibEtPan 的 CFStream 操作会在 runloop 中等待，如果 runloop 运行在较低 QoS 的线程上，
/// 会导致 User Initiated QoS 的线程等待 Default QoS 的线程，产生优先级反转警告
static void ensureUserInitiatedQoS(void) {
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0);
}

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
    
    // 设置线程 QoS 为 User Initiated，避免优先级反转
    // LibEtPan 的 CFStream 操作会在 runloop 中等待，需要确保 runloop 运行在正确的 QoS 级别
    ensureUserInitiatedQoS();
    
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
    
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
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
    
    // 文件夹名称可能已经是 Modified UTF-7 编码的（从服务器返回的），直接使用
    // 如果传入的是已解码的名称（包含中文等非ASCII字符），需要编码
    NSString *encodedName = folderName;
    
    // 检查是否包含非ASCII字符（需要编码）
    NSData *utf8Data = [folderName dataUsingEncoding:NSUTF8StringEncoding];
    BOOL hasNonASCII = NO;
    for (NSUInteger i = 0; i < utf8Data.length; i++) {
        unsigned char byte = ((unsigned char *)utf8Data.bytes)[i];
        if (byte > 127) {
            hasNonASCII = YES;
            break;
        }
    }
    
    // 如果包含非ASCII字符且不是已编码格式（不包含 &...- 模式），需要编码
    if (hasNonASCII && [folderName rangeOfString:@"&-"].location == NSNotFound) {
        // 检查是否已经是编码格式（包含 & 和 -，但不是 &-）
        NSRange ampRange = [folderName rangeOfString:@"&"];
        if (ampRange.location != NSNotFound) {
            // 检查后面是否有 -（可能是编码格式）
            NSRange dashRange = [folderName rangeOfString:@"-" options:0 range:NSMakeRange(ampRange.location, folderName.length - ampRange.location)];
            if (dashRange.location == NSNotFound || dashRange.location == ampRange.location + 1) {
                // 没有找到 - 或者 - 紧跟在 & 后面（&- 表示 &），需要编码
                encodedName = [self encodeModifiedUTF7:folderName];
            }
            // 否则已经是编码格式，直接使用
        } else {
            // 没有 &，包含非ASCII字符，需要编码
            encodedName = [self encodeModifiedUTF7:folderName];
        }
    }
    // 如果已经是 ASCII 或已经是编码格式，直接使用
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
    const char *mb = [encodedName UTF8String];
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
    
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
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
            // IMAP 文件夹名称使用 Modified UTF-7 编码，需要解码
            NSString *encodedName = [NSString stringWithUTF8String:mb_list->mb_name];
            NSString *decodedName = [self decodeModifiedUTF7:encodedName];
            [folders addObject:decodedName];
        }
    }
    
    mailimap_list_result_free(result);
    
    NSLog(@"✅ [LibEtPan] 获取到 %lu 个文件夹", (unsigned long)folders.count);
    return folders;
}

// 解码 Modified UTF-7 编码的文件夹名称
- (NSString *)decodeModifiedUTF7:(NSString *)encoded {
    if (!encoded || encoded.length == 0) {
        return encoded;
    }
    
    if ([encoded rangeOfString:@"&"].location == NSNotFound) {
        return encoded;
    }
    
    NSMutableString *decoded = [NSMutableString string];
    NSUInteger length = encoded.length;
    NSUInteger index = 0;
    
    while (index < length) {
        unichar ch = [encoded characterAtIndex:index];
        if (ch == '&') {
            index++;
            if (index < length && [encoded characterAtIndex:index] == '-') {
                [decoded appendString:@"&"];
                index++;
                continue;
            }
            
            NSRange dashRange = [encoded rangeOfString:@"-" options:0 range:NSMakeRange(index, length - index)];
            if (dashRange.location == NSNotFound) {
                [decoded appendString:@"&"];
                break;
            }
            
            NSRange encodedRange = NSMakeRange(index, dashRange.location - index);
            NSString *base64Part = [encoded substringWithRange:encodedRange];
            NSString *base64 = [[base64Part stringByReplacingOccurrencesOfString:@"," withString:@"/"]
                                stringByReplacingOccurrencesOfString:@" " withString:@""];
            
            NSUInteger remainder = base64.length % 4;
            if (remainder > 0) {
                base64 = [base64 stringByPaddingToLength:base64.length + (4 - remainder) withString:@"=" startingAtIndex:0];
            }
            
            NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
            if (data) {
                NSString *utf16String = [[NSString alloc] initWithData:data encoding:NSUTF16BigEndianStringEncoding];
                if (utf16String) {
                    [decoded appendString:utf16String];
                }
            }
            
            index = dashRange.location + 1;
        } else {
            [decoded appendFormat:@"%C", ch];
            index++;
        }
    }
    
    return decoded;
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
    
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
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

/// 按日期搜索邮件（优化性能）
- (nullable NSArray<NSDictionary *> *)fetchMessagesSinceDate:(nullable NSDate *)sinceDate limit:(NSUInteger)limit error:(NSError **)error {
    if (!_imapSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"IMAP 会话未初始化"}];
        }
        return nil;
    }
    
    // 构建搜索条件
    struct mailimap_search_key *search_key;
    if (sinceDate) {
        // 使用日期搜索：SINCE date
        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSDateComponents *components = [calendar components:NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear fromDate:sinceDate];
        
        struct mailimap_date *imap_date = mailimap_date_new(
            (int32_t)components.day,
            (int32_t)components.month,
            (int32_t)components.year
        );
        search_key = mailimap_search_key_new_since(imap_date);
    } else {
        // 获取所有邮件
        search_key = mailimap_search_key_new_all();
    }
    
    NSLog(@"🔍 [LibEtPan] 开始搜索邮件，日期: %@, 限制: %lu", sinceDate, (unsigned long)limit);
    
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
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
    
    // 先收集所有UID
    NSMutableArray<NSNumber *> *uidArray = [NSMutableArray array];
    clistiter *iter;
    for (iter = clist_begin(search_result); iter != NULL; iter = clist_next(iter)) {
        uint32_t uid = *((uint32_t *)clist_content(iter));
        [uidArray addObject:@(uid)];
    }
    
    NSUInteger totalFound = uidArray.count;
    NSLog(@"📊 [LibEtPan] 搜索到 %lu 封邮件", (unsigned long)totalFound);
    
    // 按 UID 降序排序（最新的在前）- 这一步可能很慢
    if (totalFound > 1000) {
        NSLog(@"⚠️ [LibEtPan] 邮件数量较多(%lu封)，排序可能需要时间...", (unsigned long)totalFound);
    }
    [uidArray sortUsingComparator:^NSComparisonResult(NSNumber *obj1, NSNumber *obj2) {
        return [obj2 compare:obj1]; // 降序
    }];
    
    // 限制数量
    NSMutableArray<NSDictionary *> *messages = [NSMutableArray array];
    NSUInteger count = 0;
    NSUInteger actualLimit = (limit > 0) ? limit : totalFound;
    
    for (NSNumber *uidNum in uidArray) {
        if (count >= actualLimit) {
            break;
        }
        [messages addObject:@{@"uid": uidNum}];
        count++;
    }
    
    mailimap_search_result_free(search_result);
    
    NSLog(@"✅ [LibEtPan] 返回 %lu 封邮件（总共: %lu, 限制: %lu）", 
          (unsigned long)messages.count, (unsigned long)totalFound, (unsigned long)actualLimit);
    return messages;
}

/// 按文本搜索邮件（搜索主题、发件人、正文等）
- (nullable NSArray<NSDictionary *> *)searchMessagesWithQuery:(NSString *)query limit:(NSUInteger)limit error:(NSError **)error {
    if (!_imapSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"IMAP 会话未初始化"}];
        }
        return nil;
    }
    
    if (!query || query.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"搜索查询不能为空"}];
        }
        return nil;
    }
    
    NSLog(@"🔍 [LibEtPan] 开始搜索邮件，查询: %@, 限制: %lu", query, (unsigned long)limit);
    
    // 构建搜索条件：使用 TEXT 搜索，这会搜索邮件的所有文本字段（主题、正文等）
    // TEXT 搜索是 IMAP 标准中最通用的搜索方式
    struct mailimap_search_key *searchKey = mailimap_search_key_new_text([query UTF8String]);
    
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
    clist *search_result = NULL;
    int r = mailimap_uid_search((mailimap *)_imapSession, "UTF-8", searchKey, &search_result);
    
    // 释放搜索条件
    mailimap_search_key_free(searchKey);
    
    if (r != MAILIMAP_NO_ERROR) {
        NSLog(@"❌ [LibEtPan] 搜索邮件失败，错误代码: %d", r);
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"搜索邮件失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return nil;
    }
    
    // 收集所有 UID
    NSMutableArray<NSNumber *> *uidArray = [NSMutableArray array];
    clistiter *iter;
    for (iter = clist_begin(search_result); iter != NULL; iter = clist_next(iter)) {
        uint32_t uid = *((uint32_t *)clist_content(iter));
        [uidArray addObject:@(uid)];
    }
    
    mailimap_search_result_free(search_result);
    
    NSUInteger totalFound = uidArray.count;
    NSLog(@"📊 [LibEtPan] 搜索到 %lu 封邮件", (unsigned long)totalFound);
    
    // 按 UID 降序排序（最新的在前）
    [uidArray sortUsingComparator:^NSComparisonResult(NSNumber *obj1, NSNumber *obj2) {
        return [obj2 compare:obj1]; // 降序
    }];
    
    // 限制数量
    NSMutableArray<NSDictionary *> *messages = [NSMutableArray array];
    NSUInteger count = 0;
    NSUInteger actualLimit = (limit > 0) ? limit : totalFound;
    
    for (NSNumber *uidNum in uidArray) {
        if (count >= actualLimit) {
            break;
        }
        [messages addObject:@{@"uid": uidNum}];
        count++;
    }
    
    NSLog(@"✅ [LibEtPan] 返回 %lu 封邮件", (unsigned long)messages.count);
    return messages;
}

/// 快速获取最新N封邮件的UID（不搜索，直接从最新开始获取）
- (nullable NSArray<NSDictionary *> *)fetchLatestMessagesWithLimit:(NSUInteger)limit error:(NSError **)error {
    if (!_imapSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"IMAP 会话未初始化"}];
        }
        return nil;
    }
    
    NSLog(@"⚡️ [LibEtPan] 快速获取最新 %lu 封邮件...", (unsigned long)limit);
    
    // 获取当前文件夹的状态信息(包含邮件总数)
    mailimap *imap = (mailimap *)_imapSession;
    if (!imap->imap_selection_info) {
        NSLog(@"❌ [LibEtPan] 未选择文件夹");
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"未选择文件夹"}];
        }
        return nil;
    }
    
    uint32_t uidNext = imap->imap_selection_info->sel_uidnext;
    uint32_t exists = imap->imap_selection_info->sel_exists;
    
    NSLog(@"📊 [LibEtPan] 文件夹状态 - 邮件总数: %u, 下一个UID: %u", exists, uidNext);
    
    if (exists == 0) {
        NSLog(@"⚠️ [LibEtPan] 文件夹为空");
        return @[];
    }
    
    // 计算要获取的范围: 从 (uidNext - limit) 到 (uidNext - 1)
    // 注意: UID 不是连续的,但这个方法会快很多
    uint32_t startUID = (uidNext > limit) ? (uidNext - (uint32_t)limit) : 1;
    uint32_t endUID = uidNext - 1;
    
    NSLog(@"🔍 [LibEtPan] 获取 UID 范围: %u:%u", startUID, endUID);
    
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
    // 使用 UID FETCH 获取这个范围的所有UID
    struct mailimap_set *set = mailimap_set_new_interval(startUID, endUID);
    struct mailimap_fetch_type *fetch_type = mailimap_fetch_type_new_fetch_att_list_empty();
    struct mailimap_fetch_att *fetch_att = mailimap_fetch_att_new_uid();
    mailimap_fetch_type_new_fetch_att_list_add(fetch_type, fetch_att);
    
    clist *fetch_result = NULL;
    int r = mailimap_uid_fetch(imap, set, fetch_type, &fetch_result);
    
    mailimap_set_free(set);
    mailimap_fetch_type_free(fetch_type);
    
    if (r != MAILIMAP_NO_ERROR) {
        NSLog(@"❌ [LibEtPan] 获取邮件 UID 失败，错误代码: %d", r);
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"获取邮件失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return nil;
    }
    
    // 收集UID
    NSMutableArray<NSNumber *> *uidArray = [NSMutableArray array];
    clistiter *iter;
    for (iter = clist_begin(fetch_result); iter != NULL; iter = clist_next(iter)) {
        struct mailimap_msg_att *msg_att = (struct mailimap_msg_att *)clist_content(iter);
        clistiter *att_iter;
        for (att_iter = clist_begin(msg_att->att_list); att_iter != NULL; att_iter = clist_next(att_iter)) {
            struct mailimap_msg_att_item *item = (struct mailimap_msg_att_item *)clist_content(att_iter);
            if (item->att_type == MAILIMAP_MSG_ATT_ITEM_STATIC) {
                if (item->att_data.att_static->att_type == MAILIMAP_MSG_ATT_UID) {
                    uint32_t uid = item->att_data.att_static->att_data.att_uid;
                    [uidArray addObject:@(uid)];
                }
            }
        }
    }
    
    mailimap_fetch_list_free(fetch_result);
    
    // 按UID降序排序(最新的在前)
    [uidArray sortUsingComparator:^NSComparisonResult(NSNumber *obj1, NSNumber *obj2) {
        return [obj2 compare:obj1];
    }];
    
    // 限制数量
    NSMutableArray<NSDictionary *> *messages = [NSMutableArray array];
    NSUInteger count = 0;
    for (NSNumber *uidNum in uidArray) {
        if (limit > 0 && count >= limit) {
            break;
        }
        [messages addObject:@{@"uid": uidNum}];
        count++;
    }
    
    NSLog(@"✅ [LibEtPan] 快速获取完成: %lu 封邮件", (unsigned long)messages.count);
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
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
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

/// 批量获取多封邮件头信息
- (nullable NSArray<NSDictionary *> *)fetchBatchMessageHeadersWithUIDs:(NSArray<NSNumber *> *)uids error:(NSError **)error {
    if (!_imapSession) {
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"IMAP 会话未初始化"}];
        }
        return nil;
    }
    
    if (uids.count == 0) {
        return @[];
    }
    
    NSLog(@"📦 [LibEtPan] 批量获取 %lu 封邮件头...", (unsigned long)uids.count);
    
    // 构建UID set
    struct mailimap_set *set = mailimap_set_new_empty();
    for (NSNumber *uidNum in uids) {
        uint32_t uid = [uidNum unsignedIntValue];
        mailimap_set_add_single(set, uid);
    }
    
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
    // 构建fetch请求: FETCH (UID ENVELOPE)
    struct mailimap_fetch_type *fetch_type = mailimap_fetch_type_new_fetch_att_list_empty();
    struct mailimap_fetch_att *fetch_att_uid = mailimap_fetch_att_new_uid();
    struct mailimap_fetch_att *fetch_att_env = mailimap_fetch_att_new_envelope();
    mailimap_fetch_type_new_fetch_att_list_add(fetch_type, fetch_att_uid);
    mailimap_fetch_type_new_fetch_att_list_add(fetch_type, fetch_att_env);
    
    clist *fetch_result = NULL;
    int r = mailimap_uid_fetch((mailimap *)_imapSession, set, fetch_type, &fetch_result);
    
    mailimap_set_free(set);
    mailimap_fetch_type_free(fetch_type);
    
    if (r != MAILIMAP_NO_ERROR) {
        NSLog(@"❌ [LibEtPan] 批量获取邮件头失败，错误代码: %d", r);
        if (error) {
            NSString *errorMsg = [NSString stringWithFormat:@"批量获取邮件头失败: %d", r];
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return nil;
    }
    
    if (!fetch_result || clist_begin(fetch_result) == NULL) {
        if (fetch_result) mailimap_fetch_list_free(fetch_result);
        return @[];
    }
    
    // 解析所有邮件头
    NSMutableArray<NSDictionary *> *allHeaders = [NSMutableArray array];
    
    clistiter *iter;
    for (iter = clist_begin(fetch_result); iter != NULL; iter = clist_next(iter)) {
        struct mailimap_msg_att *msg_att = (struct mailimap_msg_att *)clist_content(iter);
        
        uint32_t uid = 0;
        struct mailimap_envelope *env = NULL;
        
        // 提取UID和ENVELOPE
        clistiter *att_iter;
        for (att_iter = clist_begin(msg_att->att_list); att_iter != NULL; att_iter = clist_next(att_iter)) {
            struct mailimap_msg_att_item *item = (struct mailimap_msg_att_item *)clist_content(att_iter);
            
            if (item->att_type == MAILIMAP_MSG_ATT_ITEM_STATIC) {
                if (item->att_data.att_static->att_type == MAILIMAP_MSG_ATT_UID) {
                    uid = item->att_data.att_static->att_data.att_uid;
                } else if (item->att_data.att_static->att_type == MAILIMAP_MSG_ATT_ENVELOPE) {
                    env = item->att_data.att_static->att_data.att_env;
                }
            }
        }
        
        if (uid == 0 || !env) {
            continue;
        }
        
        // 解析ENVELOPE为字典
        NSMutableDictionary<NSString *, id> *headers = [NSMutableDictionary dictionary];
        headers[@"uid"] = @(uid);
        
        if (env->env_subject) {
            headers[@"subject"] = [NSString stringWithUTF8String:env->env_subject];
        }
        if (env->env_from && env->env_from->frm_list) {
            NSMutableString *fromStr = [NSMutableString string];
            clistiter *from_iter = clist_begin(env->env_from->frm_list);
            if (from_iter) {
                struct mailimap_address *addr = (struct mailimap_address *)clist_content(from_iter);
                if (addr) {
                    if (addr->ad_personal_name) {
                        [fromStr appendString:[NSString stringWithUTF8String:addr->ad_personal_name]];
                        [fromStr appendString:@" <"];
                    }
                    if (addr->ad_mailbox_name) {
                        [fromStr appendString:[NSString stringWithUTF8String:addr->ad_mailbox_name]];
                    }
                    if (addr->ad_host_name) {
                        [fromStr appendString:@"@"];
                        [fromStr appendString:[NSString stringWithUTF8String:addr->ad_host_name]];
                    }
                    if (addr->ad_personal_name) {
                        [fromStr appendString:@">"];
                    }
                }
            }
            if (fromStr.length > 0) {
                headers[@"from"] = fromStr;
            }
        }
        if (env->env_to && env->env_to->to_list) {
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
        if (env->env_date) {
            headers[@"date"] = [NSString stringWithUTF8String:env->env_date];
        }
        if (env->env_message_id) {
            headers[@"message-id"] = [NSString stringWithUTF8String:env->env_message_id];
        }
        
        [allHeaders addObject:headers];
    }
    
    mailimap_fetch_list_free(fetch_result);
    
    NSLog(@"✅ [LibEtPan] 批量获取完成: %lu 封邮件头", (unsigned long)allHeaders.count);
    return allHeaders;
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
    
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
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
    
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
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

// 编码 Modified UTF-7（用于选择文件夹）
- (NSString *)encodeModifiedUTF7:(NSString *)folderName {
    if (!folderName || folderName.length == 0) {
        return folderName;
    }
    
    NSMutableString *encoded = [NSMutableString string];
    NSMutableString *nonAsciiBuffer = [NSMutableString string];
    
    void (^flushBuffer)(void) = ^{
        if (nonAsciiBuffer.length == 0) { return; }
        NSData *utf16Data = [nonAsciiBuffer dataUsingEncoding:NSUTF16BigEndianStringEncoding];
        NSString *base64 = [utf16Data base64EncodedStringWithOptions:0];
        base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@","];
        base64 = [base64 stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
        [encoded appendFormat:@"&%@-", base64];
        [nonAsciiBuffer setString:@""];
    };
    
    for (NSUInteger i = 0; i < folderName.length; i++) {
        unichar ch = [folderName characterAtIndex:i];
        if (ch >= 0x20 && ch <= 0x7E) {
            flushBuffer();
            if (ch == '&') {
                [encoded appendString:@"&-"];
            } else {
                [encoded appendFormat:@"%C", ch];
            }
        } else {
            [nonAsciiBuffer appendFormat:@"%C", ch];
        }
    }
    
    flushBuffer();
    return encoded;
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
        
        // 设置连接超时为 30 秒，避免无限等待
        mailsmtp_set_timeout((mailsmtp *)_smtpSession, 30);
        NSLog(@"📧 [LibEtPan SMTP] 已设置连接超时: 30秒");
    }
    return self;
}

- (BOOL)connectWithError:(NSError **)error {
    if (!_smtpSession) {
        NSLog(@"❌ [LibEtPan SMTP] 会话未初始化");
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"SMTP 会话未初始化"}];
        }
        return NO;
    }
    
    NSLog(@"🔌 [LibEtPan SMTP] 尝试连接: %@ 端口 %ld 加密方式 %@", _host, (long)_port, _encryption);
    
    // 设置代理环境变量（如果启用）
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL proxyEnabled = [defaults boolForKey:@"emailProxyEnabled"];
    if (proxyEnabled) {
        NSString *proxyHost = [defaults stringForKey:@"emailProxyHost"] ?: @"localhost";
        NSInteger proxyPort = [defaults integerForKey:@"emailProxyPort"];
        if (proxyPort == 0) proxyPort = 7856;
        NSString *proxyType = [defaults stringForKey:@"emailProxyType"] ?: @"socks5";
        
        NSLog(@"🔌 [LibEtPan SMTP] 使用代理: %@://%@:%ld", proxyType, proxyHost, (long)proxyPort);
        
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
    } else {
        NSLog(@"🔌 [LibEtPan SMTP] 未启用代理");
    }
    
    int r;
    const char *host = [_host UTF8String];
    uint16_t port = (uint16_t)_port;
    
    NSLog(@"🔌 [LibEtPan SMTP] 开始连接，主机: %s, 端口: %d", host, port);
    
    // 设置线程 QoS 为 User Initiated，避免优先级反转
    // LibEtPan 的 CFStream 操作会在 runloop 中等待，需要确保 runloop 运行在正确的 QoS 级别
    ensureUserInitiatedQoS();
    
    if ([_encryption isEqualToString:@"ssl"]) {
        NSLog(@"🔌 [LibEtPan SMTP] 使用 SSL 加密连接");
        r = mailsmtp_ssl_connect((mailsmtp *)_smtpSession, host, port);
    } else if ([_encryption isEqualToString:@"startTLS"]) {
        NSLog(@"🔌 [LibEtPan SMTP] 使用 STARTTLS 连接");
        r = mailsmtp_socket_connect((mailsmtp *)_smtpSession, host, port);
        if (r == MAILSMTP_NO_ERROR) {
            NSLog(@"🔌 [LibEtPan SMTP] Socket 连接成功，开始 STARTTLS 握手");
            r = mailsmtp_socket_starttls((mailsmtp *)_smtpSession);
        }
    } else {
        NSLog(@"🔌 [LibEtPan SMTP] 使用无加密连接");
        r = mailsmtp_socket_connect((mailsmtp *)_smtpSession, host, port);
    }
    
    if (r != MAILSMTP_NO_ERROR) {
        NSString *errorMsg;
        NSString *errorDetail;
        
        // 根据错误代码提供更详细的错误信息
        switch (r) {
            case MAILSMTP_ERROR_STARTTLS_NOT_SUPPORTED:
                errorMsg = @"STARTTLS 不支持或握手失败";
                errorDetail = @"服务器可能不支持 STARTTLS，或 SSL/TLS 握手失败。请尝试使用 SSL 直接连接（端口 465）。";
                break;
            case MAILSMTP_ERROR_STARTTLS_TEMPORARY_FAILURE:
                errorMsg = @"STARTTLS 临时失败";
                errorDetail = @"STARTTLS 握手临时失败，请稍后重试。";
                break;
            case MAILSMTP_ERROR_SSL:
                errorMsg = @"SSL/TLS 错误";
                errorDetail = @"SSL/TLS 连接失败，可能是证书验证失败或 TLS 版本不兼容。";
                break;
            case MAILSMTP_ERROR_CONNECTION_REFUSED:
                errorMsg = @"连接被拒绝";
                errorDetail = @"服务器拒绝了连接，请检查服务器地址和端口是否正确。";
                break;
            case MAILSMTP_ERROR_STREAM:
                errorMsg = @"流错误";
                errorDetail = @"网络流错误，可能是网络连接中断。";
                break;
            case MAILSMTP_ERROR_HOSTNAME:
                errorMsg = @"主机名错误";
                errorDetail = @"无法解析主机名，请检查服务器地址是否正确。";
                break;
            default:
                errorMsg = [NSString stringWithFormat:@"连接失败: %d", r];
                errorDetail = [NSString stringWithFormat:@"LibEtPan 错误代码: %d", r];
                break;
        }
        
        NSLog(@"❌ [LibEtPan SMTP] 连接失败，错误代码: %d", r);
        NSLog(@"❌ [LibEtPan SMTP] 错误类型: %@", errorMsg);
        NSLog(@"❌ [LibEtPan SMTP] 错误详情: %@", errorDetail);
        
        if (error) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setObject:errorMsg forKey:NSLocalizedDescriptionKey];
            [userInfo setObject:errorDetail forKey:NSLocalizedFailureReasonErrorKey];
            [userInfo setObject:@(r) forKey:@"LibEtPanErrorCode"];
            
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    NSLog(@"✅ [LibEtPan SMTP] 连接成功");
    return YES;
}

- (BOOL)loginWithError:(NSError **)error {
    if (!_smtpSession) {
        NSLog(@"❌ [LibEtPan SMTP] 登录失败: 会话未初始化");
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"SMTP 会话未初始化"}];
        }
        return NO;
    }
    
    NSLog(@"🔐 [LibEtPan SMTP] 开始登录，用户名: %@", _username);
    
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
    mailsmtp *smtp = (mailsmtp *)_smtpSession;
    
    // 1. 首先发送 EHLO 命令获取服务器支持的认证方式
    NSLog(@"🔐 [LibEtPan SMTP] 步骤 1: 发送 EHLO 命令");
    int r = mailesmtp_ehlo(smtp);
    if (r != MAILSMTP_NO_ERROR) {
        NSLog(@"⚠️ [LibEtPan SMTP] EHLO 失败 (代码: %d)，尝试 HELO", r);
        // 如果 EHLO 失败，尝试传统的 HELO
        r = mailsmtp_helo(smtp);
        if (r != MAILSMTP_NO_ERROR) {
            NSString *errorMsg = [NSString stringWithFormat:@"HELO/EHLO 失败: %d", r];
            NSLog(@"❌ [LibEtPan SMTP] %@", errorMsg);
            if (error) {
                *error = [NSError errorWithDomain:@"LibEtPanError" 
                                             code:r 
                                         userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
            }
            return NO;
        }
        NSLog(@"✅ [LibEtPan SMTP] HELO 成功");
    } else {
        NSLog(@"✅ [LibEtPan SMTP] EHLO 成功");
    }
    
    // 2. 执行认证
    NSLog(@"🔐 [LibEtPan SMTP] 步骤 2: 执行认证");
    const char *username = [_username UTF8String];
    const char *password = [_password UTF8String];
    
    // 尝试使用 AUTH LOGIN 方式认证
    r = mailesmtp_auth_sasl(smtp, "LOGIN",
                           NULL, // server_fqdn
                           NULL, // local_ip_port
                           NULL, // remote_ip_port
                           username, username,
                           password, NULL /* realm */);
    
    if (r != MAILSMTP_NO_ERROR) {
        NSLog(@"⚠️ [LibEtPan SMTP] LOGIN 认证失败 (代码: %d)，尝试 PLAIN 认证", r);
        
        // 如果 LOGIN 失败，尝试 PLAIN 认证
        r = mailesmtp_auth_sasl(smtp, "PLAIN",
                               NULL, // server_fqdn
                               NULL, // local_ip_port
                               NULL, // remote_ip_port
                               username, username,
                               password, NULL /* realm */);
        
        if (r != MAILSMTP_NO_ERROR) {
            NSString *errorMsg = [NSString stringWithFormat:@"认证失败: %d", r];
            NSLog(@"❌ [LibEtPan SMTP] 认证失败，错误代码: %d", r);
            NSLog(@"❌ [LibEtPan SMTP] 错误信息: %@", errorMsg);
            NSLog(@"💡 [LibEtPan SMTP] 提示: 如果您使用 Gmail，请确保使用应用专用密码");
            if (error) {
                *error = [NSError errorWithDomain:@"LibEtPanError" 
                                             code:r 
                                         userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
            }
            return NO;
        }
        NSLog(@"✅ [LibEtPan SMTP] PLAIN 认证成功");
    } else {
        NSLog(@"✅ [LibEtPan SMTP] LOGIN 认证成功");
    }
    
    NSLog(@"✅ [LibEtPan SMTP] 登录成功");
    return YES;
}

- (BOOL)sendMessageTo:(NSArray<NSString *> *)to
                    cc:(nullable NSArray<NSString *> *)cc
                   bcc:(nullable NSArray<NSString *> *)bcc
                subject:(NSString *)subject
                   body:(NSString *)body
              htmlBody:(nullable NSString *)htmlBody
            attachments:(nullable NSArray<NSDictionary<NSString *, id> *> *)attachments
            readReceipt:(BOOL)readReceipt
                  error:(NSError **)error {
    if (!_smtpSession) {
        NSLog(@"❌ [LibEtPan SMTP] 发送失败: 会话未初始化");
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"SMTP 会话未初始化"}];
        }
        return NO;
    }
    
    NSLog(@"📧 [LibEtPan SMTP] 开始发送邮件");
    NSLog(@"📧 [LibEtPan SMTP] 发件人: %@", _username);
    NSLog(@"📧 [LibEtPan SMTP] 收件人: %@", [to componentsJoinedByString:@", "]);
    if (cc && cc.count > 0) {
        NSLog(@"📧 [LibEtPan SMTP] 抄送: %@", [cc componentsJoinedByString:@", "]);
    }
    if (bcc && bcc.count > 0) {
        NSLog(@"📧 [LibEtPan SMTP] 密送: %@", [bcc componentsJoinedByString:@", "]);
    }
    NSLog(@"📧 [LibEtPan SMTP] 主题: %@", subject);
    NSLog(@"📧 [LibEtPan SMTP] 正文长度: %lu 字符", (unsigned long)body.length);
    if (htmlBody) {
        NSLog(@"📧 [LibEtPan SMTP] HTML 正文长度: %lu 字符", (unsigned long)htmlBody.length);
    }
    if (attachments) {
        NSLog(@"📧 [LibEtPan SMTP] 附件数量: %lu", (unsigned long)attachments.count);
        for (NSDictionary *att in attachments) {
            NSString *filename = att[@"filename"] ?: @"unknown";
            NSString *mimeType = att[@"mimeType"] ?: @"application/octet-stream";
            NSData *data = att[@"data"];
            NSLog(@"📧 [LibEtPan SMTP] 附件: %@ (%@, %lu 字节)", filename, mimeType, (unsigned long)(data ? data.length : 0));
        }
    }
    
    // 设置线程 QoS，避免优先级反转
    ensureUserInitiatedQoS();
    
    // 1. 设置发件人
    NSLog(@"📧 [LibEtPan SMTP] 步骤 1: 设置发件人");
    const char *from = [_username UTF8String];
    int r = mailsmtp_mail((mailsmtp *)_smtpSession, from);
    if (r != MAILSMTP_NO_ERROR) {
        NSString *errorMsg = [NSString stringWithFormat:@"设置发件人失败: %d", r];
        NSLog(@"❌ [LibEtPan SMTP] %@", errorMsg);
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    NSLog(@"✅ [LibEtPan SMTP] 发件人设置成功");
    
    // 2. 添加收件人
    NSLog(@"📧 [LibEtPan SMTP] 步骤 2: 添加收件人");
    for (NSString *recipient in to) {
        const char *toAddr = [recipient UTF8String];
        NSLog(@"📧 [LibEtPan SMTP] 添加收件人: %@", recipient);
        r = mailsmtp_rcpt((mailsmtp *)_smtpSession, toAddr);
        if (r != MAILSMTP_NO_ERROR) {
            NSString *errorMsg = [NSString stringWithFormat:@"添加收件人失败: %@, 错误: %d", recipient, r];
            NSLog(@"❌ [LibEtPan SMTP] %@", errorMsg);
            if (error) {
                *error = [NSError errorWithDomain:@"LibEtPanError" 
                                             code:r 
                                         userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
            }
            return NO;
        }
    }
    NSLog(@"✅ [LibEtPan SMTP] 收件人添加成功");
    
    // 添加 CC 收件人
    if (cc && cc.count > 0) {
        NSLog(@"📧 [LibEtPan SMTP] 步骤 2.1: 添加 CC 收件人");
        for (NSString *recipient in cc) {
            const char *ccAddr = [recipient UTF8String];
            NSLog(@"📧 [LibEtPan SMTP] 添加 CC 收件人: %@", recipient);
            r = mailsmtp_rcpt((mailsmtp *)_smtpSession, ccAddr);
            if (r != MAILSMTP_NO_ERROR) {
                NSString *errorMsg = [NSString stringWithFormat:@"添加CC收件人失败: %@, 错误: %d", recipient, r];
                NSLog(@"❌ [LibEtPan SMTP] %@", errorMsg);
                if (error) {
                    *error = [NSError errorWithDomain:@"LibEtPanError" 
                                                 code:r 
                                             userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
                }
                return NO;
            }
        }
        NSLog(@"✅ [LibEtPan SMTP] CC 收件人添加成功");
    }
    
    // 添加 BCC 收件人
    if (bcc && bcc.count > 0) {
        NSLog(@"📧 [LibEtPan SMTP] 步骤 2.2: 添加 BCC 收件人");
        for (NSString *recipient in bcc) {
            const char *bccAddr = [recipient UTF8String];
            NSLog(@"📧 [LibEtPan SMTP] 添加 BCC 收件人: %@", recipient);
            r = mailsmtp_rcpt((mailsmtp *)_smtpSession, bccAddr);
            if (r != MAILSMTP_NO_ERROR) {
                NSString *errorMsg = [NSString stringWithFormat:@"添加BCC收件人失败: %@, 错误: %d", recipient, r];
                NSLog(@"❌ [LibEtPan SMTP] %@", errorMsg);
                if (error) {
                    *error = [NSError errorWithDomain:@"LibEtPanError" 
                                                 code:r 
                                             userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
                }
                return NO;
            }
        }
        NSLog(@"✅ [LibEtPan SMTP] BCC 收件人添加成功");
    }
    
    // 3. 开始数据阶段
    NSLog(@"📧 [LibEtPan SMTP] 步骤 3: 开始数据阶段");
    r = mailsmtp_data((mailsmtp *)_smtpSession);
    if (r != MAILSMTP_NO_ERROR) {
        NSString *errorMsg = [NSString stringWithFormat:@"开始数据阶段失败: %d", r];
        NSLog(@"❌ [LibEtPan SMTP] %@", errorMsg);
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    NSLog(@"✅ [LibEtPan SMTP] 数据阶段开始成功");
    
    // 4. 构建 MIME 消息
    NSLog(@"📧 [LibEtPan SMTP] 步骤 4: 构建 MIME 消息");
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
        for (NSDictionary *attDict in attachments) {
            NSData *attachmentData = attDict[@"data"];
            NSString *filename = attDict[@"filename"] ?: @"attachment";
            NSString *mimeType = attDict[@"mimeType"] ?: @"application/octet-stream";
            
            if (!attachmentData) {
                NSLog(@"⚠️ [LibEtPan SMTP] 跳过无效附件: %@", filename);
                continue;
            }
            
            [message appendFormat:@"--%@\r\n", boundary];
            
            // Content-Type 包含 name 参数（用于兼容性）
            NSString *encodedFilename = [self encodeMimeHeaderValue:filename];
            [message appendFormat:@"Content-Type: %@; name=\"%@\"\r\n", mimeType, encodedFilename];
            [message appendString:@"Content-Transfer-Encoding: base64\r\n"];
            
            // Content-Disposition 包含 filename 参数（Gmail 需要这个）
            [message appendFormat:@"Content-Disposition: attachment; filename=\"%@\"\r\n", encodedFilename];
            [message appendString:@"\r\n"];
            
            NSString *base64 = [attachmentData base64EncodedStringWithOptions:0];
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
    NSLog(@"📧 [LibEtPan SMTP] 步骤 5: 发送消息数据");
    NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
    NSLog(@"📧 [LibEtPan SMTP] 消息大小: %lu 字节", (unsigned long)messageData.length);
    
    r = mailsmtp_data_message((mailsmtp *)_smtpSession, 
                              (const char *)messageData.bytes, 
                              messageData.length);
    
    if (r != MAILSMTP_NO_ERROR) {
        NSString *errorMsg = [NSString stringWithFormat:@"发送消息失败: %d", r];
        NSLog(@"❌ [LibEtPan SMTP] %@", errorMsg);
        NSLog(@"❌ [LibEtPan SMTP] 错误代码: %d", r);
        if (error) {
            *error = [NSError errorWithDomain:@"LibEtPanError" 
                                         code:r 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        }
        return NO;
    }
    
    NSLog(@"✅ [LibEtPan SMTP] 邮件发送成功");
    return YES;
}

// 辅助方法：编码 MIME 头值（用于文件名等，处理非ASCII字符和特殊字符）
- (NSString *)encodeMimeHeaderValue:(NSString *)value {
    // 检查是否包含需要编码的字符
    BOOL needsEncoding = NO;
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar ch = [value characterAtIndex:i];
        if (ch > 127 || ch == '"' || ch == '\\') {
            needsEncoding = NO; // 使用 RFC 2047 编码
            break;
        }
    }
    
    // 如果包含非ASCII字符，使用 RFC 2047 base64 编码
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    BOOL hasNonASCII = NO;
    for (NSUInteger i = 0; i < data.length; i++) {
        unsigned char byte = ((unsigned char *)data.bytes)[i];
        if (byte > 127) {
            hasNonASCII = YES;
            break;
        }
    }
    
    if (hasNonASCII) {
        NSString *base64 = [data base64EncodedStringWithOptions:0];
        return [NSString stringWithFormat:@"=?UTF-8?B?%@?=", base64];
    }
    
    // 转义特殊字符
    NSMutableString *escaped = [NSMutableString string];
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar ch = [value characterAtIndex:i];
        if (ch == '"' || ch == '\\') {
            [escaped appendFormat:@"\\%C", ch];
        } else {
            [escaped appendFormat:@"%C", ch];
        }
    }
    return escaped;
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

// 编码 Modified UTF-7（用于选择文件夹）
- (NSString *)encodeModifiedUTF7:(NSString *)folderName {
    if (!folderName || folderName.length == 0) {
        return folderName;
    }
    
    NSMutableString *encoded = [NSMutableString string];
    NSMutableString *buffer = [NSMutableString string];
    
    void (^flushBuffer)(void) = ^{
        if (buffer.length == 0) { return; }
        NSData *utf16Data = [buffer dataUsingEncoding:NSUTF16BigEndianStringEncoding];
        NSString *base64 = [utf16Data base64EncodedStringWithOptions:0];
        base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@","];
        base64 = [base64 stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
        [encoded appendFormat:@"&%@-", base64];
        [buffer setString:@""];
    };
    
    for (NSUInteger i = 0; i < folderName.length; i++) {
        unichar ch = [folderName characterAtIndex:i];
        if (ch >= 0x20 && ch <= 0x7E) {
            flushBuffer();
            if (ch == '&') {
                [encoded appendString:@"&-"];
            } else {
                [encoded appendFormat:@"%C", ch];
            }
        } else {
            [buffer appendFormat:@"%C", ch];
        }
    }
    
    flushBuffer();
    return encoded;
}

@end
