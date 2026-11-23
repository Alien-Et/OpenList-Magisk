#!/system/bin/sh
# shellcheck shell=ash
# control.sh - OpenList 模块控制脚本
# WebUI / action.sh / 终端共用，避免三套逻辑
#
# 用法:
#   control.sh status
#   control.sh start | stop | restart
#   control.sh check
#   control.sh versions
#   control.sh migrate-core <base64旧目录> <base64新目录>   # 安装期用
#   control.sh mirror-get | mirror-set <base64模式|地址> | mirror-ping | mirror-rank
#   control.sh update [--force] [--asset NAME] [--proxy URL] [--tag vX.Y.Z]
#   control.sh logs [行数]
#   control.sh config-get
#   control.sh config-save <base64(完整 offline.conf)>
#   control.sh passwd <base64(新密码)>
#   control.sh migrate-data <base64(新目录)>
#   control.sh migrate-bin  <base64(新路径)>
#   control.sh fetch-bin <arm64|arm|amd64|386> [vX.Y.Z]   # 安装期用：包内没有二进制时在线取
#   control.sh version
#
# 输出统一为 key=value，一行一个；结束行 result=ok / result=fail

set -u

MODDIR="${0%/*}"
[ -d "$MODDIR" ] || MODDIR="."
MODDIR="$(cd "$MODDIR" 2>/dev/null && pwd)" || MODDIR="/data/adb/modules/openlist"
[ -f "$MODDIR/service.sh" ] || MODDIR="/data/adb/modules/openlist"

SERVICE_SH="$MODDIR/service.sh"
ACTION_SH="$MODDIR/action.sh"
MODULE_PROP="$MODDIR/module.prop"
LOG_FILE="$MODDIR/service.log"
PROGRESS_FILE="${PROGRESS_FILE:-/data/local/tmp/openlist_update.progress}"
TMP_DIR="${TMP_DIR:-/data/local/tmp}"

# GitHub 官方接口：版本列表只走 api.github.com，不再套国内代理（代理不转发 API，反而全是 403）
GH_API="https://api.github.com/repos/OpenListTeam/OpenList"
GH_DL="https://github.com/OpenListTeam/OpenList"
API_URL="$GH_API/releases/latest"
RELEASES_URL="$GH_API/releases?per_page=100"
RELEASES_CACHE="$TMP_DIR/openlist_releases.cache"
# 可选：把 PAT 写进 <模块目录>/.github_token 可把额度从 60 次/小时提到 5000
GH_TOKEN_FILE="$MODDIR/.github_token"
GH_TOKEN="${GH_TOKEN:-}"
if [ -z "$GH_TOKEN" ] && [ -f "$GH_TOKEN_FILE" ]; then
    GH_TOKEN="$(sed -n '1p' "$GH_TOKEN_FILE" 2>/dev/null | tr -d '\r\n ')"
fi
# 下载二进制走 github.com 资源镜像（实测这批对 releases/download 可用，延迟由 mirror-ping 测）
GH_PROXY="${GH_PROXY:-}"
MIRRORS="https://ghfast.top/ https://gh-proxy.com/ https://cdn.gh-proxy.com/ https://gh-proxy.org/ https://ghproxy.cn/ https://slink.ltd/ https://gh.monlor.com/ https://gh.con.sh/ https://ghproxy.cfd/ https://ghproxy.imciel.com/ https://ghp.keleyaa.com/ https://gh.7-s.cn/ https://gh-proxy.net/ https://ghproxy.net/ https://gh.ddlc.top/"
# auto 模式不写死顺序：按实测延迟从快到慢排（结果缓存 30 分钟）
PROXIES=""
# 测速探针：仓库里的 README（不绑某个 release，各镜像都转发 /raw/）
PROBE_URL="$GH_DL/releases/latest/download/md5-android.txt"

# 镜像偏好：auto（直连→镜像依次尝试）/ direct（只直连）/ custom（指定镜像优先，再退回内置列表）
# 配置文件放数据目录，不放模块目录：模块更新会整体替换模块目录
MIRROR_MODE="auto"
MIRROR_URL=""
MIRROR_CONF=""

# 当前生效的镜像前缀：
#   auto   = 按实测延迟从快到慢（缓存 30 分钟，过期自动重测）
#   direct = 不套镜像
#   custom = 指定镜像优先，其余按实测顺序兜底
download_proxies() {
    local ranked
    case "$MIRROR_MODE" in
        direct) return 0 ;;
        custom) [ -n "$MIRROR_URL" ] && printf '%s\n' "$MIRROR_URL" ;;
    esac
    ranked="$(mirror_ranking 2>/dev/null)"
    if [ -n "$ranked" ]; then
        printf '%s\n' $ranked
    else
        printf '%s\n' $MIRRORS
    fi
}

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
# service.sh 里选项 2/3 存的是字面量 $MODDIR/...（安装时用单引号写入，
# 运行时由 service.sh 自己展开）。从文件文本取出后不会二次展开，
# 必须手工替换成真实模块目录，否则 [ -f ] 判定必然失败。
expand_moddir() {
    case "$1" in
        '$MODDIR'*) printf '%s' "$MODDIR${1#\$MODDIR}" ;;
        *) printf '%s' "$1" ;;
    esac
}

DATA_DIR="$(expand_moddir "$(get_var DATA_DIR)")"
OPENLIST_BINARY="$(expand_moddir "$(get_var OPENLIST_BINARY)")"
[ -n "$DATA_DIR" ] || DATA_DIR="/data/adb/openlist"
[ -n "$OPENLIST_BINARY" ] || OPENLIST_BINARY="$MODDIR/bin/openlist"

# 读取用户选的下载镜像（安装在数据目录里，跟随数据迁移）
MIRROR_CONF="$DATA_DIR/mirror.conf"
MIRROR_RANK="$DATA_DIR/.mirror_rank"
if [ -f "$MIRROR_CONF" ]; then
    _mm="$(sed -n 's/^mode=//p' "$MIRROR_CONF" 2>/dev/null | head -n 1)"
    _mu="$(sed -n 's/^url=//p' "$MIRROR_CONF" 2>/dev/null | head -n 1)"
    case "$_mm" in auto|direct|custom) MIRROR_MODE="$_mm" ;; esac
    [ -n "$_mu" ] && MIRROR_URL="$_mu"
fi

# ---------- token / API ----------
TOKEN_CACHE="${TOKEN_CACHE:-/data/local/tmp/openlist_token.cache}"

json_escape() {
    printf '%s' "$1" | awk 'BEGIN{ORS=""} {
        gsub(/\\/,"\\\\");
        gsub(/"/,"\\\"");
        gsub(/\t/,"\\t");
        gsub(/\r/,"\\r");
        if (NR > 1) printf "\\n";
        printf "%s", $0
    }'
}

sed_escape() { printf '%s' "$1" | sed -e 's/[&\\|]/\\&/g'; }
sed_pattern_escape() { printf '%s' "$1" | sed -e 's/[.[\*^$]/\\&/g'; }

get_token() {
    local t="" now ts
    if [ -f "$TOKEN_CACHE" ]; then
        now="$(date +%s 2>/dev/null || echo 0)"
        ts="$(sed -n 's/^ts=//p' "$TOKEN_CACHE" 2>/dev/null | head -n 1)"
        if [ -n "$ts" ] && [ "$((now - ts))" -lt 120 ] 2>/dev/null; then
            t="$(sed -n 's/^token=//p' "$TOKEN_CACHE" 2>/dev/null | head -n 1)"
        fi
    fi
    [ -n "$t" ] && { printf '%s' "$t"; return 0; }

    if [ -x "$OPENLIST_BINARY" ]; then
        t="$("$OPENLIST_BINARY" admin token --data "$DATA_DIR" 2>/dev/null | sed -n 's/^Admin token: //p' | head -n 1)"
    fi
    [ -z "$t" ] && t="$(sed -n 's/^TOKEN=//p' "$DATA_DIR/offline.conf" 2>/dev/null | head -n 1)"
    [ -n "$t" ] || return 1
    { echo "token=$t"; echo "ts=$(date +%s 2>/dev/null || echo 0)"; } > "$TOKEN_CACHE" 2>/dev/null || true
    chmod 600 "$TOKEN_CACHE" 2>/dev/null || true
    printf '%s' "$t"
}

# ---------- 网络 ----------
http_get() { # url [timeout]
    local t="${2:-20}"
    if have curl; then curl -fsSL -m "$t" "$1" 2>/dev/null && return 0; fi
    if [ -n "$BB" ]; then "$BB" wget -q -T "$t" -O - "$1" 2>/dev/null && return 0; fi
    if have wget; then wget -q -T "$t" -O - "$1" 2>/dev/null && return 0; fi
    return 1
}

