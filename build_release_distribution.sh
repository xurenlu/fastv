#!/bin/bash

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}开始构建 Release 分发版本...${NC}"

# 项目配置
PROJECT_NAME="fastv"
SCHEME_NAME="typecho"
CONFIGURATION="Release"
BUILD_DIR="build"
APP_NAME="typecho"
DMG_NAME="${APP_NAME}_v1.0.1"

# 查找 Developer ID 证书
echo -e "${YELLOW}查找 Developer ID 证书...${NC}"
DEVELOPER_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')

if [ -z "${DEVELOPER_ID}" ]; then
    echo -e "${RED}错误: 未找到 Developer ID Application 证书${NC}"
    echo -e "${YELLOW}请先申请 Developer ID Application 证书：${NC}"
    echo -e "${BLUE}1. 访问 https://developer.apple.com/account${NC}"
    echo -e "${BLUE}2. 进入 Certificates, Identifiers & Profiles${NC}"
    echo -e "${BLUE}3. 创建 Developer ID Application 证书${NC}"
    echo -e "${BLUE}4. 下载并安装到 Keychain${NC}"
    echo ""
    echo -e "${YELLOW}当前可用的签名证书：${NC}"
    security find-identity -v -p codesigning | grep -E "Apple Development|Apple Distribution|Developer ID"
    exit 1
fi

echo -e "${GREEN}找到 Developer ID 证书: ${DEVELOPER_ID}${NC}"

# 清理之前的构建
echo -e "${YELLOW}清理之前的构建...${NC}"
rm -rf "${BUILD_DIR}"
rm -rf "${DMG_NAME}.dmg"

# 创建构建目录
mkdir -p "${BUILD_DIR}"

# 编译 Release 版本
echo -e "${YELLOW}编译 Release 版本...${NC}"
xcodebuild \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    archive \
    CODE_SIGN_IDENTITY="${DEVELOPER_ID}" \
    DEVELOPMENT_TEAM="W49B66SUW3" \
    CODE_SIGN_STYLE="Manual" \
    || exit 1

# 导出应用
echo -e "${YELLOW}导出应用...${NC}"
APP_PATH="${BUILD_DIR}/DerivedData/Build/Products/${CONFIGURATION}/${APP_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
    # 尝试从 archive 中提取
    ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app"
    if [ -d "${ARCHIVE_PATH}" ]; then
        cp -R "${ARCHIVE_PATH}" "${BUILD_DIR}/"
        APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
    else
        echo -e "${RED}错误: 找不到应用文件${NC}"
        exit 1
    fi
fi

# 验证应用是否存在
if [ ! -d "${APP_PATH}" ]; then
    echo -e "${RED}错误: 应用文件不存在: ${APP_PATH}${NC}"
    exit 1
fi

echo -e "${GREEN}应用已构建: ${APP_PATH}${NC}"

# 使用 Developer ID 重新签名应用（确保使用正确的证书）
echo -e "${YELLOW}使用 Developer ID 签名应用...${NC}"
codesign --force --deep --sign "${DEVELOPER_ID}" --options runtime --timestamp "${APP_PATH}"

# 检查签名
echo -e "${YELLOW}检查签名状态...${NC}"
codesign -dvv "${APP_PATH}" 2>&1 | head -20

# 验证签名
echo -e "${YELLOW}验证签名...${NC}"
if codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1; then
    echo -e "${GREEN}签名验证通过${NC}"
else
    echo -e "${RED}错误: 签名验证失败${NC}"
    exit 1
fi

# 创建 DMG
echo -e "${YELLOW}创建 DMG 文件...${NC}"
DMG_TEMP="${BUILD_DIR}/dmg_temp"
rm -rf "${DMG_TEMP}"
mkdir -p "${DMG_TEMP}"

# 复制应用到临时目录
cp -R "${APP_PATH}" "${DMG_TEMP}/"

# 创建 Applications 链接
ln -s /Applications "${DMG_TEMP}/Applications"

# 创建 DMG
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_TEMP}" -ov -format UDZO "${DMG_NAME}.dmg"

# 签名 DMG 文件
echo -e "${YELLOW}签名 DMG 文件...${NC}"
codesign --force --sign "${DEVELOPER_ID}" --timestamp "${DMG_NAME}.dmg"

# 验证 DMG 签名
echo -e "${YELLOW}验证 DMG 签名...${NC}"
codesign -dvv "${DMG_NAME}.dmg" 2>&1 | head -10

if spctl -a -vv -t install "${DMG_NAME}.dmg" 2>&1 | grep -q "accepted"; then
    echo -e "${GREEN}DMG 签名验证通过，Gatekeeper 已接受${NC}"
else
    echo -e "${YELLOW}警告: Gatekeeper 可能未接受 DMG（可能需要公证）${NC}"
fi

# 清理临时文件
rm -rf "${DMG_TEMP}"

echo -e "${GREEN}✅ DMG 文件已创建并签名: ${DMG_NAME}.dmg${NC}"

# 显示文件信息
ls -lh "${DMG_NAME}.dmg"

echo ""
echo -e "${GREEN}构建完成！${NC}"
echo ""
echo -e "${BLUE}下一步（可选但推荐）：${NC}"
echo -e "${YELLOW}1. 进行公证（notarization）以消除 Gatekeeper 警告${NC}"
echo -e "${YELLOW}2. 使用以下命令进行公证：${NC}"
echo -e "   xcrun notarytool submit ${DMG_NAME}.dmg \\"
echo -e "     --apple-id \"your-email@example.com\" \\"
echo -e "     --team-id \"W49B66SUW3\" \\"
echo -e "     --password \"app-specific-password\" \\"
echo -e "     --wait"
echo ""
echo -e "${YELLOW}3. 公证完成后装订票据：${NC}"
echo -e "   xcrun stapler staple ${DMG_NAME}.dmg"

