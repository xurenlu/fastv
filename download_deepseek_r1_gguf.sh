#!/bin/bash
# DeepSeek-R1:1.5B GGUF 模型下载脚本

set -e

MODEL_DIR="$HOME/models/deepseek-r1"
MODEL_NAME="deepseek-r1-1.5b"

echo "=========================================="
echo "DeepSeek-R1:1.5B GGUF 模型下载"
echo "=========================================="
echo ""

# 创建模型目录
mkdir -p "$MODEL_DIR"
cd "$MODEL_DIR"

echo "模型目录: $MODEL_DIR"
echo ""

# 设置代理（如果需要）
if [ -n "$https_proxy" ] || [ -n "$http_proxy" ]; then
    echo "使用代理: $https_proxy"
else
    echo "提示: 如果下载慢，可以设置代理："
    echo "  export https_proxy=http://127.0.0.1:7890"
    echo "  export http_proxy=http://127.0.0.1:7890"
    echo "  all_proxy=socks5://127.0.0.1:7890"
    echo ""
fi

# 方法 1：使用 huggingface-cli（推荐）
if command -v huggingface-cli &> /dev/null; then
    echo "✅ 找到 huggingface-cli"
    echo ""
    echo "尝试从 HuggingFace 下载..."
    echo ""
    
    # 可能的仓库列表
    REPOS=(
        "deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B"
        "deepseek-ai/deepseek-r1-1.5b"
        "TheBloke/deepseek-r1-1.5B-instruct-GGUF"
        "lmstudio-community/deepseek-r1-distill-qwen-1.5b"
    )
    
    SUCCESS=false
    for repo in "${REPOS[@]}"; do
        echo "尝试仓库: $repo"
        if huggingface-cli download "$repo" \
            --local-dir "$MODEL_DIR" \
            --local-dir-use-symlinks False \
            --include "*.gguf" \
            2>&1 | tee /tmp/hf_download.log; then
            if grep -q "\.gguf" /tmp/hf_download.log || ls "$MODEL_DIR"/*.gguf 2>/dev/null; then
                echo "✅ 下载成功！"
                SUCCESS=true
                break
            fi
        fi
        echo ""
    done
    
    if [ "$SUCCESS" = true ]; then
        echo ""
        echo "下载的文件："
        ls -lh "$MODEL_DIR"/*.gguf 2>/dev/null || echo "未找到 GGUF 文件"
        exit 0
    fi
else
    echo "⚠️  未找到 huggingface-cli"
    echo ""
fi

# 方法 2：使用 wget/curl 直接下载（如果知道具体链接）
echo "=========================================="
echo "方法 2：手动下载指南"
echo "=========================================="
echo ""
echo "请访问以下链接手动下载："
echo ""
echo "1. HuggingFace 官方仓库："
echo "   https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B"
echo "   https://huggingface.co/models?search=deepseek-r1+gguf"
echo ""
echo "2. LM Studio 社区模型："
echo "   https://lmstudio.ai/models?search=deepseek-r1-1.5b"
echo ""
echo "3. 推荐下载的量化版本："
echo "   - Q4_K_M.gguf（推荐，平衡速度和质量，约 1GB）"
echo "   - Q2_K.gguf（最快，质量略降，约 600MB）"
echo "   - Q8_0.gguf（质量最好，速度较慢，约 2GB）"
echo ""
echo "4. 下载后保存到："
echo "   $MODEL_DIR/"
echo ""
echo "5. 重命名为（如果需要）："
echo "   deepseek-r1-1.5b.Q4_K_M.gguf"
echo ""

# 方法 3：使用 git lfs（如果仓库支持）
if command -v git &> /dev/null && command -v git-lfs &> /dev/null; then
    echo "=========================================="
    echo "方法 3：使用 git lfs 下载"
    echo "=========================================="
    echo ""
    read -p "是否尝试使用 git lfs 下载？[y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "安装 git-lfs（如果未安装）："
        echo "  brew install git-lfs"
        echo "  git lfs install"
        echo ""
        echo "克隆仓库："
        echo "  cd $MODEL_DIR"
        echo "  git lfs clone https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B"
        echo ""
    fi
fi

# 方法 4：从 Ollama 提取（不可行，格式不同）
echo "=========================================="
echo "注意事项"
echo "=========================================="
echo ""
echo "⚠️  Ollama 使用的模型格式不是 GGUF，无法直接提取"
echo "⚠️  必须下载 GGUF 格式的模型文件"
echo ""
echo "如果下载遇到问题："
echo "1. 检查网络连接和代理设置"
echo "2. 尝试使用浏览器直接访问 HuggingFace 下载"
echo "3. 使用国内镜像（如果可用）"
echo ""
echo "下载完成后，运行以下命令验证："
echo "  ls -lh $MODEL_DIR/*.gguf"
echo "  llama-cli -m $MODEL_DIR/*.gguf -p '测试'"
echo ""

