#!/bin/bash

# 使用指定 Team ID 重新签名脚本

set -e

TEAM_ID="${1:-W49B66SUW3}"

echo "🔧 使用 Team ID ${TEAM_ID} 重新签名"
echo "===================================="
echo ""

# 查找所有可用的证书
echo "🔍 查找可用证书..."
ALL_CERTS=$(security find-identity -v -p codesigning 2>/dev/null | grep -E "Apple Development|Developer ID" | grep -v "Certification Authority")

if [ -z "${ALL_CERTS}" ]; then
    echo "❌ 未找到任何签名证书"
    exit 1
fi

echo "📋 可用证书："
echo "${ALL_CERTS}" | nl
echo ""

# 尝试查找匹配的证书
SIGN_IDENTITY=$(echo "${ALL_CERTS}" | grep "${TEAM_ID}" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")

if [ -z "${SIGN_IDENTITY}" ]; then
    echo "⚠️  未找到 Team ID ${TEAM_ID} 的证书"
    echo ""
    echo "请从上面的列表中选择证书编号（1-$(echo "${ALL_CERTS}" | wc -l | tr -d ' ')）："
    read -r CERT_NUM
    
    if [ -z "${CERT_NUM}" ] || ! [[ "${CERT_NUM}" =~ ^[0-9]+$ ]]; then
        echo "❌ 无效的选择"
        exit 1
    fi
    
    SIGN_IDENTITY=$(echo "${ALL_CERTS}" | sed -n "${CERT_NUM}p" | sed 's/.*"\(.*\)".*/\1/')
    
    if [ -z "${SIGN_IDENTITY}" ]; then
        echo "❌ 无法获取证书"
        exit 1
    fi
fi

echo "✅ 使用证书: ${SIGN_IDENTITY}"
echo ""

# 查找并重新签名所有应用
APPS=(
    "build/typecho.app"
    "build/typecho.xcarchive/Products/Applications/typecho.app"
    "$(find ~/Library/Developer/Xcode/DerivedData -name 'typecho.app' -type d 2>/dev/null | head -1)"
)

for APP_PATH in "${APPS[@]}"; do
    if [ -z "${APP_PATH}" ] || [ ! -d "${APP_PATH}" ]; then
        continue
    fi
    
    echo "📱 处理应用: ${APP_PATH}"
    
    # 重新签名库文件
    LIB_PATH="${APP_PATH}/Contents/Frameworks/libonnxruntime.1.23.2.dylib"
    if [ -f "${LIB_PATH}" ]; then
        echo "  🔧 重新签名库文件..."
        codesign --remove-signature "${LIB_PATH}" 2>/dev/null || true
        codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none "${LIB_PATH}" 2>/dev/null || {
            echo "  ❌ 库文件签名失败"
            continue
        }
        echo "  ✅ 库文件签名完成"
    fi
    
    # 重新签名应用
    echo "  🔧 重新签名应用..."
    codesign --remove-signature "${APP_PATH}" 2>/dev/null || true
    codesign --force --deep --sign "${SIGN_IDENTITY}" --timestamp=none "${APP_PATH}" 2>/dev/null || {
        echo "  ❌ 应用签名失败"
        continue
    }
    echo "  ✅ 应用签名完成"
    
    # 验证签名
    echo "  🔍 验证签名..."
    codesign -dvv "${APP_PATH}" 2>&1 | grep -E "Authority|TeamIdentifier" | head -2 || echo "    验证失败"
    echo ""
done

echo "✅ 所有应用重新签名完成！"

