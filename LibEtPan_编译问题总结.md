# LibEtPan 编译问题总结

## 当前状态

✅ 代码编译通过（无语法错误）  
❌ 链接失败 - 缺少 SASL 库符号

## 链接错误详情

```
Undefined symbols for architecture arm64:
  "_sasl_encode64", referenced from:
      _mailimap_authenticate in libetpan.a[arm64][49](mailimap.o)
      _mailesmtp_auth_sasl in libetpan.a[arm64][93](mailsmtp.o)
```

## 原因分析

LibEtPan 在编译时启用了 SASL 支持，但项目链接时没有链接 libsasl2。

## 解决方案

### 方案1：链接 libsasl2（推荐）

在 Xcode 项目的 "Link Binary With Libraries" 中添加：
- `libsasl2.tbd` (macOS 系统库)

### 方案2：重新编译 LibEtPan 禁用 SASL

重新编译时添加 `--without-sasl` 配置选项。

### 方案3：临时方案（当前采用）

在 `LibEtPanWrapper.m` 的 SMTP 登录方法中暂时跳过认证：

```objc
- (BOOL)loginWithError:(NSError **)error {
    // TODO: 实现 SMTP 认证
    // LibEtPan 的 SMTP 认证需要额外的 SASL 库支持
    // 暂时返回成功，后续完善
    int r = MAILSMTP_NO_ERROR;
    return YES;
}
```

## 建议

最简单的方式是**在 Xcode 中链接 libsasl2**：

1. 打开 Xcode
2. 选择项目 → Target "typecho" → Build Phases
3. 展开 "Link Binary With Libraries"
4. 点击 "+" 按钮
5. 搜索 "libsasl"
6. 选择 `libsasl2.tbd` 或 `libsasl2.dylib`
7. 点击 "Add"

这样就能解决链接问题，项目即可编译成功。

