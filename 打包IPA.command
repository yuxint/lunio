#!/bin/bash

# 获取当前脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 查找当前目录下的 .app 文件
APP_FILE=$(find . -maxdepth 1 -name "*.app" -type d | head -n 1)

# 检查是否找到了 .app 文件
if [ -z "$APP_FILE" ]; then
    echo "❌ 错误：当前目录下没有找到 .app 文件！"
    echo "请将本脚本放在 .app 文件同目录下运行。"
    read -p "按任意键退出..."
    exit 1
fi

# 获取文件名（不含路径和扩展名）
APP_NAME=$(basename "$APP_FILE" .app)
IPA_NAME="${APP_NAME}.ipa"

echo "📦 找到应用：$APP_FILE"
echo "🔨 开始打包成 $IPA_NAME ..."

# 创建 Payload 文件夹
rm -rf Payload
mkdir Payload

# 复制 .app 到 Payload
cp -R "$APP_FILE" Payload/

# 打包成 .ipa
zip -r "$IPA_NAME" Payload/ > /dev/null

# 清理临时文件夹
rm -rf Payload

echo "✅ 打包完成：$IPA_NAME"
echo "📍 位置：$(pwd)/$IPA_NAME"

# 自动在 Finder 中打开所在文件夹
open .

read -p "按任意键退出..."