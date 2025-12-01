//
//  LibEtPanWrapper.h
//  fastv
//
//  Objective-C wrapper for LibEtPan C API
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// LibEtPan IMAP 会话包装
@interface LibEtPanIMAPSession : NSObject

@property (nonatomic, readonly, nullable) void *imapSession; // mailimap *

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithHost:(NSString *)host
                                  port:(NSInteger)port
                            encryption:(NSString *)encryption // "ssl", "startTLS", "none"
                              username:(NSString *)username
                              password:(NSString *)password;

/// 连接到 IMAP 服务器
- (BOOL)connectWithError:(NSError **)error;

/// 登录
- (BOOL)loginWithError:(NSError **)error;

/// 选择文件夹
- (BOOL)selectFolder:(NSString *)folderName error:(NSError **)error;

/// 获取文件夹列表
- (nullable NSArray<NSString *> *)fetchFoldersWithError:(NSError **)error;

/// 获取邮件列表（UID范围，返回包含 UID 和基本信息的字典）
- (nullable NSArray<NSDictionary *> *)fetchMessagesFromUID:(uint32_t)fromUID toUID:(uint32_t)toUID error:(NSError **)error;

/// 按日期搜索邮件（sinceDate 为 nil 时获取所有邮件）
- (nullable NSArray<NSDictionary *> *)fetchMessagesSinceDate:(nullable NSDate *)sinceDate limit:(NSUInteger)limit error:(NSError **)error;

/// 按文本搜索邮件（搜索主题、发件人、正文等）
- (nullable NSArray<NSDictionary *> *)searchMessagesWithQuery:(NSString *)query limit:(NSUInteger)limit error:(NSError **)error;

/// 快速获取最新N封邮件的UID（不搜索，直接从最新开始获取）
- (nullable NSArray<NSDictionary *> *)fetchLatestMessagesWithLimit:(NSUInteger)limit error:(NSError **)error;

/// 获取单封邮件头信息（Subject, From, To, Date等）
- (nullable NSDictionary<NSString *, id> *)fetchMessageHeadersWithUID:(uint32_t)uid error:(NSError **)error;

/// 批量获取多封邮件头信息（性能优化：一次请求获取多封）
- (nullable NSArray<NSDictionary *> *)fetchBatchMessageHeadersWithUIDs:(NSArray<NSNumber *> *)uids error:(NSError **)error;

/// 获取邮件内容
- (nullable NSData *)fetchMessageBodyWithUID:(uint32_t)uid error:(NSError **)error;

/// 标记为已读
- (BOOL)markAsReadWithUID:(uint32_t)uid error:(NSError **)error;

/// 断开连接
- (void)disconnect;

/// 解码 Modified UTF-7 编码的文件夹名称
- (NSString *)decodeModifiedUTF7:(NSString *)encoded;

/// 编码 Modified UTF-7（用于选择文件夹）
- (NSString *)encodeModifiedUTF7:(NSString *)folderName;

@end

/// LibEtPan SMTP 会话包装
@interface LibEtPanSMTPSession : NSObject

@property (nonatomic, readonly, nullable) void *smtpSession; // mailsmtp *

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithHost:(NSString *)host
                                  port:(NSInteger)port
                            encryption:(NSString *)encryption // "ssl", "startTLS", "none"
                              username:(NSString *)username
                              password:(NSString *)password;

/// 连接到 SMTP 服务器
- (BOOL)connectWithError:(NSError **)error;

/// 登录
- (BOOL)loginWithError:(NSError **)error;

/// 发送邮件
/// attachments: 附件数组，每个元素是包含 "data"(NSData), "filename"(NSString), "mimeType"(NSString) 的字典
- (BOOL)sendMessageTo:(NSArray<NSString *> *)to
                    cc:(nullable NSArray<NSString *> *)cc
                   bcc:(nullable NSArray<NSString *> *)bcc
                subject:(NSString *)subject
                   body:(NSString *)body
              htmlBody:(nullable NSString *)htmlBody
            attachments:(nullable NSArray<NSDictionary<NSString *, id> *> *)attachments
            readReceipt:(BOOL)readReceipt
                  error:(NSError **)error;

/// 断开连接
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
