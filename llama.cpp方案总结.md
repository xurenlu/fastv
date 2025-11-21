# 不使用 Ollama 运行模型 - 方案总结

## ✅ 可行性确认

**是的，完全可以使用 llama.cpp 替代 Ollama！**

## 📊 当前状态

### 已具备的条件
- ✅ **llama-cli 已安装**：`/opt/homebrew/bin/llama-cli`
- ✅ **项目已有相关脚本**：
  - `llama_cpp_api.py` - HTTP API 包装器
  - `start_llama_api.sh` - 启动脚本
  - `download_deepseek_model.sh` - 模型下载脚本
- ✅ **虚拟环境已创建**：`venv_llama/`

### 需要完成的事项
- ⚠️ **下载 GGUF 格式模型**：`~/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf`
- ⚠️ **安装 Flask**：在虚拟环境中安装（遇到了一些问题，但可以解决）

## 🚀 快速开始步骤

### 步骤 1：安装 Flask（在虚拟环境中）

```bash
# 激活虚拟环境
source venv_llama/bin/activate

# 升级 pip
pip install --upgrade pip

# 安装 Flask（可能需要多次尝试或使用国内镜像）
pip install flask flask-cors

# 或使用国内镜像
pip install -i https://pypi.tuna.tsinghua.edu.cn/simple flask flask-cors

# 退出虚拟环境
deactivate
```

### 步骤 2：下载 GGUF 格式模型

**方法 A：使用 huggingface-cli（推荐）**

```bash
# 安装 huggingface-cli
pip3 install --user huggingface_hub[cli]

# 设置代理
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
all_proxy=socks5://127.0.0.1:7890

# 创建模型目录
mkdir -p ~/models/deepseek-r1
cd ~/models/deepseek-r1

# 下载模型（需要找到正确的仓库名）
# 可能的仓库：
huggingface-cli download deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B \
  --local-dir . \
  --include "*.gguf"
```

**方法 B：手动下载**

1. 访问 https://huggingface.co/models?search=deepseek-r1+gguf
2. 找到 deepseek-r1-1.5b 的 GGUF 格式模型
3. 下载 Q4_K_M 量化版本
4. 保存到 `~/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf`

**方法 C：使用下载脚本**

```bash
bash download_deepseek_model.sh
```

### 步骤 3：启动服务

```bash
# 启动 HTTP API 服务
bash start_llama_api.sh
```

服务会在 `http://127.0.0.1:11435` 启动

### 步骤 4：测试

```bash
# 测试健康检查
curl http://127.0.0.1:11435/health

# 运行性能测试
ruby test_injection.rb http://127.0.0.1:11435 deepseek-r1-1.5b
```

## 📈 预期性能提升

| 指标 | Ollama | llama.cpp | 提升 |
|------|--------|-----------|------|
| **平均响应时间** | 7-8s | **1.5-3s** | **60-80%** ⚡ |
| CPU 利用率 | 部分核心 | 所有核心 | ✅ |
| 配置灵活性 | 中等 | 高 | ✅ |
| 环境变量控制 | 困难 | 容易 | ✅ |

## 💡 优势

1. **更快的速度**：预期提升 60-80%
2. **完全控制**：可以精确设置所有参数
3. **CPU 优化**：可以使用所有 CPU 核心
4. **无 GUI 限制**：不受 macOS GUI 应用限制

## ⚠️ 注意事项

1. **模型格式**：必须使用 GGUF 格式，不是 PyTorch 格式
2. **模型下载**：需要找到正确的 HuggingFace 仓库
3. **首次运行**：第一次运行会加载模型，可能较慢
4. **Flask 安装**：可能需要使用国内镜像或多次尝试

## 🎯 推荐方案

**如果你想要最快的速度**：
- ✅ 使用 llama.cpp 方案
- ✅ 下载 Q4_K_M 或 Q2_K 量化版本
- ✅ 使用所有 CPU 核心
- ✅ 启用 Metal GPU 加速

**如果你想要简单易用**：
- ✅ 继续使用 Ollama
- ✅ 使用 API 参数优化（已在测试脚本中配置）

## 📝 下一步

1. **解决 Flask 安装问题**：使用国内镜像或升级 pip
2. **下载 GGUF 模型**：找到正确的 HuggingFace 仓库
3. **启动服务并测试**：验证性能提升

## 🔗 相关文件

- `llama_cpp_api.py` - HTTP API 包装器
- `start_llama_api.sh` - 启动脚本
- `download_deepseek_model.sh` - 模型下载脚本
- `不使用Ollama运行模型指南.md` - 详细指南

