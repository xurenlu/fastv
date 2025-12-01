//
//  LuaWrapper.h
//  fastv
//
//  Created for Lua integration
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class LuaWrapper;

/// Lua 执行结果
@interface LuaResult : NSObject
@property (nonatomic, strong, nullable) id value;
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic, assign) BOOL success;
@end

/// Lua 包装器
@interface LuaWrapper : NSObject

/// 初始化 Lua 状态机
- (instancetype)init;

/// 加载并执行 Lua 脚本文件
- (LuaResult *)loadFile:(NSString *)filePath error:(NSError **)error;

/// 加载并执行 Lua 代码字符串
- (LuaResult *)loadString:(NSString *)luaCode error:(NSError **)error;

/// 调用 Lua 函数
- (LuaResult *)callFunction:(NSString *)functionName withArguments:(NSArray *)arguments error:(NSError **)error;

/// 设置全局变量
- (BOOL)setGlobal:(NSString *)name value:(id)value error:(NSError **)error;

/// 获取全局变量
- (id)getGlobal:(NSString *)name error:(NSError **)error;

/// 注册 Swift 函数到 Lua
- (BOOL)registerFunction:(NSString *)name block:(id (^)(NSArray *))block error:(NSError **)error;

/// 清理资源
- (void)cleanup;

@end

NS_ASSUME_NONNULL_END

