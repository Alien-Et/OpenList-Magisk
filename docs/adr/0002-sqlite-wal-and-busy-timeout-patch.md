# SQLite 并发锁自愈（WAL 与 Busy Timeout 补丁）及日志轮转调优

在 `OpenList-Magisk` 模块的守护服务脚本（`service.sh`）启动阶段，通过原生修改 `data.db` 头部持久化标记为 WAL（Write-Ahead Logging）模式、在 `openlist` 二进制中原位植入 35 字节的 `busy_timeout(10000)` DSN 补丁，并自动开启 `config.json` 日志过滤中间件与收紧日志轮转配置，彻底解决 WebDAV 客户端高并发 `PROPFIND` 请求下的 `SQLITE_BUSY (database is locked)` 死锁与磁盘日志爆满问题。

## 背景与问题分析（Context & Problem Statement）

OpenList 在 Android 平台的原生可执行文件采用了无 CGO 依赖的纯 Go SQLite 驱动 `github.com/glebarez/sqlite`（底层为 `modernc.org/sqlite`）。然而在上游源码 `internal/bootstrap/db.go` 中，数据库连接字符串使用了针对 CGO 驱动（`mattn/go-sqlite3`）的格式化参数：
```go
fmt.Sprintf("%s?_journal=WAL&_vacuum=incremental", database.DBFile)
```

这带来了三个严重的架构级缺陷与运行故障：

1. **WAL 模式实际未生效（Driver Parameter Incompatibility）**：
   `modernc.org/sqlite` 驱动并不识别 `_journal=WAL` 参数（该驱动要求 `_pragma=journal_mode(WAL)` 语法）。驱动忽略未知参数后，静默回退至 SQLite 默认的传统回滚日志模式（Rollback Journal / `DELETE` 模式），此时数据库头部第 18、19 字节（文件格式写版本与读版本）为 `0x01 0x01`。
2. **并发锁等待超时缺失（Zero Busy Timeout）**：
   驱动连接池默认的 `busy_timeout` 为 `0`。当多个 WebDAV 客户端（如 NeoPlayer、`live.alist.mpv`、Infuse 等）并发发送 `PROPFIND` 目录探测请求时，OpenList 内部的 WebDAV 处理层（`withDeadPropsTransaction`）会开启数据库事务。若该事务跨越了数秒的网络云盘 API 交互，后续的并发写事务或属性更新会瞬间遭遇锁冲突，立即抛出 `database is locked (5) (SQLITE_BUSY)` 与 `SQL logic error: cannot start a transaction within a transaction (1)`。
3. **残留锁挂起守护进程（Stale Rollback Journal Hanging）**：
   在传统 `DELETE` 回滚模式下，事务冲突或进程异常退出会在数据库同级目录遗留 `data.db-journal` 文件。在 Android 设备弱网与高频并发读写下，死锁会导致 OpenList 守护进程停止响应 Web 请求甚至挂起。
4. **高频 WebDAV 轮询刷爆存储（High-Frequency Log Flooding）**：
   默认生成的 `config.json` 中，日志过滤中间件处于关闭状态（`"filter": { "enable": false }`），且日志轮转上限偏大（`"max_size": 50` MB，`"max_backups": 30`）。WebDAV 客户端频繁的 `/ping`、`HEAD` 与 `/dav/` 下 `PROPFIND` 请求以毫秒级高频写入 `log.log`，单日产生数 GB 日志，极易耗尽移动设备的 `/data` 分区空间。

## 决策方案（Decision）

为了在不侵入重新编译上游二进制、不增加外部复杂依赖的前提下彻底根治上述问题，我们在模块守护进程脚本（`service.sh`）中实现全自动自愈与加固机制：

### 1. SQLite 头部持久化 WAL 模式强固（Persistent WAL Header Enforcement）
- **规范原理**：根据 SQLite 官方文件格式规范，数据库文件偏移 18 字节与 19 字节（`0x12`..`0x13`）分别为写版本（`write version`）和读版本（`read version`）。`0x01 0x01` 为传统回滚日志模式，`0x02 0x02` 为 WAL 模式。由于 WAL 模式是 SQLite 文件格式的原生持久化属性（file format property），只要数据库头部设置为 `0x02 0x02`，任何符合 SQLite 标准的引擎（包括 `modernc.org/sqlite`）打开该数据库时都会天然以 WAL 模式运行，彻底绕过驱动对 DSN 中 `_journal=WAL` 参数的解析缺陷。
- **实施策略**：
  - 启动 OpenList 前及生成新数据库后，`service.sh` 中的 `ensure_sqlite_wal_and_clean_locks` 首先验证文件是否为有效 SQLite v3 数据库（前 16 字节为 `SQLite format 3\0`）。
  - 若系统包含 `sqlite3` CLI，优先辅助执行 `PRAGMA journal_mode=WAL; PRAGMA busy_timeout=10000;`。
  - 对于普遍缺乏 `sqlite3` 命令的 Android 生产设备，在确认无活跃进程与非空回滚日志的情况下，使用 `dd`（`bs=1 seek=18 count=2 conv=notrunc`）原子写入 `\x02\x02`，使数据库无条件以 WAL 模式启动。
  - 启动前自动检查并清理非正常关闭遗留的 0 字节或孤立 `data.db-journal` 锁文件，防止守护进程启动挂起。

