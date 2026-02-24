#!/system/bin/sh
# shellcheck shell=ash
# action.sh for OpenList Magisk Module
MODDIR="${0%/*}"
MODULE_PROP="$MODDIR/module.prop"
SERVICE_SH="$MODDIR/service.sh"
OPENLIST_BINARY="__PLACEHOLDER_BINARY_PATH__"
REPO_URL="https://github.com/Alien-Et/OpenList-Magisk"

# 修复：用字符串替代数组，适配 Ash Shell（不支持数组）
find_busybox() {
    local busybox_paths="/data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/bin/busybox /system/xbin/busybox /system/bin/busybox"
    
    for path in $busybox_paths; do
        if [ -x "$path" ]; then
            echo "$path"
            return 0
        fi
    done

    local which_busybox
    which_busybox=$(which busybox 2>/dev/null)
    if [ -x "$which_busybox" ]; then
        echo "$which_busybox"
        return 0
    fi

    echo "错误:找不到BusyBox！" >&2
    exit 1
}

# 初始化BusyBox绝对路径
BUSYBOX=$(find_busybox)

# 核心函数：检查OpenList服务状态
check_openlist_status() {
    if "$BUSYBOX" pgrep -f "$OPENLIST_BINARY" 2>/dev/null; then
        return 0  # 找到并运行中，返回成功，并打印出pid
    else
        return 1  # 未找到或未运行，返回失败
    fi
}

# 更新模块状态为“已停止”
update_module_prop_stopped() {
    "$BUSYBOX" sed -i "s|^description=.*|description=【已停止】请点击\"操作\"启动程序。项目地址：${REPO_URL}|" "$MODULE_PROP"
}

# 主逻辑：启停服务
if check_openlist_status; then
    # 服务已运行：执行停止
    echo "正在停止 OpenList 服务..."
    "$BUSYBOX" pkill -f "$OPENLIST_BINARY"
    sleep 1  # 等待进程终止
    if check_openlist_status; then
        echo "❌ 停止失败"
        exit 1
    else
        echo "✅ 停止成功"
        update_module_prop_stopped
    fi
else
    # 服务未运行：执行启动
    echo "正在启动 OpenList 服务..."
    if [ -f "$SERVICE_SH" ]; then
        sh "$SERVICE_SH"
        sleep 1  # 等待服务启动
        if check_openlist_status; then
            echo "✅ 启动成功"
        else
            echo "❌ 启动失败"
            exit 1
        fi
    else
        echo "❌ service.sh 不存在"
        exit 1
    fi
fi
