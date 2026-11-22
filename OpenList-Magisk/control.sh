#!/system/bin/sh
# shellcheck shell=ash
# control.sh - OpenList 模块控制脚本
# WebUI / action.sh / 终端共用，避免三套逻辑
#
# 用法:
#   control.sh status
#   control.sh start | stop | restart
#   control.sh check
#   control.sh update [--force] [--asset NAME] [--proxy URL]
#   control.sh logs [行数]
#   control.sh config-get
#   control.sh config-save <base64(完整 offline.conf)>
#   control.sh passwd <base64(新密码)>
#   control.sh migrate-data <base64(新目录)>
#   control.sh migrate-bin  <base64(新路径)>
#   control.sh version
#
# 输出统一为 key=value，一行一个；结束行 result=ok / result=fail

set -u

MODDIR="${0%/*}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/openlist"
[ -f "$MODDIR/service.sh" ] || MODDIR="/data/adb/modules/openlist"

SERVICE_SH="$MODDIR/service.sh"
ACTION_SH="$MODDIR/action.sh"
MODULE_PROP="$MODDIR/module.prop"
LOG_FILE="$MODDIR/service.log"
PROGRESS_FILE="${PROGRESS_FILE:-/data/local/tmp/openlist_update.progress}"
TMP_DIR="${TMP_DIR:-/data/local/tmp}"

API_URL="https://api.github.com/repos/OpenListTeam/OpenList/releases/latest"
GH_PROXY="${GH_PROXY:-}"
PROXIES="https://ghfast.top/ https://gh-proxy.com/ https://ghproxy.net/"

