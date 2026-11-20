# Implementation Plan: 115 Storage Menu Visibility Gate & Revert SQLite WAL Patch from Upstream PR

## Spec & Global Constraints
- Spec authority: `GLOSSARY.md` (`Companion Menu Visibility`) and `docs/adr/0001-companion-apk-process-text-offline-download.md` (Section: 伴侣菜单可见性与守护服务生命周期强绑定).
- Target component identifier: `io.openlist.helper/io.openlist.helper.ProcessTextActivity` (package `io.openlist.helper`).
- **115 Storage Menu Gate Requirement**:
  - In addition to requiring `OpenList Daemon` to be running and the module not disabled/removed (`! -f "$MODDIR/disable" && ! -f "$MODDIR/remove"`), the companion menu (`io.openlist.helper/io.openlist.helper.ProcessTextActivity`) MUST ALSO be disabled (`pm disable io.openlist.helper/io.openlist.helper.ProcessTextActivity`) if OpenList storages do not have any 115 netdisk storage added (`115 Cloud`, `115 Open`, or `115`), or if all added 115 storages are disabled (`disabled = true` / `1` / `status = "disabled"`).
  - Only when at least one 115 storage (`115 Cloud`, `115 Open`, or `115`) is added AND enabled (`disabled = false` / `0`) while `OpenList Daemon` is running and the module is enabled should `set_companion_menu_enabled 1` be called.
  - Maintain a 3-tier detection helper `has_enabled_115_storage()` in `OpenList-Magisk/service.sh`:
    1. Live HTTP Admin API `GET http://127.0.0.1:${port}/api/admin/storage/list` (with `Authorization: ${token}` via `curl` or `wget`, 2s timeout): when response contains `"code":200`, return `0` iff at least one storage item has `"driver"` matching `"115 Cloud"`, `"115 Open"`, or `"115"` AND `"disabled":false`; otherwise return `1`.
    2. `sqlite3` CLI on `$DATA_DIR/data.db`: query `SELECT COUNT(*) FROM x_storages WHERE driver IN ('115 Cloud', '115 Open', '115') AND (disabled = 0 OR disabled = '0' OR disabled = 'false' OR disabled IS NULL);`. If query succeeds, return `0` when count > 0, else return `1`.
    3. Pure binary/string fallback on `$DATA_DIR/data.db-wal` and `$DATA_DIR/data.db` (for Android ROMs without `sqlite3` or before HTTP is ready): inspect `115 (Cloud|Open).{0,24}` matches; return `0` iff at least one match does not contain `disabled`, otherwise return `1`.
  - In `watch_module_disable_state()`, track `last_menu_state` and poll `has_enabled_115_storage` on each cycle so adding/enabling or disabling/deleting a 115 storage in OpenList Web UI dynamically enables or disables the companion menu at runtime without spamming `pm` when unchanged.
  - In `OpenList-Magisk/action.sh`, when starting the service via `sh "$SERVICE_SH"`, avoid unconditionally overwriting the menu state set by `service.sh` (`sync_companion_apk_and_config`) if `service.sh` contains `sync_companion_apk_and_config`.
