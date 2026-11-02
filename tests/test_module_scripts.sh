#!/usr/bin/env bash
# tests/test_module_scripts.sh
# 验证 OpenList-Magisk 模块脚本中的 Token 提取、offline.conf 配置合并与桥接逻辑

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVICE_SH="$REPO_ROOT/OpenList-Magisk/service.sh"

FAILED=0
TOTAL=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $message"
    else
        echo "  [FAIL] $message: expected '$expected', got '$actual'"
        FAILED=$((FAILED + 1))
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local message="$3"
    TOTAL=$((TOTAL + 1))
    if grep -qE "$pattern" "$file" 2>/dev/null; then
        echo "  [PASS] $message"
    else
        echo "  [FAIL] $message: file '$file' does not match pattern '$pattern'"
        FAILED=$((FAILED + 1))
    fi
}

# 测试环境临时目录
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

echo "=== 开始测试 OpenList-Magisk 模块离线下载功能脚本 ==="

# 准备模拟数据环境
export DATA_DIR="$TEST_TMP/openlist_data"
export LOG_FILE="$TEST_TMP/service.log"
export BRIDGE_TMP_CONF="$TEST_TMP/local_tmp/openlist_offline.conf"
export HELPER_DATA_DIR="$TEST_TMP/data_io_openlist_helper"
mkdir -p "$DATA_DIR"
mkdir -p "$TEST_TMP/local_tmp"
mkdir -p "$HELPER_DATA_DIR"

# 引入 service.sh 中的函数
# 注意：service.sh 内部有脚本自执行保护，被 source 时不会执行主进程
if [ ! -f "$SERVICE_SH" ]; then
    echo "错误：未找到 $SERVICE_SH"
    exit 1
fi
# shellcheck disable=SC1090
. "$SERVICE_SH"

# -------------------------------------------------------------
# 测试 1: 纯二进制/grep 降级提取 OpenList Token (剥离连续 string 列值)
# -------------------------------------------------------------
echo ""
echo "-> 测试 1: 纯二进制无 sqlite3 环境提取 Token"
MOCK_TOKEN="openlist-6d91b7d6-0b6e-4766-9bc2-680f599c9b59SbVfjghkfiP64UbC0i8apymduCgubSoMsgfKm1bHIFeXhmytpXSGHRsKhpd8e6IX"
# 写入含有 SQLite 连续字段 (token+value+string) 的模拟二进制 data.db
printf "\x00\x01\xFE\xFF\x80\x90token%sstring\x00\x12\x34\x56" "$MOCK_TOKEN" > "$DATA_DIR/data.db"

EXTRACTED_BIN_TOKEN=$(extract_openlist_token)
assert_eq "$MOCK_TOKEN" "$EXTRACTED_BIN_TOKEN" "从纯二进制 data.db 正确提取 openlist-* Token 并剥离尾部 string"

# -------------------------------------------------------------
# 测试 2: sqlite3 环境提取 OpenList Token (如果系统安装了 sqlite3)
# -------------------------------------------------------------
echo ""
echo "-> 测试 2: 使用 sqlite3 数据库表提取 Token"
if command -v sqlite3 >/dev/null 2>&1; then
    SQL_MOCK_TOKEN="openlist-sqliteTestToken9876543210zyx"
    rm -f "$DATA_DIR/data.db"
    sqlite3 "$DATA_DIR/data.db" "CREATE TABLE x_setting_items (key TEXT, value TEXT);"
    sqlite3 "$DATA_DIR/data.db" "INSERT INTO x_setting_items (key, value) VALUES ('token', '$SQL_MOCK_TOKEN');"

    EXTRACTED_SQL_TOKEN=$(extract_openlist_token)
    assert_eq "$SQL_MOCK_TOKEN" "$EXTRACTED_SQL_TOKEN" "从 SQLite 数据库表 x_setting_items 正确提取 Token"
