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
# 架构判定：框架给 $ARCH，部分老框架只给 abi，两处都要看
case "$ARCH" in
    arm64) BIN_ARCH=arm64 ;;
    arm)   BIN_ARCH=arm ;;
    x86_64|amd64) BIN_ARCH=amd64 ;;
    x86|i386|i686) BIN_ARCH=386 ;;
    *)
        case "$DEV_ABI" in
            arm64*)        BIN_ARCH=arm64 ;;
            armeabi*|arm*) BIN_ARCH=arm ;;
            x86_64*)       BIN_ARCH=amd64 ;;
            x86*)          BIN_ARCH=386 ;;
            *) abort "❌ 无法识别的架构：${ARCH:-未知} / ${DEV_ABI:-未知}" ;;
        esac
        ;;
esac
ui_print "🎯 目标架构：$BIN_ARCH"

# 取二进制的四级回退：
#   ① 包内 $MODROOT/openlist-<arch>           （完整包 / 单架构包）
#   ② /sdcard/Download/openlist-android-<arch>.tar.gz  （用户提前放好的离线兜底）
#   ③ control.sh fetch-bin <arch>             （在线下载，复用镜像列表与 md5 校验）
#   ④ 全失败 → abort 并打印手动下载指引
BIN_SRC=""
BIN_FROM=""
MOD_VER=""
FETCH_URL=""

PKG_BIN="$MODROOT/openlist-$BIN_ARCH"
if [ -f "$PKG_BIN" ]; then
    ui_print "📦 使用安装包内置的 $BIN_ARCH 二进制"
    BIN_SRC="$PKG_BIN"
    BIN_FROM="package"
fi

if [ -z "$BIN_SRC" ]; then
    for d in /sdcard/Download /storage/emulated/0/Download /sdcard0/Download; do
        f="$d/openlist-android-$BIN_ARCH.tar.gz"
        [ -f "$f" ] || continue
        ui_print "📂 发现手动放置的压缩包：$f"

        # 上游的包内文件名是 openlist，但自己打的包常常是 openlist-<arch>，
        # 甚至任意名字，所以解压到临时目录后按 ELF 头找，不写死文件名。
        tmpd="$MODROOT/.tarx"
        rm -rf "$tmpd"; mkdir -p "$tmpd" 2>/dev/null

        if tar -xzf "$f" -C "$tmpd" >/dev/null 2>&1; then
            cand=""
            # 先按最常见的一批名字找，找不到再扫一遍
            for n in openlist "openlist-$BIN_ARCH" "openlist-android-$BIN_ARCH"; do
                if [ -f "$tmpd/$n" ]; then
                    cand="$tmpd/$n"
                    break
                fi
            done
            if [ -z "$cand" ]; then
                for n in "$tmpd"/*; do
                    [ -f "$n" ] || continue
                    case "$n" in
                        *.tar.gz|*.tgz|*.zip|*.txt|*.md) continue ;;
                    esac
                    # ELF magic：7f 45 4c 46
                    if [ "$(head -c 4 "$n" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]; then
                        cand="$n"
                        break
                    fi
                done
            fi

            if [ -n "$cand" ] && [ -f "$cand" ]; then
                cp -f "$cand" "$MODROOT/.openlist-fetched"
                chmod 755 "$MODROOT/.openlist-fetched"
                BIN_SRC="$MODROOT/.openlist-fetched"
                BIN_FROM="manual"
                ui_print "✅ 压缩包里找到：${cand##*/}"
                rm -rf "$tmpd"
                break
            fi
        fi

        rm -rf "$tmpd"
        ui_print "⚠️ 解压失败，继续尝试在线下载"
    done
fi

