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
点击划词菜单“115 离线”后弹出的底部半屏对话框，用于预览解析出的磁力链接、确认或修改本次投递的目标虚拟路径，并触发最终提交。
_Avoid_: 设置页, 主界面

**Target Virtual Path（目标虚拟路径）**:
离线下载任务完成后在 OpenList 虚拟文件系统中转存落盘的挂载目录路径（默认 `/115/影视/`）。
_Avoid_: 本地路径, 物理目录, 下载文件夹

**Offline Engine（离线下载引擎）**:
OpenList 内部执行离线任务的驱动标识（本项目固定默认使用 `115 Open` 官方开放平台云端离线驱动）。
_Avoid_: 下载器, 插件名

**Offline Config（离线配置文件）**:
位于 OpenList 数据目录下的键值配置文件（`offline.conf`），由模块启动脚本自动同步 OpenList API Token、端口与默认路径，并桥接至伴侣应用私有目录供免权限读取。
_Avoid_: 数据库配置, 环境变量