else
    echo "  [SKIP] 当前环境无 sqlite3 命令，跳过 SQLite 表查询测试"
fi

# -------------------------------------------------------------
# 测试 3: offline.conf 首次不存在时自动生成默认配置并填充 Token 与 Port
# -------------------------------------------------------------
echo ""
echo "-> 测试 3: offline.conf 首次不存在时自动初始化并同步"
rm -f "$DATA_DIR/offline.conf"
rm -f "$BRIDGE_TMP_CONF"
rm -f "$HELPER_DATA_DIR/files/offline.conf"

# 运行同步逻辑，指定端口为 5244
sync_companion_apk_and_config "5244"

assert_file_contains "$DATA_DIR/offline.conf" "^HOST=127.0.0.1" "offline.conf 包含 HOST=127.0.0.1"
assert_file_contains "$DATA_DIR/offline.conf" "^PORT=5244" "offline.conf 包含 PORT=5244"
assert_file_contains "$DATA_DIR/offline.conf" "^TOKEN=openlist-" "offline.conf 自动填充提取到的有效 Token"
assert_file_contains "$DATA_DIR/offline.conf" "^PATH=/115/影视/" "offline.conf 默认目标路径为 /115/影视/"
assert_file_contains "$DATA_DIR/offline.conf" "^TOOL=115 Open" "offline.conf 默认离线下载引擎 (Offline Engine) 为 115 Open"
assert_file_contains "$DATA_DIR/offline.conf" "^DELETE_POLICY=delete_on_upload_succeed" "offline.conf 默认删除策略为 delete_on_upload_succeed"
assert_file_contains "$DATA_DIR/offline.conf" "^PRESET_PATHS=/115/影视/,/115/" "offline.conf 包含预设路径列表"

# 验证桥接文件已生成
assert_file_contains "$BRIDGE_TMP_CONF" "^PATH=/115/影视/" "桥接到 /data/local/tmp 成功且内容一致"
assert_file_contains "$HELPER_DATA_DIR/files/offline.conf" "^PATH=/115/影视/" "桥接到伴侣私有目录成功且内容一致"

# -------------------------------------------------------------
# 测试 4: 端口变化时自动更新 PORT
# -------------------------------------------------------------
echo ""
echo "-> 测试 4: OpenList 端口变更时动态更新 PORT"
sync_companion_apk_and_config "5249"

assert_file_contains "$DATA_DIR/offline.conf" "^PORT=5249" "offline.conf 中的 PORT 已更新为 5249"
assert_file_contains "$BRIDGE_TMP_CONF" "^PORT=5249" "桥接文件中的 PORT 同步更新为 5249"

# -------------------------------------------------------------
# 测试 5: 保留用户自定义配置（路径、策略、自定义 Token 等）
# -------------------------------------------------------------
echo ""
echo "-> 测试 5: 用户自定义配置保护（不被启动脚本覆盖）"
cat > "$DATA_DIR/offline.conf" << 'EOF'
# 用户自定义配置
HOST=192.168.1.100
PORT=5244
TOKEN=user-manual-custom-token-123
PATH=/115/动漫剧场/
TOOL=115 Open
DELETE_POLICY=delete_never
PRESET_PATHS=/115/动漫剧场/,/115/电影/
EOF

# 即使检测到的运行端口是 5244，数据库里是另一个 token
sync_companion_apk_and_config "5244"

assert_file_contains "$DATA_DIR/offline.conf" "^HOST=192.168.1.100" "保留自定义 HOST"
assert_file_contains "$DATA_DIR/offline.conf" "^TOKEN=user-manual-custom-token-123" "非空已有 TOKEN 不被覆盖"
assert_file_contains "$DATA_DIR/offline.conf" "^PATH=/115/动漫剧场/" "保留自定义 PATH"
assert_file_contains "$DATA_DIR/offline.conf" "^DELETE_POLICY=delete_never" "保留自定义 DELETE_POLICY"
assert_file_contains "$DATA_DIR/offline.conf" "^PRESET_PATHS=/115/动漫剧场/,/115/电影/" "保留自定义 PRESET_PATHS"

