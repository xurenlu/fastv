#!/bin/bash
# DeepSeek-R1:1.5B 模型下载脚本

set -e

MODEL_DIR="$HOME/models/deepseek-r1"
MODEL_NAME="deepseek-r1-1.5b"

echo "=========================================="
echo "DeepSeek-R1:1.5B 模型下载脚本"
echo "=========================================="
echo ""

# 创建模型目录
mkdir -p "$MODEL_DIR"
cd "$MODEL_DIR"

echo "模型目录: $MODEL_DIR"
echo ""

# 检查是否已安装 huggingface-cli
if command -v huggingface-cli &> /dev/null; then
    echo "✅ 找到 huggingface-cli"
    echo ""
    echo "正在下载模型..."
    echo "注意：如果模型不存在，请手动下载 GGUF 格式的模型"
    echo ""
    
    # 尝试从 HuggingFace 下载（需要找到正确的仓库名）
    # 这里提供几个可能的仓库名
    REPOS=(
        "deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B"
        "deepseek-ai/deepseek-r1-1.5b"
        "TheBloke/deepseek-r1-1.5B-instruct-GGUF"
    )
    
    for repo in "${REPOS[@]}"; do
        echo "尝试从 $repo 下载..."
        if huggingface-cli download "$repo" --local-dir "$MODEL_DIR" --local-dir-use-symlinks False 2>&1 | grep -q "GGUF\|gguf"; then
            echo "✅ 下载成功！"
            break
        fi
    done
    
else
    echo "⚠️  未找到 huggingface-cli"
    echo ""
    echo "请选择下载方式："
    echo ""
    echo "方式 1：安装 huggingface-cli（推荐）"
    echo "  pip install huggingface_hub[cli]"
    echo ""
    echo "方式 2：手动下载"
    echo "  1. 访问 https://huggingface.co/models?search=deepseek-r1+gguf"
    echo "  2. 找到 deepseek-r1-1.5b 的 GGUF 格式模型"
    echo "  3. 下载 Q4_K_M 量化版本（推荐）"
    echo "  4. 将文件保存到: $MODEL_DIR/"
    echo ""
    echo "方式 3：使用 Ollama（如果已有模型）"
    echo "  如果已经在 Ollama 中下载了 deepseek-r1:1.5b，"
    echo "  可以直接使用 Ollama API，无需下载 GGUF 模型"
    echo ""
fi

echo ""
echo "=========================================="
echo "下载完成！"
echo "=========================================="
echo ""
echo "模型应该保存在: $MODEL_DIR/"
echo ""
echo "如果下载失败，请："
echo "1. 检查网络连接"
echo "2. 设置代理（如果需要）"
echo "3. 手动下载模型文件"
echo ""

