# 模型转换状态

## 转换尝试结果

尝试将 ONNX 模型转换为 CoreML 格式时遇到以下问题：

1. **版本兼容性问题**：
   - coremltools 7.2 需要 protobuf <= 4.0.0
   - onnx 1.19.1 需要 protobuf >= 4.25.1
   - Python 3.14 移除了 distutils（coremltools 7.2 需要）

2. **SenseVoice 模型复杂性**：
   - 模型包含复杂的注意力机制（SANM）
   - 可能包含动态形状
   - 某些操作可能不被 CoreML 完全支持

## 推荐方案

### 方案 1：使用 ONNX Runtime（推荐）

**优势**：
- ✅ 完全支持 ONNX 标准
- ✅ 无需转换，直接使用原模型
- ✅ 更好的兼容性
- ✅ 支持更复杂的模型结构

**步骤**：
1. 在 Xcode 中添加 Swift Package：`https://github.com/microsoft/onnxruntime-swift`
2. 更新 `ONNXRuntimeWrapper.swift` 启用实际实现
3. 构建并运行

**详细说明**：参考 `INSTALL_GUIDE.md`

### 方案 2：尝试 CoreML 转换（如果必须）

如果坚持使用 CoreML，可以尝试：

1. **使用 Python 3.11 或 3.12**（而不是 3.14）
2. **安装兼容版本**：
   ```bash
   source venv/bin/activate
   pip install "coremltools>=8.0" "onnx>=1.15.0" "protobuf>=4.25.1"
   ```
3. **手动转换**：可能需要固定输入形状或简化模型

## 当前状态

- ✅ 模型文件已复制到项目资源目录
- ✅ CoreML 包装类已实现（`CoreMLWrapper.swift`）
- ✅ ONNX Runtime 包装类已实现（`ONNXRuntimeWrapper.swift`）
- ✅ 代码自动支持两种方案（优先 CoreML，回退 ONNX Runtime）
- ⚠️ CoreML 转换因版本兼容性问题暂时失败

## 建议

**最佳实践**：直接使用 ONNX Runtime
- 无需转换，节省时间
- 更好的模型兼容性
- 代码已经实现，只需添加依赖

**如果未来需要 CoreML**：
- 等待 coremltools 更新支持 Python 3.14
- 或使用 Python 3.11/3.12 环境
- 或考虑使用 Apple 的官方转换工具

## 下一步操作

1. **立即使用**：按照 `INSTALL_GUIDE.md` 添加 ONNX Runtime 依赖
2. **未来优化**：如果 CoreML 转换成功，可以替换为 CoreML 以获得更好的性能

