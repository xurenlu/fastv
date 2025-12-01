//
//  LuaWrapper.m
//  fastv
//
//  Created for Lua integration
//

#import "LuaWrapper.h"

// Lua C API 头文件
// 注意：如果 Lua 库未集成，这些头文件可能不存在
// 需要先集成 Lua 库到项目中
#ifdef LUA_AVAILABLE
#import <lua.h>
#import <lauxlib.h>
#import <lualib.h>
#else
// 如果没有 Lua，定义空类型和空函数以避免编译错误
typedef struct lua_State lua_State;
#define LUA_OK 0
#define LUA_MULTRET (-1)
static inline lua_State* luaL_newstate(void) { return NULL; }
static inline void luaL_openlibs(lua_State* L) {}
static inline void lua_close(lua_State* L) {}
static inline int luaL_loadfile(lua_State* L, const char* filename) { return -1; }
static inline int luaL_loadstring(lua_State* L, const char* s) { return -1; }
static inline const char* lua_tostring(lua_State* L, int index) { return "Lua not available"; }
static inline void lua_pop(lua_State* L, int n) {}
static inline int lua_pcall(lua_State* L, int nargs, int nresults, int msgh) { return -1; }
static inline void lua_getglobal(lua_State* L, const char* name) {}
static inline int lua_isfunction(lua_State* L, int index) { return 0; }
static inline void lua_pushnil(lua_State* L) {}
static inline void lua_pushboolean(lua_State* L, int b) {}
static inline void lua_pushinteger(lua_State* L, long long n) {}
static inline void lua_pushnumber(lua_State* L, double n) {}
static inline void lua_pushstring(lua_State* L, const char* s) {}
static inline void lua_newtable(lua_State* L) {}
static inline void lua_settable(lua_State* L, int index) {}
static inline void lua_setglobal(lua_State* L, const char* name) {}
static inline int lua_isnil(lua_State* L, int index) { return 1; }
static inline int lua_toboolean(lua_State* L, int index) { return 0; }
static inline double lua_tonumber(lua_State* L, int index) { return 0; }
static inline int lua_istable(lua_State* L, int index) { return 0; }
static inline int lua_next(lua_State* L, int index) { return 0; }
static inline int lua_gettop(lua_State* L) { return 0; }
static inline void* lua_touserdata(lua_State* L, int index) { return NULL; }
static inline void lua_pushlightuserdata(lua_State* L, void* p) {}
static inline void lua_pushcclosure(lua_State* L, int (*fn)(lua_State*), int n) {}
static inline int lua_upvalueindex(int i) { return 0; }
#endif

// Lua C API 桥接
// 注意：这里假设 Lua 库已经集成到项目中
// 如果没有，需要先添加 Lua 源码或预编译库

@interface LuaWrapper ()
@property (nonatomic, assign) lua_State *L;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id (^)(NSArray *)> *registeredFunctions;
@end

@implementation LuaWrapper

- (instancetype)init {
    self = [super init];
    if (self) {
#ifdef LUA_AVAILABLE
        _L = luaL_newstate();
        if (_L) {
            luaL_openlibs(_L);
        }
#else
        _L = NULL; // Lua 不可用
#endif
        _registeredFunctions = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
}

- (void)cleanup {
#ifdef LUA_AVAILABLE
    if (_L) {
        lua_close(_L);
        _L = NULL;
    }
#endif
}

- (LuaResult *)loadFile:(NSString *)filePath error:(NSError **)error {
    LuaResult *result = [[LuaResult alloc] init];
    
#ifdef LUA_AVAILABLE
    if (!_L) {
        if (error) {
            *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lua state not initialized"}];
        }
        result.success = NO;
        result.error = *error;
        return result;
    }
    
    int status = luaL_loadfile(_L, [filePath UTF8String]);
    if (status != LUA_OK) {
        const char *errorMsg = lua_tostring(_L, -1);
        lua_pop(_L, 1);
        if (error) {
            *error = [NSError errorWithDomain:@"LuaWrapper" code:status userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errorMsg]}];
        }
        result.success = NO;
        result.error = *error;
        return result;
    }
    
    status = lua_pcall(_L, 0, LUA_MULTRET, 0);
    if (status != LUA_OK) {
        const char *errorMsg = lua_tostring(_L, -1);
        lua_pop(_L, 1);
        if (error) {
            *error = [NSError errorWithDomain:@"LuaWrapper" code:status userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errorMsg]}];
        }
        result.success = NO;
        result.error = *error;
        return result;
    }
    
    result.success = YES;
    return result;
