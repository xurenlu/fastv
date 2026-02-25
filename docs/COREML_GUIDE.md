# 使用 CoreML 运行模型（推荐方案）

## 优势

✅ **无需外部依赖** - CoreML 是 Apple 原生框架，已内置在 macOS/iOS 中  
✅ **更好的性能** - 可以利用 Neural Engine、GPU 加速  
✅ **更简单的集成** - 不需要添加 Swift Package 或 CocoaPods  
✅ **更好的兼容性** - 专为 Apple 平台优化  

## 转换步骤

### 1. 安装转换工具

```bash
# 设置代理（端口 7856）
export https_proxy=http://127.0.0.1:7856
export http_proxy=http://127.0.0.1:7856

# 安装 coremltools
pip3 install coremltools onnx
```

### 2. 转换模型

在项目根目录执行：

```bash
cd /Users/rocky/Sites/fastv
python3 convert_to_coreml.py
```

**注意**：转换可能需要几分钟时间，模型较大（894MB）。

### 3. 如果转换失败

SenseVoice 模型可能包含一些 CoreML 不完全支持的操作。如果转换失败：

**选项 A：使用 ONNX Runtime（备选方案）**
- 参考 `INSTALL_GUIDE.md` 使用 Swift Package Manager 添加 ONNX Runtime

**选项 B：尝试修复转换**
- 检查错误信息
- 可能需要固定输入形状
- 可能需要移除某些不支持的操作

### 4. 添加 CoreML 模型到项目

转换成功后：

1. 在 Xcode 中打开项目
2. 找到 `fastv/Resources/Models/sensevoice-small/model.mlmodel`
3. 如果文件未显示在项目中：
   - 右键点击 `fastv/Resources/Models/sensevoice-small` 文件夹
   - 选择 "Add Files to fastv..."
   - 选择 `model.mlmodel`
   - 确保勾选 "Copy items if needed" 和 "Create groups"
   - 确保 "Add to targets" 中勾选了 "fastv"

### 5. 更新代码

代码已经自动支持 CoreML！`SpeechTranscriber.swift` 会优先尝试使用 CoreML，如果找不到 CoreML 模型才会回退到 ONNX Runtime。

### 6. 构建和测试

1. 清理构建：Product → Clean Build Folder (⇧⌘K)
2. 构建项目：Product → Build (⌘B)
3. 运行应用：Product → Run (⌘R)

## 验证

如果一切正常：
- ✅ 项目能够成功编译
- ✅ 应用能够加载 CoreML 模型
- ✅ 语音转文字功能可以正常工作
- ✅ 在 Activity Monitor 中可以看到 Neural Engine 使用（如果设备支持）

## 性能优化

CoreML 会自动选择最佳的计算单元：
- **Neural Engine**（如果可用）- 最佳性能，最低功耗
- **GPU** - 高性能
- **CPU** - 兼容性最好

你可以在 `CoreMLWrapper.swift` 中调整 `computeUnits` 设置：
- `.all` - 使用所有可用单元（推荐）
- `.cpuAndGPU` - 仅使用 CPU 和 GPU
- `.cpuOnly` - 仅使用 CPU

## 故障排除

### 问题：转换失败，提示不支持的操作

**解决方案：**
1. 查看详细错误信息
2. 某些 ONNX 操作可能无法直接转换
3. 考虑使用 ONNX Runtime（支持更完整的 ONNX 操作集）

### 问题：模型加载失败

**解决方案：**
1. 检查 `model.mlmodel` 是否已添加到项目资源中
2. 确认文件的 Target Membership 设置正确
3. 检查模型文件是否损坏

### 问题：推理结果不正确

**解决方案：**
1. 检查输入输出名称是否正确
2. 验证输入数据格式（形状、数据类型）
3. 对比 ONNX Runtime 的结果（如果可用）

## 总结

**推荐流程：**
1. ✅ 尝试转换为 CoreML（最简单，无需外部依赖）
2. ⚠️ 如果转换失败，使用 ONNX Runtime（功能更完整）

两种方案代码都已实现，会自动选择可用的方案！

