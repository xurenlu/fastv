#!/bin/bash

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}开始构建 Release 版本...${NC}"

# 项目配置
PROJECT_NAME="fastv"
SCHEME_NAME="typecho"
CONFIGURATION="Release"
BUILD_DIR="build"
APP_NAME="typecho"
DMG_NAME="${APP_NAME}_v1.0.1"

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
    CODE_SIGN_IDENTITY="Apple Development" \
    DEVELOPMENT_TEAM="W49B66SUW3" \
    CODE_SIGN_STYLE="Automatic" || exit 1

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

# 检查签名
echo -e "${YELLOW}检查签名状态...${NC}"
codesign -dvv "${APP_PATH}" 2>&1 | head -20

# 验证签名
echo -e "${YELLOW}验证签名...${NC}"
if codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1; then
    echo -e "${GREEN}签名验证通过${NC}"
else
    echo -e "${YELLOW}警告: 签名验证失败，尝试重新签名...${NC}"
    # 查找匹配的签名身份
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "W49B66SUW3\|9K5FH5XTHD" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    if [ -n "${SIGN_IDENTITY}" ]; then
        echo -e "${YELLOW}使用签名身份: ${SIGN_IDENTITY}${NC}"
        codesign --force --deep --sign "${SIGN_IDENTITY}" --timestamp=none "${APP_PATH}"
        codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
    else
        echo -e "${RED}错误: 找不到匹配的签名身份${NC}"
        exit 1
    fi
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

# 清理临时文件
rm -rf "${DMG_TEMP}"

echo -e "${GREEN}✅ DMG 文件已创建: ${DMG_NAME}.dmg${NC}"

# 显示文件信息
ls -lh "${DMG_NAME}.dmg"

echo -e "${GREEN}构建完成！${NC}"