# ---------- 基础 ----------
kv() { echo "$1=$2"; }
fail() { kv result fail; kv error "$1"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
progress() {
    echo "stage=$1" > "$PROGRESS_FILE" 2>/dev/null
    [ -n "${2:-}" ] && echo "detail=$2" >> "$PROGRESS_FILE" 2>/dev/null
    return 0
}

find_busybox() {
    for p in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/bin/busybox /system/xbin/busybox /system/bin/busybox; do
        [ -x "$p" ] && { echo "$p"; return 0; }
    done
    command -v busybox 2>/dev/null || true
}
BB="$(find_busybox 2>/dev/null || true)"

get_var() { sed -n "s/^$1=\"\\(.*\\)\"/\\1/p" "$SERVICE_SH" 2>/dev/null | head -n 1; }
DATA_DIR="$(get_var DATA_DIR)"
OPENLIST_BINARY="$(get_var OPENLIST_BINARY)"
[ -n "$DATA_DIR" ] || DATA_DIR="/data/adb/openlist"
[ -n "$OPENLIST_BINARY" ] || OPENLIST_BINARY="$MODDIR/bin/openlist"

# ---------- 网络 ----------
http_get() { # url [timeout]
    local t="${2:-20}"
    if have curl; then curl -fsSL -m "$t" "$1" 2>/dev/null && return 0; fi
    if [ -n "$BB" ]; then "$BB" wget -q -T "$t" -O - "$1" 2>/dev/null && return 0; fi
    if have wget; then wget -q -T "$t" -O - "$1" 2>/dev/null && return 0; fi
    return 1
}

http_download() { # url out
    local url="$1" out="$2" p
    rm -f "$out"
    for p in "" "$GH_PROXY" $PROXIES; do
        if [ -z "$p" ] && [ "${SKIP_DIRECT:-0}" = "1" ]; then continue; fi
        if have curl; then
            if curl -fL --connect-timeout 10 -m 1800 -o "$out" "${p}${url}" 2>/dev/null && [ -s "$out" ]; then
                return 0
            fi
        elif [ -n "$BB" ]; then
            if "$BB" wget -q -T 120 -O "$out" "${p}${url}" 2>/dev/null && [ -s "$out" ]; then
                return 0
            fi
        fi
        rm -f "$out"
    done
    return 1
}

# ---------- 探测 ----------
detect_port() {
    local p=""
    if [ -f "$DATA_DIR/config.json" ]; then
        p="$(sed -n 's/.*"http_port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$DATA_DIR/config.json" | head -n 1)"
    fi
    [ -n "$p" ] && { echo "$p"; return; }

    if have ss; then
        p="$(ss -ltnp 2>/dev/null | grep -i openlist | sed -n 's/.*:\([0-9][0-9]*\)[[:space:]].*/\1/p' | head -n 1)"
    fi
    [ -n "$p" ] && { echo "$p"; return; }
    if have netstat; then
        p="$(netstat -tlnp 2>/dev/null | grep -i openlist | sed -n 's/.*:\([0-9][0-9]*\)[[:space:]].*/\1/p' | head -n 1)"
    fi
    echo "${p:-5244}"
}

detect_ip() {
    local ip=""
    ip="$(sed -n 's/.*http:\/\/\([0-9.]*\):[0-9]*.*/\1/p' "$MODULE_PROP" 2>/dev/null | head -n 1)"
    [ -n "$ip" ] && { echo "$ip"; return; }
    if have ip; then
        ip="$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -n 1)"
    fi
    echo "${ip:-127.0.0.1}"
}

openlist_pid() {
    local pid
    pid="$(pgrep -f "$OPENLIST_BINARY server" 2>/dev/null | head -n 1)"
    [ -n "$pid" ] || pid="$(pgrep -f "openlist server" 2>/dev/null | head -n 1)"
    echo "$pid"
}

# ---------- 命令 ----------
cmd_status() {
    local pid port ip ver
    pid="$(openlist_pid)"
    port="$(detect_port)"
    ip="$(detect_ip)"
    ver="$(sed -n 's/^version=//p' "$MODULE_PROP" 2>/dev/null | head -n 1)"
    kv running "$([ -n "$pid" ] && echo 1 || echo 0)"
    kv pid "${pid:--}"
    kv port "${port:-5244}"
    kv ip "${ip:-127.0.0.1}"
    kv version "${ver:-unknown}"
    kv data_dir "$DATA_DIR"
    kv bin "$OPENLIST_BINARY"
    kv module_dir "$MODDIR"
    kv abi "$(getprop ro.product.cpu.abi 2>/dev/null)"
    kv result ok
}

cmd_stop() {
    local pid i=0
    pid="$(openlist_pid)"
    if [ -n "$pid" ]; then
        pkill -f "$OPENLIST_BINARY" 2>/dev/null || true
        while [ "$i" -lt 10 ] && [ -n "$(openlist_pid)" ]; do
            sleep 0.5
            i=$((i + 1))
        done
        [ -n "$(openlist_pid)" ] && pkill -9 -f "$OPENLIST_BINARY" 2>/dev/null || true
        sleep 0.3
    fi
    kv stopped 1
    kv result ok
}

cmd_start() {
    if [ -n "$(openlist_pid)" ]; then
        kv started 1
        kv pid "$(openlist_pid)"
        kv result ok
        return 0
    fi
    if [ ! -f "$OPENLIST_BINARY" ]; then
        fail "二进制不存在: $OPENLIST_BINARY"
    fi
    if [ ! -x "$OPENLIST_BINARY" ]; then
        chmod 755 "$OPENLIST_BINARY" 2>/dev/null || fail "无法设置执行权限"
    fi
    # service.sh 内部会等待开机完成并后台拉起 openlist，这里放后台避免阻塞
    sh "$SERVICE_SH" >/dev/null 2>&1 &
    local i=0
    while [ "$i" -lt 15 ]; do
        sleep 1
        i=$((i + 1))
        if [ -n "$(openlist_pid)" ]; then
            kv started 1
            kv pid "$(openlist_pid)"
            kv result ok
            return 0
        fi
    done
    kv started 0
    kv result fail
    kv error "启动失败，请查看 service.log"
}

cmd_restart() {
    cmd_stop >/dev/null 2>&1
    cmd_start
}

pick_asset() {
    local abi
    abi="$(getprop ro.product.cpu.abi 2>/dev/null)"
    case "$abi" in
        arm64*) echo "openlist-android-arm64.tar.gz" ;;
        armeabi*|arm*) echo "openlist-android-arm.tar.gz" ;;
        x86_64*) echo "openlist-android-amd64.tar.gz" ;;
        x86*) echo "openlist-android-386.tar.gz" ;;
        *) echo "openlist-android-arm64.tar.gz" ;;
    esac
}