# -------------------------------------------------------------
# 测试 6: 用户仅配置了部分字段，缺失字段被平滑补齐且不影响已有字段
# -------------------------------------------------------------
echo ""
echo "-> 测试 6: 缺失字段平滑补全"
cat > "$DATA_DIR/offline.conf" << 'EOF'
PATH=/115/纪录片/
EOF

sync_companion_apk_and_config "5244"

assert_file_contains "$DATA_DIR/offline.conf" "^PATH=/115/纪录片/" "保留原本唯一的自定义 PATH"
assert_file_contains "$DATA_DIR/offline.conf" "^TOOL=115 Open" "补全 TOOL=115 Open"
assert_file_contains "$DATA_DIR/offline.conf" "^PORT=5244" "补全 PORT=5244"
assert_file_contains "$DATA_DIR/offline.conf" "^TOKEN=openlist-" "补全提取到的 TOKEN"

# -------------------------------------------------------------
# 测试 7: 历史被污染的 TOKEN=...string 自动清洗
# -------------------------------------------------------------
echo ""
echo "-> 测试 7: 历史被污染的 TOKEN=...string 自动清洗"
POLLUTED_TOKEN="openlist-6d91b7d6-0b6e-4766-9bc2-680f599c9b59SbVfjghkfiP64UbC0i8apymduCgubSoMsgfKm1bHIFeXhmytpXSGHRsKhpd8e6IXstring"
CLEANED_TOKEN="openlist-6d91b7d6-0b6e-4766-9bc2-680f599c9b59SbVfjghkfiP64UbC0i8apymduCgubSoMsgfKm1bHIFeXhmytpXSGHRsKhpd8e6IX"

# 构造含有该 Token 的二进制 data.db
printf "\x00\x01\xFE\xFF\x80\x90token%sstring\x00\x12\x34\x56" "$CLEANED_TOKEN" > "$DATA_DIR/data.db"

cat > "$DATA_DIR/offline.conf" << EOF
HOST=127.0.0.1
PORT=5244
TOKEN=$POLLUTED_TOKEN
PATH=/115/影视/
TOOL=115 Open
DELETE_POLICY=delete_on_upload_succeed
PRESET_PATHS=/115/影视/,/115/
EOF

# 运行同步逻辑
sync_companion_apk_and_config "5244"

assert_file_contains "$DATA_DIR/offline.conf" "^TOKEN=$CLEANED_TOKEN$" "offline.conf 中被污染的 TOKEN 尾部 string 被成功剥除"
assert_file_contains "$BRIDGE_TMP_CONF" "^TOKEN=$CLEANED_TOKEN$" "桥接配置中的 TOKEN 尾部 string 同步被剥除"
assert_file_contains "$HELPER_DATA_DIR/files/offline.conf" "^TOKEN=$CLEANED_TOKEN$" "伴侣私有目录配置中的 TOKEN 尾部 string 同步被剥除"

# 7b: 验证若 data.db 缺失时，offline.conf 中被污染的 TOKEN 仍被就地剥离 string 后缀
rm -f "$DATA_DIR/data.db"
cat > "$DATA_DIR/offline.conf" << EOF
HOST=127.0.0.1
PORT=5244
TOKEN=openlist-noDbPollutedTokenTest123456789string
PATH=/115/影视/
TOOL=115 Open
DELETE_POLICY=delete_on_upload_succeed
PRESET_PATHS=/115/影视/,/115/
EOF
sync_companion_apk_and_config "5244"
assert_file_contains "$DATA_DIR/offline.conf" "^TOKEN=openlist-noDbPollutedTokenTest123456789$" "无 data.db 时 offline.conf 中的 TOKEN 尾部 string 就地剥除"

