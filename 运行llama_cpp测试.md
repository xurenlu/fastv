# 运行 llama.cpp 性能测试指南

## 当前状态

✅ **llama.cpp 已安装** - `/opt/homebrew/bin/llama-cli`  
⚠️ **模型文件缺失** - 需要下载 GGUF 格式模型  
⚠️ **Flask 未安装** - HTTP API 需要 Flask

## 方案 1：直接测试 llama-cli（推荐）

### 步骤 1：下载一个测试模型

由于 deepseek-r1:1.5b 的 GGUF 模型不容易找到，我们可以先测试其他小模型：

```bash
# 方法 1：使用 huggingface-cli（如果已安装）
pip3 install --user huggingface_hub[cli]
huggingface-cli download TheBloke/gemma-2b-it-GGUF gemma-2b-it-q4_k_m.gguf --local-dir ~/models/

# 方法 2：手动下载
# 访问 https://huggingface.co/TheBloke/gemma-2b-it-GGUF
# 下载 gemma-2b-it-q4_k_m.gguf 文件
# 保存到 ~/models/gemma-2b-it-q4_k_m.gguf
```

### 步骤 2：直接测试性能

```bash
# 使用测试脚本
ruby test_llama_direct.rb ~/models/gemma-2b-it-q4_k_m.gguf

# 或者手动测试
time llama-cli \
  -m ~/models/gemma-2b-it-q4_k_m.gguf \
  -p "请优化这段文本：嗯那个我今天想去超市买点东西" \
  --temp 0.2 \
  --top-k 20 \
  -n 200 \
  --threads 8
```

## 方案 2：使用 HTTP API（需要 Flask）

### 步骤 1：安装 Flask

```bash
# 创建虚拟环境
python3 -m venv venv_llama
source venv_llama/bin/activate

# 安装 Flask
pip install flask flask-cors

# 退出虚拟环境
deactivate
```

### 步骤 2：修改模型路径

编辑 `llama_cpp_api.py`，修改 `MODEL_PATH` 为你的模型路径：

```python
MODEL_PATH = os.path.expanduser("~/models/gemma-2b-it-q4_k_m.gguf")
```

### 步骤 3：启动 API 服务

```bash
bash start_llama_api.sh
```

### 步骤 4：测试 API

```bash
# 在另一个终端测试
curl -X POST http://127.0.0.1:11435/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "请优化：嗯那个我今天想去超市",
    "system": "你是一个专业的文本优化助手",
    "options": {
      "temperature": 0.2,
      "top_k": 20
    }
  }'
```

## 方案 3：性能对比测试

### 对比 Ollama 和 llama.cpp

```bash
# 测试 Ollama
ruby test_injection.rb http://127.0.0.1:11434 gemma3:1b

# 测试 llama.cpp（如果有模型）
ruby test_llama_direct.rb ~/models/gemma-2b-it-q4_k_m.gguf

# 对比测试
ruby test_llama_cpp_performance.rb \
  http://127.0.0.1:11434 \
  gemma3:1b \
  ~/models/gemma-2b-it-q4_k_m.gguf
```

## 快速测试（无需模型）

如果你想先测试 llama-cli 是否正常工作：

```bash
# 测试 llama-cli 命令
llama-cli --help

# 查看可用选项
llama-cli --version
```

## 推荐的小模型（GGUF 格式）

1. **gemma-2b-it-GGUF** - 2B 参数，速度快
   - 下载：https://huggingface.co/TheBloke/gemma-2b-it-GGUF
   - 推荐：`gemma-2b-it-q4_k_m.gguf`

2. **qwen2-1.5b-instruct-GGUF** - 1.5B 参数，中文支持好
   - 下载：https://huggingface.co/TheBloke/Qwen2-1.5B-Instruct-GGUF
   - 推荐：`qwen2-1.5b-instruct-q4_k_m.gguf`

3. **llama-3.2-1b-instruct-GGUF** - 1B 参数，非常快
   - 下载：https://huggingface.co/TheBloke/Llama-3.2-1B-Instruct-GGUF
   - 推荐：`llama-3.2-1b-instruct-q4_k_m.gguf`

## 下载模型示例

```bash
# 使用 curl 下载（需要找到直接下载链接）
cd ~/models/
curl -L -o gemma-2b-it-q4_k_m.gguf \
  "https://huggingface.co/TheBloke/gemma-2b-it-GGUF/resolve/main/gemma-2b-it-q4_k_m.gguf"
```

## 注意事项

1. **模型文件较大** - Q4_K_M 量化版本通常 1-2GB
2. **首次运行慢** - 第一次加载模型需要时间
3. **内存需求** - 确保有足够内存（至少 4GB 可用）

## 如果遇到问题

1. **模型文件不存在** - 先下载模型
2. **Flask 安装失败** - 使用方案 1（直接测试）
3. **llama-cli 命令不存在** - 检查安装：`brew list llama.cpp`

## 当前推荐

由于没有现成的 deepseek-r1:1.5b GGUF 模型，**建议继续使用优化后的 Ollama 方案**：

- ✅ 已配置好
- ✅ 速度已优化（3.25秒）
- ✅ 质量最好（61.3分）
- ✅ 开箱即用

如果需要测试 llama.cpp，可以先下载一个小模型（如 gemma-2b）进行测试。