if [ -z "$BIN_SRC" ]; then
    # 二进制版本必须跟模块版本对齐：
    # 只取 latest 会出现「模块 v4.2.10、二进制 v4.2.11」的错配，
    # 出了问题既对不上日志也回不了旧版。这里把 module.prop 的 version 传下去。
    MOD_VER="$(sed -n 's/^version=//p' "$MODROOT/module.prop" 2>/dev/null | head -n 1)"
    case "$MOD_VER" in
        v[0-9]*) ;;
        *) MOD_VER="" ;;   # 取不到就让 control.sh 退回 latest
    esac
    if [ -n "$MOD_VER" ]; then
        ui_print "🌐 安装包内没有 $BIN_ARCH 二进制，开始在线获取（模块 $MOD_VER，约 55 MB）"
    else
        ui_print "🌐 安装包内没有 $BIN_ARCH 二进制，开始在线获取（约 55 MB）"
    fi
    ui_print "   优先取与模块对应的版本，上游没有该版本时自动改用最新版"
    ui_print "   网络慢时请耐心等待，别退出管理器"
    if [ -f "$MODROOT/control.sh" ]; then
        chmod 755 "$MODROOT/control.sh" 2>/dev/null || true
        FETCH_OUT="$MODROOT/.fetch.out"
        sh "$MODROOT/control.sh" fetch-bin "$BIN_ARCH" $MOD_VER > "$FETCH_OUT" 2>&1
        FETCH_OK="$(sed -n 's/^ok=//p' "$FETCH_OUT" 2>/dev/null | head -n 1)"
        BIN_SRC="$(sed -n 's/^path=//p' "$FETCH_OUT" 2>/dev/null | head -n 1)"
        FETCH_ERR="$(sed -n 's/^error=//p' "$FETCH_OUT" 2>/dev/null | head -n 1)"
        FETCH_URL="$(sed -n 's/^url=//p' "$FETCH_OUT" 2>/dev/null | head -n 1)"
        rm -f "$FETCH_OUT" 2>/dev/null
        if [ "$FETCH_OK" = "1" ] && [ -n "$BIN_SRC" ] && [ -f "$BIN_SRC" ]; then
            ui_print "✅ 下载完成"
            BIN_FROM="online"
        else
            ui_print "❌ 在线下载失败：${FETCH_ERR:-未知原因}"
            BIN_SRC=""
        fi
    else
        ui_print "❌ 模块内缺少 control.sh，无法在线下载"
    fi
fi

if [ -z "$BIN_SRC" ]; then
    ui_print " "
    ui_print "━━━━━━━━━━━━━━━━━━━━━━"
    ui_print "❌ 无法获取 $BIN_ARCH 架构的 OpenList 二进制"
    ui_print " "
    ui_print "手动解决："
    ui_print "1. 用浏览器打开下面地址下载"
    if [ -n "$FETCH_URL" ]; then
        ui_print "   $FETCH_URL"
    elif [ -n "$MOD_VER" ]; then
        ui_print "   https://github.com/OpenListTeam/OpenList/releases/download/$MOD_VER/openlist-android-$BIN_ARCH.tar.gz"
    else
        ui_print "   https://github.com/OpenListTeam/OpenList/releases/latest/download/openlist-android-$BIN_ARCH.tar.gz"
    fi
    ui_print "2. 把下载到的文件放进 Download 目录（不要解压）"
    ui_print "3. 重新刷入本模块"
    ui_print "━━━━━━━━━━━━━━━━━━━━━━"
    abort "安装中止：缺少 $BIN_ARCH 二进制"
fi

mv -f "$BIN_SRC" "$BINARY_PATH/$BINARY_NAME" || abort "❌ 二进制安装失败"
# 清掉包里其它架构的二进制，避免模块目录白占空间
for a in arm arm64 amd64 386; do
    [ "$a" = "$BIN_ARCH" ] || rm -f "$MODROOT/openlist-$a" 2>/dev/null
done
rm -f "$MODROOT/.openlist-fetched" 2>/dev/null

chmod 755 "$BINARY_PATH/$BINARY_NAME"

[ "$BINARY_PATH" = "$MODROOT/system/bin" ] && chcon -R u:object_r:system_file:s0 "$BINARY_PATH/$BINARY_NAME"

# 记下这份二进制自己的版本，WebUI 靠它显示「OpenList 版本」。
# online 包的 module.prop version 是模块版本（日期+流水号），跟二进制版本是两个东西。
# 版本号在第 5 行「Version: vX.Y.Z」；第 2 行的 Go Version（go1.27.3）同样形如 x.y.z，
# 之前只取第一行（Built At: …）导致永远解析失败，.bin_version 从来没有写成功过。
v_out="$("$BINARY_PATH/$BINARY_NAME" version 2>/dev/null | head -n 20)"
BIN_VER_NOW="$(printf '%s\n' "$v_out" | grep -iE '^[[:space:]]*(web)?version[[:space:]]*:' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
[ -n "$BIN_VER_NOW" ] || BIN_VER_NOW="$(printf '%s\n' "$v_out" | grep -viE 'go version|built at|commit id|author' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
case "$BIN_VER_NOW" in
    v[0-9]*) ;;
    [0-9]*) BIN_VER_NOW="v$BIN_VER_NOW" ;;
    *) ;;
esac
if [ -n "$BIN_VER_NOW" ]; then
    printf '%s\n' "$BIN_VER_NOW" > "$MODROOT/.bin_version" 2>/dev/null || true
    ui_print "🏷️ OpenList 二进制版本：$BIN_VER_NOW"
else
    rm -f "$MODROOT/.bin_version" 2>/dev/null
fi

case "$BIN_FROM" in
    package) ui_print "✅ 已安装 $BIN_ARCH 二进制（安装包内置）" ;;
    manual)  ui_print "✅ 已安装 $BIN_ARCH 二进制（来自 Download 目录）" ;;
    online)  ui_print "✅ 已安装 $BIN_ARCH 二进制（在线下载）" ;;
