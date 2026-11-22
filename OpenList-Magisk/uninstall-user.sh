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

# 从 service.sh 读取安装/迁移后的实际路径
get_service_var() {
    sed -n "s/^$1=\"\\(.*\\)\"/\\1/p" "$MODROOT/service.sh" 2>/dev/null | head -n 1
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
    local dyn
    dyn="$(get_service_var OPENLIST_BINARY)"
    case "$dyn" in '$MODDIR'*) dyn="$MODROOT${dyn#\$MODDIR}" ;; esac
    local paths="$dyn /data/adb/openlist/bin/openlist $MODROOT/bin/openlist $MODROOT/system/bin/openlist"
    
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

# 清理数据目录
clean_data() {
    echo "数据清理选项："
    echo "1. 保留数据"
    echo "2. 删除所有数据"
    echo "请选择（输入数字）："
    read -r choice

    case "$choice" in
        1)
            log "已选择保留数据"
            ;;
        2)
            log "开始清理数据目录..."
            local dyn
            dyn="$(get_service_var DATA_DIR)"
            case "$dyn" in '$MODDIR'*) dyn="$MODROOT${dyn#\$MODDIR}" ;; esac
            for dir in "$dyn" "/data/adb/openlist" "/sdcard/Android/openlist"; do
                if [ -d "$dir" ]; then
                    log "正在删除数据目录：$dir"
                    rm -rf "$dir"
                fi
            done
            log "数据目录清理完成"
            ;;
        *)
            log "无效选择，默认保留数据"
            ;;
    esac
}

# 主要卸载流程
main() {
    log "开始卸载 OpenList Magisk 模块..."

    # 停止服务
    stop_service
    
    # 清理二进制文件
    clean_binaries
    
    # 清理数据（用户选择）
    clean_data
    
    log "卸载完成"
    echo "请重启设备以完成卸载"
}

# 执行主函数
main