# GitHub 官方 API 请求：body 落文件，stdout 回 HTTP 码（拿不到码时为 000）
# 用 -o/-O 而不是管道，才能同时拿到状态码和响应体；4xx 也保留 body 用于判断限流
gh_api() { # url outfile
    local url="$1" out="$2" code=""
    : > "$out" 2>/dev/null
    if have curl; then
        if [ -n "$GH_TOKEN" ]; then
            code="$(curl -sSL --compressed --connect-timeout 8 -m 20 -o "$out" -w '%{http_code}' \
                -H "User-Agent: OpenList-Magisk" -H "Accept: application/vnd.github+json" \
                -H "Authorization: Bearer $GH_TOKEN" "$url" 2>/dev/null)" || code=""
        else
            code="$(curl -sSL --compressed --connect-timeout 8 -m 20 -o "$out" -w '%{http_code}' \
                -H "User-Agent: OpenList-Magisk" -H "Accept: application/vnd.github+json" \
                "$url" 2>/dev/null)" || code=""
        fi
    elif [ -n "$BB" ]; then
        if [ -n "$GH_TOKEN" ]; then
            "$BB" wget -q -T 30 -O "$out" --header="User-Agent: OpenList-Magisk" \
                --header="Accept: application/vnd.github+json" \
                --header="Authorization: Bearer $GH_TOKEN" "$url" 2>/dev/null && code="200"
        else
            "$BB" wget -q -T 30 -O "$out" --header="User-Agent: OpenList-Magisk" \
                --header="Accept: application/vnd.github+json" "$url" 2>/dev/null && code="200"
        fi
    elif have wget; then
        wget -q -T 30 -O "$out" --header="User-Agent: OpenList-Magisk" "$url" 2>/dev/null && code="200"
    fi
    [ -n "$code" ] || code="000"
    printf '%s' "$code"
}

# 把 HTTP 码翻译成人话（限流要能和"没网"区分开）
gh_api_error() { # code bodyfile
    case "$1" in
        403|429)
            if grep -qi 'rate limit' "$2" 2>/dev/null; then
                printf 'GitHub API 限流（未认证 60 次/小时）。稍后重试，或在 %s 写入 token 提高到 5000' "$GH_TOKEN_FILE"
            else
                printf 'GitHub API 拒绝访问（HTTP %s）' "$1"
            fi
            ;;
        401) printf 'GitHub Token 无效或过期（HTTP 401），检查 %s' "$GH_TOKEN_FILE" ;;
        404) printf 'GitHub 上找不到该 release（HTTP 404）' ;;
        000) printf '无法访问 GitHub API（网络不通或超时）' ;;
        *) printf 'GitHub API 返回异常（HTTP %s）' "$1" ;;
    esac
}

# 缓存列表里的最新版本（列表按 GitHub 顺序，第一条就是最新）
cache_latest_tag() {
    sed -n 's/^item=//p' "$RELEASES_CACHE" 2>/dev/null | head -n 1 | cut -d'|' -f1
}

# ---------- 下载镜像偏好 ----------
# 并发测速：输出 <url>|<ms>|<code>，ms 为空表示不可达
probe_mirrors() {
    local d i=0 p r code ms
    d="$TMP_DIR/.mirror_probe.$$"
    rm -rf "$d" 2>/dev/null
    mkdir -p "$d" 2>/dev/null || return 1
    if have curl; then
        for p in $MIRRORS; do
            i=$((i + 1))
            ( r="$(curl -sL -r 0-512 -o /dev/null --connect-timeout 5 -m 8 -w '%{http_code} %{time_total}' "${p}${PROBE_URL}" 2>/dev/null)"
              printf '%s' "$r" > "$d/$i" 2>/dev/null ) &
        done
        wait
    fi
    i=0
    for p in $MIRRORS; do
        i=$((i + 1))
        code=""
        ms=""
        [ -f "$d/$i" ] && read -r code ms < "$d/$i" 2>/dev/null
        case "$code" in
            200|206) ms="$(awk -v t="${ms:-0}" 'BEGIN{printf "%d", t * 1000}')" ;;
            # 3xx 说明镜像本身响应正常，只是多跳一次，也算可达
            301|302|303|307|308) ms="$(awk -v t="${ms:-0}" 'BEGIN{printf "%d", t * 1000}')" ;;
            *) ms=""; code="${code:-000}" ;;
        esac
        echo "$p|$ms|${code:-000}"
    done
    rm -rf "$d" 2>/dev/null
}

# 按实测延迟从快到慢（只含可达的）；缓存 30 分钟，过期自动重测
mirror_ranking() {
    local now ts
    # 安装期取二进制不做测速：15 个镜像并发探测要 8 秒，
    # 安装界面停在那儿不动比慢一点更难受，直接按内置顺序试
    if [ "${NO_RANK:-0}" = "1" ]; then
        printf '%s\n' $MIRRORS
        return 0
    fi
    now="$(date +%s 2>/dev/null || echo 0)"
    if [ -f "$MIRROR_RANK" ]; then
        ts="$(sed -n 's/^ts=//p' "$MIRROR_RANK" 2>/dev/null | head -n 1)"
        if [ -n "$ts" ] && [ "$((now - ts))" -lt 1800 ] 2>/dev/null; then
            sed -n 's/^m=//p' "$MIRROR_RANK" 2>/dev/null | sort -n | awk '{print $2}'
            return 0
        fi
    fi
    cmd_mirror_ping >/dev/null 2>&1
    sed -n 's/^m=//p' "$MIRROR_RANK" 2>/dev/null | sort -n | awk '{print $2}'
}

cmd_mirror_get() {
    kv mode "$MIRROR_MODE"
    kv url "$MIRROR_URL"
    kv list "$MIRRORS"
    kv result ok
}

# 参数：base64("<mode>|<url>")，mode = auto / direct / custom
cmd_mirror_set() {
    local b64="${1:-}" val mode url _host
    [ -n "$b64" ] || fail "缺少参数"
    val="$(echo "$b64" | base64 -d 2>/dev/null)"
    mode="${val%%|*}"
    url="${val#*|}"
    case "$mode" in
        auto|direct)
            url=""
            ;;
        custom)
            case "$url" in
                "") fail "请填写镜像地址" ;;
                http://*|https://*) ;;
                *) url="https://$url" ;;
            esac
            case "$url" in */) ;; *) url="$url/" ;; esac
            case "$url" in
                *" "*|*"|"*|*"\\"*|*"<"*|*">"*|*"\""*|*"["*|*"]"*) fail "地址不合法" ;;
                http://*/|https://*/) ;;
                *) fail "地址不合法（应形如 https://mirror.example/）" ;;
            esac
            # 域名部分必须是 host.domain 形式，挡掉 http://[bad 这类垃圾输入
            _host="${url#*://}"
            _host="${_host%%/*}"
            case "$_host" in
                *.*) ;;
                *) fail "地址不合法（域名缺少点号）" ;;
            esac
            case "$_host" in
                *[!A-Za-z0-9.-]*) fail "地址不合法（域名含非法字符）" ;;
            esac
            ;;
        *) fail "模式不合法" ;;
    esac
    mkdir -p "$(dirname "$MIRROR_CONF")" 2>/dev/null || true
    {
        echo "mode=$mode"
        echo "url=$url"
    } > "$MIRROR_CONF.tmp" 2>/dev/null || fail "写入失败"
    mv -f "$MIRROR_CONF.tmp" "$MIRROR_CONF" 2>/dev/null || fail "写入失败"
    chmod 600 "$MIRROR_CONF" 2>/dev/null || true
    MIRROR_MODE="$mode"
    MIRROR_URL="$url"
    kv mode "$mode"
    kv url "$url"
    kv result ok
}

# 并发测所有镜像，输出 item=<url>|<ms>|<code>，并把可达的按延迟写进排序缓存
cmd_mirror_ping() {
    local now d p ms code
    now="$(date +%s 2>/dev/null || echo 0)"
    d="$TMP_DIR/.mirror_ping_out.$$"
    probe_mirrors > "$d" 2>/dev/null
    mkdir -p "$(dirname "$MIRROR_RANK")" 2>/dev/null || true
    {
        echo "ts=$now"
        while IFS='|' read -r p ms code; do
            case "$ms" in ''|*[!0-9]*) continue ;; esac
            echo "m=$ms $p"
        done < "$d"
    } > "$MIRROR_RANK.tmp" 2>/dev/null && mv -f "$MIRROR_RANK.tmp" "$MIRROR_RANK" 2>/dev/null
    while IFS='|' read -r p ms code; do
        echo "item=$p|$ms|$code"
    done < "$d"
    rm -f "$d" 2>/dev/null
    kv result ok
}

