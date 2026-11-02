#!/system/bin/sh
# shellcheck shell=ash
# service.sh for OpenList Magisk Module

MODDIR="${0%/*}"
DATA_DIR="${DATA_DIR:-__PLACEHOLDER_DATA_DIR__}"
OPENLIST_BINARY="${OPENLIST_BINARY:-__PLACEHOLDER_BINARY_PATH__}"
MODULE_PROP_FILE="${MODULE_PROP_FILE:-$MODDIR/module.prop}"
LOG_FILE="${LOG_FILE:-$MODDIR/service.log}"
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

update_module_prop_running() {
    # 异步执行 IP 和端口获取
    get_lan_ip &
    IP_PID=$!
    pid=$(pgrep -f "$OPENLIST_BINARY server --data" 2>/dev/null | head -n 1)
    if [ -z "$pid" ]; then
        log "错误: 未找到运行中的 openlist"
        NEW_DESC="description=【未运行】无法找到 openlist 进程，请检查日志 $LOG_FILE"
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
        DETECTED_PORT="$port"

        PASSWORD_TEXT=""
        if [ -f "${DATA_DIR}/初始密码.txt" ]; then
            PASSWORD_TEXT=" | 初始密码：$(cat "${DATA_DIR}/初始密码.txt")"
        fi

        if [ -n "$port" ] && [ "$CURRENT_IP" != "无法获取IP" ]; then
            NEW_DESC="description=【运行中】当前地址：http://${CURRENT_IP}:${port} | PID:$pid | 数据目录：${DATA_DIR} | 点击▲操作关闭程序${PASSWORD_TEXT}"
        else
            log "错误: IP 或端口获取失败 (IP: $CURRENT_IP, 端口: $port)"
            NEW_DESC="description=【运行中】无法检测 openlist 地址（IP: $CURRENT_IP, 端口: $port，PID:$pid），请检查日志 $LOG_FILE | 数据目录：${DATA_DIR} | 点击▲操作关闭程序${PASSWORD_TEXT}"
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

extract_openlist_token() {
    local db_file="$DATA_DIR/data.db"
    [ ! -f "$db_file" ] && return 0

    local token=""
    # 方法 1：若存在 sqlite3 命令则直接查询 x_setting_items
    if command -v sqlite3 >/dev/null 2>&1; then
        token=$(sqlite3 "$db_file" "SELECT value FROM x_setting_items WHERE key='token' LIMIT 1;" 2>/dev/null)
    fi

    local token_regex='(openlist|alist)-[A-Za-z0-9._-]{20,}'

    # 方法 2：纯二进制/字符串正则兜底（免 sqlite3 依赖，兼容所有 Android 固件）
    if [ -z "$token" ]; then
        token=$(grep -aoE "$token_regex" "$db_file" 2>/dev/null | head -n 1)
    fi
    if [ -z "$token" ] && command -v strings >/dev/null 2>&1; then
        token=$(strings "$db_file" 2>/dev/null | grep -oE "$token_regex" | head -n 1)
    fi
    if [ -z "$token" ]; then
        token=$(tr -cd '[:print:]\n' < "$db_file" 2>/dev/null | grep -oE "$token_regex" | head -n 1)
    fi

    # SQLite 二进制页面中，x_setting_items 表里 value 紧跟 type='string'，纯二进制抽取会贪婪带出尾部 string
    token=$(echo "$token" | tr -d '\r' | sed 's/string$//')

    echo "$token"
}

sync_companion_apk_and_config() {
    local target_port="${1:-${DETECTED_PORT:-5244}}"
    [ -z "$target_port" ] && target_port="5244"

    # 1. 确保伴侣 APK (io.openlist.helper) 已安装
    local helper_apk="$MODDIR/system/app/OpenListHelper/OpenListHelper.apk"
    if [ -f "$helper_apk" ] && command -v pm >/dev/null 2>&1; then
        if ! pm path io.openlist.helper >/dev/null 2>&1; then
            log "伴侣应用未安装，尝试后台安装: $helper_apk"
            pm install -r "$helper_apk" >/dev/null 2>&1 || log "警告: pm install 伴侣应用失败"
        fi
    fi

    # 2. 确保 $DATA_DIR/offline.conf 存在，若不存在则使用预设配置创建
    local conf_file="$DATA_DIR/offline.conf"
    if [ ! -f "$conf_file" ]; then
        cat > "$conf_file" << 'EOF'
# OpenList 115 离线下载伴侣配置
HOST=127.0.0.1
PORT=5244
TOKEN=
PATH=/115/影视/
TOOL=115 Open
DELETE_POLICY=delete_on_upload_succeed
PRESET_PATHS=/115/影视/,/115/
EOF
        chmod 644 "$conf_file" 2>/dev/null || true
    fi

    # 补充缺失的核心配置项（平滑升级，保留用户已有自定义）
    grep -q '^HOST=' "$conf_file" || echo "HOST=127.0.0.1" >> "$conf_file"
    grep -q '^PORT=' "$conf_file" || echo "PORT=${target_port}" >> "$conf_file"
    grep -q '^TOKEN=' "$conf_file" || echo "TOKEN=" >> "$conf_file"
    grep -q '^PATH=' "$conf_file" || echo "PATH=/115/影视/" >> "$conf_file"
    grep -q '^TOOL=' "$conf_file" || echo "TOOL=115 Open" >> "$conf_file"
    grep -q '^DELETE_POLICY=' "$conf_file" || echo "DELETE_POLICY=delete_on_upload_succeed" >> "$conf_file"
    grep -q '^PRESET_PATHS=' "$conf_file" || echo "PRESET_PATHS=/115/影视/,/115/" >> "$conf_file"

    # 3. 更新 PORT 为当前检测到的运行端口
    sed -i "s|^PORT=.*|PORT=${target_port}|" "$conf_file"

    # 4. 若 TOKEN 为空或以 string 结尾（历史提取 Bug 导致），从 data.db 提取或清洗并更新
    local current_token
    current_token=$(grep -E '^TOKEN=' "$conf_file" | head -n 1 | cut -d'=' -f2- | tr -d '\r' | sed 's/string$//')

    local token_needs_update=0
    if [ -z "$current_token" ]; then
        token_needs_update=1
    elif grep -E '^TOKEN=' "$conf_file" | head -n 1 | tr -d '\r' | grep -qE 'string$'; then
        token_needs_update=1
        sed -i "s|^TOKEN=.*|TOKEN=${current_token}|" "$conf_file"
        log "已从 offline.conf 中清理历史残留的 string 后缀"
    fi

    if [ "$token_needs_update" -eq 1 ]; then
        local extracted_token=""
        local retry_max="${TOKEN_RETRY_MAX:-5}"
        local retry_count=0
        while [ "$retry_count" -lt "$retry_max" ]; do
            extracted_token=$(extract_openlist_token 2>/dev/null || true)
            [ -n "$extracted_token" ] && break
            retry_count=$((retry_count + 1))
            if [ "$retry_count" -lt "$retry_max" ]; then
                if [ -z "${TOKEN_RETRY_MAX:-}" ]; then
                    sleep 1
                fi
            fi
        done
        if [ -n "$extracted_token" ]; then
            if [ "$extracted_token" != "$current_token" ] || [ -z "$current_token" ]; then
                sed -i "s|^TOKEN=.*|TOKEN=${extracted_token}|" "$conf_file"
                log "已自动从 data.db 提取 Token 并更新 offline.conf"
            fi
        fi
    fi

    # 5. 桥接 offline.conf 至公共临时目录供免权限读取
    local bridge_tmp="${BRIDGE_TMP_CONF:-/data/local/tmp/openlist_offline.conf}"
    cp -f "$conf_file" "$bridge_tmp" 2>/dev/null || true
    chmod 644 "$bridge_tmp" 2>/dev/null || true
    chcon u:object_r:shell_data_file:s0 "$bridge_tmp" 2>/dev/null || true

    # 6. 桥接 offline.conf 至伴侣应用私有目录
    local helper_pkg_dir="${HELPER_DATA_DIR:-/data/data/io.openlist.helper}"
    if [ -d "$helper_pkg_dir" ]; then
        local helper_files_dir="$helper_pkg_dir/files"
        mkdir -p "$helper_files_dir" 2>/dev/null || true
        cp -f "$conf_file" "$helper_files_dir/offline.conf" 2>/dev/null || true
        local owner_ug
        owner_ug=$(stat -c %u:%g "$helper_pkg_dir" 2>/dev/null)
        if [ -n "$owner_ug" ]; then
            chown "$owner_ug" "$helper_files_dir" "$helper_files_dir/offline.conf" 2>/dev/null || true
        fi
        chmod 700 "$helper_files_dir" 2>/dev/null || true
        chmod 600 "$helper_files_dir/offline.conf" 2>/dev/null || true
        restorecon -R "$helper_files_dir" 2>/dev/null || true
    fi
}

reload_openlist_storages() {
    local port="${1:-${DETECTED_PORT:-5244}}"
    [ -z "$port" ] && port="5244"
    local conf_file="$DATA_DIR/offline.conf"
    local token=""
    if [ -f "$conf_file" ]; then
        token=$(grep -E '^TOKEN=' "$conf_file" | head -n 1 | cut -d'=' -f2- | tr -d '\r' | sed 's/string$//')
    fi
    if [ -z "$token" ]; then
        token=$(extract_openlist_token 2>/dev/null || true)
    fi

    if [ -z "$token" ]; then
        log "提示: 未获取到有效 Token，跳过开机存储自动重载"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log "提示: 未找到 curl 或 wget，跳过开机存储自动重载"
        return 0
    fi

    # 延迟待网络与 DNS 就绪后异步重载全部存储驱动 (例如 115 Open、GoogleDrive 等在开机无网时初始化失败的云存储)
    (
        delay="${RELOAD_DELAY:-3}"
        if [ "$delay" -gt 0 ] 2>/dev/null; then
            sleep "$delay"
        fi
        url="http://127.0.0.1:${port}/api/admin/storage/load_all"
        if command -v curl >/dev/null 2>&1; then
            log "已触发 OpenList 存储重载 (POST $url via curl)"
            curl -s -m 10 -X POST -H "Authorization: ${token}" "$url" >/dev/null 2>&1
        elif command -v wget >/dev/null 2>&1; then
            log "已触发 OpenList 存储重载 (POST $url via wget)"
            wget -q -T 10 -O /dev/null --header="Authorization: ${token}" --post-data="" "$url" >/dev/null 2>&1
        fi
    ) &
}

main() {
    log "启动 service.sh 于 $(date '+%Y-%m-%d %H:%M:%S')"

    if ! command -v ip >/dev/null; then
        log "错误: 未找到 ip 命令"
        exit 1
    fi

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

    ELAPSED=0
    MAX_WAIT=60
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

    log "启动 OpenList: $OPENLIST_BINARY server --data $DATA_DIR"
    $OPENLIST_BINARY server --data "$DATA_DIR" &
    OPENLIST_PID=$!

    if ps -p $OPENLIST_PID >/dev/null || pgrep -f "$OPENLIST_BINARY server --data" >/dev/null; then
        log "OpenList 服务启动成功 (PID: $OPENLIST_PID)"
        update_module_prop_running
        sync_companion_apk_and_config "$DETECTED_PORT"
        reload_openlist_storages "$DETECTED_PORT"
    else
        log "错误: 无法启动 OpenList 服务"
        OUTPUT=$($OPENLIST_BINARY server --data "$DATA_DIR" 2>&1)
        log "手动运行输出: $OUTPUT"
        exit 1
    fi
}

if [ "${0##*/}" = "service.sh" ]; then
    main "$@"
fi
