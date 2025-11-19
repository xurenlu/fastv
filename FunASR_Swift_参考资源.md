# FunASR/SenseVoice Swift 集成参考资源

## 📌 现状说明

**重要发现**：目前网上**没有**现成的 Swift + FunASR 开源示例代码。FunASR 主要提供：
- Python API（最完善）
- C++ API（需要桥接）
- ONNX Runtime（跨平台推理引擎）

你的项目已经实现了**最接近**的 Swift 集成方案！

## 🎯 你的项目优势

你的代码已经包含了：
1. ✅ **完整的 ONNX Runtime C API 集成** - `ONNXRuntimeWrapper.swift`
2. ✅ **音频特征提取** - `AudioFeatureExtractor.swift`（Mel 频谱、LFR、CMVN）
3. ✅ **语音转文字流程** - `SpeechTranscriber.swift`
4. ✅ **桥接头文件配置** - `ONNXRuntimeBridge.h`
5. ✅ **模型文件** - SenseVoice Small ONNX 模型

这已经是**非常完整**的实现了！

## 📚 可参考的资源

### 1. ONNX Runtime Swift 官方资源

虽然 `onnxruntime-swift` 仓库不存在，但你可以参考：

- **ONNX Runtime C API 文档**
  - 位置：`Libraries/onnxruntime/onnxruntime-osx-universal2-1.23.2/include/onnxruntime_c_api.h`
  - 这是最权威的 API 参考

- **ONNX Runtime 官方文档**
  - https://onnxruntime.ai/docs/
  - C API 部分：https://onnxruntime.ai/docs/api/c/

### 2. FunASR/SenseVoice Python 实现参考

虽然语言不同，但可以理解算法流程：

- **FunASR 官方仓库**
  - https://github.com/alibaba-damo-academy/FunASR
  - 查看 `funasr/runtime/onnxruntime` 目录下的 Python 实现

- **SenseVoice 项目**
  - 你的项目中已有：`SenseVoice/demo_onnx.py`
  - 这是最直接的参考，展示了如何使用 ONNX Runtime 调用 SenseVoice

### 3. 其他 Swift + ONNX Runtime 项目（虽然不是 FunASR）

虽然找不到 FunASR 的 Swift 示例，但可以参考其他使用 ONNX Runtime 的 Swift 项目：

- **搜索关键词**：`swift onnxruntime github`
- **搜索关键词**：`ios onnx runtime example`

### 4. 你的项目中的参考代码

你的项目中已经有一些参考：

- **Python 实现**：`SenseVoice/demo_onnx.py` - 展示了完整的推理流程
- **Python API**：`SenseVoice/api.py` - 展示了如何调用模型

## 🔍 如果遇到问题

### 问题 1：编译错误

**检查清单**：
1. ✅ 桥接头文件路径是否正确
2. ✅ Header Search Paths 是否配置
3. ✅ Library Search Paths 是否配置
4. ✅ 动态库文件是否存在：`Libraries/onnxruntime/current/lib/libonnxruntime.dylib`

**调试方法**：
```bash
# 检查动态库是否存在
ls -la Libraries/onnxruntime/current/lib/libonnxruntime.dylib

# 检查头文件是否存在
ls -la Libraries/onnxruntime/current/include/onnxruntime_c_api.h
```

### 问题 2：运行时错误

**常见问题**：
- 模型文件路径错误
- 输入张量形状不匹配
- 输出解码错误

**调试建议**：
1. 在 `ONNXRuntimeWrapper.swift` 中添加更多 `#if DEBUG` 日志
2. 对比 Python 版本的输入输出
3. 检查 `tokens.json` 是否正确加载

### 问题 3：性能问题

**优化建议**：
1. 使用 GPU 加速（如果支持）
2. 批量处理音频
3. 缓存 token 映射表（你已经做了）

## 💡 替代方案（如果 C API 集成困难）

### 方案 A：Python 脚本桥接（临时方案）

如果 Swift 集成太困难，可以：
1. 使用 Python 脚本调用 ONNX Runtime
2. Swift 通过进程调用 Python 脚本
3. 传递音频文件路径，获取转录结果

**优点**：Python 的 ONNX Runtime 支持完善，实现简单
**缺点**：需要 Python 环境，性能稍差

### 方案 B：HTTP API 服务

1. 创建一个 Python HTTP 服务（使用 FastAPI）
2. Swift 通过 HTTP 请求调用
3. 你的项目中已有 `SenseVoice/api.py`，可以直接使用

**优点**：解耦，易于调试
**缺点**：需要运行服务进程

## 🎓 学习资源

### ONNX Runtime 相关

1. **ONNX Runtime 官方文档**
   - https://onnxruntime.ai/docs/
   - 重点关注 C API 部分

2. **ONNX Runtime GitHub**
   - https://github.com/microsoft/onnxruntime
   - Issues 和 Discussions 可能有类似问题

### Swift C API 桥接

1. **Apple 官方文档**
   - https://developer.apple.com/documentation/swift/imported-c-and-objective-c-apis
   - 了解如何在 Swift 中使用 C API

2. **Swift 与 C 互操作**
   - 搜索 "Swift C interop" 或 "Swift bridging header"

## 📝 总结

**好消息**：
- ✅ 你的代码已经非常完整了
- ✅ 没有现成的示例，说明你走在了前面
- ✅ 你的实现思路是正确的（使用 ONNX Runtime C API）

**建议**：
1. 继续完善你现有的代码
2. 遇到具体错误时，参考 ONNX Runtime C API 文档
3. 对比 Python 版本的实现，确保逻辑一致
4. 如果实在困难，可以考虑 Python 脚本桥接作为临时方案

## 🚀 下一步

1. **测试当前实现**
   - 尝试编译和运行
   - 记录遇到的错误

2. **逐步调试**
   - 先确保模型能加载
   - 再确保推理能运行
   - 最后确保输出解码正确

3. **参考 Python 实现**
   - 对比 `SenseVoice/demo_onnx.py`
   - 确保输入输出格式一致

## 📞 获取帮助

如果遇到具体问题：
1. 查看 ONNX Runtime C API 文档
2. 查看 FunASR Python 实现
3. 在 ONNX Runtime GitHub Issues 中搜索类似问题
4. 在 FunASR GitHub Issues 中提问

---

**记住**：没有现成的示例不代表你的方向错了，而是说明你在做一件很有价值的事情！💪

