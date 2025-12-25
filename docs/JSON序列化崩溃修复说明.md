# JSON 序列化崩溃修复说明

## 问题描述

应用在添加文字水印时崩溃,错误信息:
```
*** Terminating app due to uncaught exception 'NSInvalidArgumentException', 
reason: 'Invalid type in JSON write (__SwiftValue)'
```

## 根本原因

在 `VideoWatermark.swift` 的调试日志代码中,尝试将 Swift 元组类型直接序列化为 JSON:

```swift
let logData: [String: Any] = [
    "randomIntervalRange": randomIntervalRange as Any,  // ❌ 元组无法序列化
    "driftSpeedRange": driftSpeedRange as Any,          // ❌ 元组无法序列化
]
```

Swift 元组在转换为 `Any` 后会变成 `__SwiftValue`,这是一个内部类型,`JSONSerialization` 无法处理它。

## 解决方案

将元组转换为字典格式:

```swift
let logData: [String: Any] = [
    "randomIntervalRange": randomIntervalRange.map { ["min": $0.min, "max": $0.max] } as Any? ?? NSNull(),
    "driftSpeedRange": driftSpeedRange.map { ["min": $0.min, "max": $0.max] } as Any? ?? NSNull(),
]
```

### 修复要点

1. **使用 `.map` 转换元组为字典**: `randomIntervalRange.map { ["min": $0.min, "max": $0.max] }`
2. **处理可选值**: 使用 `as Any? ?? NSNull()` 确保 nil 值也能正确序列化
3. **保持类型安全**: 字典格式可以安全地序列化为 JSON

## 修改文件

- `fastv/Services/VideoWatermark.swift` (第 447-453 行)

## 测试建议

1. 启用随机移动功能
2. 设置随机间隔范围和漂移速度范围
3. 添加文字水印
4. 验证应用不再崩溃,且日志文件正常生成

## 相关知识

### JSON 可序列化的类型

`JSONSerialization` 只支持以下类型:
- `String`
- `Number` (Int, Double, Float, Bool)
- `Array`
- `Dictionary`
- `NSNull`

### 不可序列化的类型

- Swift 元组 `(min: Double, max: Double)`
- 自定义结构体/类(除非实现 `Codable`)
- 枚举(除非转换为原始值)
- 闭包/函数

### 最佳实践

在构建 JSON 数据时:
1. 将元组转换为字典或数组
2. 将枚举转换为原始值(rawValue)
3. 使用 `NSNull()` 表示空值
4. 对于可选值,使用 `?? NSNull()` 或先解包再使用

