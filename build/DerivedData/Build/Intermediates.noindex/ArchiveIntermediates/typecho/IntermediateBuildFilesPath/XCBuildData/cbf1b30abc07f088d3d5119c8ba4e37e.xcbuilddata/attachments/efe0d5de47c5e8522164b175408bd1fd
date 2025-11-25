#!/bin/sh
mkdir -p "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
cp -f "${SRCROOT}/Libraries/onnxruntime/current/lib/libonnxruntime.1.23.2.dylib" "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libonnxruntime.1.23.2.dylib"
# 创建符号链接
cd "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
rm -f libonnxruntime.dylib
ln -s libonnxruntime.1.23.2.dylib libonnxruntime.dylib
# 移除旧的代码签名
codesign --remove-signature "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libonnxruntime.1.23.2.dylib" 2>/dev/null || true
# 查找完整的签名身份
FULL_SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "${DEVELOPMENT_TEAM}" | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")
if [ -n "${FULL_SIGN_IDENTITY}" ]; then
    codesign --force --sign "${FULL_SIGN_IDENTITY}" --timestamp=none "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libonnxruntime.1.23.2.dylib" 2>/dev/null || true
    echo "✅ 库文件已使用 ${FULL_SIGN_IDENTITY} 签名"
elif [ -n "${CODE_SIGN_IDENTITY}" ] && [ "${CODE_SIGN_IDENTITY}" != "-" ]; then
    codesign --force --sign "${CODE_SIGN_IDENTITY}" --timestamp=none "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libonnxruntime.1.23.2.dylib" 2>/dev/null || true
    echo "✅ 库文件已使用 ${CODE_SIGN_IDENTITY} 签名"
else
    codesign --force --sign - --timestamp=none "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libonnxruntime.1.23.2.dylib" 2>/dev/null || true
fi

