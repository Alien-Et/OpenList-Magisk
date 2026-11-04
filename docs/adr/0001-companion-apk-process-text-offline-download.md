# 内置 PROCESS_TEXT 伴侣 APK 实现浏览器划词与磁力超链接 115 离线下载

在 `OpenList-Magisk` 模块中内置轻量级伴侣应用（`OpenListHelper.apk`），通过注册 Android 原生 Intent Filter 拦截浏览器文本划选、磁力超链接点击与分享，弹出底部半屏确认弹窗（默认路径 `/115/影视/`，默认驱动 `115 Open`），并在确认后调用本地 `http://127.0.0.1:5244/api/fs/add_offline_download` 提交离线下载任务；鉴权 Token 与配置通过 `service.sh` 从 OpenList 数据目录（`$DATA_DIR/data.db` 与 `offline.conf`）自动提取并同步至伴侣应用私有目录。

## 触发入口（Three Trigger Entrypoints）

针对 Android 浏览器（Chrome、Edge、Via、Firefox、WebView 等）中磁力链接的不同形态与用户交互习惯，伴侣 APK 的 `ProcessTextActivity` 声明了三种原生 Intent 触发入口：

1. **文本划选菜单 (`android.intent.action.PROCESS_TEXT`)**：
   - 过滤条件：`category.DEFAULT`，`mimeType="text/plain"`。
   - 场景：网页中为纯文本展示的磁力链接或 40 位/32 位 Hash（非超链接），长按划选后在系统划词菜单中点击 "115 离线"。
2. **超链接长按分享 (`android.intent.action.SEND`)**：
   - 过滤条件：`category.DEFAULT`，`mimeType="text/plain"`。
   - 场景：网页中为 `<a href="magnet:?xt=...">` 超链接，长按超链接弹出浏览器专属上下文菜单（如“复制链接地址”、“共享链接”），点击“共享链接”并在应用面板中选择 "115 离线"。
3. **超链接直接点击 (`android.intent.action.VIEW`)**：
   - 过滤条件：`category.DEFAULT`，`category.BROWSABLE`，`<data android:scheme="magnet" />`。
   - 场景：在任意网页或应用中直接单击 `magnet:` 超链接，系统直接调起伴侣应用弹出离线确认半屏弹窗，免去长按与多步复制。

### 多来源输入防御提取
`ProcessTextActivity.extractIncomingText(Intent intent)` 统一支持以下传递格式并按优先级提取：
- `Intent.EXTRA_PROCESS_TEXT`（划词）
- `Intent.EXTRA_TEXT`（分享文本）
- `intent.getDataString()`（直接点击的 URI）
- `intent.getClipData()`（部分浏览器通过剪贴板 ClipData 传递的文本或 URI）

## 交互式目录浏览与预设标签（Interactive Folder Picker & Preset Chips）

离线确认半屏弹窗（`Offline Confirm Sheet`）内置了虚拟路径交互式浏览与快速切换能力：

1. **预设路径快速选择（Preset Path Chips）**：
   - 在路径输入框下方渲染横向滑动标签栏（`HorizontalScrollView`），预载 `offline.conf` 中配置的 `PRESET_PATHS`（默认 `/115/影视/` 与 `/115/`）。
   - 用户单按标签即可将对应路径瞬间填入输入框，免去在移动设备端频繁手打长路径。
   - 每次提交离线任务或从目录选择器确认路径后，新路径自动追加至用户私有配置 `user_offline.conf` 的预设列表最前端，实现最近使用路径的动态记忆。

