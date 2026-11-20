# Implementation Plan: Companion Menu Visibility Lifecycle Sync

## Spec & Global Constraints
- Spec authority: `GLOSSARY.md` (`Companion Menu Visibility`) and `docs/adr/0001-companion-apk-process-text-offline-download.md` (Section: 伴侣菜单可见性与守护服务生命周期强绑定).
- Target component identifier: `io.openlist.helper/io.openlist.helper.ProcessTextActivity` (package `io.openlist.helper`).
- All three entrypoints (`PROCESS_TEXT`, `SEND`, `VIEW magnet:`) live on `ProcessTextActivity` and must be toggled together.
- Default state in `companion-apk/AndroidManifest.xml` for `.ProcessTextActivity` must be `android:enabled="false"`.
- When `OpenList Daemon` is confirmed running and the module is enabled (no `$MODDIR/disable` or `$MODDIR/remove`), enable the component via `pm enable io.openlist.helper/io.openlist.helper.ProcessTextActivity` (and ensure package `io.openlist.helper` is enabled).
- When stopping the service via `OpenList-Magisk/action.sh`, when `service.sh` fails to start `OpenList Daemon`, when `$MODDIR/disable` or `$MODDIR/remove` exists, or after `customize.sh` installs the APK before service start, disable the component via `pm disable io.openlist.helper/io.openlist.helper.ProcessTextActivity`.
- Maintain Ash shell compatibility (`#!/system/bin/sh`, `# shellcheck shell=ash`, no bash arrays) across all `OpenList-Magisk/*.sh` scripts.

## Task 1: Default-disable ProcessTextActivity in Companion APK Manifest and add unit tests

### Files Owned
- `companion-apk/AndroidManifest.xml`
- `companion-apk/test/io/openlist/helper/OfflineHelperCoreTest.java`

### Requirements
1. In `companion-apk/AndroidManifest.xml`, add `android:enabled="false"` to `<activity android:name=".ProcessTextActivity" ...>` so that a newly installed Companion APK keeps all three trigger entrypoints (`PROCESS_TEXT`, `SEND`, `VIEW magnet:`) hidden until `service.sh` or `action.sh` explicitly enables the component after verifying `OpenList Daemon` is running.
2. In `companion-apk/test/io/openlist/helper/OfflineHelperCoreTest.java`, add a test verifying `companion-apk/AndroidManifest.xml` declares `android:name=".ProcessTextActivity"` with `android:enabled="false"` and retains all three intent actions (`android.intent.action.PROCESS_TEXT`, `android.intent.action.SEND`, `android.intent.action.VIEW`).
3. Run the Java test suite (`javac` + `java` on `OfflineHelperCoreTest`) to verify RED/GREEN.

## Task 2: Sync Companion Menu Visibility across service.sh, action.sh, customize.sh, uninstall.sh and tests

### Files Owned
- `OpenList-Magisk/service.sh`
- `OpenList-Magisk/action.sh`
- `OpenList-Magisk/customize.sh`
- `OpenList-Magisk/uninstall.sh`
- `tests/test_module_scripts.sh`

### Requirements
1. In `OpenList-Magisk/service.sh`:
   - Define helper functions:
     - `set_companion_menu_enabled()`: takes `1` (enable) or `0` (disable). When `command -v pm >/dev/null 2>&1`:
       - If `1`: runs `pm enable io.openlist.helper >/dev/null 2>&1 || true` and `pm enable io.openlist.helper/io.openlist.helper.ProcessTextActivity >/dev/null 2>&1 || true`, logging the state transition.
       - If `0`: runs `pm disable io.openlist.helper/io.openlist.helper.ProcessTextActivity >/dev/null 2>&1 || true`, logging the state transition.
     - `install_boot_companion_sync_guard()`: installs a lightweight boot/watcher script at `${SERVICE_D_DIR:-/data/adb/service.d}/openlist_companion_sync.sh` (mode `0755`) that checks if the module is disabled/removed (`[ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]` or `[ ! -d "$MODDIR" ]`) or if `openlist server` is not running after boot, and disables `io.openlist.helper/io.openlist.helper.ProcessTextActivity`. Also in `service.sh`, spawn a lightweight background monitor (or check) that watches for `$MODDIR/disable` or `$MODDIR/remove` while the phone is running: if the user toggles the module off in Magisk/KSU/APatch manager, immediately stop `OpenList Daemon` (or hide menu) by calling `pm disable io.openlist.helper/io.openlist.helper.ProcessTextActivity`.
   - In `sync_companion_apk_and_config()`:
     - Ensure `install_boot_companion_sync_guard` is called.
     - Enable the companion menu (`set_companion_menu_enabled 1`) when syncing config for a running service (unless `$MODDIR/disable` or `$MODDIR/remove` is present, in which case call `set_companion_menu_enabled 0`).
   - In `main()` of `service.sh`:
     - If `[ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]`, call `set_companion_menu_enabled 0` and exit 0.
     - If `OpenList` fails to start in `main()`, call `set_companion_menu_enabled 0` before exiting.
2. In `OpenList-Magisk/action.sh`:
   - Define `set_companion_menu_enabled()` (or invoke `pm enable` / `pm disable` on `io.openlist.helper/io.openlist.helper.ProcessTextActivity`).
   - When stopping `OpenList` succeeds, immediately call `set_companion_menu_enabled 0` so the "115 离线" menu disappears right away.
   - When starting `OpenList` via `sh "$SERVICE_SH"` succeeds, ensure `set_companion_menu_enabled 1` is called (and if starting fails, call `set_companion_menu_enabled 0`).
3. In `OpenList-Magisk/customize.sh`:
   - After `pm install -r "$HELPER_APK"`, immediately run `pm disable io.openlist.helper/io.openlist.helper.ProcessTextActivity >/dev/null 2>&1 || true` if `openlist server` is not currently running, so the menu remains hidden until the service actually runs.
4. In `OpenList-Magisk/uninstall.sh`:
   - In `clean_companion()`, remove `/data/adb/service.d/openlist_companion_sync.sh` (or `${SERVICE_D_DIR:-/data/adb/service.d}/openlist_companion_sync.sh`) and run `pm disable io.openlist.helper/io.openlist.helper.ProcessTextActivity >/dev/null 2>&1 || true` before `pm uninstall io.openlist.helper`.
5. In `tests/test_module_scripts.sh`:
   - Add comprehensive tests with a mock `pm` command verifying:
     - `set_companion_menu_enabled 1` invokes `pm enable io.openlist.helper/io.openlist.helper.ProcessTextActivity`.
     - `set_companion_menu_enabled 0` invokes `pm disable io.openlist.helper/io.openlist.helper.ProcessTextActivity`.
     - When `$MODDIR/disable` exists, `sync_companion_apk_and_config` disables the companion menu instead of enabling it.
     - `install_boot_companion_sync_guard` generates `openlist_companion_sync.sh` and when executed with `$MODDIR/disable` present, it runs `pm disable io.openlist.helper/io.openlist.helper.ProcessTextActivity`.
     - `action.sh` disables the menu when stopping the service and enables it when starting.
     - `clean_companion` removes `openlist_companion_sync.sh`.