#else
    if (error) {
        *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lua library not available. Please install Lua or enable LUA_AVAILABLE."}];
    }
    result.success = NO;
    result.error = *error;
    return result;
#endif
}

- (LuaResult *)loadString:(NSString *)luaCode error:(NSError **)error {
    LuaResult *result = [[LuaResult alloc] init];
    
#ifdef LUA_AVAILABLE
    if (!_L) {
        if (error) {
            *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lua state not initialized"}];
        }
        result.success = NO;
        result.error = *error;
        return result;
    }
    
    int status = luaL_loadstring(_L, [luaCode UTF8String]);
    if (status != LUA_OK) {
        const char *errorMsg = lua_tostring(_L, -1);
        lua_pop(_L, 1);
        if (error) {
            *error = [NSError errorWithDomain:@"LuaWrapper" code:status userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errorMsg]}];
        }
        result.success = NO;
        result.error = *error;
        return result;
    }
    
    status = lua_pcall(_L, 0, LUA_MULTRET, 0);
    if (status != LUA_OK) {
        const char *errorMsg = lua_tostring(_L, -1);
        lua_pop(_L, 1);
        if (error) {
            *error = [NSError errorWithDomain:@"LuaWrapper" code:status userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errorMsg]}];
        }
        result.success = NO;
        result.error = *error;
        return result;
    }
    
    result.success = YES;
#else
    if (error) {
        *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lua library not available"}];
    }
    result.success = NO;
    result.error = *error;
#endif
    return result;
}

- (LuaResult *)callFunction:(NSString *)functionName withArguments:(NSArray *)arguments error:(NSError **)error {
    LuaResult *result = [[LuaResult alloc] init];
    
#ifdef LUA_AVAILABLE
    if (!_L) {
        if (error) {
            *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lua state not initialized"}];
        }
        result.success = NO;
        result.error = *error;
        return result;
    }
    
    // 获取函数
    lua_getglobal(_L, [functionName UTF8String]);
    if (!lua_isfunction(_L, -1)) {
        lua_pop(_L, 1);
        if (error) {
            *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Function '%@' not found", functionName]}];
        }
        result.success = NO;
        result.error = *error;
        return result;
    }
    
    // 推送参数
    for (id arg in arguments) {
        [self pushValue:arg];
    }
    
    // 调用函数
    int status = lua_pcall(_L, (int)arguments.count, 1, 0);
    if (status != LUA_OK) {
        const char *errorMsg = lua_tostring(_L, -1);
        lua_pop(_L, 1);
        if (error) {
            *error = [NSError errorWithDomain:@"LuaWrapper" code:status userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errorMsg]}];
        }
        result.success = NO;
        result.error = *error;
        return result;
    }
    
    // 获取返回值
    result.value = [self popValue];
    result.success = YES;
#else
    if (error) {
        *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lua library not available"}];
    }
    result.success = NO;
    result.error = *error;
#endif
    return result;
}

- (BOOL)setGlobal:(NSString *)name value:(id)value error:(NSError **)error {
#ifdef LUA_AVAILABLE
    if (!_L) {
        if (error) {
            *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lua state not initialized"}];
        }
        return NO;
    }
    
    [self pushValue:value];
    lua_setglobal(_L, [name UTF8String]);
    return YES;
#else
    if (error) {
        *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lua library not available"}];
    }
    return NO;
#endif
}

- (id)getGlobal:(NSString *)name error:(NSError **)error {
#ifdef LUA_AVAILABLE
    if (!_L) {
        if (error) {
            *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lua state not initialized"}];
        }
        return nil;
    }
    
    lua_getglobal(_L, [name UTF8String]);
    id value = [self popValue];
    return value;
#else
    if (error) {
        *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lua library not available"}];
    }
    return nil;
#endif
}