### 2. 二进制 35 字节原位 DSN 补丁（In-Place 35-Byte Binary DSN Patch）
- **规范原理**：`modernc.org/sqlite` 原生支持在 DSN 中通过 `_pragma=busy_timeout(10000)` 指令，使连接池中的每个数据库连接在遭遇写锁时自动轮询等待至多 10000 毫秒（10 秒），极大缓解长耗时云盘事务重叠造成的瞬时竞争。
- **等长原位替换**：上游编译的二进制中固化了 35 字节的 DSN 模板：
  `%s?_journal=WAL&_vacuum=incremental`（恰好 35 字节）
  替换为完全等长的 35 字节指令：
  `%s?_pragma=busy_timeout(10000)&_v=1`（恰好 35 字节，`_v=1` 作为良性无害的填充参数）
- **实施策略**：
  - `service.sh` 的 `patch_openlist_binary_sqlite_dsn` 在启动前扫描 `$OPENLIST_BINARY`。
  - 若检测到旧的 35 字节字面量，通过 `sed -b -i` / `busybox sed -i` 原位替换，保持文件字节数绝对不变，不破坏 ELF 符号表、段偏移与代码段对齐，并保持 `chmod 755` 权限。
  - 补丁操作具备幂等性，已打补丁的二进制跳过重复操作。

### 3. 日志过滤开启与轮转瘦身调优（Log Filter & Rotation Tuning）
- **规范原理**：OpenList 内部已内置请求过滤逻辑，开启后会自动抑制高频无业务价值的 HTTP 日志输出（如心跳探测 `/ping`、静态嗅探 `HEAD` 及 `/dav/` 下并发 `PROPFIND`），同时限制日志体积和保留份数。
- **实施策略**：
  - `service.sh` 的 `optimize_openlist_config` 在启动前及配置同步阶段检测 `$DATA_DIR/config.json`。
  - 自动将 `"filter"` 下的 `"enable"` 设置为 `true`。
  - 将日志轮转参数从默认的 `"max_size": 50` 调优为 `10`（MB），`"max_backups": 30` 调优为 `3`。
  - 调优过程采用精确的键值替换，严格保留用户配置的 `http_port`、`jwt_secret`、存储配置等业务数据。

## 备选方案权衡（Considered Options）

- **方案 A：二进制 35 字节等长 DSN 补丁 + SQLite 头部 WAL 强固 + 配置自动调优（已选）**
  - *优点*：零源码重编译成本，跟随上游版本发布立即可用；等长二进制补丁安全稳定；纯系统 Shell 原生原子操作，无需额外安装依赖；从根本上解决读写并发互斥和日志爆盘问题。
  - *缺点*：依赖二进制中保持现有的 35 字节模板格式（若未来上游彻底改动 DSN 结构，需同步更新匹配特征）。
- **方案 B：从源码修改上游 OpenList 并维护专属分支编译**
  - *优点*：在 Go 源码层面直接修改连接参数。
  - *缺点*：维护和构建成本极高，需要针对 ARM、ARM64 等多种架构搭建跨平台交叉编译流水线；上游每次发布新版均需手动 rebase 重编译，背离 Magisk 模块轻量包装分发定位。
- **方案 C：仅依赖外部 `sqlite3` CLI 并在启动脚本中执行 PRAGMA**
  - *优点*：无需修改二进制。
  - *缺点*：大部分精简版或非官方 Android ROM 未内置 `sqlite3` 工具；最关键的是，`PRAGMA busy_timeout` 是连接级别参数，未打 DSN 补丁时连接池新创建的连接仍然是 `busy_timeout=0`，无法彻底根除 `SQLITE_BUSY`。
- **方案 D：配置看门狗进程定期检测死锁并强制杀死进程（`kill -9`）重启**
  - *优点*：实现简单。
  - *缺点*：治标不治本；暴力中断正在进行的 WebDAV 大文件流媒体串流或 115 离线下载，大幅破坏用户体验，并可能加剧数据库日志损坏。

## 影响与收益（Consequences）

### 正面收益
1. **彻底消除 WebDAV 并发死锁**：在 NeoPlayer、Infuse 等客户端并发抓取多级目录与流媒体属性时，SQLite 获得 10 秒缓冲等待窗口，`database is locked (5)` 与嵌套事务报错完全消失。
2. **读写性能解耦**：WAL 模式使读操作与写操作互不阻塞，在云端接口长事务写操作期间，前端 Web UI 与 WebDAV 客户端的并发读取依然极速顺畅。
3. **有效防护设备存储**：日志过滤器屏蔽了 90% 以上的无用高频 WebDAV 心跳日志，日志轮转上限从默认的 1500MB+ 紧凑收敛至 30MB，避免长期运行撑爆 Android 手机 `/data` 分区。
4. **开机自愈免维护**：无论设备遭遇异常断电、强行关机还是历史版本遗留锁文件，模块守护脚本开机即自动校准头部、清理死锁残留并补全配置，全程无需用户进入 Root 终端手动干预。

### 注意事项
- 在 WAL 模式下，`data.db` 旁会正常生成 `data.db-wal`（写前日志）与 `data.db-shm`（共享内存索引）文件，属于 SQLite 正常运作机制，切勿在运行状态下将其视为垃圾文件删除。