- **Branch Split Requirement (Fork vs Upstream PR)**:
  - The user's fork (`main` -> `origin/main`) keeps the SQLite WAL Concurrency Self-Healing & Log Tuning (commit `9fb90d2`, ADR 0002) AND receives the new 115 storage menu visibility gate.
  - The upstream PR branch (`feat/magnet-115-offline` -> `origin/feat/magnet-115-offline`, backing PR #37 on `Alien-Et/OpenList-Magisk`) receives the new 115 storage menu visibility gate AND removes the SQLite WAL Concurrency Self-Healing & Log Tuning (ADR 0002) changes (`patch_openlist_binary_sqlite_dsn`, `ensure_sqlite_wal_and_clean_locks`, `optimize_openlist_config`, `docs/adr/0002-sqlite-wal-and-busy-timeout-patch.md`, `docs/plans/sqlite-wal-self-healing-plan.md`, and the ADR 0002 sections in `GLOSSARY.md`, `README.md`, `OpenList-Magisk/README.md`, and `tests/test_module_scripts.sh`).
- Maintain Ash shell compatibility (`#!/system/bin/sh`, `# shellcheck shell=ash`, no bash arrays) across all `OpenList-Magisk/*.sh` scripts.
- Follow `CLAUDE.md` `graphify` rules: when `graphify-out/graph.json` exists, run `graphify query "<question>"` before any first grep/search/read for a codebase question.

## Task 1: Gate Companion Menu Visibility on Added & Enabled 115 Storage

### Files Owned
- `OpenList-Magisk/service.sh`
- `OpenList-Magisk/action.sh`
- `GLOSSARY.md`
- `docs/adr/0001-companion-apk-process-text-offline-download.md`
- `README.md`
- `OpenList-Magisk/README.md`
- `tests/test_module_scripts.sh`

### Requirements
1. In `OpenList-Magisk/service.sh`:
   - Implement `has_enabled_115_storage()`:
     - Accepts optional port `${1:-${DETECTED_PORT:-5244}}`.
     - Tier 1: Reads `TOKEN` from `$DATA_DIR/offline.conf` (fallback `extract_openlist_token`). If non-empty and `curl` or `wget` is available, requests `http://127.0.0.1:${port}/api/admin/storage/list` with `Authorization: ${token}` (2s timeout). If output contains `"code"[[:space:]]*:[[:space:]]*200`, splits objects on `{"id":` and checks if any line matches `"driver"[[:space:]]*:[[:space:]]*"115( Cloud| Open)?"` AND `"disabled"[[:space:]]*:[[:space:]]*false`. Returns `0` if matched, `1` if not matched.
     - Tier 2: If `$DATA_DIR/data.db` exists and `sqlite3` is available, runs `sqlite3 "$db_file" "SELECT COUNT(*) FROM x_storages WHERE driver IN ('115 Cloud', '115 Open', '115') AND (disabled = 0 OR disabled = '0' OR disabled = 'false' OR disabled IS NULL);" 2>/dev/null`. If `sqlite3` exits 0 and returns a non-empty count, returns `0` if `count > 0`, else `1`.
     - Tier 3: Pure binary/string fallback on `${db_file}-wal` (if non-empty, check last match of `115 (Cloud|Open).{0,24}` for `disabled`) and `$db_file` (extract `115 (Cloud|Open).{0,24}` via `grep -aoE`, fallback `strings` / `tr -cd '[:print:]\n'`). Returns `0` iff at least one match does not contain `disabled`; returns `1` if file is missing, no 115 storage match exists, or all matches contain `disabled`.
   - In `sync_companion_apk_and_config()`:
     - Ensure `offline.conf` port and token are synced BEFORE checking `has_enabled_115_storage "$target_port"`.
     - Call `install_boot_companion_sync_guard`.
     - If `[ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]`, call `set_companion_menu_enabled 0`.
     - Else if `has_enabled_115_storage "$target_port"`, call `set_companion_menu_enabled 1`.
     - Else log `未检测到已启用的 115 网盘存储，隐藏 115 离线下载系统菜单入口` and call `set_companion_menu_enabled 0`.
   - In `watch_module_disable_state()`:
     - Track `last_menu_state=""` inside the `while pgrep -f "$OPENLIST_BINARY server"` loop.
     - After checking `$MODDIR/disable` and `$MODDIR/remove`, compute `desired_state="0"`; if `has_enabled_115_storage "${DETECTED_PORT:-5244}"`, set `desired_state="1"`.
     - If `[ "$desired_state" != "$last_menu_state" ]`, call `set_companion_menu_enabled "$desired_state"` and update `last_menu_state="$desired_state"`.
2. In `OpenList-Magisk/action.sh`:
   - In the service start branch (`if check_openlist_status; then`), only call `set_companion_menu_enabled 1` directly if `! grep -q "sync_companion_apk_and_config" "$SERVICE_SH" 2>/dev/null`, so when `action.sh` invokes the real `service.sh`, it respects the 115 storage gate evaluated by `sync_companion_apk_and_config`.
3. In `GLOSSARY.md`, `docs/adr/0001-companion-apk-process-text-offline-download.md`, `README.md`, and `OpenList-Magisk/README.md`:
   - Update the `Companion Menu Visibility` definition and documentation to state that the menu is also hidden when no 115 storage (`115 Cloud` / `115 Open`) is added in OpenList or when all 115 storages are disabled.
4. In `tests/test_module_scripts.sh`:
   - In Test 12 (and Test 16b), ensure `$DATA_DIR/data.db` contains an enabled 115 storage record when testing the normal enabled path.
   - Add a comprehensive test section verifying:
     - When `data.db` has no 115 storage (missing or only non-115 storage), `has_enabled_115_storage` returns non-zero and `sync_companion_apk_and_config` calls `pm disable io.openlist.helper/io.openlist.helper.ProcessTextActivity`.
     - When `data.db` has a 115 storage (`115 Cloud` or `115 Open`) that is disabled (`disabled=1`, `status='disabled'`), `has_enabled_115_storage` returns non-zero and `sync_companion_apk_and_config` calls `pm disable io.openlist.helper/io.openlist.helper.ProcessTextActivity`.
     - When `data.db` has an enabled 115 storage (`disabled=0`, `status='work'`), `has_enabled_115_storage` returns 0 and `sync_companion_apk_and_config` calls `pm enable io.openlist.helper/io.openlist.helper.ProcessTextActivity`.
     - Live HTTP API `/api/admin/storage/list` mock via `curl`: returns non-zero when `content` has no 115 storage or `"disabled":true`, and returns 0 when `"driver":"115 Open"` has `"disabled":false`.
     - `watch_module_disable_state` dynamically toggles `pm disable` and `pm enable` when 115 storage state changes at runtime.

## Task 2: Revert SQLite WAL Concurrency Self-Healing & Log Tuning (ADR 0002) from Upstream PR Branch

### Files Owned
- `OpenList-Magisk/service.sh`
- `GLOSSARY.md`
- `OpenList-Magisk/README.md`
- `README.md`
- `docs/adr/0002-sqlite-wal-and-busy-timeout-patch.md`
- `docs/plans/sqlite-wal-self-healing-plan.md`
- `tests/test_module_scripts.sh`

### Requirements
1. Before starting Task 2 edits, ensure local `main` branch points to the completed Task 1 commit (`git branch -f main HEAD`) so the user's fork branch (`main`) preserves both ADR 0002 and Task 1.
2. On `feat/magnet-115-offline` (the upstream PR branch):
   - In `OpenList-Magisk/service.sh`: remove `patch_openlist_binary_sqlite_dsn()`, `ensure_sqlite_wal_and_clean_locks()`, `optimize_openlist_config()`, and their invocations in `main()`.
   - Delete `docs/adr/0002-sqlite-wal-and-busy-timeout-patch.md` and `docs/plans/sqlite-wal-self-healing-plan.md`.
   - In `GLOSSARY.md`: remove the `SQLite Concurrency Self-Healing（SQLite 并发锁自愈）` entry while keeping `Directory Cache Auto-Refresh` and the updated `Companion Menu Visibility`.
   - In `README.md` and `OpenList-Magisk/README.md`: remove the bullet `- **SQLite 并发锁自愈与日志调优**...`, the section `### SQLite 并发锁自愈与日志调优（SQLite WAL & Concurrency Self-Healing）`, and troubleshooting item `4. **WebDAV 播放器多并发闪退或提示 database is locked**`, while preserving all 115 offline download, directory cache auto-refresh, and companion menu visibility documentation.
   - In `tests/test_module_scripts.sh`: remove the tests for `patch_openlist_binary_sqlite_dsn`, `ensure_sqlite_wal_and_clean_locks`, and `optimize_openlist_config` (Tests 17, 18, 19 from `9fb90d2`), keeping all other tests including the 115 storage menu visibility gate test from Task 1.
   - Run `bash tests/test_module_scripts.sh` and verify all tests pass with 0 failures.
