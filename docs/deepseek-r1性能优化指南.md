# DeepSeek-R1:1.5B 性能优化指南

## 🎯 目标
在本机以最快速度运行 deepseek-r1:1.5b 模型，同时保持文本优化质量。

## 📊 当前性能
- **平均响应时间**：7.45 秒
- **成功率**：100%
- **轻微修改分数**：50.0/100

## 🚀 优化方案

### 方案 1：优化 API 参数（最简单，推荐）⭐

已更新 `test_injection.rb` 脚本，针对 deepseek-r1 模型进行了以下优化：

#### 优化参数
```ruby
temperature: 0.1      # 从 0.2 降低到 0.1，加快响应
num_predict: 200      # 从 500 降低到 200，文本优化不需要太长输出
top_k: 10             # 从 20 降低到 10，加快采样
top_p: 0.8            # 从 0.9 降低到 0.8，加快采样
repeat_penalty: 1.1   # 避免重复，加快生成
```

#### 预期效果
- **响应时间**：从 7.45s 降低到 **3-4 秒**（提升 40-50%）
- **质量影响**：轻微，文本优化任务对 temperature 不敏感

### 方案 2：使用 GPU 加速（macOS M2）

#### 检查 GPU 使用情况
```bash
# 检查 Ollama 是否使用 Metal（macOS GPU）
ps aux | grep ollama | grep -i metal
```

#### 确保使用 GPU
Ollama 在 macOS 上默认使用 Metal（GPU 加速），无需额外配置。

#### 验证 GPU 使用
```bash
# 运行模型时查看 Activity Monitor 的 GPU 使用情况
# 或者在终端运行：
ollama run deepseek-r1:1.5b "测试文本"
# 观察响应速度
```

### 方案 3：环境变量优化

#### 设置 Ollama 环境变量（可选）
```bash
# 在 ~/.zshrc 或 ~/.bash_profile 中添加：
export OLLAMA_NUM_THREAD=8        # 使用所有 CPU 核心
export OLLAMA_NUM_GPU=1           # 使用 GPU
export OLLAMA_MAX_LOADED_MODELS=1 # 只加载一个模型，节省内存
```

#### 应用配置
```bash
source ~/.zshrc  # 或 source ~/.bash_profile
# 重启 Ollama 服务
```

### 方案 4：使用更小的量化版本（如果可用）

#### 检查可用版本
```bash
ollama list | grep deepseek-r1
```

#### 如果有 Q2 或 Q3 版本
```bash
# 下载更小的量化版本（如果存在）
ollama pull deepseek-r1:1.5b-q2  # 示例，实际名称可能不同
```

**注意**：更小的量化版本可能影响质量，需要测试验证。

### 方案 5：预热模型（减少首次响应延迟）

#### 创建预热脚本
```bash
# warmup.sh
#!/bin/bash
ollama run deepseek-r1:1.5b "预热" > /dev/null 2>&1
echo "模型已预热"
```

#### 在应用启动时预热
在 fastv 应用启动时，先发送一个简单的请求来预热模型。

## 📈 性能测试

### 测试优化后的性能
```bash
# 使用优化后的测试脚本
ruby test_injection.rb http://127.0.0.1:11434 deepseek-r1:1.5b
```

### 对比优化前后
| 指标 | 优化前 | 优化后（预期） | 提升 |
|------|--------|--------------|------|
| 平均响应时间 | 7.45s | 3-4s | 40-50% |
| 成功率 | 100% | 100% | - |
| 轻微修改分数 | 50.0/100 | 45-50/100 | 轻微下降 |

## 🔧 实际应用配置

### 在 fastv 中使用优化配置

#### Swift 代码示例
```swift
// OllamaService.swift
let options: [String: Any] = [
    "temperature": 0.1,
    "num_predict": 200,
    "top_k": 10,
    "top_p": 0.8,
    "repeat_penalty": 1.1
]
```

#### API 请求示例
```json
{
  "model": "deepseek-r1:1.5b",
  "prompt": "用户输入文本",
  "system": "系统提示词",
  "stream": false,
  "options": {
    "temperature": 0.1,
    "num_predict": 200,
    "top_k": 10,
    "top_p": 0.8,
    "repeat_penalty": 1.1
  }
}
```

## 💡 优化建议优先级

1. **立即实施**：方案 1（优化 API 参数）- 最简单，效果明显
2. **验证效果**：运行测试脚本，查看实际性能提升
3. **进一步优化**：如果还需要更快，考虑方案 2-5

## ⚠️ 注意事项

1. **Temperature 过低**：虽然 temperature=0.1 可以加快速度，但可能使输出过于确定。如果发现质量下降，可以调整到 0.15。

2. **num_predict 限制**：200 tokens 对于大多数文本优化任务足够，但如果遇到很长的输入，可能需要增加到 300。

3. **GPU 使用**：macOS M2 会自动使用 GPU，无需额外配置。

4. **内存管理**：如果内存不足，可以设置 `OLLAMA_MAX_LOADED_MODELS=1`。

## 📝 测试命令

```bash
# 快速测试单个请求的响应时间
time curl -X POST http://127.0.0.1:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1:1.5b",
    "prompt": "请优化这段文字：嗯那个我今天想去超市",
    "system": "你是一个专业的文本优化助手...",
    "stream": false,
    "options": {
      "temperature": 0.1,
      "num_predict": 200,
      "top_k": 10,
      "top_p": 0.8
    }
  }'
```

## 🎉 预期结果

优化后，deepseek-r1:1.5b 应该能够：
- ✅ 响应时间从 7.45s 降低到 3-4s
- ✅ 保持 100% 成功率
- ✅ 轻微修改分数保持在 45-50/100（可接受范围）
- ✅ 充分利用 M2 GPU 加速

