# OpenList-Magisk

在 AndroidRoot 环境（Magisk / KernelSU / APatch）中以后台守护进程方式运行 OpenList 服务，并通过系统级伴侣应用提供划词磁力离线下载能力。

## Language

**OpenList Daemon（OpenList 守护服务）**:
由模块在系统启动阶段拉起并常驻后台的 `openlist` 原生二进制进程，默认监听本地 `5244` 端口，统一托管网盘挂载与离线下载任务。
_Avoid_: 后台脚本, 服务端, AList

**Companion APK（伴侣应用）**:
随 Magisk 模块内置安装的轻量级 Android 辅助应用（`OpenListHelper`），负责向系统注册 `PROCESS_TEXT` 划词菜单与磁力协议入口，展示半屏确认弹窗并将任务转发给本地 OpenList Daemon。
_Avoid_: 插件, 悬浮窗应用, 客户端

**Text Selection Menu（系统划词菜单）**:
用户在浏览器或任意应用中长按选中文本时，由 Android 系统通过 `android.intent.action.PROCESS_TEXT` 聚合弹出的上下文操作菜单。
_Avoid_: 右键菜单, 剪贴板菜单, 气泡框

**Offline Confirm Sheet（离线确认半屏弹窗）**:
点击划词菜单“115 离线”后弹出的底部半屏对话框，用于预览解析出的磁力链接、确认或修改本次投递的目标虚拟路径（支持通过交互式选择器浏览挂载目录或点击预设标签切换），并在确认提交后触发双阶段缓存刷新。
_Avoid_: 设置页, 主界面

**Target Virtual Path（目标虚拟路径）**:
离线下载任务完成后在 OpenList 虚拟文件系统中转存落盘的挂载目录路径（默认 `/115/影视/`）。
_Avoid_: 本地路径, 物理目录, 下载文件夹

**Interactive Folder Browser（交互式文件夹选择器）**:
伴侣应用离线确认弹窗中内置的目录浏览对话框，基于 OpenList `/api/fs/list` 接口，支持直观逐级浏览挂载点与子文件夹并快速选定落盘目录，点击“🔄 刷新”或“🔄 重试”时显式传入 `"refresh": true` 强制穿透并刷新 OpenList 目录缓存。
_Avoid_: 系统文件选择器, SAF 文件管理器

**Directory Cache Auto-Refresh（目标目录缓存自动刷新）**:
伴侣应用在成功添加 115 离线任务后执行的缓存同步机制，通过即时与 1.5 秒延迟双阶段向 OpenList 接口（`POST /api/fs/list`）发送 `"refresh": true`，强制失效并更新目标路径的内存目录缓存，使 Web UI 与 WebDAV 客户端无需手动刷新即可立即可见云端秒传与离线完成文件。
_Avoid_: 定时轮询, 手动刷新

**Preset Path Chips（预设路径快速选择标签）**:
伴侣应用离线确认弹窗中目标虚拟路径输入框下方的横向滑动标签栏，展示 `offline.conf` 中配置的常用落盘路径及最近选择记录，支持单次点击直接填入。
_Avoid_: 快捷方式, 收藏夹

**Offline Engine（离线下载引擎）**:
OpenList 内部执行离线任务的驱动标识（本项目固定默认使用 `115 Open` 官方开放平台云端离线驱动）。
_Avoid_: 下载器, 插件名

**Offline Config（离线配置文件）**:
位于 OpenList 数据目录下的键值配置文件（`offline.conf`），由模块启动脚本自动同步 OpenList API Token、端口与默认路径，并桥接至伴侣应用私有目录供免权限读取。
_Avoid_: 数据库配置, 环境变量

**Companion Menu Visibility（伴侣菜单可见性）**:
伴侣应用三个系统级触发入口（`PROCESS_TEXT` 划词菜单、`SEND` 分享菜单、`VIEW` 磁力链接拦截）在 Android 系统中的启用与隐藏状态，与 OpenList Daemon 的在线存活状态、模块启用状态以及 115 网盘存储（`115 Cloud` / `115 Open`）的添加与启用状态强绑定（未添加 115 存储或所有 115 存储处于禁用时自动隐藏）。
_Avoid_: 卸载应用, 杀后台

**SQLite Concurrency Self-Healing（SQLite 并发锁自愈）**:
模块启动阶段针对 OpenList 数据库与二进制执行的并发防死锁加固机制，通过将 `data.db` 持久化为 WAL（Write-Ahead Logging）模式、清理异常残留回滚日志，并为数据库驱动注入 `busy_timeout` 锁等待超时，消除 WebDAV 与 API 高频并发访问下的 `SQLITE_BUSY` 死锁。
_Avoid_: 删库重建, 定时重启脚本


