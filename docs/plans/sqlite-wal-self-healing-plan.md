# Implementation Plan: SQLite Concurrency Self-Healing & Log Rotation Tuning

## Spec & Global Constraints
- Spec authority: `GLOSSARY.md` (`SQLite Concurrency Self-Healing（SQLite 并发锁自愈）`) and `docs/adr/0002-sqlite-wal-and-busy-timeout-patch.md`.
- Problem Statement:
  1. Upstream OpenList opens SQLite via `fmt.Sprintf("%s?_journal=WAL&_vacuum=incremental", database.DBFile)` using `github.com/glebarez/sqlite` (`modernc.org/sqlite`). However, `modernc.org/sqlite` ignores `_journal=WAL` (it requires `_pragma=journal_mode(WAL)`) and defaults to `busy_timeout = 0` and legacy `DELETE` rollback journal mode (`data.db` header bytes 18/19 = `0x01 0x01`).
  2. Concurrent WebDAV `PROPFIND` transactions (`withDeadPropsTransaction`) hold open SQLite transactions across slow cloud storage network calls, triggering `database is locked (5) (SQLITE_BUSY)`, `SQL logic error: cannot start a transaction within a transaction (1)`, and leaving stale `data.db-journal` files that hang OpenList.
  3. Default `config.json` leaves `log.filter.enable` as `false` and `max_size: 50` / `max_backups: 30`, causing high-frequency WebDAV `PROPFIND` polling to flood `log.log` and waste `/data` storage.
- Agreed Design Decisions:
  - **Q1=C & Q4=A**: In `service.sh` before starting OpenList (and after first initialization if `data.db` is newly created):
    1. Patch the 35-byte DSN format string `%s?_journal=WAL&_vacuum=incremental` in `$OPENLIST_BINARY` in-place to `%s?_pragma=busy_timeout(10000)&_v=1` (idempotent, exact 35-byte replacement).
    2. Ensure `data.db` has persistent WAL mode enabled by setting SQLite header bytes at offset 18 and 19 (`0x12` and `0x13`) to `0x02 0x02` (verified via SQLite magic header `SQLite format 3\0`), and clean up any stale 0-byte or orphaned rollback lock artifacts before daemon launch.
  - **Q3=A & Q5=B**: In `service.sh`, tune `$DATA_DIR/config.json` (when present) to enable the built-in log filter (`"enable": true` inside `"filter"`), and cap log rotation to `"max_size": 10` and `"max_backups": 3` without altering user ports, tokens, or other settings.
  - **Q2=C & Q6=A**: Keep process lifecycle management simple without an automatic restart watchdog.
  - **Q7=A**: Record the architectural decision in `docs/adr/0002-sqlite-wal-and-busy-timeout-patch.md`.

## Task 1: Implement SQLite WAL Header Persistence, Binary Busy-Timeout Patch, and Config Log Tuning in `service.sh` + Unit Tests

### Files Owned
- `OpenList-Magisk/service.sh`
- `tests/test_module_scripts.sh`

### Requirements
1. In `OpenList-Magisk/service.sh`:
   - Add `patch_openlist_binary_sqlite_dsn()`:
     - Check if `$OPENLIST_BINARY` contains the literal 35-byte string `%s?_journal=WAL&_vacuum=incremental`.
     - Replace it in-place with the exact 35-byte string `%s?_pragma=busy_timeout(10000)&_v=1` using `sed -b -i` / `busybox sed -i` (preserving executable permissions `chmod 755` and SELinux context if applicable), and log the patch execution.
   - Add `ensure_sqlite_wal_and_clean_locks()`:
     - If `$DATA_DIR/data.db-journal` exists while no `openlist` process is running and it is a stale lock or if `sqlite3` is available, recover/clean appropriately; specifically, if `sqlite3` is available, run `sqlite3 "$db_file" "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=10000;" >/dev/null 2>&1 || true`.
     - For universal Android compatibility without `sqlite3`: verify `$DATA_DIR/data.db` is at least 100 bytes and starts with `SQLite format 3`, and if there is no active non-empty rollback journal `$DATA_DIR/data.db-journal` (or after rolling it back/removing 0-byte journal), check bytes at offset 18 and 19; if they are `\x01\x01`, write `\x02\x02` at offset 18 (`dd` with `bs=1 seek=18 count=2 conv=notrunc`) so SQLite opens `data.db` in persistent WAL mode.
   - Add `optimize_openlist_config()`:
     - When `$DATA_DIR/config.json` exists, idempotently ensure `"filter"` has `"enable": true`, `"max_size": 10`, and `"max_backups": 3` (replacing default `"max_size": 50` and `"max_backups": 30`, and enabling `log.filter.enable`), while preserving all other user settings.
   - Invoke `patch_openlist_binary_sqlite_dsn`, `ensure_sqlite_wal_and_clean_locks`, and `optimize_openlist_config` in `main()` before starting `$OPENLIST_BINARY`, and also call `ensure_sqlite_wal_and_clean_locks` / `optimize_openlist_config` inside `sync_companion_apk_and_config` so first-boot newly generated `data.db` and `config.json` are immediately hardened.
2. In `tests/test_module_scripts.sh`:
   - Add TDD tests verifying:
     - `patch_openlist_binary_sqlite_dsn` replaces `%s?_journal=WAL&_vacuum=incremental` with `%s?_pragma=busy_timeout(10000)&_v=1` without changing binary file byte size!
     - `ensure_sqlite_wal_and_clean_locks` upgrades a valid SQLite v3 header (`offset 18..19` from `01 01` to `02 02`) and leaves non-SQLite or already-WAL files intact.
     - `optimize_openlist_config` updates `log.filter.enable` from `false` to `true`, `max_size` from `50` to `10`, and `max_backups` from `30` to `3` while keeping `http_port`, `jwt_secret`, etc. unchanged.

## Task 2: Author ADR 0002 & Update Project Documentation

### Files Owned
- `docs/adr/0002-sqlite-wal-and-busy-timeout-patch.md`
- `README.md`
- `OpenList-Magisk/README.md`

### Requirements
1. Create `docs/adr/0002-sqlite-wal-and-busy-timeout-patch.md` following `ADR-FORMAT.md`.
2. Update `README.md` and `OpenList-Magisk/README.md` to document SQLite Concurrency Self-Healing（SQLite 并发锁自愈） and WebDAV log noise reduction.
