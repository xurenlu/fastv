# MicroAPP 进程隔离和安全机制

## 📋 概述

为了防止某个 microAPP 的代码质量问题导致整个程序崩溃，我们实现了完整的进程隔离和安全机制。

## 🔒 核心隔离机制

### 1. **独立进程池（WKProcessPool）**

每个 microAPP 使用独立的 `WKProcessPool`，确保：

- ✅ **进程隔离**：每个 microAPP 运行在独立的 WebContent 进程中
- ✅ **崩溃隔离**：某个 microAPP 崩溃不会影响其他 microAPP 或主进程
- ✅ **资源隔离**：每个进程有独立的内存空间

**实现位置**：`MicroAppProcessPoolManager.swift`

```swift
// 为每个应用创建独立的进程池
let processPool = MicroAppProcessPoolManager.shared.getProcessPool(for: appId)
config.processPool = processPool
```

### 2. **进程崩溃处理**

当 WebContent 进程意外终止时：

- ✅ 自动检测进程崩溃（`webViewWebContentProcessDidTerminate`）
- ✅ 清理崩溃应用的进程池
- ✅ 显示错误消息，但不影响主程序
- ✅ 其他 microAPP 继续正常运行

**实现位置**：`MicroAppHostView.swift` - `Coordinator.webViewWebContentProcessDidTerminate`

### 3. **独立数据存储**

每个 microAPP 使用非持久化的数据存储：

- ✅ 应用关闭后数据自动清除
- ✅ 防止数据泄露和污染
- ✅ 更好的隔离性

```swift
let dataStore = WKWebsiteDataStore.nonPersistent()
config.websiteDataStore = dataStore
```

## 🛡️ 安全策略

### 1. **网络访问限制**

- ❌ 禁止直接访问外部网络（http/https）
- ✅ 必须通过 Bridge API 访问网络资源
- ✅ 只允许加载本地文件（file://）

**实现**：`decidePolicyFor navigationAction` 方法拦截外部请求

### 2. **资源限制**

- ✅ 禁用媒体自动播放（减少资源消耗）
- ✅ 限制 JavaScript 窗口打开
- ✅ CPU 监控和自动终止（见 `MicroAppCPUMonitor`）

### 3. **权限控制**

- ✅ 通过 `MicroAppManifest` 控制权限
- ✅ Bridge API 检查权限后才执行操作
- ✅ 防止未授权访问系统资源

## 📊 CPU 监控和自动终止

### 工作原理

1. **监控频率**：每 2 秒检测一次 CPU 使用率
2. **检测方法**：
   - WebContent 进程 CPU（通过 `ps` 命令）
   - JavaScript 主线程响应性检测
3. **终止条件**：连续 3 次（6 秒）超过阈值（默认 80%）
4. **终止操作**：
   - 停止 WebView 加载
   - 停止 JavaScript 执行
   - 清理进程池
   - 显示错误消息和通知

### 配置参数

```swift
cpuMonitor.cpuThreshold = 80.0          // CPU 阈值（%）
cpuMonitor.checkInterval = 2.0           // 检测间隔（秒）
cpuMonitor.consecutiveThreshold = 3      // 连续超过阈值次数
```

## 🔄 进程生命周期管理

### 进程池创建

```
应用启动 → 创建独立进程池 → WebView 使用进程池 → 进程隔离运行
```

### 进程池清理

```
应用关闭 → 释放进程池引用 → 引用计数归零 → 自动清理进程池
```

### 进程崩溃恢复

```
进程崩溃 → 检测崩溃事件 → 清理进程池 → 显示错误 → 主程序继续运行
```

## 🎯 隔离效果

### 场景 1：某个 microAPP 代码有死循环

**结果**：
- ✅ CPU 监控检测到高 CPU 使用率
- ✅ 自动终止该 microAPP
- ✅ 其他 microAPP 和主程序不受影响

### 场景 2：某个 microAPP JavaScript 崩溃

**结果**：
- ✅ WebContent 进程崩溃
- ✅ 自动检测并清理
- ✅ 显示错误消息
- ✅ 其他 microAPP 继续运行

### 场景 3：某个 microAPP 内存泄漏

**结果**：
- ✅ 进程隔离限制内存影响范围
- ✅ 应用关闭后自动清理数据存储
- ✅ 不影响其他应用

## 📝 最佳实践

### 对于 microAPP 开发者

1. **避免死循环**：使用 `setTimeout`/`setInterval` 而不是同步循环
2. **错误处理**：使用 `try-catch` 捕获错误
3. **资源清理**：及时清理事件监听器和定时器
4. **性能优化**：避免频繁的 DOM 操作和重绘

### 对于主程序

1. **监控日志**：查看控制台日志了解 microAPP 状态
2. **用户通知**：当 microAPP 被终止时，用户会收到通知
3. **错误处理**：主程序会自动处理进程崩溃，无需额外代码

## 🔍 调试和监控

### 查看进程隔离状态

```swift
// 在控制台查看进程池创建日志
🔒 [MicroAppProcessPoolManager] 为应用 xxx 创建独立进程池
```

### 查看进程崩溃

```swift
💥 [MicroAppWebView] WebContent 进程崩溃: xxx
🛑 [MicroAppProcessPoolManager] 强制清理应用 xxx 的进程池（进程崩溃）
```

### 查看 CPU 监控

```swift
🔍 [MicroAppCPUMonitor] 开始监控应用: xxx, CPU阈值: 80.0%, 检测间隔: 2.0秒
⚠️ [MicroAppCPUMonitor] 应用 xxx CPU使用率: 85.3% (连续 1/3 次超过阈值)
🛑 [MicroAppCPUMonitor] 应用 xxx CPU使用率持续过高，自动终止
```

## ✅ 总结

通过以上机制，我们实现了：

1. ✅ **进程隔离**：每个 microAPP 独立进程，互不影响
2. ✅ **崩溃隔离**：进程崩溃不影响主程序
3. ✅ **资源隔离**：独立数据存储和内存空间
4. ✅ **自动监控**：CPU 监控和自动终止
5. ✅ **安全策略**：网络访问限制和权限控制

即使某个 microAPP 的代码质量很差，也不会把整个程序带垮！

---

**文档版本**: 1.0  
**更新时间**: 2025年1月  
**相关文件**:
- `fastv/Services/MicroAppProcessPoolManager.swift`
- `fastv/Services/MicroAppCPUMonitor.swift`
- `fastv/Views/MicroAppHostView.swift`