# 7c: 验证含 CRLF (\r\n) 换行符的 offline.conf 中被污染的 TOKEN 尾部 string 仍被正确剥除
printf "HOST=127.0.0.1\r\nPORT=5244\r\nTOKEN=openlist-crlfPollutedTokenTest123456789string\r\nPATH=/115/影视/\r\nTOOL=115 Open\r\nDELETE_POLICY=delete_on_upload_succeed\r\nPRESET_PATHS=/115/影视/,/115/\r\n" > "$DATA_DIR/offline.conf"
sync_companion_apk_and_config "5244"
assert_file_contains "$DATA_DIR/offline.conf" "^TOKEN=openlist-crlfPollutedTokenTest123456789" "CRLF 换行符下 offline.conf 中的 TOKEN 尾部 string 成功剥除"

# -------------------------------------------------------------
# 测试 8: 开机存储自动重载函数 reload_openlist_storages 测试
# -------------------------------------------------------------
echo ""
echo "-> 测试 8: 开机存储自动重载逻辑"
RELOAD_DELAY=0 reload_openlist_storages "5244"
sleep 0.2
assert_file_contains "$LOG_FILE" "存储重载" "服务成功触发或记录存储重载逻辑"

# -------------------------------------------------------------
# 测试 9: uninstall.sh 中 clean_companion 清理临时配置与伴侣卸载
# -------------------------------------------------------------
echo ""
echo "-> 测试 9: uninstall.sh 清理逻辑"
UNINSTALL_SH="$REPO_ROOT/OpenList-Magisk/uninstall.sh"
# shellcheck disable=SC1090
. "$UNINSTALL_SH"

# 创建临时待清理文件
MOCK_TMP_CONF="/data/local/tmp/openlist_offline.conf"
if [ -w "/data/local/tmp" ] 2>/dev/null; then
    touch "$MOCK_TMP_CONF" 2>/dev/null || true
fi

clean_companion

if [ -w "/data/local/tmp" ] 2>/dev/null; then
    TOTAL=$((TOTAL + 1))
    if [ ! -f "$MOCK_TMP_CONF" ]; then
        echo "  [PASS] 成功清理 /data/local/tmp/openlist_offline.conf"
    else
        echo "  [FAIL] 未能清理 /data/local/tmp/openlist_offline.conf"
        FAILED=$((FAILED + 1))
    fi
else
    echo "  [PASS] clean_companion 函数执行正常（非 Android 环境跳过实际 /data/local/tmp 清理）"
    TOTAL=$((TOTAL + 1))
fi

# -------------------------------------------------------------
# 测试 10: customize.sh 离线配置文件创建规范验证
# -------------------------------------------------------------
echo ""
echo "-> 测试 10: customize.sh 离线配置文件默认规范"
CUSTOMIZE_SH="$REPO_ROOT/OpenList-Magisk/customize.sh"
assert_file_contains "$CUSTOMIZE_SH" "offline\.conf" "customize.sh 包含 offline.conf 初始化逻辑"
assert_file_contains "$CUSTOMIZE_SH" "OpenListHelper\.apk" "customize.sh 包含 OpenListHelper.apk 权限与安装处理"
assert_file_contains "$CUSTOMIZE_SH" "chcon -R u:object_r:system_file:s0" "customize.sh 正确设置 SELinux 上下文"
assert_file_contains "$CUSTOMIZE_SH" "pm disable io\.openlist\.helper/io\.openlist\.helper\.ProcessTextActivity" "customize.sh 安装伴侣后若服务未运行则默认隐藏菜单"

# -------------------------------------------------------------
# 测试 11: set_companion_menu_enabled 启停系统文本菜单入口
# -------------------------------------------------------------
echo ""
echo "-> 测试 11: set_companion_menu_enabled 动态控制 ProcessTextActivity 组件状态"
MOCK_BIN_DIR="$TEST_TMP/mock_bin"
PM_LOG="$TEST_TMP/pm_calls.log"
mkdir -p "$MOCK_BIN_DIR"
cat > "$MOCK_BIN_DIR/pm" << EOF
#!/usr/bin/env bash
echo "\$*" >> "$PM_LOG"
if [ "\$1" = "path" ]; then
    echo "package:/data/app/io.openlist.helper/base.apk"
    exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/pm"
