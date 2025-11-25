#!/bin/bash

# 检查应用 Bundle ID 和权限匹配的脚本

echo "🔍 检查应用 Bundle ID 和权限状态"
echo "=================================="
echo ""

# 检查应用 Bundle ID
APP_PATH="build/typecho.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 应用不存在: $APP_PATH"
    echo "请先构建应用"
    exit 1
fi

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist" 2>/dev/null)
APP_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$APP_PATH/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Print :CFBundleName" "$APP_PATH/Contents/Info.plist" 2>/dev/null)

echo "📱 应用信息:"
echo "  Bundle ID: $BUNDLE_ID"
echo "  应用名称: $APP_NAME"
echo ""

# 检查系统权限设置
echo "🔐 系统权限设置:"
echo "  请检查以下位置的应用名称和 Bundle ID 是否匹配:"
echo "  1. 系统设置 > 隐私与安全性 > 麦克风"
echo "  2. 系统设置 > 隐私与安全性 > 辅助功能"
echo ""

# 检查 tccutil（如果可用）
if command -v tccutil &> /dev/null; then
    echo "📋 使用 tccutil 检查权限状态:"
    echo "  麦克风权限:"
    tccutil reset Microphone "$BUNDLE_ID" 2>&1 | head -1 || echo "    无法重置（可能需要管理员权限）"
    echo ""
fi

echo "💡 诊断建议:"
echo "  1. 如果系统设置中显示的应用名称是 'typecho'，但实际应用名称是 '妙打'，"
echo "     可能是 Bundle ID 不匹配导致的"
echo "  2. 如果权限已授权但应用仍提示需要权限，请尝试："
echo "     - 在系统设置中移除应用权限，然后重新授权"
echo "     - 确保应用签名一致（新电脑上签名可能不同）"
echo "  3. 检查应用签名:"
echo "     codesign -dvv build/typecho.app | grep -E 'Authority|TeamIdentifier|Identifier'"
echo ""

