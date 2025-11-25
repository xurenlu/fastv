#!/bin/sh
# 在应用签名之后（如果已签名），使用与应用相同的签名重新签名库文件
LIB_PATH="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libonnxruntime.1.23.2.dylib"
APP_PATH="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}"
if [ -f "${LIB_PATH}" ] && [ -d "${APP_PATH}" ]; then
    # 使用完整的签名身份（硬编码以确保一致性）
    SIGN_IDENTITY="Apple Development: suhang hu (9K5FH5XTHD)"
    # 如果应用已签名，获取应用的签名身份
    APP_SIGN=$(codesign -dvv "${APP_PATH}" 2>&1 | grep "Authority=" | head -1 | sed 's/.*Authority=\([^)]*)\).*/\1/' 2>/dev/null || echo "")
    if [ -n "${APP_SIGN}" ]; then
        SIGN_IDENTITY="${APP_SIGN}"
    fi
    # 重新签名库文件
    codesign --remove-signature "${LIB_PATH}" 2>/dev/null || true
    codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none "${LIB_PATH}" 2>/dev/null || true
    # 重新签名整个应用以确保签名一致性
    codesign --force --deep --sign "${SIGN_IDENTITY}" --timestamp=none "${APP_PATH}" 2>/dev/null || true
    echo "✅ 库文件和应用已使用 ${SIGN_IDENTITY} 签名"
fi

