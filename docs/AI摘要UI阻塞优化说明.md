# AI 摘要 UI 阻塞优化说明

## 问题描述

在获取邮件 AI 摘要时，可能会引起 UI 阻塞。原因是 `EmailAIService` 中的方法多次使用 `await MainActor.run` 来获取配置和偏好设置，每次调用都会切换到主线程，如果主线程繁忙，会造成 UI 卡顿。

## 问题分析

### 之前的实现问题

在 `EmailAIService` 中，每个 AI 方法（`generateSummary`、`generateSmartTags`、`detectPriority`）都会：

1. 使用 `await MainActor.run` 获取配置（第1次切换到主线程）
2. 使用 `await MainActor.run` 获取 preferences（第2次切换到主线程）

如果同时调用多个方法（如标签、优先级、摘要），就会多次切换到主线程，造成阻塞。

### 示例代码（优化前）

```swift
func generateSummary(for message: EmailMessage) async throws -> String {
    let config = await MainActor.run {  // 第1次切换到主线程
        preferences.getConfig(for: .aiChat)
    }
    
    // ... 构建 prompt ...
    
    let prefs = await MainActor.run {  // 第2次切换到主线程
        preferences
    }
    
    let result = try await chatAIService.sendMessage(...)
    return result.content
}
```

## 优化方案

### 1. 修改 AI 服务方法签名

为 `EmailAIService` 的方法添加可选参数，允许调用者传入已获取的配置：

```swift
func generateSummary(
    for message: EmailMessage, 
    config: AIServiceConfig? = nil, 
    preferences: UserPreferences? = nil
) async throws -> String
```

如果提供了配置，就直接使用；否则才切换到主线程获取（但只切换一次）。

### 2. 在 ViewModel 中一次性获取配置

在 `EmailViewModel.analyzeMessageWithAI` 中，一次性从主线程获取所有需要的配置和数据：

```swift
let (currentMessage, needsTagging, needsPriority, needsSummary, config, prefs) = await MainActor.run {
    // 一次性获取所有数据，只切换一次主线程
    let msg = messages.first(where: { $0.id == message.id }) ?? message
    let tagging = preferences.emailAISmartTaggingEnabled && msg.aiTags.isEmpty
    let priority = preferences.emailAIPriorityDetectionEnabled && msg.aiPriority == nil
    let summary = preferences.emailAISummaryEnabled && msg.aiSummary == nil
    let aiConfig = preferences.getConfig(for: .aiChat)
    return (msg, tagging, priority, summary, aiConfig, preferences)
}
```

然后将配置传递给 AI 服务方法：

```swift
if needsSummary {
    let summary = try await emailAIService.generateSummary(
        for: currentMessage, 
        config: config,      // 传入已获取的配置
        preferences: prefs   // 传入已获取的偏好设置
    )
    updated.aiSummary = summary
}
```

## 优化效果

### 优化前
- 每个 AI 方法调用：2次主线程切换
- 如果同时调用3个方法（标签+优先级+摘要）：6次主线程切换
- 每次切换都可能造成 UI 短暂卡顿

### 优化后
- ViewModel 中：1次主线程切换（一次性获取所有配置）
- AI 服务方法：0次主线程切换（使用传入的配置）
- 总共：1次主线程切换，大幅减少 UI 阻塞

## 修改的文件

1. **fastv/Services/EmailAIService.swift**
   - `generateSummary(for:config:preferences:)` - 添加可选参数
   - `generateSmartTags(for:config:preferences:)` - 添加可选参数
   - `detectPriority(for:config:preferences:)` - 添加可选参数

2. **fastv/ViewModels/EmailViewModel.swift**
   - `analyzeMessageWithAI(_:)` - 优化为一次性获取配置并传递给 AI 服务

## 兼容性

所有修改都保持了向后兼容：
- 新参数都有默认值 `nil`
- 如果调用者不提供配置，方法会自动从主线程获取（保持原有行为）
- 不影响其他调用这些方法的地方

## 测试建议

1. 测试邮件 AI 摘要生成功能，确保正常工作
2. 测试邮件智能标签生成功能
3. 测试邮件优先级检测功能
4. 使用 Instruments 的 Time Profiler 检查主线程阻塞情况
5. 测试同时启用多个 AI 功能时的性能表现

## 相关文档

- [Swift Concurrency: MainActor](https://developer.apple.com/documentation/swift/mainactor)
- [Swift Concurrency: Avoiding Data Races](https://developer.apple.com/documentation/swift/avoiding-data-races)