# 从 API JSON 里按出现顺序配对 tag_name / published_at
# 每个 release 对象里 tag_name 在前、published_at 在后，draft 的 published_at 为 null，
# 靠 "新 TAG 覆盖旧 TAG" 自愈，不会像分别过滤再 paste 那样整体错位
parse_releases() {
    sed -e 's/"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\nTAG \1\n/g' \
        -e 's/"published_at"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\nDATE \1\n/g' \
    | awk '
        $1 == "TAG"  { tag = $2 }
        $1 == "DATE" { if (tag != "") { printf "%s|%.10s\n", tag, $2; tag = "" } }
      '
}

http_download() { # url out
    local url="$1" out="$2" p
    rm -f "$out"
    for p in "" "$GH_PROXY" $(download_proxies); do
        if [ -z "$p" ] && [ "${SKIP_DIRECT:-0}" = "1" ]; then continue; fi
        if have curl; then
            if curl -fL --connect-timeout 8 -m 1800 -o "$out" "${p}${url}" 2>/dev/null && [ -s "$out" ]; then
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

# 只探测资产在不在（HEAD），用来区分「版本不存在」和「网络不通」。
# 不做镜像轮询：调用方通常已经有明确的 URL。
url_head_ok() { # url
    local u="$1" code=""
    if have curl; then
        code="$(curl -sIL -o /dev/null -w '%{http_code}' --connect-timeout 6 -m 12 "$u" 2>/dev/null)"
        [ "$code" = "200" ] && return 0
        return 1
    fi
    if [ -n "$BB" ]; then
        "$BB" wget --spider -q -T 12 "$u" 2>/dev/null && return 0
    fi
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

update_desc_stopped() {
    [ -f "$MODULE_PROP" ] || return 0
    sed -i 's|^description=.*|description=【已停止】请点击"操作"启动程序。项目地址：https://github.com/Alien-Et/OpenList-Magisk|' "$MODULE_PROP" 2>/dev/null || true
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
    update_desc_stopped
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
    local f code tag cur msg cached
    f="$TMP_DIR/.latest.$$"
    code="$(gh_api "$API_URL" "$f")"
    if [ "$code" != "200" ]; then
        msg="$(gh_api_error "$code" "$f")"
        kv debug "HTTP $code $(head -c 160 "$f" 2>/dev/null | tr '\n' ' ')"
        rm -f "$f"
        # API 不可达时用缓存里的最新版本兜底
        cached="$(cache_latest_tag)"
        if [ -n "$cached" ]; then
            cur="$(sed -n 's/^version=//p' "$MODULE_PROP" 2>/dev/null | head -n 1)"
            kv current "${cur:-unknown}"
            kv latest "$cached"
            kv asset "$(pick_asset)"
            kv abi "$(getprop ro.product.cpu.abi 2>/dev/null)"
            kv up_to_date "$([ "$cur" = "$cached" ] && echo 1 || echo 0)"
            kv stale 1
            kv error "$msg"
            kv result ok
            return 0
        fi
        fail "$msg"
    fi
    tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n 1)"
    rm -f "$f"
    [ -n "$tag" ] || fail "解析最新版本失败"
    cur="$(sed -n 's/^version=//p' "$MODULE_PROP" 2>/dev/null | head -n 1)"
    kv current "${cur:-unknown}"
    kv latest "$tag"
    kv asset "$(pick_asset)"
    kv abi "$(getprop ro.product.cpu.abi 2>/dev/null)"
    kv up_to_date "$([ "$cur" = "$tag" ] && echo 1 || echo 0)"
    kv result ok
}

# 列出所有 release（含历史），供回退选择。输出 item=版本|发布日期
# 列出所有 release（含历史），供回退选择。输出 item=版本|发布日期
# 只走 GitHub 官方 API：per_page=100 分页翻到底，不再套国内代理，也不再用 HTML 兜底
# 列出所有 release（含历史），供回退选择。输出 item=版本|发布日期
# 只走 GitHub 官方 API：per_page=100 分页翻到底；API 不可达时退回上次成功的结果
cmd_versions() {
    local now ts page code n f list msg
    now="$(date +%s 2>/dev/null || echo 0)"
    ts="$(sed -n 's/^ts=//p' "$RELEASES_CACHE" 2>/dev/null | head -n 1)"
    # 5 分钟内复用缓存，避免反复消耗 GitHub 未认证额度（60 次/小时）
    if [ -f "$RELEASES_CACHE" ] && [ -n "$ts" ] && [ "$((now - ts))" -lt 300 ] 2>/dev/null; then
        sed -n 's/^item=//p' "$RELEASES_CACHE"
        kv result ok
        return 0
    fi

    f="$TMP_DIR/.rel_page.$$"
    list="$TMP_DIR/.rel_items.$$"
    : > "$list" 2>/dev/null
    msg=""

    page=1
    while [ "$page" -le 10 ]; do
        code="$(gh_api "$RELEASES_URL&page=$page" "$f")"
        if [ "$code" != "200" ]; then
            msg="$(gh_api_error "$code" "$f")"
            kv debug "HTTP $code $(head -c 160 "$f" 2>/dev/null | tr '\n' ' ')"
            break
        fi
        # 注意：API 返回是压缩成一行的 JSON，grep -c 只数行数（恒为 1），
        # 必须数出现次数，否则永远不满 100、翻不到第二页
        n="$(grep -o '"tag_name"' "$f" 2>/dev/null | wc -l | tr -d ' ')"
        n="${n:-0}"
        [ "$n" -gt 0 ] || break
        parse_releases < "$f" >> "$list" 2>/dev/null
        # 满页才继续翻，避免多打一次空请求
        [ "$n" -lt 100 ] && break
        page=$((page + 1))
    done
    rm -f "$f"

    if [ -z "$msg" ]; then
        grep -E '^v[0-9]' "$list" > "$list.ok" 2>/dev/null
        if [ -s "$list.ok" ]; then
            {
                echo "ts=$now"
                while IFS= read -r line; do
                    echo "item=$line"
                done < "$list.ok"
            } > "$RELEASES_CACHE.tmp" 2>/dev/null
            mv -f "$RELEASES_CACHE.tmp" "$RELEASES_CACHE" 2>/dev/null || true
            chmod 600 "$RELEASES_CACHE" 2>/dev/null || true
            # 回显本次抓到的列表，而不是再读缓存：缓存写失败也不影响本次结果
            sed -n 's/^item=//p' "$list.ok"
            rm -f "$list" "$list.ok"
            kv result ok
            return 0
        fi
        msg="解析版本列表失败（GitHub 返回里没有可用的 release）"
    fi
    rm -f "$list" "$list.ok"

    # 无代理时 api.github.com 往往不可达：退回上次成功的列表，
    # 至少还能看到版本并点安装（下载走 github.com 镜像）
    if [ -s "$RELEASES_CACHE" ] && grep -q '^item=' "$RELEASES_CACHE" 2>/dev/null; then
        sed -n 's/^item=//p' "$RELEASES_CACHE"
        kv stale 1
        kv error "$msg"
        kv result ok
        return 0
    fi
    fail "$msg"
}

# ---------- 路径体检 ----------
# 列出 3 个二进制位置与 2 个数据目录的实际占用，标出当前使用的那份
cmd_scan() {
    local p sz cur n mt
    for p in /data/adb/openlist/bin/openlist "$MODDIR/bin/openlist" "$MODDIR/system/bin/openlist"; do
        [ -f "$p" ] || continue
        sz="$(stat -c %s "$p" 2>/dev/null || echo 0)"
        cur=0
        [ "$p" = "$OPENLIST_BINARY" ] && cur=1
        echo "item=bin|$p|$sz|$cur"
    done
    for p in /data/adb/openlist /sdcard/Android/openlist; do
        [ -d "$p" ] || continue
        n="$(find "$p" -type f 2>/dev/null | wc -l | tr -d ' ')"
        mt="$(stat -c %y "$p/data.db" 2>/dev/null | cut -c1-16)"
        [ -n "$mt" ] || mt="-"
        cur=0
        [ "$p" = "$DATA_DIR" ] && cur=1
        echo "item=data|$p|$n|$mt|$cur"
    done
    kv current_bin "$OPENLIST_BINARY"
    kv current_data "$DATA_DIR"
    kv result ok
}

# 删除非当前使用的二进制副本
cmd_clean_bins() {
    local p removed=0
    for p in /data/adb/openlist/bin/openlist "$MODDIR/bin/openlist" "$MODDIR/system/bin/openlist"; do
        [ -f "$p" ] || continue
        [ "$p" = "$OPENLIST_BINARY" ] && continue
        rm -f "$p" 2>/dev/null && {
            echo "removed=$p"
            removed=$((removed + 1))
        }
    done
    kv count "$removed"
    kv result ok
}

# 删除指定的数据目录（不能是当前使用的；目录里有二进制时保留 bin）
cmd_delete_data() {
    local b64="${1:-}" dir f
    [ -n "$b64" ] || fail "缺少目录"
    dir="$(echo "$b64" | base64 -d 2>/dev/null)"
    [ -n "$dir" ] || fail "目录解析失败"
    case "$dir" in /data/*|/sdcard/*|/storage/*) ;; *) fail "路径不合法" ;; esac
    [ "$dir" = "$DATA_DIR" ] && fail "不能删除当前正在使用的数据目录"
    [ -d "$dir" ] || fail "目录不存在"

    case "$OPENLIST_BINARY" in
        "$dir"/bin/*)
            for f in "$dir"/* "$dir"/.[!.]*; do
                [ -e "$f" ] || continue
                [ "$f" = "$dir/bin" ] && continue
                rm -rf "$f" 2>/dev/null
            done
            kv kept_bin 1
            ;;
        *)
            rm -rf "$dir" 2>/dev/null || fail "删除失败（权限不足？）"
            ;;
    esac
    kv deleted "$dir"
    kv result ok
}

# 切换数据目录（不搬文件，只改 service.sh 与 config.json 里的绝对路径）
cmd_use_data() {
    local b64="${1:-}" dir old old_esc new_esc was_running=0
    [ -n "$b64" ] || fail "缺少目录"
    dir="$(echo "$b64" | base64 -d 2>/dev/null)"
    [ -n "$dir" ] || fail "目录解析失败"
    case "$dir" in /data/*|/sdcard/*|/storage/*) ;; *) fail "路径不合法" ;; esac
    [ "$dir" = "$DATA_DIR" ] && fail "已经是当前数据目录"
    [ -d "$dir" ] || fail "目录不存在"
    [ -f "$dir/data.db" ] || fail "该目录里没有 data.db，不是有效的数据目录"

    old="$DATA_DIR"
    [ -n "$(openlist_pid)" ] && was_running=1
    [ "$was_running" = "1" ] && cmd_stop >/dev/null 2>&1

    sed -i "s|^DATA_DIR=.*|DATA_DIR=\"$dir\"|" "$SERVICE_SH" || fail "更新 service.sh 失败"
    if [ -f "$dir/config.json" ] && [ "$old" != "$dir" ]; then
        old_esc="$(sed_pattern_escape "$old")"
        new_esc="$(sed_escape "$dir")"
        sed -i "s|\"$old_esc|\"$new_esc|g" "$dir/config.json" 2>/dev/null || true
        kv config_updated 1
    fi
    DATA_DIR="$dir"

    [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
    kv old_data_dir "$old"
    kv data_dir "$dir"
    kv result ok
}

# 更新任务放到独立会话里跑：WebUI 宿主的 exec 一旦返回/超时会把同一进程组的
# 子进程一起收走，长下载就会「更新失败」且没有任何输出。用 setsid + 结果文件，
# 前端轮询 update-status 取结果，exec 单次调用永远只有毫秒级。
UPDATE_RUN_FILE="$TMP_DIR/openlist_update.running"
UPDATE_OUT_FILE="$TMP_DIR/openlist_update.out"
UPDATE_DONE_FILE="$TMP_DIR/openlist_update.done"

update_alive() { # pid
    local state
    [ -n "${1:-}" ] || return 1
    [ -d "/proc/$1" ] || return 1
    state="$(sed -n 's/^State:[[:space:]]*//p' "/proc/$1/status" 2>/dev/null | head -n 1)"
    case "$state" in Z*|"") return 1 ;; esac
    return 0
}

