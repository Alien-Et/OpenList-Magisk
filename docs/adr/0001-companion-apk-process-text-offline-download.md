# 内置 PROCESS_TEXT 伴侣 APK 实现浏览器划词 115 离线下载

在 `OpenList-Magisk` 模块中内置轻量级伴侣应用（`OpenListHelper.apk`），通过注册 Android 原生 `android.intent.action.PROCESS_TEXT` 拦截浏览器划词文本，弹出底部半屏确认弹窗（默认路径 `/115/影视/`，默认驱动 `115 Open`），并在确认后调用本地 `http://127.0.0.1:5244/api/fs/add_offline_download` 提交离线下载任务；鉴权 Token 与配置通过 `service.sh` 从 OpenList 数据目录（`$DATA_DIR/data.db` 与 `offline.conf`）自动提取并同步至伴侣应用私有目录。

## Considered Options

- **内置 Companion APK（已选）**：利用 Android 系统原生 `PROCESS_TEXT` 机制，无需无障碍权限或后台常驻轮询剪贴板，跨所有浏览器（Chrome、Via、Edge、Firefox 等）通用，且支持弹出原生半屏确认框修改目标路径。
- **浏览器油猴脚本**：仅在支持扩展/脚本的特定浏览器中生效，且受浏览器 Mixed Content（HTTPS 页面请求 `http://127.0.0.1:5244`）与 CORS 策略限制。
- **端侧直连 115 接口**：需要在伴侣应用中重复维护 115 Open OAuth Token 刷新与目录 CID 解析逻辑，违背复用原则。

## Consequences

- 伴侣 APK 运行在普通应用沙箱 UID 下，无法直接读取 `/data/adb/openlist`（权限 `0700`）；因此由具备 Root 权限的 `service.sh` 在启动时从 `$DATA_DIR/data.db` 自动提取 API Token 并与 `$DATA_DIR/offline.conf` 合并写入 `/data/data/io.openlist.helper/files/offline.conf`，实现零 GUI 配置与沙箱安全读取。