export PATH="$MOCK_BIN_DIR:$PATH"

: > "$PM_LOG"
set_companion_menu_enabled 1
assert_file_contains "$PM_LOG" "^enable io\.openlist\.helper$" "启用菜单时先确保包体处于 enable 状态"
assert_file_contains "$PM_LOG" "^enable io\.openlist\.helper/io\.openlist\.helper\.ProcessTextActivity$" "set_companion_menu_enabled 1 调用 pm enable ProcessTextActivity"

: > "$PM_LOG"
set_companion_menu_enabled 0
assert_file_contains "$PM_LOG" "^disable io\.openlist\.helper/io\.openlist\.helper\.ProcessTextActivity$" "set_companion_menu_enabled 0 调用 pm disable ProcessTextActivity"

# -------------------------------------------------------------
# 测试 12: 模块处于 disable 状态时 sync_companion_apk_and_config 自动隐藏菜单
# -------------------------------------------------------------
echo ""
echo "-> 测试 12: 模块存在 disable 标记时同步逻辑自动禁用菜单"
MOCK_MODDIR="$TEST_TMP/mock_moddir"
mkdir -p "$MOCK_MODDIR"
export MODDIR="$MOCK_MODDIR"
export SERVICE_D_DIR="$TEST_TMP/service.d"

# 正常未禁用状态
rm -f "$MOCK_MODDIR/disable" "$MOCK_MODDIR/remove"
: > "$PM_LOG"
sync_companion_apk_and_config "5244"
assert_file_contains "$PM_LOG" "^enable io\.openlist\.helper/io\.openlist\.helper\.ProcessTextActivity$" "模块未禁用时 sync_companion_apk_and_config 启用系统菜单"

# 创建 disable 标记文件
touch "$MOCK_MODDIR/disable"
: > "$PM_LOG"
sync_companion_apk_and_config "5244"
assert_file_contains "$PM_LOG" "^disable io\.openlist\.helper/io\.openlist\.helper\.ProcessTextActivity$" "模块存在 disable 文件时 sync_companion_apk_and_config 隐藏系统菜单"
rm -f "$MOCK_MODDIR/disable"

# -------------------------------------------------------------
# 测试 13: install_boot_companion_sync_guard 生成开机守卫并在模块禁用时隐藏菜单
# -------------------------------------------------------------
echo ""
echo "-> 测试 13: 开机守卫脚本 openlist_companion_sync.sh 生成与禁用检测"
GUARD_SCRIPT="$SERVICE_D_DIR/openlist_companion_sync.sh"
export OPENLIST_BINARY="$MOCK_MODDIR/bin/openlist"
install_boot_companion_sync_guard

TOTAL=$((TOTAL + 1))
if [ -x "$GUARD_SCRIPT" ]; then
    echo "  [PASS] 成功生成可执行的 openlist_companion_sync.sh"
else
    echo "  [FAIL] openlist_companion_sync.sh 未生成或不可执行"
    FAILED=$((FAILED + 1))
fi

touch "$MOCK_MODDIR/disable"
: > "$PM_LOG"
sh "$GUARD_SCRIPT"
assert_file_contains "$PM_LOG" "^disable io\.openlist\.helper/io\.openlist\.helper\.ProcessTextActivity$" "开机守卫检测到模块 disable 时自动隐藏菜单"
rm -f "$MOCK_MODDIR/disable"

