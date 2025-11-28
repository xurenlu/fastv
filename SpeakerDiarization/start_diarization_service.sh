#!/bin/bash
# 启动说话人分离 API 服务
# 自动检测和安装依赖，自动启动服务

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "启动说话人分离 API 服务"
echo "=========================================="
echo ""

# 检查 Python
if ! command -v python3 &> /dev/null; then
    echo "❌ 错误: 未找到 python3"
    echo "请先安装 Python 3"
    exit 1
fi

# 设置代理（如果需要）
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890

# 检查并安装依赖
echo "检查 Python 依赖..."
if ! python3 -c "import fastapi, uvicorn, pyannote.audio" 2>/dev/null; then
    echo "安装依赖（这可能需要几分钟）..."
    python3 -m pip install --user --quiet fastapi uvicorn[standard] pyannote.audio torch torchaudio
    echo "✅ 依赖已安装"
else
    echo "✅ 依赖已就绪"
fi

echo ""
echo "启动服务..."
echo "API 地址: http://127.0.0.1:50001"
echo "API 文档: http://127.0.0.1:50001/docs"
echo "按 Ctrl+C 停止服务"
echo ""

# 启动服务
python3 speaker_diarization_api.py --host 127.0.0.1 --port 50001

