#!/system/bin/sh
# shellcheck shell=ash
# service.sh for OpenList Magisk Module

MODDIR="${0%/*}"
# 支持相对路径调用（sh service.sh / sh modpath/service.sh）：统一转成绝对目录，
# 否则 ${0%/*} 会得到 "service.sh" 或 "modpath" 这种相对值，日志/临时文件全部写错位置
[ -d "$MODDIR" ] || MODDIR="."
MODDIR="$(cd "$MODDIR" 2>/dev/null && pwd)" || MODDIR="/data/adb/modules/openlist"
DATA_DIR="__PLACEHOLDER_DATA_DIR__"
OPENLIST_BINARY="__PLACEHOLDER_BINARY_PATH__"
MODULE_PROP_FILE="$MODDIR/module.prop"
LOG_FILE="$MODDIR/service.log"
OPENLIST_LOG="$MODDIR/openlist.log"
TEMP_IP_FILE="$MODDIR/ip_result.tmp"
TEMP_PORT_FILE="$MODDIR/port_result.tmp"

# 查找可用的busybox路径，兼容Magisk和KSU
toast_find_busybox() {
    if [ -x "/data/adb/magisk/busybox" ]; then
        echo "/data/adb/magisk/busybox"
    elif [ -x "/data/adb/ksu/bin/busybox" ]; then
        echo "/data/adb/ksu/bin/busybox"
    elif [ -x "/data/adb/ap/bin/busybox" ]; then
        echo "/data/adb/ap/bin/busybox"
    elif command -v busybox >/dev/null; then
        echo "$(command -v busybox)"
    else
        echo ""
    fi
}

