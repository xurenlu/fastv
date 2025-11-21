# DeepSeek-R1:1.5B C++ 版本优化指南

## 为什么 C++ 版本更快？

1. **直接推理**：llama.cpp 是纯 C++ 实现，没有 Python 解释器开销
2. **更好的内存管理**：C++ 的内存管理更高效
3. **优化的计算**：针对 CPU/GPU 进行了深度优化
4. **无 thinking 模式延迟**：可以更精确控制推理过程

## 安装 llama.cpp

### macOS 安装

```bash
# 使用 Homebrew 安装
brew install llama.cpp

# 或者从源码编译（性能更好）
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
make -j$(sysctl -n hw.ncpu)
```

### 下载 DeepSeek-R1:1.5B GGUF 模型

```bash
# 创建模型目录
mkdir -p ~/models/deepseek-r1

# 下载模型（推荐 Q4_K_M 量化版本，平衡速度和质量）
cd ~/models/deepseek-r1

# 使用代理下载（如果需要）
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890

# 下载模型（从 HuggingFace）
# 注意：需要找到 deepseek-r1:1.5b 的 GGUF 格式下载链接
# 通常可以在 HuggingFace 的模型页面找到
```

## 使用 llama.cpp 运行

### 基本用法

```bash
# 基本推理
llama-cli -m ~/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf \
  -p "请优化这段文本：嗯那个我今天想去超市买点东西" \
  --system-prompt "你是一个专业的文本优化助手..." \
  -n 200 \
  --temp 0.2 \
  --top-k 20
```

### 性能优化参数

```bash
# 快速推理配置
llama-cli \
  -m ~/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf \
  -p "用户输入文本" \
  --system-prompt "系统提示词" \
  -n 200 \              # 最大输出 token 数
  --temp 0.2 \          # 降低温度加快速度
  --top-k 20 \          # 限制候选词数量
  --top-p 0.9 \         # nucleus sampling
  --threads 8 \         # CPU 线程数（根据你的 CPU 核心数调整）
  --batch-size 512 \    # 批处理大小
  --ctx-size 2048       # 上下文大小
```

## 创建 HTTP API 服务

llama.cpp 本身不提供 HTTP API，但可以使用 `llama-server` 或第三方工具：

### 方法 1：使用 llama-server（如果可用）

```bash
llama-server \
  -m ~/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  --threads 8 \
  --temp 0.2 \
  --top-k 20
```

### 方法 2：使用 text-generation-webui

```bash
# 安装 text-generation-webui
git clone https://github.com/oobabooga/text-generation-webui.git
cd text-generation-webui

# 安装依赖
pip install -r requirements.txt

# 运行（支持 llama.cpp）
python server.py \
  --model-dir ~/models/deepseek-r1 \
  --model deepseek-r1-1.5b.Q4_K_M.gguf \
  --loader llama.cpp \
  --api
```

### 方法 3：使用简单的 Python HTTP 包装器

创建一个简单的 Python 脚本来包装 llama.cpp：

```python
#!/usr/bin/env python3
# llama_cpp_api.py

import subprocess
import json
import sys
from flask import Flask, request, jsonify

app = Flask(__name__)
MODEL_PATH = "~/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf"

def llama_inference(prompt, system_prompt=None, max_tokens=200):
    """调用 llama.cpp 进行推理"""
    cmd = [
        "llama-cli",
        "-m", MODEL_PATH,
        "-p", prompt,
        "-n", str(max_tokens),
        "--temp", "0.2",
        "--top-k", "20",
        "--threads", "8"
    ]
    
    if system_prompt:
        cmd.extend(["--system-prompt", system_prompt])
    
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=10
    )
    
    return result.stdout.strip()

@app.route('/api/generate', methods=['POST'])
def generate():
    data = request.json
    prompt = data.get('prompt', '')
    system = data.get('system', '')
    
    try:
        response = llama_inference(prompt, system)
        return jsonify({
            "response": response,
            "done": True
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=11435)
```

运行：
```bash
python llama_cpp_api.py
```

## 性能对比

### 预期性能提升

| 方法 | 平均响应时间 | 说明 |
|------|------------|------|
| Ollama (优化后) | ~3.25s | 当前配置 |
| llama.cpp (Q4_K_M) | ~1.5-2.5s | 预期提升 30-50% |
| llama.cpp (Q8_0) | ~2.0-3.0s | 质量更好但稍慢 |
| llama.cpp (Q2_K) | ~1.0-1.5s | 最快但质量略降 |

### 优化建议

1. **使用量化模型**：
   - Q2_K：最快，质量可接受
   - Q4_K_M：推荐，平衡速度和质量
   - Q8_0：质量最好，但速度较慢

2. **调整线程数**：
   ```bash
   # 查看 CPU 核心数
   sysctl -n hw.ncpu
   
   # 设置为 CPU 核心数
   --threads $(sysctl -n hw.ncpu)
   ```

3. **使用 GPU 加速**（如果有）：
   ```bash
   # 编译支持 Metal 的版本（macOS）
   make LLAMA_METAL=1
   
   # 运行时自动使用 GPU
   ```

## 集成到 fastv

如果使用 llama.cpp，需要修改 `OllamaService.swift` 来支持新的 API 端点：

```swift
// 如果使用自定义的 HTTP API 包装器
let endpoint = "http://127.0.0.1:11435"  // llama.cpp API
```

## 注意事项

1. **模型格式**：确保下载的是 GGUF 格式，不是 PyTorch 格式
2. **量化级别**：Q4_K_M 是推荐的平衡点
3. **内存需求**：1.5B 模型大约需要 1-2GB RAM
4. **首次运行**：第一次运行会加载模型，可能较慢

## 参考资源

- llama.cpp GitHub: https://github.com/ggerganov/llama.cpp
- GGUF 模型下载: https://huggingface.co/models?search=deepseek-r1+gguf
- DeepSeek 官方文档: https://github.com/deepseek-ai/DeepSeek-R1

## 快速测试

```bash
# 测试 llama.cpp 性能
time llama-cli \
  -m ~/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf \
  -p "请优化：嗯那个我今天想去超市" \
  --temp 0.2 \
  --top-k 20 \
  -n 100
```

对比 Ollama：
```bash
time ollama run deepseek-r1:1.5b "请优化：嗯那个我今天想去超市"
```

