#!/bin/bash
# 快速启动本地 HTTP 服务器
# 用法: ./serve.sh [端口号]

PORT=${1:-8000}

echo "正在启动 HTTP 服务器..."
echo "访问地址: http://localhost:$PORT"
echo "按 Ctrl+C 停止服务器"
echo ""

# 检查 Python 3 是否可用
if command -v python3 &> /dev/null; then
    python3 -m http.server $PORT
elif command -v python &> /dev/null; then
    python -m http.server $PORT
else
    echo "错误: 未找到 Python，请先安装 Python"
    exit 1
fi

