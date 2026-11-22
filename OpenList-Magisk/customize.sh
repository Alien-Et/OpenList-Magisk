# shellcheck shell=ash

#==== 侦探：Magisk or KernelSU or APatch ====
if [ -n "$MAGISK_VER" ]; then
    MODROOT="$MODPATH"
elif [ -n "$KSU" ] || [ -n "$KERNELSU" ]; then
    MODROOT="$MODULEROOT"
elif [ -n "$APATCH" ]; then
    MODROOT="$MODULEROOT"
else
    MODROOT="$MODPATH"  # 兜底，保持旧逻辑
fi
#==== 侦探结束 ====

# Magisk/KernelSU 安装环境只提供 MODPATH/MODULEROOT，没有 MODDIR。
# 菜单和 BINARY_SERVICE_PATH 里用到的 $MODDIR 必须先补齐，否则菜单会显示成 "2、/bin"。
MODDIR="${MODDIR:-$MODROOT}"

ui_print "正在安装 OpenList Magisk 模块..."

# 检测设备架构：框架会提供 $ARCH（arm64/arm/x86/x86_64）。
# 旧代码直接拿 abi 覆盖 $ARCH，x86_64 设备会被误判成 arm 分支。
DEV_ABI="$(getprop ro.product.cpu.abi)"
ui_print "检测到架构: ${ARCH:-未知} (abi: ${DEV_ABI:-未知})"

# 定义二进制文件名
BINARY_NAME="openlist"

# Code from NGA SDK (https://github.com/TianwanTW/NGA-SDK/blob/nga/src/shell/nga-utils.sh)
until_key() {
    local eventCode idle=0
    while :; do
        eventCode=$(getevent -qlc 1 2>/dev/null | awk '{if ($2=="EV_KEY" && $4=="DOWN") {print $3; exit}}')
        case "$eventCode" in
        KEY_VOLUMEUP)
            printf up
            return
            ;;
        KEY_VOLUMEDOWN)
            printf down
            return
            ;;
        KEY_POWER)
            echo -n power
            return
            ;;
        KEY_F[1-9] | KEY_F1[0-9] | KEY_F2[0-4])
            echo -n "$eventCode" | sed 's/KEY_F/f/g'
            return
            ;;
        esac
        # getevent 不可用或始终读不到事件时避免无限空转：约 90 秒后按默认选项继续
        idle=$((idle + 1))
        [ "$idle" -ge 300 ] && { printf up; return; }
        sleep 0.3
    done
}

# 显示菜单选项
show_binary_menu() {
    local current=$1
    ui_print " "
    ui_print "📂 选择安装位置"
    ui_print "1、adb/openlist/bin"
    ui_print "2、$MODDIR/bin"
    ui_print "3、$MODDIR/system/bin"
    ui_print "━━━━━━━━━━━━━━━━━━━━━━"
    ui_print "音量+ 确认  |  音量- 切换"
    ui_print "━━━━━━━━━━━━━━━━━━━━━━"
    ui_print "👉 当前选择：选项 $current"
}

show_data_menu() {
    local current=$1
    ui_print " "
    ui_print "📁 选择数据目录"
    ui_print "1、data/adb/openlist"
    ui_print "2、Android/openlist"
    ui_print "━━━━━━━━━━━━━━━━━━━━━━"
    ui_print "音量+ 确认  |  音量- 切换"
    ui_print "━━━━━━━━━━━━━━━━━━━━━━"
    ui_print "👉 当前选择：选项 $current"
}

# 选择函数
make_selection() {
    local menu_type="$1"
    local max_options="$2"
    local current=1
    
    # 显示初始菜单
    case "$menu_type" in
        "binary")
            show_binary_menu "$current"
            ;;
        "data")
            show_data_menu "$current"
            ;;
    esac
    
    while true; do
        case "$(until_key)" in
            "up")
                ui_print "✅ 已确认选项 $current"
                return $current
                ;;
            "down")
                current=$((current + 1))
                [ $current -gt $max_options ] && current=1
                ui_print "👉 当前选择：选项 $current"
                ;;
        esac
        sleep 0.3
    done
}

# 安装流程开始
ui_print "⚙️ 开始配置..."

# 选择二进制安装路径
make_selection "binary" "3"
INSTALL_OPTION=$?

# 定义安装路径和service.sh中的路径
case $INSTALL_OPTION in
    1) 
        BINARY_PATH="/data/adb/openlist/bin"
        BINARY_SERVICE_PATH="/data/adb/openlist/bin/openlist"
        ;;
    2) 
        BINARY_PATH="$MODROOT/bin"
        BINARY_SERVICE_PATH='$MODDIR/bin/openlist'
        ;;
    3) 
        BINARY_PATH="$MODROOT/system/bin"
        BINARY_SERVICE_PATH='$MODDIR/system/bin/openlist'
        ;;
esac

# 创建安装目录
mkdir -p "$BINARY_PATH"

# 安装二进制文件
case "$ARCH" in
    arm64) BIN_ARCH=arm64 ;;
    arm)   BIN_ARCH=arm ;;
    *)
        case "$DEV_ABI" in
            arm64*)        BIN_ARCH=arm64 ;;
            armeabi*|arm*) BIN_ARCH=arm ;;
            *) abort "❌ 不支持的架构：${ARCH:-未知} / ${DEV_ABI:-未知}，本模块仅提供 arm / arm64" ;;
        esac
        ;;
