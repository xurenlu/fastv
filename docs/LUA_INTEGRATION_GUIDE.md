# Lua 集成指南

邮件规则引擎使用 Lua 脚本引擎来实现灵活的规则处理。**默认情况下，项目可以在没有 Lua 的情况下编译和运行**，规则引擎功能会被禁用。

## 默认行为（无需 Lua）

- ✅ 项目可以在没有 Lua 的情况下正常编译和运行
- ✅ 邮件的基本功能不受影响
- ✅ 规则引擎会在运行时检测 Lua 是否可用，如果不可用则跳过规则处理
- ⚠️ 规则引擎功能将被禁用，但不会影响其他功能

## 启用 Lua 支持（可选）

如果你想使用邮件规则引擎功能，需要集成 Lua 库：

### 方法一：使用 Homebrew 安装 Lua（推荐）

```bash
brew install lua
```

安装后，Lua 库通常位于 `/opt/homebrew/lib` 或 `/usr/local/lib`。

### 方法二：手动集成 Lua 源码

1. 下载 Lua 5.4 源码：https://www.lua.org/download.html
2. 解压并编译：
```bash
cd lua-5.4.x
make macosx
```
3. 将编译好的库文件添加到 Xcode 项目

### Xcode 项目配置

1. **添加 Lua 头文件路径**
   - 在 Build Settings 中搜索 "Header Search Paths"
   - 添加 Lua 头文件所在目录（例如：`/opt/homebrew/include`）

2. **添加 Lua 库路径**
   - 在 Build Settings 中搜索 "Library Search Paths"
   - 添加 Lua 库所在目录（例如：`/opt/homebrew/lib`）

3. **链接 Lua 库**
   - 在 Build Phases > Link Binary With Libraries 中添加 `liblua.a` 或 `liblua.dylib`

4. **定义 LUA_AVAILABLE**
   - 在 Build Settings > Preprocessor Macros 中添加 `LUA_AVAILABLE=1`

5. **确保 LuaWrapper 文件已添加到编译目标**
   - 检查 `fastv/Services/LuaWrapper.h` 和 `LuaWrapper.m` 是否在编译目标中
   - 检查桥接头文件 `fastv/fastv-Bridging-Header.h` 是否正确配置

## 验证集成

编译项目，如果成功编译且没有 Lua 相关的链接错误，说明集成成功。

运行应用后，查看控制台日志：
- 如果看到 "✅ [LuaEngine] Lua 引擎初始化成功"，说明 Lua 已正确集成
- 如果看到 "⚠️ [LuaEngine] LuaWrapper 类未找到"，说明 Lua 未集成（这是正常的，不影响基本功能）

## 注意事项

- **默认情况下不需要 Lua**：项目设计为可以在没有 Lua 的情况下运行
- 规则引擎功能是可选的，不影响邮件的核心功能
- 如果 Lua 不可用，规则引擎会在日志中输出警告信息，但不会崩溃

