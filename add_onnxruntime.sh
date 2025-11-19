#!/bin/bash
# 自动添加 ONNX Runtime Swift Package 依赖
# 注意：此脚本需要 Xcode 命令行工具

set -e

PROJECT_PATH="fastv.xcodeproj"
PACKAGE_URL="https://github.com/microsoft/onnxruntime-swift"
PACKAGE_VERSION="1.15.0"

echo "=========================================="
echo "添加 ONNX Runtime Swift Package 依赖"
echo "=========================================="
echo ""

# 检查 Xcode 是否安装
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 错误：未找到 Xcode 命令行工具"
    echo "请先安装 Xcode Command Line Tools："
    echo "  xcode-select --install"
    exit 1
fi

echo "✅ Xcode 命令行工具已安装"
echo ""

# 注意：xcodebuild 无法直接添加 Swift Package
# 需要在 Xcode GUI 中手动添加
echo "⚠️  注意：Swift Package 依赖需要在 Xcode 中手动添加"
echo ""
echo "请按照以下步骤操作："
echo ""
echo "1. 打开 Xcode："
echo "   open $PROJECT_PATH"
echo ""
echo "2. 在 Xcode 中："
echo "   - 点击项目文件（蓝色图标）"
echo "   - 选择 Target 'fastv'"
echo "   - 切换到 'Package Dependencies' 标签"
echo "   - 点击 '+' 按钮"
echo "   - 输入：$PACKAGE_URL"
echo "   - 选择版本并添加"
echo ""
echo "3. 构建项目："
echo "   xcodebuild -project $PROJECT_PATH -scheme fastv -configuration Debug build"
echo ""
echo "或者查看 QUICK_START.md 获取详细步骤"
echo ""

