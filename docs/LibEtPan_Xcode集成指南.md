# LibEtPan Xcode 集成指南

## 已完成的工作

1. ✅ LibEtPan 源码已下载到 `ThirdParty/libetpan`
2. ✅ LibEtPan 静态库已编译成功（`libetpan.a`）
3. ✅ 创建了桥接头文件 `fastv/fastv-Bridging-Header.h`
4. ✅ 创建了 Objective-C 包装类 `LibEtPanWrapper.h/m`
5. ✅ 更新了 `EmailService.swift` 使用 LibEtPan

## 需要在 Xcode 中配置的步骤

### 1. 添加静态库到项目 ✅ 已完成

静态库文件已复制到项目目录：
- **相对路径**：`Libraries/libetpan/libetpan.a`（相对于项目根目录）
- **绝对路径**：`/Users/rocky/Sites/fastv/Libraries/libetpan/libetpan.a`
- **文件大小**：11MB
- **架构**：Universal Binary (arm64 + x86_64)
- **状态**：✅ 文件已存在并可用

**下一步（在 Xcode 中操作）：**
1. 在 Xcode 中打开 `fastv.xcodeproj`
2. 右键点击项目导航器中的项目根目录
3. 选择 "Add Files to 'fastv'..."
4. 导航到 `Libraries/libetpan/libetpan.a` 并选择
5. 确保勾选：
   - ✅ "Copy items if needed"（如果还没复制）
   - ✅ Target "typecho"
6. 点击 "Add"

### 2. 配置头文件搜索路径 ⚠️ 重要

LibEtPan 的头文件使用系统路径格式 `<libetpan/...>`，因此需要配置正确的 Header Search Paths。

1. 选择项目 → Build Settings
2. 搜索 "Header Search Paths"
3. 添加以下路径（**必须设置为递归**）：
   ```
   $(SRCROOT)/ThirdParty/libetpan/include
   ```
   
   **重要说明：**
   - LibEtPan 的头文件在 `include/libetpan/` 目录下
   - 这些头文件使用 `<libetpan/...>` 格式导入其他头文件
   - 因此 Header Search Paths 必须指向 `include` 目录，而不是 `src` 目录
   - 必须勾选 "recursive"（递归）选项

### 3. 配置桥接头文件

1. 选择项目 → Build Settings
2. 搜索 "Objective-C Bridging Header"
3. 设置为：`fastv/fastv-Bridging-Header.h`

### 4. 链接必要的框架和库 ⚠️ 重要

LibEtPan 依赖多个系统库，必须全部链接才能编译通过。

在 Build Phases → Link Binary With Libraries 中添加以下所有库：

**必须添加的库（共 7 个）：**
1. `libz.tbd` - zlib 压缩库（解决 _deflate, _inflate 等符号错误）
2. `libsasl2.tbd` - SASL 认证库（解决 _sasl_* 符号错误）
3. `libiconv.tbd` - 字符编码转换库（解决 _iconv_* 符号错误）
4. `libresolv.tbd` - DNS 解析库（解决 _res_* 符号错误）
5. `Security.framework` - 安全框架（SSL/TLS 支持）
6. `CFNetwork.framework` - 网络框架（解决 _CF* 网络相关符号错误）
7. `libetpan.a` - LibEtPan 静态库

**添加步骤：**
1. 在 Xcode 中选择项目 → Target "typecho" → Build Phases
2. 展开 "Link Binary With Libraries"
3. 点击 "+" 按钮
4. 搜索并添加上述每个库
5. 对于 `.tbd` 文件，在搜索框中输入库名（如 "libz"）即可找到
6. 对于 `libetpan.a`，点击 "Add Other..." → "Add Files..."，导航到 `Libraries/libetpan/libetpan.a`

**常见链接错误及解决方案：**
- `Undefined symbol: _deflate` / `_inflate` → 需要链接 `libz.tbd`
- `Undefined symbol: _sasl_*` → 需要链接 `libsasl2.tbd`
- `Undefined symbol: _iconv` / `_iconv_open` / `_iconv_close` → 需要链接 `libiconv.tbd`
- `Undefined symbol: _res_*` → 需要链接 `libresolv.tbd`
- `Undefined symbol: _CF*` (如 _CFReadStreamOpen) → 需要链接 `CFNetwork.framework`
- `Undefined symbol: _Sec*` (如 _SecCertificateCopyData) → 需要链接 `Security.framework`

### 5. 配置库搜索路径

1. 选择项目 → Build Settings
2. 搜索 "Library Search Paths"
3. 添加以下路径（递归）：
   ```
   $(SRCROOT)/Libraries/libetpan
   ```
   这样 Xcode 就能找到 `libetpan.a` 静态库文件

## 验证集成

编译项目，如果出现以下错误，需要检查：
- 找不到头文件 → 检查 Header Search Paths
- 链接错误 → 检查是否添加了所有必要的框架和库
- 桥接错误 → 检查桥接头文件路径是否正确

## 注意事项

1. LibEtPan 是 C 库，需要通过 Objective-C 包装才能在 Swift 中使用
2. 确保所有 LibEtPan 的头文件路径正确
3. 某些功能（如邮件正文获取、发送邮件）需要进一步实现 MIME 解析

## 下一步

完成 Xcode 配置后，可以：
1. 测试连接功能
2. 实现完整的邮件同步
3. 实现邮件发送功能
4. 完善 MIME 解析

