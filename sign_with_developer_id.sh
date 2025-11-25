#!/bin/bash

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}开始使用 Developer ID 签名...${NC}"

# 查找 Developer ID 证书
echo -e "${YELLOW}查找 Developer ID Application 证书...${NC}"
DEVELOPER_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')

if [ -z "${DEVELOPER_ID}" ]; then
    echo -e "${RED}错误: 未找到 Developer ID Application 证书${NC}"
    echo ""
    echo -e "${YELLOW}请先安装证书：${NC}"
    echo -e "${BLUE}1. 双击 developerID_application.cer 文件${NC}"
    echo -e "${BLUE}2. 或者在终端运行: open developerID_application.cer${NC}"
    echo -e "${BLUE}3. 证书会自动添加到 Keychain${NC}"
    echo ""
    echo -e "${YELLOW}当前可用的签名证书：${NC}"
    security find-identity -v -p codesigning
    exit 1
fi

echo -e "${GREEN}找到 Developer ID 证书: ${DEVELOPER_ID}${NC}"
echo ""

# 检查应用是否存在
APP_PATH="build/typecho.app"
if [ ! -d "${APP_PATH}" ]; then
    echo -e "${RED}错误: 找不到应用文件: ${APP_PATH}${NC}"
    echo -e "${YELLOW}请先运行构建脚本生成应用${NC}"
    exit 1
fi

# 签名应用
echo -e "${YELLOW}使用 Developer ID 签名应用...${NC}"
codesign --force --deep --sign "${DEVELOPER_ID}" --options runtime --timestamp "${APP_PATH}"

# 验证应用签名
echo -e "${YELLOW}验证应用签名...${NC}"
if codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1; then
    echo -e "${GREEN}✅ 应用签名验证通过${NC}"
else
    echo -e "${RED}❌ 应用签名验证失败${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}应用签名信息：${NC}"
codesign -dvv "${APP_PATH}" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier" | head -5

# 检查 DMG 文件
DMG_FILE="typecho_v1.0.1.dmg"
if [ -f "${DMG_FILE}" ]; then
    echo ""
    echo -e "${YELLOW}签名 DMG 文件...${NC}"
    codesign --force --sign "${DEVELOPER_ID}" --timestamp "${DMG_FILE}"
    
    echo -e "${YELLOW}验证 DMG 签名...${NC}"
    codesign -dvv "${DMG_FILE}" 2>&1 | grep -E "Authority|TeamIdentifier" | head -3
    
    if spctl -a -vv -t install "${DMG_FILE}" 2>&1 | grep -q "accepted"; then
        echo -e "${GREEN}✅ DMG 签名验证通过，Gatekeeper 已接受${NC}"
    else
        echo -e "${YELLOW}⚠️  DMG 可能需要公证才能完全消除 Gatekeeper 警告${NC}"
    fi
else
    echo ""
    echo -e "${YELLOW}未找到 DMG 文件，跳过 DMG 签名${NC}"
fi

echo ""
echo -e "${GREEN}✅ 签名完成！${NC}"