log() {
    # 日志轮转（限制日志文件大小，例如 1MB）
    if [ -f "$LOG_FILE" ] && [ $(stat -c %s "$LOG_FILE" 2>/dev/null) -gt 1048576 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.bak"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 日志文件已轮转" >> "$LOG_FILE"
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

get_lan_ip() {
    # 使用通用的busybox查找函数
    BUSYBOX=$(toast_find_busybox)
    if [ -x "$BUSYBOX" ]; then
        IP_CMD="$BUSYBOX ip"
        IFCONFIG_CMD="$BUSYBOX ifconfig"
        GREP_CMD="$BUSYBOX grep"
        AWK_CMD="$BUSYBOX awk"
        CUT_CMD="$BUSYBOX cut"
        HEAD_CMD="$BUSYBOX head"
    else
        IP_CMD="ip"
        IFCONFIG_CMD="ifconfig"
        GREP_CMD="grep"
        AWK_CMD="awk"
        CUT_CMD="cut"
        HEAD_CMD="head"
        log "警告: BusyBox 未找到，使用系统命令"
    fi

    MAX_RETRY=30
    RETRY_COUNT=0

    while [ $RETRY_COUNT -lt $MAX_RETRY ]; do
        # 首选默认路由的出口地址：能避开 docker / tun 的 172.16-31 虚拟网段
        ip_address=$($IP_CMD route get 1.1.1.1 2>/dev/null | $AWK_CMD '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' | $HEAD_CMD -n 1)
        case "$ip_address" in
            172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) ip_address="" ;;
        esac
        if [ -n "$ip_address" ]; then
            log "成功获取 IP（默认路由）: ip_address=$ip_address (尝试次数: $((RETRY_COUNT + 1)))"
            echo "$ip_address" > "$TEMP_IP_FILE"
            return 0
        fi

        # 新增：检测是否有活跃的Wi-Fi接口（wlan开头且state UP）
        WLAN_INTERFACE=$($IP_CMD link | $GREP_CMD "state UP" | $AWK_CMD '{print $2}' | $CUT_CMD -d: -f1 | $GREP_CMD -E "^wlan" | $HEAD_CMD -n 1)
        
        if [ -z "$WLAN_INTERFACE" ]; then
            # 无活跃Wi-Fi，判定为移动数据环境，返回localhost
            log "未检测到活跃的Wi-Fi连接，使用移动数据模式"
            echo "localhost" > "$TEMP_IP_FILE"
            return 0
        fi

        # 原有逻辑：Wi-Fi已连接，获取局域网IP
        INTERFACE=$($IP_CMD link | $GREP_CMD "state UP" | $AWK_CMD '{print $2}' | $CUT_CMD -d: -f1 | $GREP_CMD -E "wlan|eth|rmnet" | $HEAD_CMD -n 1)
        [ -z "$INTERFACE" ] && INTERFACE="wlan0"
        ip_address=$($IP_CMD addr show $INTERFACE | $GREP_CMD 'inet ' | $AWK_CMD '{print $2}' | $CUT_CMD -d/ -f1)
        if [ -z "$ip_address" ]; then
            ip_address=$($IFCONFIG_CMD $INTERFACE 2>/dev/null | $GREP_CMD "inet addr" | $AWK_CMD '{print $2}' | $CUT_CMD -d: -f2)
        fi
        if [ -n "$ip_address" ] && [ "$ip_address" != "无法获取IP" ]; then
            log "成功获取 IP: ip_address=$ip_address (尝试次数: $((RETRY_COUNT + 1)))"
            echo "$ip_address" > "$TEMP_IP_FILE"
            return 0
        fi
        log "未获取到有效 IP (尝试 $((RETRY_COUNT + 1))/$MAX_RETRY)，1秒后重试"
        sleep 1
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done
    ip_address="无法获取IP"
    log "错误: 获取 IP 超时，ip_address=$ip_address"
    echo "$ip_address" > "$TEMP_IP_FILE"
}

get_port() {
    pid=$1
    # 使用通用的busybox查找函数
    BUSYBOX=$(toast_find_busybox)
    if [ -x "$BUSYBOX" ]; then
        GREP_CMD="$BUSYBOX grep"
        AWK_CMD="$BUSYBOX awk"
        CUT_CMD="$BUSYBOX cut"
        HEAD_CMD="$BUSYBOX head"
    else
        GREP_CMD="grep"
        AWK_CMD="awk"
        CUT_CMD="cut"
        HEAD_CMD="head"
        log "警告: BusyBox 未找到，使用系统命令"
    fi

    MAX_RETRY=30
    RETRY_COUNT=0
    port=""

    while [ $RETRY_COUNT -lt $MAX_RETRY ]; do
        port=$(ss -tulnp 2>/dev/null | $GREP_CMD "$pid" | $AWK_CMD '{print $5}' | $CUT_CMD -d':' -f2 | sort -u | $HEAD_CMD -n 1)
        if [ -z "$port" ] && command -v netstat >/dev/null; then
            port=$(netstat -tulnp 2>/dev/null | $GREP_CMD "$pid" | $AWK_CMD '{print $4}' | $CUT_CMD -d':' -f2 | sort -u | $HEAD_CMD -n 1)
        fi
        if [ -n "$port" ]; then
            log "成功获取 Openlist 端口: $port (尝试次数: $((RETRY_COUNT + 1)))"
            echo "$port" > "$TEMP_PORT_FILE"
            return 0
        fi
        log "未获取到 Openlist 端口 (PID: $pid, 尝试 $((RETRY_COUNT + 1))/$MAX_RETRY)，1秒后重试"
        sleep 1
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done
    log "错误: 获取 Openlist 端口超时 (PID: $pid)"
    echo "" > "$TEMP_PORT_FILE"
}

# module.prop 的 description 里要显示二进制版本号：
# 优先用本次启动已经算出的 BIN_VER，其次读两处 .bin_version
# （模块目录那份每次升级都会丢，数据目录那份能留住）。
desc_ver() {
    local v="${BIN_VER:-}"
    [ -n "$v" ] || v="$(head -n 1 "$MODDIR/.bin_version" 2>/dev/null | tr -d '\r')"
    [ -n "$v" ] || v="$(head -n 1 "$DATA_DIR/.bin_version" 2>/dev/null | tr -d '\r')"
    printf '%s' "${v:-版本未知}"
}

update_module_prop_running() {
    # 异步执行 IP 和端口获取
    get_lan_ip &
    IP_PID=$!
    pid=$(pgrep -f "$OPENLIST_BINARY server --data" 2>/dev/null | head -n 1)
    if [ -z "$pid" ]; then
        log "错误: 未找到运行中的 openlist"
        NEW_DESC="description=【未运行】OpenList $(desc_ver) | 找不到进程，详见 $LOG_FILE"
        # 直接更新 module.prop 并返回
        grep -v '^description=' "$MODULE_PROP_FILE" > "${MODULE_PROP_FILE}.tmp" 2>/dev/null
        echo "$NEW_DESC" >> "${MODULE_PROP_FILE}.tmp"
        mv "${MODULE_PROP_FILE}.tmp" "$MODULE_PROP_FILE" 2>/dev/null
        return 1
    else
        log "找到 Openlist PID: $pid"
        get_port "$pid" &
        PORT_PID=$!
    fi

    # 等待两个后台任务完成或超时
    MAX_WAIT=30
    ELAPSED=0
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        if [ -f "$TEMP_IP_FILE" ] && { [ -f "$TEMP_PORT_FILE" ] || [ -z "$pid" ]; }; then
            log "IP 和端口获取任务完成 (耗时: $ELAPSED 秒)"
            break
        fi
        sleep 1
        ELAPSED=$((ELAPSED + 1))
    done

    # 检查是否超时
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        log "警告: 异步任务超时，强制终止后台任务"
        kill $IP_PID 2>/dev/null
        [ -n "$pid" ] && kill $PORT_PID 2>/dev/null
    fi

    # 读取结果
    CURRENT_IP=$(cat "$TEMP_IP_FILE" 2>/dev/null || echo "无法获取IP")
    rm -f "$TEMP_IP_FILE" 2>/dev/null
    log "最终 IP: $CURRENT_IP"

    if [ -n "$pid" ]; then
        port=$(cat "$TEMP_PORT_FILE" 2>/dev/null || echo "")
        rm -f "$TEMP_PORT_FILE" 2>/dev/null
        log "最终端口: $port"

        if [ -n "$port" ] && [ "$CURRENT_IP" != "无法获取IP" ]; then
            NEW_DESC="description=【运行中】OpenList $(desc_ver) | http://${CURRENT_IP}:${port} | PID:$pid"
        else
            log "错误: IP 或端口获取失败 (IP: $CURRENT_IP, 端口: $port)"
            NEW_DESC="description=【运行中】OpenList $(desc_ver) | 地址未取到（IP:$CURRENT_IP 端口:$port PID:$pid），详见 $LOG_FILE"
        fi
    fi

    # 更新 module.prop
    if [ ! -f "$MODULE_PROP_FILE" ]; then
        log "错误: $MODULE_PROP_FILE 不存在"
        return 1
    fi
    if [ ! -w "$MODULE_PROP_FILE" ]; then
        log "警告: $MODULE_PROP_FILE 不可写，尝试修复权限"
        chmod 644 "$MODULE_PROP_FILE" 2>/dev/null || log "错误: 无法设置 $MODULE_PROP_FILE 的权限"
    fi

    log "更新前的 module.prop 内容: $(cat "$MODULE_PROP_FILE" 2>/dev/null || echo '无法读取 module.prop')"
    grep -v '^description=' "$MODULE_PROP_FILE" > "${MODULE_PROP_FILE}.tmp" 2>/dev/null
    echo "$NEW_DESC" >> "${MODULE_PROP_FILE}.tmp"
    if mv "${MODULE_PROP_FILE}.tmp" "$MODULE_PROP_FILE" 2>/dev/null; then
        log "成功更新 module.prop"
    else
        log "错误: 更新 module.prop 失败"
    fi

    rm -f "${MODULE_PROP_FILE}.bak" "${MODULE_PROP_FILE}.tmp.*" 2>/dev/null
    if grep -vE '^[a-zA-Z_]+=' "$MODULE_PROP_FILE" >/dev/null; then
        log "警告: module.prop 包含无效行，正在清理"
        grep -E '^[a-zA-Z_]+=' "$MODULE_PROP_FILE" > "${MODULE_PROP_FILE}.clean" 2>/dev/null
        mv "${MODULE_PROP_FILE}.clean" "$MODULE_PROP_FILE" 2>/dev/null
        log "清理后的 module.prop 内容: $(cat "$MODULE_PROP_FILE" 2>/dev/null || echo '无法读取 module.prop')"
    fi
}

log "启动 service.sh 于 $(date '+%Y-%m-%d %H:%M:%S')"

# 早期日志：排查"重启后没自动起来"时，先看这两行路径对不对
log "数据目录: $DATA_DIR ；二进制: $OPENLIST_BINARY"

if ! command -v ip >/dev/null; then
    log "警告: 未找到 ip 命令，IP 检测会失败，但服务仍会继续启动"
fi

# 先等启动阶段过去再碰数据目录：
# late_start 阶段 /sdcard(FUSE) 往往还没挂载，数据目录在外部存储时提前 mkdir
# 会直接失败退出，表现出来就是"重启后模块没有自动启动"
ELAPSED=0
MAX_WAIT=120
while [ $ELAPSED -lt $MAX_WAIT ]; do
    if [ "$(getprop sys.boot_completed)" = "1" ]; then
        log "Android 系统启动完成"
        break
    fi
    log "等待 Android 系统启动... ($ELAPSED/$MAX_WAIT 秒)"
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
if [ $ELAPSED -ge $MAX_WAIT ]; then
    log "警告: 系统启动超时，继续尝试启动 openlist"
fi

# 数据目录在外部存储时再单独等它就绪（部分机型 boot_completed 之后 FUSE 才可用）
case "$DATA_DIR" in
    /sdcard/*|/storage/*)
        WAIT_STORAGE=0
        while [ $WAIT_STORAGE -lt 180 ]; do
            if mkdir -p "$DATA_DIR" 2>/dev/null && [ -w "$DATA_DIR" ]; then
                log "外部存储已就绪：$DATA_DIR"
                break
            fi
            log "等待外部存储就绪... ($WAIT_STORAGE/180 秒)"
            sleep 1
            WAIT_STORAGE=$((WAIT_STORAGE + 1))
        done
        if [ $WAIT_STORAGE -ge 180 ]; then
            log "错误: 外部存储 180 秒内仍不可写：$DATA_DIR（/sdcard 可能未挂载）"
            exit 1
        fi
        ;;
esac

if [ ! -f "$OPENLIST_BINARY" ]; then
    log "错误: $OPENLIST_BINARY 不存在"
    exit 1
fi
if [ ! -x "$OPENLIST_BINARY" ]; then
    log "警告: $OPENLIST_BINARY 不可执行，尝试修复"
    chmod 755 "$OPENLIST_BINARY" 2>/dev/null || {
        log "错误: 无法设置 $OPENLIST_BINARY 的执行权限"
        exit 1
    }
fi

mkdir -p "$DATA_DIR" 2>/dev/null
if [ $? -ne 0 ]; then
    log "错误: 无法创建数据目录 $DATA_DIR"
    exit 1
fi
if [ ! -w "$DATA_DIR" ]; then
    log "警告: 数据目录 $DATA_DIR 不可写，尝试修复权限"
    chmod 777 "$DATA_DIR" 2>/dev/null || {
        log "错误: 无法设置 $DATA_DIR 的写权限"
        exit 1
    }
fi
log "已创建或验证数据目录：$DATA_DIR"

log "启动 OpenList: $OPENLIST_BINARY server --data $DATA_DIR"

# 程序自身的 stdout/stderr 落到 openlist.log（1MB 轮转）。
# 这些内容不会进 service.log，但端口占用、驱动加载失败、数据库锁冲突
# 这类只在运行中出现一次的报错只有在这里才看得到。
if [ -f "$OPENLIST_LOG" ] && [ "$(stat -c %s "$OPENLIST_LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$OPENLIST_LOG" "$OPENLIST_LOG.bak" 2>/dev/null
fi

# 不预设 admin 密码：OpenList v4.2.10 起由网页安装向导创建管理员
# （POST /api/public/init/setup），首次打开 http://IP:PORT 会引导设置账号密码。
# 输出落到 openlist.log：WebUI 能看日志，同时避免 service.sh 退出、终端/管道关闭后
# openlist 再往 stderr 写时收到 SIGPIPE 直接退出（PR #38 反馈的问题）
$OPENLIST_BINARY server --data "$DATA_DIR" >> "$OPENLIST_LOG" 2>&1 </dev/null &
OPENLIST_PID=$!

if ps -p $OPENLIST_PID >/dev/null || pgrep -f "$OPENLIST_BINARY server --data" >/dev/null; then
    log "OpenList 服务启动成功 (PID: $OPENLIST_PID)"
    # 记录这份二进制的版本，WebUI 靠它显示「OpenList 版本」和「所有版本」里的「当前」标记。
    # 模块目录每次升级都会被整体替换，所以在数据目录再存一份，升级后不会退化成 unknown。
    # 版本在第 5 行「Version: vX.Y.Z」，第 2 行的 go1.27.3 也是 x.y.z，所以要按行挑
    v_out="$("$OPENLIST_BINARY" version 2>/dev/null | head -n 20)"
    BIN_VER="$(printf '%s\n' "$v_out" | grep -iE '^[[:space:]]*(web)?version[[:space:]]*:' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
    [ -n "$BIN_VER" ] || BIN_VER="$(printf '%s\n' "$v_out" | grep -viE 'go version|built at|commit id|author' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
    if [ -n "$BIN_VER" ]; then
        case "$BIN_VER" in v*) ;; *) BIN_VER="v$BIN_VER" ;; esac
        printf '%s\n' "$BIN_VER" > "$MODDIR/.bin_version" 2>/dev/null || true
        [ -d "$DATA_DIR" ] && printf '%s\n' "$BIN_VER" > "$DATA_DIR/.bin_version" 2>/dev/null || true
        log "二进制版本: $BIN_VER"
    fi
    update_module_prop_running
else
    log "错误: 无法启动 OpenList 服务"
    OUTPUT=$($OPENLIST_BINARY server --data "$DATA_DIR" 2>&1)
    log "手动运行输出: $OUTPUT"
    exit 1
fi
