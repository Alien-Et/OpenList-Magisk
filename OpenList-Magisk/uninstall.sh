# shellcheck shell=ash
# uninstall.sh for OpenList Magisk/KSU Module

#==== 侦探：Magisk or KernelSU ====
if [ -n "$MAGISK_VER" ]; then
    MODROOT="$MODPATH"
elif [ -n "$KSU" ] || [ -n "$KERNELSU" ]; then
    MODROOT="$MODULEROOT"
else
    MODROOT="$MODPATH"  # 兜底，保持旧逻辑
fi
#==== 侦探结束 ====

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 停止服务函数
stop_service() {
    if pgrep -f openlist >/dev/null; then
        log "正在停止 OpenList 服务..."
        pkill -f openlist
        sleep 1
        if pgrep -f openlist >/dev/null; then
            log "警告：无法完全停止 OpenList 服务"
            return 1
        else
            log "OpenList 服务已停止"
            return 0
        fi
    else
        log "OpenList 服务未运行"
        return 0
    fi
}

# 清理二进制文件
clean_binaries() {
    local found=0
    local paths="/data/adb/openlist/bin/openlist $MODROOT/bin/openlist $MODROOT/system/bin/openlist"
    
    for path in $paths; do
        if [ -f "$path" ]; then
            log "正在删除二进制文件：$path"
            rm -f "$path"
            found=1
        fi
    done
    
    if [ $found -eq 0 ]; then
        log "未找到 OpenList 二进制文件"
    fi
}

# 自动清理数据目录
clean_data() {
    log "开始自动清理数据目录..."
    local found=0
    
    # 清理所有可能的数据目录
    for dir in "/data/adb/openlist" "/sdcard/Android/openlist"; do
        if [ -d "$dir" ]; then
            log "正在删除数据目录：$dir"
            rm -rf "$dir"
            found=1
        fi
    done
    
    if [ $found -eq 1 ]; then
        log "数据目录清理完成"
    else
        log "未找到 OpenList 数据目录"
    fi
}

# 清理伴侣应用及临时配置
clean_companion() {
    log "正在清理伴侣应用及离线配置..."
    rm -f /data/local/tmp/openlist_offline.conf 2>/dev/null || true
    rm -f "${SERVICE_D_DIR:-/data/adb/service.d}/openlist_companion_sync.sh" 2>/dev/null || true
    if command -v pm >/dev/null 2>&1; then
        pm disable io.openlist.helper/io.openlist.helper.ProcessTextActivity >/dev/null 2>&1 || true
        pm uninstall io.openlist.helper >/dev/null 2>&1 || true
    fi
}

# 主要卸载流程
main() {
    log "开始卸载 OpenList Magisk 模块..."

    # 停止服务
    stop_service

    # 清理伴侣应用及临时配置
    clean_companion

    # 清理二进制文件
    clean_binaries

    # 自动清理数据目录
    clean_data

    log "卸载完成"
    echo "请重启设备以完成卸载"
}

# 执行主函数（被 source 时不自动运行）
if [ "${0##*/}" = "uninstall.sh" ]; then
    main "$@"
fi
