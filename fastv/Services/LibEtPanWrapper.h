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

/// 获取单个 MIME part 的原始字节（按 IMAP BODY[<section>] 抓取）。
/// partPath 形如 "2"、"1.2"，对应 EmailContentDecoder.parseAttachments 给出的 IMAP body section。
/// 返回的字节仍是 Content-Transfer-Encoding 编码后的原始内容（base64 / quoted-printable / 8bit），由调用方负责解码。
- (nullable NSData *)fetchMessagePartWithUID:(uint32_t)uid
                                     partPath:(NSString *)partPath
                                        error:(NSError **)error;

/// 服务器是否声明支持 IDLE（CAPABILITY 里包含 IDLE）
- (BOOL)hasIdleCapability;

/// 进入 IDLE 状态（同步阻塞，直到服务器接收 `+ idling` 返回）。
/// 调用前需先 selectFolder:。后续读 untagged response 应通过 idleFd 上的 select/poll 监听可读事件。
- (BOOL)idleWithError:(NSError **)error;

/// 退出 IDLE 状态。会消化 IDLE 期间缓存的 untagged response（EXISTS / RECENT / EXPUNGE 等）。
- (BOOL)idleDoneWithError:(NSError **)error;

/// 当前 IDLE 模式下的底层 socket fd，调用方用 select/poll 监听可读以判断有新事件。
- (int)idleFd;

/// 发送一次 NOOP 命令（如果服务器不支持 IDLE，可以靠定时 NOOP 维持轮询）
- (BOOL)noopWithError:(NSError **)error;

/// 标记为已读
- (BOOL)markAsReadWithUID:(uint32_t)uid error:(NSError **)error;

/// 标记为未读（移除 \Seen 标志）
- (BOOL)markAsUnreadWithUID:(uint32_t)uid error:(NSError **)error;

/// 添加 \Flagged 标志（IMAP 星标）
- (BOOL)addFlaggedWithUID:(uint32_t)uid error:(NSError **)error;

/// 移除 \Flagged 标志
- (BOOL)removeFlaggedWithUID:(uint32_t)uid error:(NSError **)error;

/// 标记为已删除并 EXPUNGE，将邮件从当前 mailbox 物理移除
- (BOOL)deleteAndExpungeWithUID:(uint32_t)uid error:(NSError **)error;

/// 将邮件 MOVE 到目标文件夹；若服务器不支持 MOVE 扩展则降级为 COPY + STORE +DELETED + EXPUNGE
- (BOOL)moveMessageWithUID:(uint32_t)uid
            toFolder:(NSString *)destinationFolder
                error:(NSError **)error;

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