# pid 可能因为 setsid fork 之类对不上，再用 progress 文件新鲜度兜一层
update_running() {
    local pid mtime now
    pid="$(sed -n '1p' "$UPDATE_RUN_FILE" 2>/dev/null | tr -d ' \r\n')"
    update_alive "$pid" && return 0
    if [ -f "$PROGRESS_FILE" ]; then
        mtime="$(stat -c %Y "$PROGRESS_FILE" 2>/dev/null || echo 0)"
        now="$(date +%s 2>/dev/null || echo 0)"
        [ $((now - mtime)) -lt 60 ] 2>/dev/null && return 0
    fi
    return 1
}

cmd_update_bg() {
    local pid="" wrap="" uid=""
    if [ -f "$UPDATE_RUN_FILE" ]; then
        pid="$(sed -n '1p' "$UPDATE_RUN_FILE" 2>/dev/null | tr -d ' \r\n')"
        if update_alive "$pid"; then
            kv running 1
            kv pid "$pid"
            kv result ok
            return 0
        fi
    fi
    rm -f "$UPDATE_OUT_FILE" "$UPDATE_DONE_FILE" "$UPDATE_RUN_FILE" 2>/dev/null
    progress resolve "启动更新任务"
    # 包一层极小的 wrapper：子进程写自己的输出与退出码，父 shell 不用 wait
    uid="$$"
    wrap="$TMP_DIR/.openlist_upd_wrap.$uid"
    cat > "$wrap" <<'EOS'
#!/system/bin/sh
echo $$ > "$UPD_PID"
"$@" > "$UPD_OUT" 2>&1
echo $? > "$UPD_DONE"
rm -f "$0"
EOS
    chmod 755 "$wrap" 2>/dev/null || true
    if have setsid; then
        UPD_OUT="$UPDATE_OUT_FILE" UPD_DONE="$UPDATE_DONE_FILE" UPD_PID="$UPDATE_RUN_FILE" \
            setsid sh "$wrap" sh "$MODDIR/control.sh" update "$@" < /dev/null >/dev/null 2>&1 &
    else
        UPD_OUT="$UPDATE_OUT_FILE" UPD_DONE="$UPDATE_DONE_FILE" UPD_PID="$UPDATE_RUN_FILE" \
            nohup sh "$wrap" sh "$MODDIR/control.sh" update "$@" < /dev/null >/dev/null 2>&1 &
    fi
    sleep 1
    pid="$(sed -n '1p' "$UPDATE_RUN_FILE" 2>/dev/null | tr -d ' \r\n')"
    if [ -z "$pid" ]; then
        rm -f "$wrap" 2>/dev/null
        kv result fail
        kv error "更新任务没能启动（进程未落地），请确认 /data/local/tmp 可写"
        return 1
    fi
    kv running 1
    kv pid "$pid"
    kv result ok
}

cmd_update_status() {
    if [ ! -f "$UPDATE_DONE_FILE" ] && [ ! -f "$UPDATE_RUN_FILE" ]; then
        kv done 1
        kv result fail
        kv error "没有正在进行的更新任务"
        return 0
    fi
    if [ -f "$UPDATE_DONE_FILE" ]; then
        cat "$UPDATE_OUT_FILE" 2>/dev/null
        if ! grep -q '^result=' "$UPDATE_OUT_FILE" 2>/dev/null; then
            kv result fail
            kv error "更新进程异常退出（exit=$(sed -n '1p' "$UPDATE_DONE_FILE" 2>/dev/null)）$(sed -n '1p' "$UPDATE_OUT_FILE" 2>/dev/null)"
        fi
        kv done 1
        rm -f "$UPDATE_DONE_FILE" "$UPDATE_RUN_FILE" "$UPDATE_OUT_FILE" 2>/dev/null
        return 0
    fi
    if [ -f "$UPDATE_RUN_FILE" ]; then
        if ! update_running; then
            # 进程没了但 done 文件还没落：给它一点时间，连续两次都没有才判失败
            sleep 1
            if [ -f "$UPDATE_DONE_FILE" ]; then
                cat "$UPDATE_OUT_FILE" 2>/dev/null
                grep -q '^result=' "$UPDATE_OUT_FILE" 2>/dev/null || { kv result fail; kv error "更新进程异常退出"; }
                kv done 1
                rm -f "$UPDATE_DONE_FILE" "$UPDATE_RUN_FILE" "$UPDATE_OUT_FILE" 2>/dev/null
                return 0
            fi
            kv result fail
            kv error "更新进程已退出但没有结果（可能被系统杀掉），请查看 /data/local/tmp/openlist_update.out"
            kv done 1
            rm -f "$UPDATE_RUN_FILE" 2>/dev/null
            return 0
        fi
    fi
    kv running 1
    if [ -f "$PROGRESS_FILE" ]; then
        kv stage "$(sed -n 's/^stage=//p' "$PROGRESS_FILE" 2>/dev/null | head -n 1)"
        kv detail "$(sed -n 's/^detail=//p' "$PROGRESS_FILE" 2>/dev/null | head -n 1)"
    fi
    kv result ok
}

