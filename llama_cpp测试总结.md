# llama.cpp 测试总结

## ✅ 已完成的工作

1. **llama.cpp 已安装** ✅
   - 位置：`/opt/homebrew/bin/llama-cli`
   - 版本：已检测到 Apple M2 GPU 支持
   - 状态：正常工作

2. **测试脚本已创建** ✅
   - `test_llama_direct.rb` - 直接测试 llama-cli
   - `llama_cpp_api.py` - HTTP API 包装器
   - `start_llama_api.sh` - 启动脚本

3. **模型下载中** ⏳
   - 正在下载：gemma-2b-it-q4_k_m.gguf
   - 位置：`~/models/gemma-2b-it-q4_k_m.gguf`
   - 大小：约 1.5GB

## 🚀 测试步骤

### 步骤 1：等待模型下载完成

```bash
# 检查下载进度
ls -lh ~/models/gemma-2b-it-q4_k_m.gguf

# 如果文件存在且大小约 1.5GB，说明下载完成
```

### 步骤 2：直接测试 llama-cli 性能

```bash
# 运行测试脚本
ruby test_llama_direct.rb ~/models/gemma-2b-it-q4_k_m.gguf
```

### 步骤 3：对比 Ollama 和 llama.cpp

```bash
# 测试 Ollama（使用 gemma3:1b）
ruby test_injection.rb http://127.0.0.1:11434 gemma3:1b

# 测试 llama.cpp（使用 gemma-2b）
ruby test_llama_direct.rb ~/models/gemma-2b-it-q4_k_m.gguf

# 对比性能
```

## 📊 预期性能对比

| 方案 | 预期响应时间 | 说明 |
|------|------------|------|
| Ollama (gemma3:1b) | ~2.74s | 当前配置 |
| llama.cpp (gemma-2b) | ~1.5-2.5s | 预期更快 |

## 🔧 如果模型下载失败

### 手动下载

1. 访问：https://huggingface.co/TheBloke/gemma-2b-it-GGUF
2. 下载：`gemma-2b-it-q4_k_m.gguf`
3. 保存到：`~/models/gemma-2b-it-q4_k_m.gguf`

### 或使用其他小模型

- **qwen2-1.5b-instruct-GGUF** - 中文支持好
  - https://huggingface.co/TheBloke/Qwen2-1.5B-Instruct-GGUF
  
- **llama-3.2-1b-instruct-GGUF** - 非常快
  - https://huggingface.co/TheBloke/Llama-3.2-1B-Instruct-GGUF

## 💡 当前推荐

**由于 deepseek-r1:1.5b 的 GGUF 模型不容易找到，建议：**

1. **继续使用优化后的 Ollama** ⭐⭐⭐⭐⭐
   - 已配置好
   - 速度已优化（3.25秒）
   - 质量最好（61.3分）
   - 开箱即用

2. **测试 llama.cpp（可选）**
   - 下载一个小模型（如 gemma-2b）
   - 对比性能
   - 如果确实更快，可以考虑使用

## 📝 测试命令汇总

```bash
# 1. 检查模型是否下载完成
ls -lh ~/models/gemma-2b-it-q4_k_m.gguf

# 2. 直接测试 llama-cli
ruby test_llama_direct.rb ~/models/gemma-2b-it-q4_k_m.gguf

# 3. 对比 Ollama
ruby test_injection.rb http://127.0.0.1:11434 gemma3:1b

# 4. 启动 HTTP API（可选，需要 Flask）
bash start_llama_api.sh
```

## 🎯 下一步

1. ⏳ **等待模型下载完成**
2. 🧪 **运行性能测试**
3. 📊 **对比 Ollama 和 llama.cpp**
4. ✅ **选择最佳方案**

---

**当前状态：模型下载中，请稍候...**