cmd_check() {
    local json tag cur
    json="$(http_get "$API_URL" 30)" || fail "无法访问 GitHub API（检查网络或代理）"
    tag="$(echo "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$tag" ] || fail "解析最新版本失败"
    cur="$(sed -n 's/^version=//p' "$MODULE_PROP" 2>/dev/null | head -n 1)"
    kv current "${cur:-unknown}"
    kv latest "$tag"
    kv asset "$(pick_asset)"
    kv abi "$(getprop ro.product.cpu.abi 2>/dev/null)"
    kv up_to_date "$([ "$cur" = "$tag" ] && echo 1 || echo 0)"
    kv result ok
}

cmd_update() {
    local force=0 asset="" tag cur url md5url work tgz md5file want got
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1 ;;
            --asset) asset="${2:-}"; shift ;;
            --proxy) GH_PROXY="${2:-}"; shift ;;
        esac
        shift
    done
    [ -n "$asset" ] || asset="$(pick_asset)"

    progress resolve "获取最新版本"
    local json
    json="$(http_get "$API_URL" 30)" || fail "无法访问 GitHub API"
    tag="$(echo "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$tag" ] || fail "解析最新版本失败"
    cur="$(sed -n 's/^version=//p' "$MODULE_PROP" 2>/dev/null | head -n 1)"
    if [ "$cur" = "$tag" ] && [ "$force" != "1" ]; then
        kv current "$cur"
        kv latest "$tag"
        kv up_to_date 1
        kv result ok
        return 0
    fi

    url="$(echo "$json" | tr ',' '\n' | grep -o 'https://[^"]*'"$asset" | head -n 1)"
    [ -n "$url" ] || fail "未找到资产: $asset"

    work="$TMP_DIR/openlist_update.$$"
    mkdir -p "$work" || fail "无法创建临时目录"
    tgz="$work/$asset"

    progress download "$asset"
    http_download "$url" "$tgz" || { rm -rf "$work"; fail "下载失败（直连和代理都不可用）"; }

    # md5 校验（失败只提示，不中止：release 的 md5 文件偶发缺失）
    md5url="$(echo "$json" | tr ',' '\n' | grep -o 'https://[^"]*md5-android.txt' | head -n 1)"
    if [ -n "$md5url" ] && http_download "$md5url" "$work/md5.txt"; then
        want="$(awk -v f="$asset" '{n=$2; sub(/^\.\//,"",n); if (n==f) {print $1; exit}}' "$work/md5.txt" 2>/dev/null)"
        if [ -n "$want" ]; then
            got="$(md5sum "$tgz" 2>/dev/null | awk '{print $1}')"
            [ "$got" = "$want" ] || { rm -rf "$work"; fail "md5 校验失败"; }
        fi
    fi

    progress extract
    tar -xzf "$tgz" -C "$work" 2>/dev/null || { rm -rf "$work"; fail "解压失败"; }
    [ -f "$work/openlist" ] || { rm -rf "$work"; fail "压缩包内未找到 openlist"; }

    progress stop
    cmd_stop >/dev/null 2>&1

    progress replace
    mkdir -p "$(dirname "$OPENLIST_BINARY")" 2>/dev/null || true
    [ -f "$OPENLIST_BINARY" ] && cp -f "$OPENLIST_BINARY" "$OPENLIST_BINARY.bak" 2>/dev/null || true
    cp -f "$work/openlist" "$OPENLIST_BINARY.new" || { rm -rf "$work"; fail "复制新二进制失败"; }
    chmod 755 "$OPENLIST_BINARY.new"
    mv -f "$OPENLIST_BINARY.new" "$OPENLIST_BINARY" || { rm -rf "$work"; fail "替换二进制失败"; }
    case "$OPENLIST_BINARY" in
        /system/bin/*) chcon u:object_r:system_file:s0 "$OPENLIST_BINARY" 2>/dev/null || true ;;
    esac

    progress start
    cmd_start >/dev/null 2>&1
    rm -rf "$work"
    rm -f "$PROGRESS_FILE"

    kv previous "$cur"
    kv current "$tag"
    kv asset "$asset"
    if [ -n "$(openlist_pid)" ]; then
        kv result ok
    else
        kv result fail
        kv error "新版本已替换但启动失败，可用 $OPENLIST_BINARY.bak 回滚"
    fi
}

cmd_logs() {
    tail -n "${1:-120}" "$LOG_FILE" 2>/dev/null || echo "(无日志)"
}

# ---------- 配置 ----------
CONF_KEYS="HOST PORT TOKEN PATH TOOL DELETE_POLICY PRESET_PATHS"

cmd_config_get() {
    local f="$DATA_DIR/offline.conf" k v
    for k in $CONF_KEYS; do
        v="$(sed -n "s/^$k=//p" "$f" 2>/dev/null | head -n 1)"
        kv "$k" "$v"
    done
    kv result ok
}

cmd_config_save() {
    local b64="${1:-}" raw tmp k v
    [ -n "$b64" ] || fail "缺少配置内容"
    raw="$TMP_DIR/openlist_conf.$$.raw"
    tmp="$DATA_DIR/offline.conf.tmp"
    echo "$b64" | base64 -d > "$raw" 2>/dev/null || { rm -f "$raw"; fail "base64 解码失败"; }
    : > "$tmp"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in \#*) continue ;; esac
        case "$line" in *=*) ;; *) continue ;; esac
        k="${line%%=*}"
        v="${line#*=}"
        case "$k" in
            HOST|PORT|TOKEN|PATH|TOOL|DELETE_POLICY|PRESET_PATHS) ;;
            *) continue ;;
        esac
        case "$k" in
            PORT)
                echo "$v" | grep -qE '^[0-9]{1,5}$' || { rm -f "$raw" "$tmp"; fail "端口不合法"; }
                [ "$(echo "$v" | awk '{print ($1 >= 1 && $1 <= 65535) ? 1 : 0}')" = "1" ] || {
                    rm -f "$raw" "$tmp"; fail "端口超出范围"
                }
                ;;
            TOKEN) echo "$v" | grep -qE '^[A-Za-z0-9._-]*$' || { rm -f "$raw" "$tmp"; fail "Token 不合法"; } ;;
            HOST) echo "$v" | grep -qE '^[A-Za-z0-9._:-]+$' || { rm -f "$raw" "$tmp"; fail "HOST 不合法"; } ;;
            PATH)
                case "$v" in /*) ;; *) rm -f "$raw" "$tmp"; fail "路径必须以 / 开头" ;; esac
                if echo "$v" | grep -qE "[[:space:]'\"\`\$|&;<>()*?!~\\\\]"; then
                    rm -f "$raw" "$tmp"; fail "路径含非法字符"
                fi
                ;;
            PRESET_PATHS)
                if echo "$v" | grep -qE "[[:space:]'\"\`\$|&;<>()*?!~\\\\]"; then
                    rm -f "$raw" "$tmp"; fail "预设路径含非法字符"
                fi
                ;;
        esac
        echo "$k=$v" >> "$tmp"
    done < "$raw"
    rm -f "$raw"
    mv -f "$tmp" "$DATA_DIR/offline.conf" || fail "写入失败"
    chmod 644 "$DATA_DIR/offline.conf" 2>/dev/null || true
    kv result ok
}

# ---------- 密码 ----------
cmd_passwd() {
    local b64="${1:-}" p was_running=0
    [ -n "$b64" ] || fail "缺少新密码"
    p="$(echo "$b64" | base64 -d 2>/dev/null)"
    [ -n "$p" ] || fail "密码为空或解码失败"

    [ -n "$(openlist_pid)" ] && was_running=1
    [ "$was_running" = "1" ] && cmd_stop >/dev/null 2>&1

    "$OPENLIST_BINARY" admin set "$p" --data "$DATA_DIR" >/dev/null 2>&1 || {
        [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
        fail "改密失败（检查二进制和数据目录）"
    }

    [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
    kv result ok
}

# ---------- 迁移 ----------
cmd_migrate_data() {
    local b64="${1:-}" new old was_running=0 a b
    [ -n "$b64" ] || fail "缺少目标目录"
    new="$(echo "$b64" | base64 -d 2>/dev/null)"
    old="$DATA_DIR"
    case "$new" in
        /data/*|/sdcard/*|/storage/*) ;;
        *) fail "目标路径不合法" ;;
    esac
    [ "$new" = "$DATA_DIR" ] && fail "目标与当前数据目录相同"
    if [ -d "$new" ] && [ -n "$(ls -A "$new" 2>/dev/null)" ]; then
        fail "目标目录非空"
    fi
    mkdir -p "$new" 2>/dev/null || fail "无法创建目标目录"

    [ -n "$(openlist_pid)" ] && was_running=1
    [ "$was_running" = "1" ] && cmd_stop >/dev/null 2>&1

    progress copy "$DATA_DIR -> $new"
    cp -a "$DATA_DIR/." "$new/" 2>/dev/null || {
        [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
        fail "复制失败"
    }

    a="$(find "$DATA_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
    b="$(find "$new" -type f 2>/dev/null | wc -l | tr -d ' ')"
    [ "$a" = "$b" ] || {
        [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
        fail "文件数不一致（$a != $b）"
    }
    if [ -f "$DATA_DIR/data.db" ] && have md5sum; then
        a="$(md5sum "$DATA_DIR/data.db" 2>/dev/null | awk '{print $1}')"
        b="$(md5sum "$new/data.db" 2>/dev/null | awk '{print $1}')"
        [ "$a" = "$b" ] || {
            [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
            fail "data.db 校验失败"
        }
    fi

    sed -i "s|^DATA_DIR=.*|DATA_DIR=\"$new\"|" "$SERVICE_SH" || fail "更新 service.sh 失败"
    DATA_DIR="$new"
    rm -f "$PROGRESS_FILE"

    [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
    kv old_data_dir "$old"
    kv new_data_dir "$new"
    kv result ok
}

cmd_migrate_bin() {
    local b64="${1:-}" new was_running=0
    [ -n "$b64" ] || fail "缺少目标路径"
    new="$(echo "$b64" | base64 -d 2>/dev/null)"
    case "$new" in
        /data/*|/system/bin/*) ;;
        *) fail "目标路径不合法（仅支持 /data 或 /system/bin）" ;;
    esac
    [ "$new" = "$OPENLIST_BINARY" ] && fail "目标与当前路径相同"
    [ -f "$new" ] && fail "目标文件已存在"

    [ -n "$(openlist_pid)" ] && was_running=1
    [ "$was_running" = "1" ] && cmd_stop >/dev/null 2>&1

    mkdir -p "$(dirname "$new")" 2>/dev/null || fail "无法创建目标目录"
    cp -f "$OPENLIST_BINARY" "$new" 2>/dev/null || {
        [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
        fail "复制二进制失败"
    }
    chmod 755 "$new" 2>/dev/null || true
    case "$new" in
        /system/bin/*) chcon u:object_r:system_file:s0 "$new" 2>/dev/null || true ;;
    esac

    sed -i "s|^OPENLIST_BINARY=.*|OPENLIST_BINARY=\"$new\"|" "$SERVICE_SH" || fail "更新 service.sh 失败"
    [ -f "$ACTION_SH" ] && sed -i "s|^OPENLIST_BINARY=.*|OPENLIST_BINARY=\"$new\"|" "$ACTION_SH" 2>/dev/null || true
    OPENLIST_BINARY="$new"

    [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
    kv new_bin "$new"
    kv result ok
}

# ---------- 入口 ----------
cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
    status) cmd_status ;;
    start) cmd_start ;;
    stop) cmd_stop ;;
    restart) cmd_restart ;;
    check) cmd_check ;;
    update) cmd_update "$@" ;;
    logs) cmd_logs "$@" ;;
    config-get) cmd_config_get ;;
    config-save) cmd_config_save "$@" ;;
    passwd) cmd_passwd "$@" ;;
    migrate-data) cmd_migrate_data "$@" ;;
    migrate-bin) cmd_migrate_bin "$@" ;;
    version)
        kv version "$(sed -n 's/^version=//p' "$MODULE_PROP" 2>/dev/null | head -n 1)"
        kv result ok
        ;;
    *)
        echo "usage: control.sh {status|start|stop|restart|check|update|logs|config-get|config-save|passwd|migrate-data|migrate-bin|version}"
        exit 2
        ;;
esac