esac

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

# ---------- 旧数据检测 + 迁移决策 ----------
# 更新安装时旧模块目录还在（框架先解压到 MODPATH，customize.sh 跑完才覆盖），
# 所以能读到上一版的 DATA_DIR，用来判断"这次选的新目录要不要搬数据"
b64() { printf '%s' "$1" | base64 2>/dev/null | tr -d '\n'; }

OLD_MOD="/data/adb/modules/openlist"
OLD_DATA=""
OLD_BIN_PATH=""
if [ -f "$OLD_MOD/service.sh" ]; then
    OLD_DATA="$(sed -n 's/^DATA_DIR="\(.*\)"/\1/p' "$OLD_MOD/service.sh" 2>/dev/null | head -n 1)"
    case "$OLD_DATA" in
        '$MODDIR'*) OLD_DATA="$OLD_MOD${OLD_DATA#\$MODDIR}" ;;
    esac
    # 数据目录指向模块目录本身属于异常配置，直接不参与迁移（否则会删到模块）
    case "$OLD_DATA" in
        "$OLD_MOD"|"$OLD_MOD"/*) OLD_DATA="" ;;
    esac
    OLD_BIN_PATH="$(sed -n 's/^OPENLIST_BINARY="\(.*\)"/\1/p' "$OLD_MOD/service.sh" 2>/dev/null | head -n 1)"
    case "$OLD_BIN_PATH" in
        '$MODDIR'*) OLD_BIN_PATH="$OLD_MOD${OLD_BIN_PATH#\$MODDIR}" ;;
    esac
fi

MIGRATE=0
if [ -n "$OLD_DATA" ] && [ -d "$OLD_DATA" ] && [ -f "$OLD_DATA/data.db" ] && [ "$OLD_DATA" != "$DATA_DIR" ]; then
    NEED_MB="$(du -sk "$OLD_DATA" 2>/dev/null | awk '{print int($1 / 1024)}')"
    FREE_MB="$(df -k "$DATA_DIR" 2>/dev/null | awk 'NR==2{print int($4 / 1024)}')"
    ui_print " "
    ui_print "📦 检测到旧数据目录：$OLD_DATA"
    ui_print "   占用约 ${NEED_MB:-?} MB，目标可用 ${FREE_MB:-?} MB"
    ui_print "   迁移成功后删除旧目录；任何一步校验不过，旧数据原样保留"
    ui_print "━━━━━━━━━━━━━━━━━━━━━━"
    ui_print "音量+ 迁移到 $DATA_DIR"
    ui_print "音量- 跳过（保留旧数据，装好后可在 WebUI 迁移）"
    ui_print "（90 秒无操作按跳过继续）"
    if [ "$(until_key)" = "up" ]; then
        MIGRATE=1
    fi
fi

# 二进制若装在旧数据目录里（选项 1），先复制一份到模块 bin：
# 复制而不是移动，迁移没成功时旧模块的二进制还在原位
if [ "$MIGRATE" = "1" ]; then
    case "$BINARY_PATH" in
        "$OLD_DATA"/*)
            ui_print "⚠️ 二进制位于旧数据目录内，改放到模块 bin"
            mkdir -p "$MODROOT/bin" 2>/dev/null
            cp -f "$BINARY_PATH/$BINARY_NAME" "$MODROOT/bin/$BINARY_NAME" 2>/dev/null || abort "❌ 二进制复制失败"
            chmod 755 "$MODROOT/bin/$BINARY_NAME" 2>/dev/null
            BINARY_PATH="$MODROOT/bin"
            BINARY_SERVICE_PATH='$MODDIR/bin/openlist'
            ;;
    esac
fi

ui_print " "
ui_print "📢 数据目录设置"
ui_print "━━━━━━━━━━━━━━━━━━━━━━"
ui_print "✓ 已选择: $DATA_DIR"

# 二进制版本在数据目录再存一份：模块目录每次升级都被整体替换，只有数据目录这份能留住，
# 否则升级重启后 WebUI 会显示「OpenList 版本 unknown」、版本列表也没有「当前」标记。
if [ -n "${BIN_VER_NOW:-}" ] && [ -d "$DATA_DIR" ]; then
    printf '%s\n' "$BIN_VER_NOW" > "$DATA_DIR/.bin_version" 2>/dev/null || true
fi

ui_print "ℹ️ 说明："
ui_print "1. 新数据目录在下次启动时生效"
if [ "$MIGRATE" = "1" ]; then
    ui_print "2. 安装最后会迁移旧数据并删除旧目录（失败则中止，旧数据保留）"
else
    ui_print "2. 本次不搬数据；旧数据目录原样保留，可在 WebUI 迁移页搬"
fi
ui_print "3. config.json 里的绝对路径会在迁移时同步"
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

# ---------- 执行数据迁移（放在最后：前面步骤都成功才动旧数据） ----------
if [ "$MIGRATE" = "1" ]; then
    # 旧服务可能还在跑：不先停掉，复制出来的 data.db 可能是写了一半的
    if [ -n "$OLD_BIN_PATH" ] && [ -f "$OLD_BIN_PATH" ] && command -v pgrep >/dev/null 2>&1; then
        OLD_PID="$(pgrep -f "^$OLD_BIN_PATH server" 2>/dev/null | head -n 1)"
        if [ -n "$OLD_PID" ]; then
            ui_print "⏹ 停止运行中的 OpenList（PID $OLD_PID）"
            kill "$OLD_PID" 2>/dev/null
            k=0
            while [ -n "$(pgrep -f "^$OLD_BIN_PATH server" 2>/dev/null)" ] && [ "$k" -lt 10 ]; do
                sleep 1
                k=$((k + 1))
            done
            if [ -n "$(pgrep -f "^$OLD_BIN_PATH server" 2>/dev/null)" ]; then
                pkill -9 -f "^$OLD_BIN_PATH server" 2>/dev/null
                sleep 1
            fi
        fi
    fi

    ui_print "🚚 开始迁移，请勿断电..."
    MIG_PF="$MODROOT/.migrate.progress"
    MIG_LOG="$MODROOT/.migrate.log"
    MIG_DONE="$MODROOT/.migrate.done"
    rm -f "$MIG_PF" "$MIG_LOG" "$MIG_DONE"
    (
        PROGRESS_FILE="$MIG_PF" sh "$MODROOT/control.sh" migrate-core \
            "$(b64 "$OLD_DATA")" "$(b64 "$DATA_DIR")" > "$MIG_LOG" 2>&1
        echo "$?" > "$MIG_DONE"
    ) &
    MIG_PID=$!
    MIG_LAST=""
    # 用 done 文件而不是 kill -0：子进程退出后到 wait 之前仍是僵尸，kill -0 会一直成功
    while [ ! -f "$MIG_DONE" ]; do
        if [ -f "$MIG_PF" ]; then
            MIG_CUR="$(tr '\n' ' ' < "$MIG_PF" 2>/dev/null)"
            if [ -n "$MIG_CUR" ] && [ "$MIG_CUR" != "$MIG_LAST" ]; then
                ui_print "   $MIG_CUR"
                MIG_LAST="$MIG_CUR"
            fi
        fi
        sleep 2
    done
    wait "$MIG_PID" 2>/dev/null
    MIG_RC="$(cat "$MIG_DONE" 2>/dev/null)"
    MIG_RC="${MIG_RC:-1}"
    rm -f "$MIG_DONE" "$MIG_PF"
    if [ "$MIG_RC" -ne 0 ]; then
        ui_print "❌ 迁移失败，旧数据未删除："
        sed -n '1,6p' "$MIG_LOG" 2>/dev/null | while IFS= read -r line; do ui_print "   $line"; done
        abort "安装中止（旧数据完整保留；可重刷本包，或装好后在 WebUI 迁移）"
    fi
    ui_print "✅ 迁移完成，旧目录已删除"
    rm -f "$MIG_LOG"
fi

# ---------- 清理旧安装位置的残留二进制 ----------
# 这次选的安装位置和上次不一样时，旧位置那份二进制就没人管了：
# 既占空间，又可能被 pgrep/旧脚本误启动成第二个实例，所以主动删掉。
# 旧位置落在当前模块目录内的情况不用处理（模块目录会整体替换）。
# 同一位置重装时 OLD_BIN_PATH == CUR_BIN，直接跳过，等于覆盖安装。
if [ -n "$OLD_BIN_PATH" ] && [ -f "$OLD_BIN_PATH" ]; then
    CUR_BIN="$BINARY_PATH/$BINARY_NAME"
    if [ "$OLD_BIN_PATH" != "$CUR_BIN" ]; then
        case "$OLD_BIN_PATH" in
            "$MODROOT"/*)
                ;;  # 模块目录内，随安装被替换
            *)
                if rm -f "$OLD_BIN_PATH" 2>/dev/null; then
                    ui_print "🧹 已删除旧位置的二进制：$OLD_BIN_PATH"
                    OLD_BIN_DIR="$(dirname "$OLD_BIN_PATH")"
                    # 目录空了就顺手删掉，别留空壳
                    rmdir "$OLD_BIN_DIR" 2>/dev/null || true
                else
                    ui_print "⚠️ 旧位置的二进制删不掉（可能仍在运行）：$OLD_BIN_PATH"
                fi
                ;;
        esac
    fi
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