- (BOOL)registerFunction:(NSString *)name block:(id (^)(NSArray *))block error:(NSError **)error {
#ifdef LUA_AVAILABLE
    if (!_L) {
        if (error) {
            *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lua state not initialized"}];
        }
        return NO;
    }
    
    self.registeredFunctions[name] = block;
    
    // 创建 Lua C 函数包装器
    lua_pushlightuserdata(_L, (__bridge void *)self);
    lua_pushstring(_L, [name UTF8String]);
    lua_pushcclosure(_L, luaFunctionWrapper, 2);
    lua_setglobal(_L, [name UTF8String]);
    
    return YES;
#else
    if (error) {
        *error = [NSError errorWithDomain:@"LuaWrapper" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Lua library not available"}];
    }
    return NO;
#endif
}

// 辅助方法：推送值到 Lua 栈
- (void)pushValue:(id)value {
#ifdef LUA_AVAILABLE
    if (value == nil || [value isKindOfClass:[NSNull class]]) {
        lua_pushnil(_L);
    } else if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber *num = (NSNumber *)value;
        if (strcmp([num objCType], @encode(BOOL)) == 0) {
            lua_pushboolean(_L, [num boolValue]);
        } else if ([num isEqualToNumber:@(floor([num doubleValue]))]) {
            lua_pushinteger(_L, [num longLongValue]);
        } else {
            lua_pushnumber(_L, [num doubleValue]);
        }
    } else if ([value isKindOfClass:[NSString class]]) {
        lua_pushstring(_L, [(NSString *)value UTF8String]);
    } else if ([value isKindOfClass:[NSArray class]]) {
        lua_newtable(_L);
        NSArray *array = (NSArray *)value;
        for (NSUInteger i = 0; i < array.count; i++) {
            lua_pushinteger(_L, (lua_Integer)(i + 1));
            [self pushValue:array[i]];
            lua_settable(_L, -3);
        }
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        lua_newtable(_L);
        NSDictionary *dict = (NSDictionary *)value;
        for (NSString *key in dict) {
            [self pushValue:key];
            [self pushValue:dict[key]];
            lua_settable(_L, -3);
        }
    } else {
        lua_pushnil(_L);
    }
#endif
}

// 辅助方法：从 Lua 栈弹出值
- (id)popValue {
#ifdef LUA_AVAILABLE
    if (lua_isnil(_L, -1)) {
        lua_pop(_L, 1);
        return [NSNull null];
    } else if (lua_isboolean(_L, -1)) {
        BOOL value = lua_toboolean(_L, -1);
        lua_pop(_L, 1);
        return @(value);
    } else if (lua_isnumber(_L, -1)) {
        double value = lua_tonumber(_L, -1);
        lua_pop(_L, 1);
        return @(value);
    } else if (lua_isstring(_L, -1)) {
        const char *str = lua_tostring(_L, -1);
        NSString *value = [NSString stringWithUTF8String:str];
        lua_pop(_L, 1);
        return value;
    } else if (lua_istable(_L, -1)) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        lua_pushnil(_L);
        while (lua_next(_L, -2) != 0) {
            id key = [self popValue];
            id value = [self popValue];
            if ([key isKindOfClass:[NSString class]]) {
                dict[key] = value;
            } else if ([key isKindOfClass:[NSNumber class]]) {
                // 数组索引
                NSInteger index = [key integerValue];
                if (dict[@"__array"] == nil) {
                    dict[@"__array"] = [NSMutableArray array];
                }
                NSMutableArray *array = dict[@"__array"];
                while (array.count < index) {
                    [array addObject:[NSNull null]];
                }
                array[index - 1] = value;
            }
            lua_pop(_L, 1);
        }
        lua_pop(_L, 1);
        
        // 如果是数组（连续数字索引）
        if (dict[@"__array"]) {
            return dict[@"__array"];
        }
        return dict;
    } else {
        lua_pop(_L, 1);
        return [NSNull null];
    }
#else
    return [NSNull null];
#endif
}

@end

// Lua C 函数包装器
#ifdef LUA_AVAILABLE
static int luaFunctionWrapper(lua_State *L) {
    LuaWrapper *wrapper = (__bridge LuaWrapper *)lua_touserdata(L, lua_upvalueindex(1));
    const char *name = lua_tostring(L, lua_upvalueindex(2));
    NSString *functionName = [NSString stringWithUTF8String:name];
    
    id (^block)(NSArray *) = wrapper.registeredFunctions[functionName];
    if (!block) {
        return 0;
    }
    
    // 收集参数
    NSMutableArray *arguments = [NSMutableArray array];
    int argCount = lua_gettop(L);
    for (int i = 1; i <= argCount; i++) {
        id value = [wrapper popValue];
        [arguments insertObject:value atIndex:0];
    }
    
    // 调用 block
    id result = block(arguments);
    
    // 推送返回值
    [wrapper pushValue:result];
    return 1;
}
#endif

@implementation LuaResult
@end