2. **交互式文件夹选择器（Interactive Folder Browser）**：
   - 点击路径输入框右侧的“📁 选择目录”按钮，弹出独立的目录浏览底部弹窗。
   - 弹窗通过后台线程异步请求 OpenList 原生目录接口 `POST /api/fs/list`（携带伴侣私有鉴权 Token，过滤仅展示文件夹对象 `is_dir = true`）。
   - 支持逐级钻取进入子目录（`joinVirtualPath`）、点击“⬆️ 上级目录”返回父路径（`parentVirtualPath`）、点击“🏠 根目录 (/)”直达挂载根节点，以及“🔄 刷新”重新载入。
   - 若用户初始配置路径不存在或网络异常导致读取失败，界面友好展示错误原因并提供“📂 退回根目录 (/)”与“🔄 重试”快捷按钮，便于用户从所有 OpenList 存储挂载点（如 `/115`、`/quark`、`/本地存储` 等）重新选择。
   - 选定目标目录后点击“✅ 选择当前目录”，自动规范化路径格式并写回主弹窗输入框与预设标签栏。

## 容错与自愈机制

1. **Token 后缀防御过滤**：
   - `service.sh` 从 SQLite 提取字段时，若旧版本脚本带入字段类型后缀 `"string"`（如 `openlist-...string`），`OfflineHelperCore.sanitizeToken` 在 APK 侧自动识别并剔除结尾 `"string"`，确保无论配置来自历史同步还是直接修改，`Authorization` 请求头始终合法。
2. **开机 Wi-Fi 未就绪导致 115 存储未初始化自愈**：
   - Android 开机引导阶段，OpenList 守护进程可能早于 Wi-Fi DNS（`proapi.115.com`）解析就绪启动，导致 `/115` 存储初始化失败处于断开状态。
   - `OfflineHelperCore.submitOfflineDownload` 在捕获到 `code != 200` 且提示中包含 `"storage"`、`"not init"` 或 `"disabled"` 时，自动向 OpenList 发送 `POST /api/admin/storage/load_all` 触发存储全量重载，等待 800ms 后自动重试一次离线下载任务，实现用户无感知的网络延迟自愈。
3. **伴侣菜单可见性与守护服务生命周期强绑定（Companion Menu Visibility Lifecycle Sync）**：
   - 伴侣应用的 `ProcessTextActivity` 在 `AndroidManifest.xml` 中默认声明 `android:enabled="false"`，确保首次安装未启动服务或启动失败时，系统划词菜单、分享菜单与磁力链接拦截入口默认隐藏。
   - 当 `service.sh` 确认 OpenList Daemon 启动成功（且模块未被禁用）时，通过 `pm enable io.openlist.helper/io.openlist.helper.ProcessTextActivity` 动态暴露全部触发入口。
   - 当用户在 Root 管理器中点击“操作”（`action.sh`）停止服务、关闭模块启用开关（生成 `$MODDIR/disable` 或 `remove`），或开机启动失败时，立即通过 `pm disable io.openlist.helper/io.openlist.helper.ProcessTextActivity` 隐藏入口，并通过 `/data/adb/service.d/openlist_companion_sync.sh` 与后台状态守卫确保重启或模块禁用后入口不会残留。

## Considered Options

- **内置 Companion APK（已选）**：利用 Android 系统原生 `PROCESS_TEXT`、`SEND` 与 `VIEW` 机制，无需无障碍权限或后台常驻轮询剪贴板，跨所有浏览器（Chrome、Via、Edge、Firefox 等）通用，且支持弹出离线确认半屏弹窗修改目标路径。
- **浏览器油猴脚本**：仅在支持扩展/脚本的特定浏览器中生效，且受浏览器 Mixed Content（HTTPS 页面请求 `http://127.0.0.1:5244`）与 CORS 策略限制。
- **端侧直连 115 接口**：需要在伴侣应用中重复维护 115 Open OAuth Token 刷新与目录 CID 解析逻辑，违背复用原则。

## Consequences

- 伴侣 APK 运行在普通应用沙箱 UID 下，无法直接读取 `/data/adb/openlist`（权限 `0700`）；因此由具备 Root 权限的 `service.sh` 在启动时从 `$DATA_DIR/data.db` 自动提取 API Token 并与 `$DATA_DIR/offline.conf` 合并写入 `/data/data/io.openlist.helper/files/offline.conf`，实现零 GUI 配置与沙箱安全读取。
