#!/bin/bash

# 重新签名脚本 - 使用新的 Team ID (W49B66SUW3)

set -e

echo "🔧 重新签名应用和库文件"
echo "=========================="
echo ""

# 配置
TEAM_ID="W49B66SUW3"
APP_NAME="typecho"
BUILD_DIR="build"

# 查找签名证书
echo "🔍 查找 Team ID ${TEAM_ID} 的签名证书..."
SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "${TEAM_ID}" | grep -E "Apple Development|Developer ID" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")

if [ -z "${SIGN_IDENTITY}" ]; then
    echo "⚠️  未找到 Team ID ${TEAM_ID} 的证书"
    echo "📋 可用的证书："
    security find-identity -v -p codesigning 2>/dev/null | grep -E "Apple Development|Developer ID" || echo "   无"
    echo ""
    echo "请选择要使用的证书（输入完整名称，或按 Enter 使用 ad-hoc 签名）："
    read -r MANUAL_SIGN
    
    if [ -n "${MANUAL_SIGN}" ]; then
        SIGN_IDENTITY="${MANUAL_SIGN}"
    else
        SIGN_IDENTITY="-"
        echo "⚠️  使用 ad-hoc 签名（仅用于开发）"
    fi
else
    echo "✅ 找到证书: ${SIGN_IDENTITY}"
fi

echo ""

# 查找应用
APP_PATH=""
if [ -d "${BUILD_DIR}/typecho.app" ]; then
    APP_PATH="${BUILD_DIR}/typecho.app"
elif [ -d "${BUILD_DIR}/DerivedData" ]; then
    # 查找 DerivedData 中的应用
    APP_PATH=$(find "${BUILD_DIR}/DerivedData" -name "${APP_NAME}.app" -type d | head -1)
fi

if [ -z "${APP_PATH}" ] || [ ! -d "${APP_PATH}" ]; then
    echo "❌ 未找到应用，请先构建应用"
    echo "   查找路径: ${BUILD_DIR}/typecho.app"
    exit 1
fi

echo "📱 找到应用: ${APP_PATH}"
echo ""

# 查找库文件
LIB_PATH="${APP_PATH}/Contents/Frameworks/libonnxruntime.1.23.2.dylib"

if [ ! -f "${LIB_PATH}" ]; then
    echo "⚠️  库文件不存在: ${LIB_PATH}"
    echo "   将在构建时自动复制"
    LIB_PATH=""
else
    echo "📚 找到库文件: ${LIB_PATH}"
fi

echo ""

# 重新签名库文件
if [ -n "${LIB_PATH}" ] && [ -f "${LIB_PATH}" ]; then
    echo "🔧 重新签名库文件..."
    codesign --remove-signature "${LIB_PATH}" 2>/dev/null || true
    codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none "${LIB_PATH}" 2>/dev/null || {
        echo "❌ 库文件签名失败"
        exit 1
    }
    echo "✅ 库文件签名完成"
    echo ""
fi

# 重新签名应用
echo "🔧 重新签名应用..."
codesign --remove-signature "${APP_PATH}" 2>/dev/null || true
codesign --force --deep --sign "${SIGN_IDENTITY}" --timestamp=none "${APP_PATH}" 2>/dev/null || {
    echo "❌ 应用签名失败"
    exit 1
}
echo "✅ 应用签名完成"
echo ""

# 验证签名
echo "🔍 验证签名..."
echo "应用签名："
codesign -dvv "${APP_PATH}" 2>&1 | grep -E "Authority|TeamIdentifier" | head -3 || echo "   验证失败"

if [ -n "${LIB_PATH}" ] && [ -f "${LIB_PATH}" ]; then
    echo ""
    echo "库文件签名："
    codesign -dvv "${LIB_PATH}" 2>&1 | grep -E "Authority|TeamIdentifier" | head -3 || echo "   验证失败"
fi

echo ""
echo "✅ 重新签名完成！"

