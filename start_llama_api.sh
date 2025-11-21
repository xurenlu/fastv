#!/bin/bash
# 启动 llama.cpp HTTP API 服务

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "启动 llama.cpp HTTP API 服务"
echo "=========================================="
echo ""

# 检查 Python
if ! command -v python3 &> /dev/null; then
    echo "❌ 错误: 未找到 python3"
    echo "请先安装 Python 3"
    exit 1
fi

# 检查 llama-cli
if ! command -v llama-cli &> /dev/null; then
    echo "❌ 错误: 未找到 llama-cli"
    echo "请先安装: brew install llama.cpp"
    exit 1
fi

# 检查并安装 Python 依赖
echo "检查 Python 依赖..."
if ! python3 -c "import flask" 2>/dev/null; then
    echo "安装 Flask..."
    pip3 install --user flask flask-cors --quiet
    echo "✅ Flask 已安装（用户模式）"
fi

# 检查模型文件
MODEL_PATH="$HOME/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf"
if [ ! -f "$MODEL_PATH" ]; then
    echo "⚠️  警告: 模型文件不存在: $MODEL_PATH"
    echo ""
    echo "请先下载模型："
    echo "  bash download_deepseek_model.sh"
    echo ""
    echo "或者修改 llama_cpp_api.py 中的 MODEL_PATH"
    echo ""
    read -p "是否继续启动服务？（模型不存在时将无法使用）[y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo "启动服务..."
echo "API 地址: http://127.0.0.1:11435"
echo "按 Ctrl+C 停止服务"
echo ""

# 使用虚拟环境启动服务
if [ -d "venv_llama" ]; then
    echo "使用虚拟环境启动..."
    source venv_llama/bin/activate
    python3 llama_cpp_api.py
    deactivate
else
    echo "使用系统 Python 启动..."
    python3 llama_cpp_api.py
fi