esac

if [ "$BIN_ARCH" = "arm64" ]; then
    ui_print "📦 安装 ARM64 版本..."
    if [ -f "$MODROOT/openlist-arm64" ]; then
        mv "$MODROOT/openlist-arm64" "$BINARY_PATH/$BINARY_NAME"
        rm -f "$MODROOT/openlist-arm"
    else
        abort "❌ 错误：未找到 ARM64 版本文件"
    fi
else
    ui_print "📦 安装 ARM 版本..."
    if [ -f "$MODROOT/openlist-arm" ]; then
        mv "$MODROOT/openlist-arm" "$BINARY_PATH/$BINARY_NAME"
        rm -f "$MODROOT/openlist-arm64"
    else
        abort "❌ 错误：未找到 ARM 版本文件"
    fi
fi

chmod 755 "$BINARY_PATH/$BINARY_NAME"

[ "$BINARY_PATH" = "$MODROOT/system/bin" ] && chcon -R u:object_r:system_file:s0 "$BINARY_PATH/$BINARY_NAME"

# 选择数据目录
make_selection "data" "2"
DATA_DIR_OPTION=$?

case $DATA_DIR_OPTION in
    1) DATA_DIR="/data/adb/openlist" ;;
    2) DATA_DIR="/sdcard/Android/openlist" ;;
esac

# 可写性检查：recovery 安装时 /sdcard 可能还没挂载，
# 直接往下走会得到一个指向不存在目录的 service.sh
if ! mkdir -p "$DATA_DIR" 2>/dev/null || [ ! -w "$DATA_DIR" ]; then
    ui_print "⚠️ 警告：$DATA_DIR 当前不可写"
    ui_print "   常见原因：/sdcard 未挂载（recovery 安装）"
    ui_print "   服务启动后可能无法写入数据库，重启后请在 WebUI 里迁移数据目录"
fi

# 数据迁移提示
ui_print " "
ui_print "📢 数据目录设置"
ui_print "━━━━━━━━━━━━━━━━━━━━━━"
ui_print "✓ 已选择: $DATA_DIR"
ui_print "⚠️ 注意事项："
ui_print "1. 新数据目录将在重启后生效"
ui_print "2. 请手动将现有数据迁移到新目录"
ui_print "3. 迁移后更新 config.json 中的路径"
ui_print "━━━━━━━━━━━━━━━━━━━━━━"

# 更新 service.sh - 使用占位符替换
if [ -f "$MODROOT/service.sh" ] && [ -f "$MODROOT/action.sh" ]; then
    # 替换占位符为实际路径（使用单引号防止 $MODDIR 被展开）
    sed -i 's|__PLACEHOLDER_BINARY_PATH__|'"$BINARY_SERVICE_PATH"'|g' "$MODROOT/service.sh"
    sed -i 's|__PLACEHOLDER_BINARY_PATH__|'"$BINARY_SERVICE_PATH"'|g' "$MODROOT/action.sh"
    sed -i 's|__PLACEHOLDER_DATA_DIR__|'"$DATA_DIR"'|g' "$MODROOT/service.sh"

    # 验证更新是否成功 - 检查占位符是否被正确替换
    if ! grep -q "__PLACEHOLDER_BINARY_PATH__" "$MODROOT/service.sh" && \
       ! grep -q "__PLACEHOLDER_BINARY_PATH__" "$MODROOT/action.sh" && \
       ! grep -q "__PLACEHOLDER_DATA_DIR__" "$MODROOT/service.sh"; then
        ui_print "✅ 配置更新成功"
    else
        ui_print "❌ 配置更新失败"
        ui_print "调试信息："
        ui_print "期望的BINARY路径: $BINARY_SERVICE_PATH"
        ui_print "期望的DATA路径: $DATA_DIR"
        ui_print "service.sh中仍然存在未替换的占位符"
        abort "配置更新验证失败"
    fi
else
    abort "❌ 错误：未找到 service.sh"
fi

# 确保控制脚本可执行
if [ -f "$MODROOT/control.sh" ]; then
    chmod 755 "$MODROOT/control.sh" 2>/dev/null || true
fi

# 管理员账号由 OpenList 网页安装向导在首次访问时创建，
# 安装阶段不再询问初始密码（v4.2.10 起未初始化时不会自动建 admin）。
# 完成安装
ui_print " "
ui_print "✨ 安装完成"
ui_print "━━━━━━━━━━━━━━━━━━━━━━"

# 根据安装选项显示友好的二进制路径
case $INSTALL_OPTION in
    1) 
        ui_print "📍 二进制: $BINARY_PATH/$BINARY_NAME"
        ;;
    2) 
        ui_print "📍 二进制: 模块目录/bin/openlist"
        ;;
    3) 
        ui_print "📍 二进制: 模块目录/system/bin/openlist"
        ;;
esac
ui_print "📁 数据目录: $DATA_DIR"

ui_print " "
ui_print "👋 安装完成，请重启设备"
ui_print "━━━━━━━━━━━━━━━━━━━━━━"
