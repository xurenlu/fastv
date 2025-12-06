# DeepSeek-R1:1.5B GGUF 模型下载指南

## 🎯 目标
下载 deepseek-r1 1.5b 的量化 GGUF 格式模型，用于 llama.cpp 运行。

## 📋 下载方式

### 方式 1：使用 huggingface-cli（推荐）⭐

#### 步骤 1：安装 huggingface-cli

```bash
# 设置代理（如果需要）
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
all_proxy=socks5://127.0.0.1:7890

# 安装
pip3 install --user huggingface_hub[cli]

# 或使用国内镜像
pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple --user huggingface_hub[cli]
```

#### 步骤 2：下载模型

```bash
# 创建模型目录
mkdir -p ~/models/deepseek-r1
cd ~/models/deepseek-r1

# 设置代理（如果需要）
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
all_proxy=socks5://127.0.0.1:7890

# 尝试下载（可能的仓库名）
huggingface-cli download deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B \
  --local-dir . \
  --include "*.gguf"

# 或尝试其他可能的仓库
huggingface-cli download lmstudio-community/deepseek-r1-distill-qwen-1.5b \
  --local-dir . \
  --include "*.gguf"
```

#### 步骤 3：使用下载脚本

```bash
# 运行下载脚本
bash download_deepseek_r1_gguf.sh
```

### 方式 2：手动下载（浏览器）

#### 步骤 1：访问 HuggingFace

**可能的仓库链接：**
1. https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B
2. https://huggingface.co/models?search=deepseek-r1+gguf
3. https://huggingface.co/TheBloke/deepseek-r1-1.5B-instruct-GGUF

#### 步骤 2：查找 GGUF 文件

在模型页面中：
1. 点击 "Files and versions" 标签
2. 查找 `.gguf` 格式的文件
3. 选择合适的量化版本

#### 步骤 3：选择量化版本

| 版本 | 大小 | 质量 | 速度 | 推荐场景 |
|------|------|------|------|---------|
| **Q4_K_M** | ~1GB | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | **推荐，平衡** |
| Q2_K | ~600MB | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | 最快，质量可接受 |
| Q8_0 | ~2GB | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | 质量最好，速度较慢 |
| Q5_K_M | ~1.2GB | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | 质量稍好 |

#### 步骤 4：下载并保存

1. 点击文件名下载
2. 保存到：`~/models/deepseek-r1/`
3. 重命名为：`deepseek-r1-1.5b.Q4_K_M.gguf`（可选）

### 方式 3：使用 LM Studio（如果可用）

1. 访问：https://lmstudio.ai/models?search=deepseek-r1-1.5b
2. 下载 GGUF 格式模型
3. 复制到 `~/models/deepseek-r1/`

### 方式 4：使用 git lfs

```bash
# 安装 git-lfs
brew install git-lfs
git lfs install

# 克隆仓库
cd ~/models/deepseek-r1
git lfs clone https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B

# 查找 GGUF 文件
find DeepSeek-R1-Distill-Qwen-1.5B -name "*.gguf"
```

## 🔍 查找正确的仓库

### 搜索 HuggingFace

访问以下链接搜索：
- https://huggingface.co/models?search=deepseek-r1+gguf
- https://huggingface.co/models?search=deepseek-r1-distill-qwen-1.5b

### 可能的仓库名称

1. `deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B`
2. `deepseek-ai/deepseek-r1-1.5b`
3. `TheBloke/deepseek-r1-1.5B-instruct-GGUF`
4. `lmstudio-community/deepseek-r1-distill-qwen-1.5b`

## ✅ 验证下载

### 检查文件

```bash
# 查看下载的文件
ls -lh ~/models/deepseek-r1/*.gguf

# 应该看到类似：
# -rw-r--r--  1 user  staff  1.0G  Jan  1 12:00 deepseek-r1-1.5b.Q4_K_M.gguf
```

### 测试模型

```bash
# 使用 llama-cli 测试
llama-cli -m ~/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf \
  -p "请优化这段文字：嗯那个我今天想去超市" \
  -n 50 \
  --temp 0.2
```

## 🚀 快速开始脚本

创建一个快速下载脚本：

```bash
#!/bin/bash
# quick_download.sh

set -e

MODEL_DIR="$HOME/models/deepseek-r1"
mkdir -p "$MODEL_DIR"
cd "$MODEL_DIR"

# 设置代理
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
all_proxy=socks5://127.0.0.1:7890

echo "开始下载..."
echo ""

# 尝试下载
if huggingface-cli download deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B \
  --local-dir . \
  --include "*.gguf" \
  --local-dir-use-symlinks False; then
    echo ""
    echo "✅ 下载完成！"
    echo ""
    echo "下载的文件："
    ls -lh *.gguf
else
    echo ""
    echo "❌ 自动下载失败"
    echo ""
    echo "请手动下载："
    echo "1. 访问: https://huggingface.co/models?search=deepseek-r1+gguf"
    echo "2. 找到 deepseek-r1 1.5b 的 GGUF 文件"
    echo "3. 下载 Q4_K_M 版本"
    echo "4. 保存到: $MODEL_DIR/"
fi
```

## ⚠️ 常见问题

### 问题 1：找不到模型

**解决：**
- 确认模型名称正确
- 尝试不同的仓库名称
- 使用浏览器直接访问 HuggingFace 搜索

### 问题 2：下载速度慢

**解决：**
- 设置代理：`export https_proxy=http://127.0.0.1:7890`
- 使用浏览器直接下载
- 使用国内镜像（如果可用）

### 问题 3：下载的文件不是 GGUF 格式

**解决：**
- 确认下载的是 `.gguf` 文件，不是 `.safetensors` 或 `.bin`
- 查找文件名中包含 "GGUF" 或 "gguf" 的文件

### 问题 4：文件损坏

**解决：**
- 重新下载
- 检查文件大小是否匹配
- 使用 SHA256 校验（如果提供）

## 📝 下一步

下载完成后：

1. **验证文件**：`ls -lh ~/models/deepseek-r1/*.gguf`
2. **测试模型**：使用 `llama-cli` 测试
3. **启动服务**：`bash start_llama_api.sh`
4. **运行测试**：`ruby test_injection.rb http://127.0.0.1:11435 deepseek-r1-1.5b`

## 🔗 相关资源

- HuggingFace 搜索：https://huggingface.co/models?search=deepseek-r1+gguf
- LM Studio：https://lmstudio.ai/models?search=deepseek-r1-1.5b
- llama.cpp：https://github.com/ggerganov/llama.cpp