cmd_update() {
    local force=0 asset="" tag cur url md5url work tgz md5file want got new_ver new_code want_tag="" api code="" jsonf="" msg="" cached="" DL_PID="" DL_RC=0 sz=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1 ;;
            --asset) asset="${2:-}"; shift ;;
            --proxy) GH_PROXY="${2:-}"; shift ;;
            --tag) want_tag="${2:-}"; shift ;;
        esac
        shift
    done
    [ -n "$asset" ] || asset="$(pick_asset)"

    api="$API_URL"
    if [ -n "$want_tag" ]; then
        case "$want_tag" in
            v[0-9]*) ;;
            *) fail "版本号格式不正确（应形如 v4.2.9）" ;;
        esac
        # 指定版本（回退/切换）：release 资产路径是固定的，
        # 完全不需要 API —— 国内直连 api.github.com 经常不通，没必要先撞一次墙
        tag="$want_tag"
        url="$GH_DL/releases/download/$tag/$asset"
        md5url="$GH_DL/releases/download/$tag/md5-android.txt"
        progress resolve "准备 $tag"
        kv api_skipped 1
    else
        progress resolve "获取最新版本"
        jsonf="$TMP_DIR/.upd_api.$$"
        code="$(gh_api "$API_URL" "$jsonf")"
        if [ "$code" = "200" ]; then
            json="$(cat "$jsonf" 2>/dev/null)"
            tag="$(echo "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
            url="$(echo "$json" | tr ',' '\n' | grep -o 'https://[^"]*'"$asset" | head -n 1)"
            md5url="$(echo "$json" | tr ',' '\n' | grep -o 'https://[^"]*md5-android.txt' | head -n 1)"
            kv stale 0
        else
            msg="$(gh_api_error "$code" "$jsonf")"
            kv debug "HTTP $code $(head -c 160 "$jsonf" 2>/dev/null | tr '\n' ' ')"
            # API 不通时用缓存里的最新版本，走固定路径下载
            cached="$(cache_latest_tag)"
            if [ -n "$cached" ]; then
                tag="$cached"
                kv stale 1
                kv note "GitHub API 不可达，按固定路径下载 $tag"
            else
                rm -f "$jsonf"
                fail "$msg"
            fi
        fi
        rm -f "$jsonf"
        [ -n "$tag" ] || fail "解析最新版本失败"
        if [ -z "$url" ]; then
            url="$GH_DL/releases/download/$tag/$asset"
            md5url="$GH_DL/releases/download/$tag/md5-android.txt"
        fi
    fi

    cur="$(sed -n 's/^version=//p' "$MODULE_PROP" 2>/dev/null | head -n 1)"
    if [ "$cur" = "$tag" ] && [ "$force" != "1" ]; then
        kv current "$cur"
        kv latest "$tag"
        kv up_to_date 1
        kv result ok
        return 0
    fi

    work="$TMP_DIR/openlist_update.$$"
    mkdir -p "$work" || fail "无法创建临时目录"
    tgz="$work/$asset"

    progress download "0 MB / $asset"
    # 后台每 2 秒把已下载大小写进 progress 文件，UI 靠轮询它显示进度
    ( while [ ! -f "$work/.dl.done" ]; do
          sz="$(stat -c %s "$tgz" 2>/dev/null || echo 0)"
          echo "stage=download" > "$PROGRESS_FILE" 2>/dev/null
          echo "detail=$((sz / 1048576)) MB / $asset" >> "$PROGRESS_FILE" 2>/dev/null
          sleep 2
      done ) &
    DL_PID=$!
    http_download "$url" "$tgz"
    DL_RC=$?
    : > "$work/.dl.done" 2>/dev/null
    wait "$DL_PID" 2>/dev/null
    [ "$DL_RC" = "0" ] || { rm -rf "$work"; fail "下载失败（直连和代理都不可用）：$url"; }

    # md5 校验：md5 文件缺失则跳过（release 偶发不带），校验值不匹配则中止
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

    if [ -n "$(openlist_pid)" ]; then
        # 启动成功后再同步 module.prop，避免失败时版本号被改花
        case "$tag" in
            v[0-9]*.[0-9]*.[0-9]*)
                new_ver="$tag"
                new_code="$(echo "${tag#v}" | awk -F. '{printf "%d", $1 * 10000 + $2 * 100 + $3}')"
                sed -i "s/^version=.*/version=$new_ver/" "$MODULE_PROP" 2>/dev/null || true
                sed -i "s/^versionCode=.*/versionCode=$new_code/" "$MODULE_PROP" 2>/dev/null || true
                ;;
        esac
        kv previous "$cur"
        kv current "$tag"
        kv asset "$asset"
        kv result ok
    else
        # 启动失败：自动回滚二进制，版本号保持原样
        if [ -f "$OPENLIST_BINARY.bak" ]; then
            cp -f "$OPENLIST_BINARY.bak" "$OPENLIST_BINARY" 2>/dev/null
            chmod 755 "$OPENLIST_BINARY" 2>/dev/null
            cmd_start >/dev/null 2>&1
            kv rolled_back 1
        fi
        kv previous "$cur"
        kv current "$cur"
        kv asset "$asset"
        kv result fail
        kv error "新版本启动失败，已回滚到 $cur"
    fi
}

# ---------- 安装期取二进制 ----------
# customize.sh 在包内没找到对应架构的二进制时调用这里。
# 走 releases/latest/download/ 固定路径：不需要 GitHub API，不消耗额度，也不需要 token。
# 输出：ok=1 / path=<下载到的文件>，失败时 ok=0 并附 error。
cmd_fetch_bin() {
    local arch="${1:-}" ver="${2:-}" asset work url md5url want got rc=0
    case "$arch" in
        arm64|arm|amd64|386) ;;
        *) kv ok 0; kv error "未知架构：${arch:-空}"; kv result fail; return 0 ;;
    esac
    asset="openlist-android-$arch.tar.gz"

    # 版本没指定就用 latest；固定路径对镜像同样有效
    case "$ver" in
        v[0-9]*) url="$GH_DL/releases/download/$ver/$asset"
                 md5url="$GH_DL/releases/download/$ver/md5-android.txt" ;;
        *)       url="$GH_DL/releases/latest/download/$asset"
                 md5url="$GH_DL/releases/latest/download/md5-android.txt" ;;
    esac

    # 传进来的版本可能不是 OpenList 的版本号 —— online 包用的是模块自身的版本
    # （v5.0.0 之类），上游根本没有这个 Release。先用 HEAD 探一下，
    # 免得 15 个镜像逐个 404 白等一分钟，探不到就直接用 latest。
    if [ -n "$ver" ] && ! url_head_ok "$url"; then
        kv note "OpenList 没有 $ver 这个版本，改用 latest"
        kv module_version "$ver"
        ver=""
        url="$GH_DL/releases/latest/download/$asset"
        md5url="$GH_DL/releases/latest/download/md5-android.txt"
    fi

    work="$TMP_DIR/.openlist_fetch.$$"
    rm -rf "$work" 2>/dev/null
    mkdir -p "$work" 2>/dev/null || { kv ok 0; kv error "无法创建临时目录 $work"; kv result fail; return 0; }

    # 安装期不做镜像测速（NO_RANK=1），按内置顺序逐个试，第一个成功就停
    NO_RANK=1
    export NO_RANK
    if ! http_download "$url" "$work/$asset"; then
        rm -rf "$work" 2>/dev/null
        kv ok 0
        kv asset "$asset"
        kv url "$url"
        kv error "下载失败（直连与镜像均不可用）"
        kv result fail
        return 0
    fi

    # md5 校验：上游 md5-android.txt 里有对应行才校验，缺失不阻断
    if http_download "$md5url" "$work/md5.txt" 2>/dev/null; then
        want="$(awk -v f="$asset" '{n=$2; sub(/^\.\//,"",n); if (n==f) {print $1; exit}}' "$work/md5.txt" 2>/dev/null)"
        if [ -n "$want" ]; then
            got="$(md5sum "$work/$asset" 2>/dev/null | awk '{print $1}')"
            if [ "$got" != "$want" ]; then
                rm -rf "$work" 2>/dev/null
                kv ok 0
                kv asset "$asset"
                kv error "md5 校验失败（期望 $want，实际 ${got:-空}）"
                kv result fail
                return 0
            fi
            kv md5_ok 1
        fi
    fi

    tar -xzf "$work/$asset" -C "$work" 2>/dev/null || {
        rm -rf "$work" 2>/dev/null
        kv ok 0; kv asset "$asset"; kv error "解压失败"; kv result fail; return 0
    }
    [ -f "$work/openlist" ] || {
        rm -rf "$work" 2>/dev/null
        kv ok 0; kv asset "$asset"; kv error "压缩包内未找到 openlist"; kv result fail; return 0
    }

    # 留在临时目录给 customize.sh 搬走，不在这里决定落点
    chmod 755 "$work/openlist" 2>/dev/null
    kv ok 1
    kv asset "$asset"
    kv url "$url"
    kv path "$work/openlist"
    kv result ok
}

