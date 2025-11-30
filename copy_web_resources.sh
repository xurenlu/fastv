#!/bin/bash

# 复制 WebLibs 资源文件从 markly 到 fastv

SOURCE_DIR="/Users/rocky/Sites/markly/markly/Resources/WebLibs"
TARGET_DIR="/Users/rocky/Sites/fastv/fastv/Resources/WebLibs"

echo "开始复制 WebLibs 资源文件..."

# 创建目标目录
mkdir -p "$TARGET_DIR/katex"

# 复制 KaTeX 资源
if [ -d "$SOURCE_DIR/katex" ]; then
    echo "复制 KaTeX 资源..."
    cp -r "$SOURCE_DIR/katex"/* "$TARGET_DIR/katex/" 2>/dev/null
    echo "✅ KaTeX 资源复制完成"
else
    echo "⚠️ 源目录不存在: $SOURCE_DIR/katex"
fi

echo ""
echo "资源复制完成！"
echo "请确保在 Xcode 中将 WebLibs 目录添加到项目资源中。"