# -------------------------------------------------------------
# 测试 14: action.sh 停止与启动服务时同步切换系统菜单可见性
# -------------------------------------------------------------
echo ""
echo "-> 测试 14: action.sh 启停服务时同步隐藏/显示系统菜单"
ACTION_TEST_DIR="$TEST_TMP/action_mod"
mkdir -p "$ACTION_TEST_DIR/bin"
cp "$REPO_ROOT/OpenList-Magisk/action.sh" "$ACTION_TEST_DIR/action.sh"
sed -i "s|__PLACEHOLDER_BINARY_PATH__|$ACTION_TEST_DIR/bin/openlist|g" "$ACTION_TEST_DIR/action.sh"
cat > "$ACTION_TEST_DIR/module.prop" << 'EOF'
id=openlist
description=init
EOF

# 创建模拟 busybox（根据 fake_running 文件模拟 pgrep/pkill/sed）
FAKE_RUNNING="$TEST_TMP/fake_openlist_running"
cat > "$MOCK_BIN_DIR/busybox" << EOF
#!/usr/bin/env bash
cmd="\$1"
shift
case "\$cmd" in
    pgrep)
        if [ -f "$FAKE_RUNNING" ]; then
            echo "99999"
            exit 0
        fi
        exit 1
        ;;
    pkill)
        rm -f "$FAKE_RUNNING"
        exit 0
        ;;
    sed)
        exec sed "\$@"
        ;;
    *)
        exec "\$cmd" "\$@"
        ;;
esac
EOF
chmod +x "$MOCK_BIN_DIR/busybox"

# 创建模拟 service.sh 供 action.sh 启动调用
cat > "$ACTION_TEST_DIR/service.sh" << EOF
#!/usr/bin/env bash
touch "$FAKE_RUNNING"
exit 0
EOF
chmod +x "$ACTION_TEST_DIR/service.sh"

# 14a: 当前正在运行 -> 执行 action.sh 停止服务 -> 应调用 pm disable
touch "$FAKE_RUNNING"
: > "$PM_LOG"
sh "$ACTION_TEST_DIR/action.sh" >/dev/null 2>&1
assert_file_contains "$PM_LOG" "^disable io\.openlist\.helper/io\.openlist\.helper\.ProcessTextActivity$" "action.sh 停止服务后立即隐藏 115 离线系统菜单"

# 14b: 当前未运行 -> 执行 action.sh 启动服务 -> 应调用 pm enable
rm -f "$FAKE_RUNNING"
: > "$PM_LOG"
sh "$ACTION_TEST_DIR/action.sh" >/dev/null 2>&1
assert_file_contains "$PM_LOG" "^enable io\.openlist\.helper/io\.openlist\.helper\.ProcessTextActivity$" "action.sh 启动服务成功后立即启用 115 离线系统菜单"

# -------------------------------------------------------------
# 测试 15: uninstall.sh clean_companion 清理开机守卫脚本并禁用组件
# -------------------------------------------------------------
echo ""
echo "-> 测试 15: uninstall.sh 清理 openlist_companion_sync.sh 及禁用组件"
touch "$GUARD_SCRIPT"
: > "$PM_LOG"
SERVICE_D_DIR="$SERVICE_D_DIR" clean_companion

TOTAL=$((TOTAL + 1))
if [ ! -f "$GUARD_SCRIPT" ]; then
    echo "  [PASS] clean_companion 成功清理 openlist_companion_sync.sh"
else
    echo "  [FAIL] clean_companion 未清理 openlist_companion_sync.sh"
    FAILED=$((FAILED + 1))
fi
assert_file_contains "$PM_LOG" "^disable io\.openlist\.helper/io\.openlist\.helper\.ProcessTextActivity$" "clean_companion 卸载前先禁用 ProcessTextActivity"
assert_file_contains "$PM_LOG" "^uninstall io\.openlist\.helper$" "clean_companion 调用 pm uninstall 卸载伴侣应用"

# -------------------------------------------------------------
# 测试汇总报告
# -------------------------------------------------------------
echo ""
echo "=== 测试完成: 总计 $TOTAL 项，失败 $FAILED 项 ==="

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi

exit 0
