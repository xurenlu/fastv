# 不使用 Ollama 运行 DeepSeek-R1:1.5B 指南

## 🎯 方案对比

| 方案 | 优点 | 缺点 | 速度 |
|------|------|------|------|
| **Ollama** | ✅ 简单易用<br>✅ 自动管理模型<br>✅ 已有模型 | ⚠️ 环境变量优化困难<br>⚠️ GUI 应用限制 | ~7-8s |
| **llama.cpp** | ✅ 更快的速度（预期 1.5-3s）<br>✅ 完全控制参数<br>✅ 可使用所有 CPU 核心<br>✅ 无 thinking 模式延迟 | ⚠️ 需要下载 GGUF 模型<br>⚠️ 需要手动配置 | ~1.5-3s |

## 🚀 快速开始（llama.cpp 方案）

### 步骤 1：检查依赖

```bash
# 检查 llama-cli（已安装 ✅）
which llama-cli

# 检查 Python 和 Flask
python3 --version
python3 -c "import flask" || echo "需要安装 Flask"
```

### 步骤 2：安装 Flask（如果未安装）

```bash
# 设置代理（如果需要）
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
all_proxy=socks5://127.0.0.1:7890

# 安装 Flask
pip3 install --user flask flask-cors
```

### 步骤 3：下载 GGUF 格式模型

**方法 A：从 HuggingFace 下载（推荐）**

```bash
# 创建模型目录
mkdir -p ~/models/deepseek-r1
cd ~/models/deepseek-r1

# 设置代理（如果需要）
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
all_proxy=socks5://127.0.0.1:7890

# 安装 huggingface-cli（如果还没有）
pip3 install --user huggingface_hub[cli]

# 下载模型（需要找到正确的仓库名）
# 可能的仓库：
# - deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B
# - TheBloke/deepseek-r1-1.5B-instruct-GGUF
huggingface-cli download deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B \
  --local-dir ~/models/deepseek-r1 \
  --include "*.gguf"
```

**方法 B：手动下载**

1. 访问 https://huggingface.co/models?search=deepseek-r1+gguf
2. 找到 deepseek-r1-1.5b 的 GGUF 格式模型
3. 下载 Q4_K_M 量化版本（推荐，平衡速度和质量）
4. 将文件保存到 `~/models/deepseek-r1/`

**方法 C：从 Ollama 提取（如果已有模型）**

```bash
# Ollama 模型存储在：
# ~/.ollama/models/blobs/

# 但 Ollama 使用的是自己的格式，不是 GGUF
# 所以这个方法不可行，需要重新下载 GGUF 格式
```

### 步骤 4：启动 HTTP API 服务

```bash
# 进入项目目录
cd /Users/rocky/Sites/fastv

# 启动服务（会自动检查依赖和模型）
bash start_llama_api.sh
```

服务会在 `http://127.0.0.1:11435` 启动

### 步骤 5：测试服务

```bash
# 测试健康检查
curl http://127.0.0.1:11435/health

# 测试 API（使用测试脚本）
ruby test_injection.rb http://127.0.0.1:11435 deepseek-r1:1.5b
```

## 📊 性能优化配置

### llama.cpp 参数优化

编辑 `llama_cpp_api.py`，修改默认参数：

```python
DEFAULT_TEMP = 0.1          # 降低温度加快速度
DEFAULT_TOP_K = 10          # 减少候选词数量
DEFAULT_MAX_TOKENS = 250    # 限制输出长度
DEFAULT_THREADS = 8         # 使用所有 CPU 核心
```

### 启动时指定线程数

修改 `llama_cpp_api.py` 中的 `llama_inference` 函数：

```python
# 添加 Metal GPU 支持（macOS）
cmd.extend(["--gpu-layers", "1"])  # 使用 GPU 加速
```

## 🔧 完整设置脚本

创建一个一键设置脚本：