cmd_logs() {
    local n="${1:-120}" which="${2:-service}" f
    case "$which" in
        openlist|app) f="$MODDIR/openlist.log" ;;
        *) f="$LOG_FILE" ;;
    esac
    tail -n "$n" "$f" 2>/dev/null || echo "(无日志)"
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

# ---------- API 转发 ----------
cmd_api() {
    local method="${1:-GET}" path="${2:-}" b64="${3:-}" token port body
    case "$path" in /api/*) ;; *) fail "非法 API 路径" ;; esac
    case "$method" in GET|POST) ;; *) fail "不支持的方法" ;; esac
    token="$(get_token)" || fail "无法获取 admin token（服务是否在运行？）"
    port="$(detect_port)"
    body=""
    [ -n "$b64" ] && body="$(echo "$b64" | base64 -d 2>/dev/null)"

    if have curl; then
        if [ "$method" = "GET" ]; then
            curl -s -m 20 -H "Authorization: $token" "http://127.0.0.1:$port$path"
        else
            curl -s -m 20 -X POST -H "Authorization: $token" -H "Content-Type: application/json" \
                --data-binary "$body" "http://127.0.0.1:$port$path"
        fi
        return
    fi
    if [ -n "$BB" ]; then
        if [ "$method" = "GET" ]; then
            "$BB" wget -q -T 20 -O - --header="Authorization: $token" "http://127.0.0.1:$port$path"
        else
            "$BB" wget -q -T 20 -O - --header="Authorization: $token" \
                --header="Content-Type: application/json" --post-data="$body" "http://127.0.0.1:$port$path"
        fi
        return
    fi
    fail "需要 curl 或 busybox wget 才能调用 API"
}

# ---------- 密码 ----------
cmd_passwd() { # b64pass [b64user]
    local b64="${1:-}" b64u="${2:-}" p u token port obj new resp was_running=0
    [ -n "$b64" ] || fail "缺少新密码"
    p="$(echo "$b64" | base64 -d 2>/dev/null)"
    [ -n "$p" ] || fail "密码为空或解码失败"
    u=""
    if [ -n "$b64u" ]; then
        u="$(echo "$b64u" | base64 -d 2>/dev/null)"
        echo "$u" | grep -qE '^[A-Za-z0-9_.-]{3,32}$' || fail "用户名不合法"
    fi

    # 优先 API：在线写库，不需要重启
    if token="$(get_token 2>/dev/null)"; then
        port="$(detect_port)"
        if have curl; then
            obj="$(curl -s -m 15 -H "Authorization: $token" "http://127.0.0.1:$port/api/admin/user/get?id=1" 2>/dev/null)"
            # 取出 data 里的 User 对象，避免把 {"code":200,"data":...} 整个提交
            new="$(echo "$obj" | sed -n 's/^.*"data":\({.*}\)[[:space:]]*}$/\1/p')"
            if [ -n "$new" ] && echo "$obj" | grep -q '"code":200'; then
                if [ -n "$u" ]; then
                    new="$(echo "$new" | sed "s|\"username\":\"[^\"]*\"|\"username\":\"$(sed_escape "$(json_escape "$u")")\"|")"
                fi
                new="$(echo "$new" | sed "s|\"password\":\"[^\"]*\"|\"password\":\"$(sed_escape "$(json_escape "$p")")\"|")"
                resp="$(curl -s -m 15 -X POST -H "Authorization: $token" -H "Content-Type: application/json" \
                    --data-binary "$new" "http://127.0.0.1:$port/api/admin/user/update" 2>/dev/null)"
                if echo "$resp" | grep -q '"code":200'; then
                    kv method api
                    kv result ok
                    return 0
                fi
                kv api_error "$(echo "$resp" | head -c 300)"
            fi
        fi
    fi

    # 兜底 CLI：需要停服务
    [ -n "$(openlist_pid)" ] && was_running=1
    if [ "$was_running" = "1" ]; then
        cmd_stop >/dev/null 2>&1
        # 必须等进程真的退出：SQLite 在运行中可能处于写入中途，
        # 复制到一半的 data.db 会导致迁移后打不开
        while [ -n "$(openlist_pid)" ] && [ "$i" -lt 10 ]; do
            sleep 1
            i=$((i + 1))
        done
        if [ -n "$(openlist_pid)" ]; then
            pkill -9 -f "$OPENLIST_BINARY" 2>/dev/null || true
            sleep 1
        fi
    fi
    "$OPENLIST_BINARY" admin set "$p" --data "$DATA_DIR" >/dev/null 2>&1 || {
        [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
        fail "改密失败（API 不可用，CLI 也失败）"
    }
    kv method cli
    if [ -n "$u" ]; then
        if have sqlite3 && [ -f "$DATA_DIR/data.db" ]; then
            sqlite3 "$DATA_DIR/data.db" "UPDATE x_users SET username='$u' WHERE id=1;" 2>/dev/null || true
            kv user_updated 1
        else
            kv user_updated 0
            kv user_hint "无 sqlite3，用户名未改，请用 API 或网页端修改"
        fi
    fi
    [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
    kv result ok
}

# ---------- 迁移 ----------
# 安装期专用：只把数据从旧目录搬到新目录，不碰 service.sh、不启停服务
# 安装时 service.sh 还是模板占位符，重启服务也无从谈起，所以单独一条路径
# 用法: migrate-core <b64旧目录> <b64新目录>
# 输出: stage=/detail= 进度（供安装器轮询），结束给 source_removed / result
cmd_migrate_core() {
    local b64old="${1:-}" b64new="${2:-}" old new extra need avail a b before=0 f
    [ -n "$b64old" ] || fail "缺少源目录"
    [ -n "$b64new" ] || fail "缺少目标目录"
    old="$(printf '%s' "$b64old" | base64 -d 2>/dev/null)"
    new="$(printf '%s' "$b64new" | base64 -d 2>/dev/null)"
    [ -n "$old" ] && [ -n "$new" ] || fail "目录解析失败"
    # 服务正在用这个目录时不能搬：SQLite 可能写到一半，复制出来是坏库
    # 用行首锚定，避免把"命令行里只是提到这个路径"的 shell/编辑器也算进来
    if have pgrep && pgrep -f "^[^ ]*openlist server --data $old" >/dev/null 2>&1; then
        fail "有进程正在使用该目录（openlist server --data $old），请先停止服务"
    fi
    [ -d "$old" ] || fail "源目录不存在：$old"
    [ -f "$old/data.db" ] || fail "源目录里没有 data.db：$old"
    case "$new" in
        /data/*|/sdcard/*|/storage/*) ;;
        *) fail "目标路径不合法" ;;
    esac
    [ "$new" = "$old" ] && fail "源和目标相同"
    case "$new" in "$old"/*) fail "目标不能是源目录的子目录" ;; esac
    case "$old" in "$new"/*) fail "目标不能是源目录的父目录" ;; esac
    case "$MODDIR" in "$old"|"$old"/*) fail "源目录包含模块目录（$old），拒绝删除" ;; esac
    if [ -d "$new" ]; then
        extra="$(ls -A "$new" 2>/dev/null | grep -vx 'bin' | head -n 1)"
        [ -n "$extra" ] && fail "目标目录非空（含 $extra），请先清理"
    fi
    mkdir -p "$new" 2>/dev/null || fail "无法创建目标目录"
    before="$(find "$new" -type f 2>/dev/null | wc -l | tr -d ' ')"

    # 空间检查：拿不到数字（FUSE/异常 df）就跳过，不阻断安装
    need="$(du -sk "$old" 2>/dev/null | awk '{print $1}')"
    avail="$(df -k "$new" 2>/dev/null | awk 'NR==2{print $4}')"
    case "$need" in ''|*[!0-9]*) need="" ;; esac
    case "$avail" in ''|*[!0-9]*) avail="" ;; esac
    if [ -n "$need" ] && [ -n "$avail" ] && [ "$need" -gt "$avail" ]; then
        fail "空间不足：需要 $((need / 1024)) MB，可用 $((avail / 1024)) MB"
    fi

    progress copy "开始复制（约 $(( ${need:-0} / 1024 )) MB）"
    # 按顶层条目推进度：刷机界面没有进度条，至少让用户看到"正在复制哪个"
    for f in "$old"/* "$old"/.[!.]*; do
        [ -e "$f" ] || continue
        # 数据目录里的 bin 不搬：二进制由安装脚本按用户选的选项单独装
        [ "$f" = "$old/bin" ] && continue
        progress copy "正在复制 $(basename "$f")"
        cp -a "$f" "$new/" 2>/dev/null || fail "复制失败：$f"
    done

    progress verify "校验文件数"
    # 源侧统计要排掉不参与迁移的 bin/
    a="$(find "$old" -type f 2>/dev/null | grep -vF "$old/bin/" | wc -l | tr -d ' ')"
    b="$(find "$new" -type f 2>/dev/null | wc -l | tr -d ' ')"
    [ "$a" = "$((b - before))" ] || fail "文件数不一致（源 $a，新增 $((b - before))）"

    progress verify "校验 data.db"
    if have md5sum; then
        a="$(md5sum "$old/data.db" 2>/dev/null | awk '{print $1}')"
        b="$(md5sum "$new/data.db" 2>/dev/null | awk '{print $1}')"
        [ -n "$a" ] && [ "$a" = "$b" ] || fail "data.db 校验失败"
    fi

    # config.json 里是绝对路径（temp_dir / database.db_file / bleve_dir / log.name），
    # 不改写的话，删掉旧目录后 OpenList 会往不存在的路径写，看起来就像数据丢了
    if [ -f "$new/config.json" ]; then
        progress verify "改写 config.json 路径"
        old_esc="$(sed_pattern_escape "$old")"
        new_esc="$(sed_escape "$new")"
        sed -i "s|\"$old_esc|\"$new_esc|g" "$new/config.json" 2>/dev/null || true
        kv config_updated 1
    fi

    progress clean "删除旧目录 $old"
    case "$old" in
        /|/data|/sdcard|/storage) fail "源目录路径异常（$old），未执行删除" ;;
    esac
    rm -rf "$old" 2>/dev/null
    if [ -e "$old" ] && [ -n "$(ls -A "$old" 2>/dev/null)" ]; then
        fail "旧目录未能完全删除（$old），请手动清理"
    fi
    kv source_removed 1
    kv old_data_dir "$old"
    kv new_data_dir "$new"
    kv result ok
}

cmd_migrate_data() {
    local b64="${1:-}" new old was_running=0 a b old_esc new_esc extra before=0 bin_moved=0 target_bin="" old_bin="" i=0
    [ -n "$b64" ] || fail "缺少目标目录"
    new="$(echo "$b64" | base64 -d 2>/dev/null)"
    old="$DATA_DIR"
    case "$new" in
        /data/*|/sdcard/*|/storage/*) ;;
        *) fail "目标路径不合法" ;;
    esac
    [ "$new" = "$DATA_DIR" ] && fail "目标与当前数据目录相同"
    case "$new" in
        "$MODDIR"|"$MODDIR"/*) fail "数据目录不能放在模块目录内" ;;
        "$DATA_DIR"/*) fail "目标不能是当前数据目录的子目录" ;;
    esac
    case "$DATA_DIR" in
        "$new"/*) fail "目标不能是当前数据目录的父目录" ;;
    esac
    if [ -d "$new" ]; then
        # 安装选项 1 会把二进制放在 <数据目录>/bin，所以目标里只有 bin 时仍可用
        extra="$(ls -A "$new" 2>/dev/null | grep -vx 'bin' | head -n 1)"
        [ -n "$extra" ] && fail "目标目录非空（含 $extra）"
    fi
    mkdir -p "$new" 2>/dev/null || fail "无法创建目标目录"
    # 记录目标原有文件数，后面按增量比对，避免把 bin/openlist 算成复制过来的
    before="$(find "$new" -type f 2>/dev/null | wc -l | tr -d ' ')"

    [ -n "$(openlist_pid)" ] && was_running=1
    if [ "$was_running" = "1" ]; then
        cmd_stop >/dev/null 2>&1
        # 必须等进程真的退出：SQLite 在运行中可能处于写入中途，
        # 复制到一半的 data.db 会导致迁移后打不开
        while [ -n "$(openlist_pid)" ] && [ "$i" -lt 10 ]; do
            sleep 1
            i=$((i + 1))
        done
        if [ -n "$(openlist_pid)" ]; then
            pkill -9 -f "$OPENLIST_BINARY" 2>/dev/null || true
            sleep 1
        fi
    fi

    progress copy "$DATA_DIR -> $new"
    cp -a "$DATA_DIR/." "$new/" 2>/dev/null || {
        [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
        fail "复制失败"
    }

    a="$(find "$DATA_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
    b="$(find "$new" -type f 2>/dev/null | wc -l | tr -d ' ')"
    [ "$a" = "$((b - before))" ] || {
        [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
        fail "文件数不一致（源 $a，新增 $((b - before))）"
    }
    if [ -f "$DATA_DIR/data.db" ] && have md5sum; then
        a="$(md5sum "$DATA_DIR/data.db" 2>/dev/null | awk '{print $1}')"
        b="$(md5sum "$new/data.db" 2>/dev/null | awk '{print $1}')"
        [ "$a" = "$b" ] || {
            [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
            fail "data.db 校验失败"
        }
    fi

    # 迁移 = 移动：校验通过后把源目录整个删掉，不留双份
    # 二进制如果住在源目录里（安装选项 1），先搬到模块 bin/ 再删源，否则会把自己删没；
    # 不搬到新数据目录，是因为 /sdcard 上通常不可执行（noexec）
    case "$OPENLIST_BINARY" in
        "$old"/*)
            old_bin="$OPENLIST_BINARY"
            target_bin="$MODDIR/bin/openlist"
            mkdir -p "$MODDIR/bin" 2>/dev/null || {
                [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
                fail "无法创建 $MODDIR/bin"
            }
            if [ -f "$target_bin" ]; then
                if have md5sum && [ "$(md5sum "$OPENLIST_BINARY" 2>/dev/null | awk '{print $1}')" = "$(md5sum "$target_bin" 2>/dev/null | awk '{print $1}')" ]; then
                    rm -f "$OPENLIST_BINARY" 2>/dev/null
                else
                    [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
                    fail "$MODDIR/bin 已存在另一份二进制，请先「迁移二进制」再迁移数据"
                fi
            else
                mv -f "$OPENLIST_BINARY" "$target_bin" 2>/dev/null || {
                    [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
                    fail "源目录内的二进制搬移失败，已中止（数据未删除）"
                }
            fi
            chmod 755 "$target_bin" 2>/dev/null || true
            sed -i "s|^OPENLIST_BINARY=.*|OPENLIST_BINARY=\"$target_bin\"|" "$SERVICE_SH" || fail "更新 service.sh 失败"
            [ -f "$ACTION_SH" ] && sed -i "s|^OPENLIST_BINARY=.*|OPENLIST_BINARY=\"$target_bin\"|" "$ACTION_SH" 2>/dev/null || true
            OPENLIST_BINARY="$target_bin"
            bin_moved=1
            # cp -a 把源 bin/ 里的二进制也一起复制了，删掉这份多余副本（留一份在模块 bin/）
            if [ -f "$new/bin/$(basename "$old_bin")" ]; then
                rm -f "$new/bin/$(basename "$old_bin")" 2>/dev/null
                rmdir "$new/bin" 2>/dev/null || true
            fi
            ;;
    esac

    sed -i "s|^DATA_DIR=.*|DATA_DIR=\"$new\"|" "$SERVICE_SH" || fail "更新 service.sh 失败"

    # config.json 里的 temp_dir / database.db_file / bleve_dir / log.name 都是绝对路径
    if [ -f "$new/config.json" ]; then
        old_esc="$(sed_pattern_escape "$old")"
        new_esc="$(sed_escape "$new")"
        sed -i "s|\"$old_esc|\"$new_esc|g" "$new/config.json" 2>/dev/null || true
        kv config_updated 1
    fi

    # 源目录整删：先挡掉危险路径，删不干净就明确报错，不静默留下双份数据
    case "$old" in
        /|/data|/sdcard|/storage|"$MODDIR"|"$MODDIR"/*)
            [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
            fail "源目录路径异常（$old），未执行删除"
            ;;
    esac
    progress clean "删除源目录 $old"
    rm -rf "$old" 2>/dev/null
    if [ -e "$old" ] && [ -n "$(ls -A "$old" 2>/dev/null)" ]; then
        [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
        fail "源目录未能完全删除（$old），请手动清理"
    fi
    kv source_removed 1
    [ "$bin_moved" = "1" ] && kv bin_moved "$OPENLIST_BINARY"

    DATA_DIR="$new"
    rm -f "$PROGRESS_FILE"

    [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
    kv old_data_dir "$old"
    kv new_data_dir "$new"
    kv result ok
}

cmd_migrate_bin() {
    local b64="${1:-}" new was_running=0 i=0 old_src="" ok=0
    [ -n "$b64" ] || fail "缺少目标路径"
    new="$(echo "$b64" | base64 -d 2>/dev/null)"
    # 运行时 /system/bin 在 Magisk/KernelSU 下是 overlay，写进去重启即丢；
    # 统一映射到模块的 system/bin（真实文件，重启后由模块挂载到 /system/bin）
    case "$new" in
        /system/bin/*) new="$MODDIR/system/bin/${new#/system/bin/}" ;;
    esac
    case "$new" in
        /data/*|"$MODDIR"/system/bin/*) ;;
        *) fail "目标路径不合法（仅支持 /data 或模块 system/bin）" ;;
    esac
    [ "$new" = "$OPENLIST_BINARY" ] && fail "目标与当前路径相同"
    case "$new" in
        "$MODDIR"/webroot/*) fail "不能放进 webroot" ;;
        "$DATA_DIR"/*) fail "二进制不能放在数据目录内" ;;
    esac
    [ -f "$new" ] && fail "目标文件已存在"
    old_src="$OPENLIST_BINARY"

    [ -n "$(openlist_pid)" ] && was_running=1
    if [ "$was_running" = "1" ]; then
        cmd_stop >/dev/null 2>&1
        # 必须等进程真的退出：SQLite 在运行中可能处于写入中途，
        # 复制到一半的 data.db 会导致迁移后打不开
        while [ -n "$(openlist_pid)" ] && [ "$i" -lt 10 ]; do
            sleep 1
            i=$((i + 1))
        done
        if [ -n "$(openlist_pid)" ]; then
            pkill -9 -f "$OPENLIST_BINARY" 2>/dev/null || true
            sleep 1
        fi
    fi

    mkdir -p "$(dirname "$new")" 2>/dev/null || fail "无法创建目标目录"
    cp -f "$OPENLIST_BINARY" "$new" 2>/dev/null || {
        [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
        fail "复制二进制失败"
    }
    chmod 755 "$new" 2>/dev/null || true
    case "$new" in
        "$MODDIR"/system/bin/*) chcon u:object_r:system_file:s0 "$new" 2>/dev/null || true ;;
    esac

    sed -i "s|^OPENLIST_BINARY=.*|OPENLIST_BINARY=\"$new\"|" "$SERVICE_SH" || fail "更新 service.sh 失败"
    [ -f "$ACTION_SH" ] && sed -i "s|^OPENLIST_BINARY=.*|OPENLIST_BINARY=\"$new\"|" "$ACTION_SH" 2>/dev/null || true
    OPENLIST_BINARY="$new"

    # 迁移 = 移动：新副本校验通过后删掉旧二进制，避免同一份程序留两个位置
    if [ -n "$old_src" ] && [ "$old_src" != "$new" ] && [ -f "$old_src" ]; then
        ok=0
        if have md5sum; then
            [ "$(md5sum "$old_src" 2>/dev/null | awk '{print $1}')" = "$(md5sum "$new" 2>/dev/null | awk '{print $1}')" ] && ok=1
        else
            [ "$(stat -c %s "$old_src" 2>/dev/null)" = "$(stat -c %s "$new" 2>/dev/null)" ] && ok=1
        fi
        if [ "$ok" = "1" ]; then
            rm -f "$old_src" 2>/dev/null
            # 旧位置若是 <目录>/bin/xxx，且目录已空，顺手把空 bin 收掉
            case "$(dirname "$old_src")" in
                */bin) rmdir "$(dirname "$old_src")" 2>/dev/null || true ;;
            esac
            kv old_bin_removed "$old_src"
        else
            kv warn "旧二进制与新的不一致，已保留：$old_src"
        fi
    fi

    [ "$was_running" = "1" ] && cmd_start >/dev/null 2>&1
    kv new_bin "$new"
    case "$new" in
        "$MODDIR"/system/bin/*) kv note "已写入模块 system/bin，重启后同样挂载到 /system/bin" ;;
    esac
    kv result ok
}

# ---------- 路径自检/修复 ----------
cmd_fix_paths() {
    local fixed=0 svc_bin act_bin cur_db old_dir
    [ -f "$SERVICE_SH" ] || fail "service.sh 不存在"

    # service.sh 与 action.sh 的二进制路径对齐
    svc_bin="$(get_var OPENLIST_BINARY)"
    if [ -f "$ACTION_SH" ]; then
        act_bin="$(sed -n 's/^OPENLIST_BINARY="\(.*\)"/\1/p' "$ACTION_SH" 2>/dev/null | head -n 1)"
        if [ "$act_bin" != "$svc_bin" ]; then
            sed -i "s|^OPENLIST_BINARY=.*|OPENLIST_BINARY=\"$svc_bin\"|" "$ACTION_SH" 2>/dev/null || true
            kv fixed_action_bin "$svc_bin"
            fixed=1
        fi
    fi

    # config.json 的绝对路径对齐到当前 DATA_DIR
    if [ -f "$DATA_DIR/config.json" ]; then
        cur_db="$(sed -n 's/.*"db_file"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DATA_DIR/config.json" 2>/dev/null | head -n 1)"
        if [ -n "$cur_db" ]; then
            old_dir="$(dirname "$cur_db")"
            case "$cur_db" in
                "$DATA_DIR"/*) ;;
                *)
                    if [ -n "$old_dir" ] && [ "$old_dir" != "$DATA_DIR" ]; then
                        sed -i "s|\"$(sed_pattern_escape "$old_dir")|\"$(sed_escape "$DATA_DIR")|g" "$DATA_DIR/config.json" 2>/dev/null || true
                        kv fixed_config "$old_dir -> $DATA_DIR"
                        fixed=1
                    fi
                    ;;
            esac
        fi
    fi

    kv data_dir "$DATA_DIR"
    kv bin "$OPENLIST_BINARY"
    kv fixed "$fixed"
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
    versions) cmd_versions ;;
    scan) cmd_scan ;;
    clean-bins) cmd_clean_bins ;;
    delete-data) cmd_delete_data "$@" ;;
    use-data) cmd_use_data "$@" ;;
    update) cmd_update "$@" ;;
    update-bg) cmd_update_bg "$@" ;;
    update-status) cmd_update_status ;;
    fetch-bin) cmd_fetch_bin "$@" ;;
    logs) cmd_logs "$@" ;;
    config-get) cmd_config_get ;;
    config-save) cmd_config_save "$@" ;;
    passwd) cmd_passwd "$@" ;;
    token) get_token && echo && kv result ok || fail "无法获取 token" ;;
    api) cmd_api "$@" ;;
    migrate-data) cmd_migrate_data "$@" ;;
    migrate-core) cmd_migrate_core "$@" ;;
    mirror-get) cmd_mirror_get "$@" ;;
    mirror-set) cmd_mirror_set "$@" ;;
    mirror-ping) cmd_mirror_ping "$@" ;;
    mirror-rank) mirror_ranking ;;
    migrate-bin) cmd_migrate_bin "$@" ;;
    fix-paths) cmd_fix_paths ;;
    version)
        kv version "$(sed -n 's/^version=//p' "$MODULE_PROP" 2>/dev/null | head -n 1)"
        kv result ok
        ;;
    *)
        echo "usage: control.sh {status|start|stop|restart|check|versions|update|logs|config-get|config-save|passwd|token|api|migrate-data|migrate-bin|fix-paths|scan|clean-bins|delete-data|use-data|fetch-bin|version}"
        exit 2
        ;;
esac
