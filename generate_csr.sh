#!/bin/bash

# 生成 CSR 文件的脚本
# 使用方法: ./generate_csr.sh "your-email@example.com" "Your Name"

set -e

if [ $# -lt 2 ]; then
    echo "使用方法: $0 <邮箱地址> <姓名>"
    echo "示例: $0 \"your-email@example.com\" \"suhang hu\""
    exit 1
fi

EMAIL="$1"
NAME="$2"
CSR_FILE="CertificateSigningRequest.certSigningRequest"
KEY_FILE="private_key.pem"

echo "正在生成 CSR 文件..."
echo "邮箱: $EMAIL"
echo "姓名: $NAME"
echo ""

# 生成私钥
if [ ! -f "$KEY_FILE" ]; then
    echo "1. 生成私钥..."
    openssl genrsa -out "$KEY_FILE" 2048
    echo "✅ 私钥已生成: $KEY_FILE"
else
    echo "⚠️  私钥文件已存在: $KEY_FILE"
    read -p "是否使用现有私钥？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$KEY_FILE"
        openssl genrsa -out "$KEY_FILE" 2048
        echo "✅ 已生成新私钥"
    fi
fi

# 生成 CSR
echo ""
echo "2. 生成 CSR 文件..."
openssl req -new -key "$KEY_FILE" -out "$CSR_FILE" \
    -subj "/emailAddress=$EMAIL/CN=$NAME/C=CN"

echo ""
echo "✅ CSR 文件已生成: $CSR_FILE"
echo ""
echo "CSR 文件信息："
openssl req -in "$CSR_FILE" -text -noout | grep -E "Subject:|emailAddress|CN=" | head -5
echo ""
echo "下一步："
echo "1. 访问 https://developer.apple.com/account/resources/certificates/list"
echo "2. 点击 '+' 创建新证书"
echo "3. 选择 'Developer ID Application'"
echo "4. 上传 $CSR_FILE 文件"
echo ""
echo "⚠️  重要提示："
echo "- 请妥善保管 $KEY_FILE 文件（私钥）"
echo "- 不要分享私钥给任何人"
echo "- CSR 文件可以安全上传到 Apple Developer 网站"

