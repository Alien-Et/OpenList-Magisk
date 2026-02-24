#!/bin/bash

set -e

echo "========================================"
echo "OpenList Magisk 模块本地打包脚本"
echo "========================================"

# 检查依赖工具
echo "检查依赖工具..."
for cmd in curl zip awk python3; do
    if ! command -v $cmd &> /dev/null; then
        echo "错误: 缺少依赖工具 $cmd"
        exit 1
    fi
done

echo "依赖工具检查通过"

# 进入脚本所在目录
cd "$(dirname "$0")"

# 获取 OpenList 最新版本
echo "获取 OpenList 最新版本..."
API_URL="https://api.github.com/repos/OpenListTeam/OpenList/releases/latest"

for i in {1..3}; do
    RESPONSE=$(curl -s -L -w "\n%{http_code}" "$API_URL")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" -eq 200 ] && [ -n "$BODY" ]; then
        echo "成功获取 OpenList Release 数据"
        echo "$BODY" > latest_release.json
        break
    fi
    
    echo "尝试 $i 失败，HTTP 状态码: $HTTP_CODE"
    sleep $((5 * i))
done

if [ ! -f latest_release.json ] || [ ! -s latest_release.json ]; then
    echo "错误: 无法获取 OpenList 版本信息"
    exit 1
fi

# 提取版本号
VERSION=$(echo "$BODY" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$VERSION" ]; then
    echo "错误: 无法提取版本号"
    cat latest_release.json
    exit 1
fi

echo "获取到版本: $VERSION"

# 生成版本代码（比如 v4.1.10 -> 4110）
VERSION_NUM=$(echo "$VERSION" | tr -d 'v')
VERSION_CODE=$(echo "$VERSION_NUM" | awk -F. '{print $1 * 1000 + $2 * 100 + $3}')

echo "版本代码: $VERSION_CODE"

# 提取下载链接
ARM_URL=$(echo "$BODY" | grep '"browser_download_url":' | grep 'openlist-android-arm.tar.gz' | sed -E 's/.*"([^"]+)".*/\1/')
ARM64_URL=$(echo "$BODY" | grep '"browser_download_url":' | grep 'openlist-android-arm64.tar.gz' | sed -E 's/.*"([^"]+)".*/\1/')

# 提取 CHANGELOG
CHANGELOG=$(python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('body', ''))" <<< "$BODY")

if [ -z "$ARM_URL" ] || [ -z "$ARM64_URL" ]; then
    echo "错误: 无法提取二进制下载链接"
    exit 1
fi

echo "ARM 下载链接: $ARM_URL"
echo "ARM64 下载链接: $ARM64_URL"

# 同步 OpenList 二进制文件
echo "下载并同步 OpenList 二进制文件..."

# 下载并解压 ARM 版本
for i in {1..3}; do
    if curl -L -o openlist-arm.tar.gz "$ARM_URL"; then
        break
    fi
    echo "下载 ARM 版本失败，重试 $i/3"
    sleep $((5 * i))
done

if [ ! -f openlist-arm.tar.gz ]; then
    echo "错误: 下载 ARM 版本失败"
    exit 1
fi

tar -xzf openlist-arm.tar.gz
if [ ! -f openlist ]; then
    echo "错误: 解压 ARM 版本失败"
    exit 1
fi
mv openlist openlist-arm
rm -f openlist-arm.tar.gz

# 下载并解压 ARM64 版本
for i in {1..3}; do
    if curl -L -o openlist-arm64.tar.gz "$ARM64_URL"; then
        break
    fi
    echo "下载 ARM64 版本失败，重试 $i/3"
    sleep $((5 * i))
done

if [ ! -f openlist-arm64.tar.gz ]; then
    echo "错误: 下载 ARM64 版本失败"
    exit 1
fi

tar -xzf openlist-arm64.tar.gz
if [ ! -f openlist ]; then
    echo "错误: 解压 ARM64 版本失败"
    exit 1
fi
mv openlist openlist-arm64
rm -f openlist-arm64.tar.gz

# 移动二进制文件到模块目录
if [ ! -f openlist-arm ] || [ ! -f openlist-arm64 ]; then
    echo "错误: 二进制文件不存在"
    exit 1
fi

mv openlist-arm OpenList-Magisk/
mv openlist-arm64 OpenList-Magisk/

# 设置权限
chmod 755 OpenList-Magisk/openlist-arm OpenList-Magisk/openlist-arm64

echo "二进制文件同步完成"

# 更新配置文件
echo "更新配置文件..."

# 更新 update.json
cat > update.json << EOF
{
    "version": "$VERSION",
    "versionCode": $VERSION_CODE,
    "zipUrl": "https://github.com/OpenListTeam/OpenList-Magisk/releases/download/$VERSION/openlist-magisk-$VERSION.zip",
    "changelog": "https://github.com/OpenListTeam/OpenList-Magisk/raw/main/OpenList-Magisk/CHANGELOG.md"
}
EOF

# 更新 module.prop
if [ -f OpenList-Magisk/module.prop ]; then
    sed -i "s/^version=.*/version=$VERSION/" OpenList-Magisk/module.prop
    sed -i "s/^versionCode=.*/versionCode=$VERSION_CODE/" OpenList-Magisk/module.prop
else
    echo "错误: module.prop 文件不存在"
    exit 1
fi

# 更新 CHANGELOG.md
mkdir -p OpenList-Magisk
echo "$CHANGELOG" > OpenList-Magisk/CHANGELOG.md

echo "配置文件更新完成"

# 打包模块
echo "打包模块..."
cd OpenList-Magisk
zip -r ../openlist-magisk-$VERSION.zip .
cd ..

if [ ! -f openlist-magisk-$VERSION.zip ]; then
    echo "错误: 打包失败"
    exit 1
fi

# 清理临时文件
rm -f latest_release.json

echo "========================================"
echo "打包完成！"
echo "========================================"
echo "模块版本: $VERSION"
echo "版本代码: $VERSION_CODE"
echo "打包文件: openlist-magisk-$VERSION.zip"
echo "文件大小: $(du -h openlist-magisk-$VERSION.zip | cut -f1)"
echo "========================================"
