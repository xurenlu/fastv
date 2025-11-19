# ONNX Runtime 集成替代方案

## ⚠️ 问题说明

`https://github.com/microsoft/onnxruntime-swift` 仓库已不存在，需要寻找替代方案。

## 可选方案

### 方案 1：使用 ONNX Runtime C API（推荐）

这是最稳定的方案，直接使用 ONNX Runtime 的 C API，通过 Swift 桥接头文件调用。

#### 步骤 1：下载 ONNX Runtime 库

1. 访问 [ONNX Runtime 发布页面](https://github.com/microsoft/onnxruntime/releases)
2. 下载 macOS 版本（例如：`onnxruntime-osx-x64-1.x.x.tgz`）
3. 解压到项目目录：`fastv/Libraries/onnxruntime/`

#### 步骤 2：配置桥接头文件

1. 更新 `fastv/Services/ONNXRuntimeBridge.h`：
```c
#import "onnxruntime/onnxruntime_c_api.h"
```

2. 在 Xcode 项目设置中：
   - 选择 Target "fastv"
   - Build Settings → Swift Compiler - General
   - Objective-C Bridging Header: `fastv/Services/ONNXRuntimeBridge.h`
   - Header Search Paths: `$(SRCROOT)/Libraries/onnxruntime/include`
   - Library Search Paths: `$(SRCROOT)/Libraries/onnxruntime/lib`
   - Other Linker Flags: `-lonnxruntime`

#### 步骤 3：实现 C API 包装

需要创建一个 Swift 包装类来调用 C API。

### 方案 2：使用 CocoaPods（如果支持 macOS）

**注意**：`onnxruntime-mobile-objc` 可能不支持 macOS，需要验证。

1. 检查 Podfile 中的依赖是否支持 macOS
2. 运行 `pod install`
3. 如果失败，说明不支持 macOS，需要使用方案 1

### 方案 3：使用 CoreML（如果模型可以转换）

如果可以将 ONNX 模型转换为 CoreML，可以直接使用 Apple 的 CoreML 框架。

**优点**：
- 原生支持，无需第三方库
- 性能优化好
- 集成简单

**缺点**：
- 需要转换模型（之前尝试过，遇到依赖冲突）

### 方案 4：使用 Python 脚本（临时方案）

如果 Swift 集成困难，可以：
1. 使用 Python 脚本调用 ONNX Runtime
2. 通过进程调用 Python 脚本
3. 传递音频文件路径，获取转录结果

**优点**：
- Python 的 ONNX Runtime 支持完善
- 实现简单

**缺点**：
- 需要 Python 环境
- 性能可能不如原生实现

## 推荐方案

**建议使用方案 1（C API）**，因为：
- 最稳定可靠
- 性能好
- 不依赖第三方 Swift Package
- 官方支持

## 下一步

请告诉我你想使用哪个方案，我可以帮你实现具体的集成代码。