```bash
#!/bin/bash
# setup_llama_cpp.sh

set -e

echo "=========================================="
echo "设置 llama.cpp 运行环境"
echo "=========================================="

# 1. 检查 llama-cli
if ! command -v llama-cli &> /dev/null; then
    echo "❌ 未找到 llama-cli"
    echo "安装: brew install llama.cpp"
    exit 1
fi
echo "✅ llama-cli 已安装"

# 2. 安装 Flask
if ! python3 -c "import flask" 2>/dev/null; then
    echo "安装 Flask..."
    export https_proxy=http://127.0.0.1:7890
    export http_proxy=http://127.0.0.1:7890
    all_proxy=socks5://127.0.0.1:7890
    pip3 install --user flask flask-cors
fi
echo "✅ Flask 已安装"

# 3. 检查模型
MODEL_PATH="$HOME/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf"
if [ ! -f "$MODEL_PATH" ]; then
    echo "⚠️  模型文件不存在: $MODEL_PATH"
    echo ""
    echo "请下载模型："
    echo "  bash download_deepseek_model.sh"
    echo ""
    echo "或手动下载 GGUF 格式模型到: $HOME/models/deepseek-r1/"
    exit 1
fi
echo "✅ 模型文件存在"

# 4. 启动服务
echo ""
echo "启动服务..."
bash start_llama_api.sh
```

## 🎯 在 fastv 中使用

### 修改 API 端点

在 fastv 应用中，将 API 端点改为：
```
http://127.0.0.1:11435
```

### 模型名称

模型名称可以任意填写（API 会自动使用配置的模型），例如：
```
deepseek-r1-1.5b
```

## ⚠️ 注意事项

1. **模型格式**：必须使用 GGUF 格式，不是 PyTorch 格式
2. **量化级别**：Q4_K_M 是推荐的平衡点（速度和质量）
3. **首次运行**：第一次运行会加载模型，可能较慢
4. **内存需求**：1.5B 模型大约需要 1-2GB RAM
5. **GPU 加速**：macOS M2 会自动使用 Metal GPU（如果编译时启用了 Metal 支持）

## 📈 预期性能提升

| 指标 | Ollama | llama.cpp | 提升 |
|------|--------|-----------|------|
| 平均响应时间 | 7-8s | 1.5-3s | **60-80%** |
| CPU 利用率 | 部分核心 | 所有核心 | ✅ |
| 内存占用 | 较高 | 较低 | ✅ |
| 配置灵活性 | 中等 | 高 | ✅ |

## 🔍 故障排查

### 问题 1：找不到模型文件

```bash
# 检查模型路径
ls -lh ~/models/deepseek-r1/

# 修改 llama_cpp_api.py 中的 MODEL_PATH
```

### 问题 2：llama-cli 命令不存在

```bash
# 安装 llama.cpp
brew install llama.cpp

# 或从源码编译（性能更好）
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
make -j$(sysctl -n hw.ncpu) LLAMA_METAL=1
```

### 问题 3：Flask 导入错误

```bash
# 重新安装 Flask
pip3 install --user --upgrade flask flask-cors
```

### 问题 4：端口被占用

```bash
# 检查端口
lsof -i :11435

# 修改 llama_cpp_api.py 中的端口号
```

## 💡 推荐方案

**如果你想要最快的速度**：
- ✅ 使用 llama.cpp 方案
- ✅ 下载 Q4_K_M 或 Q2_K 量化版本
- ✅ 使用所有 CPU 核心
- ✅ 启用 Metal GPU 加速

**如果你想要简单易用**：
- ✅ 继续使用 Ollama
- ✅ 使用 API 参数优化（已在测试脚本中配置）

## 🎉 总结

**是的，完全可以使用 llama.cpp 替代 Ollama！**

优势：
- ✅ 更快的速度（预期提升 60-80%）
- ✅ 完全控制参数
- ✅ 可以使用所有 CPU 核心
- ✅ 无 GUI 应用限制

需要做的：
1. 下载 GGUF 格式模型
2. 安装 Flask
3. 启动 HTTP API 服务

