# OpenList Magisk/KernelSU/APatch 模块

[![Release](https://img.shields.io/github/v/release/Alien-Et/OpenList-Magisk)](https://github.com/Alien-Et/OpenList-Magisk/releases)
[![License](https://img.shields.io/github/license/Alien-Et/OpenList-Magisk)](https://github.com/Alien-Et/OpenList-Magisk/blob/main/LICENSE)

OpenList Magisk 模块将 [OpenList](https://github.com/OpenListTeam/OpenList) 文件服务器集成到 Android 系统中，通过 Magisk、KernelSU 或 APatch 以系统化方式运行，支持 ARM 和 ARM64 架构。

## 功能亮点

- **多框架支持**：同时兼容 Magisk、KernelSU 和 APatch
- **灵活安装选项**：支持三种安装位置
  - data/adb/openlist
  - 模块目录/bin
  - system/bin
- **数据目录可选**：支持两种数据存储位置
  - /data/adb/openlist/
  - /storage/emulated/0/Android/openlist/
- **账号初始化**：首次打开网页按向导设置管理员账号
- **动态服务管理**：通过 Magisk/KernelSU 的"动作"按钮一键控制服务
- **WebUI 控制台**（KernelSU / APatch）：状态、启停、在线更新、改配置、改账号、存储与任务、迁移目录、路径自检
- **命令行控制**：`control.sh` 三家通用
- **界面**：毛玻璃 + 大圆角，自动/浅色/深色主题
- **智能网络适配**：自动识别 WiFi 和移动网络 IP
- **日志支持**：详细的运行日志记录

## 截图展示

| 安装界面 | KernelSU WiFi 网络 | KernelSU 移动网络 |
|---------|------------------|------------------|
| ![安装界面](install-interface.jpg) | ![KernelSU WiFi 网络](kernelsu-wifi.jpg) | ![KernelSU 移动网络](kernelsu-mobile-network.jpg) |

## 系统要求

- Android 设备（支持 ARM 或 ARM64 架构）
- Magisk v20.4 或更高版本，或 KernelSU
- Root 权限

## 框架兼容性

本模块同时支持 **Magisk**、**KernelSU** 和 **APatch** 三大 Android Root 框架：

### Magisk 支持
- 支持 Magisk v20.4 及以上版本
- 完全兼容 Magisk 模块系统
- 支持 Magisk 动作按钮控制
- 支持 Magisk 更新机制

### KernelSU 支持  
- 支持 KernelSU 最新版本
- 完全兼容 KernelSU 模块系统
- 支持 KernelSU 动作按钮控制
- 支持 KernelSU 更新机制

### APatch 支持
- 支持 APatch 最新版本
- 完全兼容 APatch 模块系统
- 支持 APatch 动作按钮控制
- 支持 APatch 更新机制

### 通用特性
- 自动检测运行环境（Magisk/KernelSU/APatch）
- 统一的路径配置和处理
- 兼容的卸载机制
- 完整的日志记录系统

## 安装步骤

1. **下载模块**
   - 从 [GitHub Releases](https://github.com/Alien-Et/OpenList-Magisk/releases) 下载最新版本

2. **安装配置**
   - 打开 Magisk 管理器、KernelSU 管理器 或 APatch 管理器
   - 选择"从本地安装"
   - 进入安装配置界面：
     - 选择二进制文件安装位置
     - 选择数据目录存储位置
     - 更新安装时如果检测到旧数据，会多问一句要不要一起迁过来

3. **完成安装**
   - 等待安装完成
   - 重启设备

## 使用说明

### 服务管理
- 系统启动后自动运行
- 通过 Magisk/KernelSU/APatch "动作"按钮控制服务
- 服务状态显示在 module.prop：
  - 运行中：显示访问地址和数据目录
  - 已停止：显示启动提示

### 访问方式
- Web 界面访问：`http://<设备IP>:5244`
- 首次打开会进入安装向导，按提示设置管理员账号和密码
- 完成向导前，WebUI 里存储、离线任务、设置会提示「还没有管理员账号」

### 数据存储
- 默认数据目录：`/data/adb/openlist/`
- 日志文件位置：与数据目录相同
- **卸载不会删除数据**：卸载只清理二进制，数据目录会保留。确实要连数据一起删，卸载前执行
  `touch /data/adb/modules/openlist/.delete_data_on_uninstall`，或卸载后手动 `rm -rf`。

## 故障排除

### 常见问题
1. **无法访问服务**
   - 检查网络连接
   - 检查服务状态：`pgrep -f openlist`
   - 查看日志文件
   - 手动重启服务：`su -c /data/adb/modules/openlist/service.sh`

2. **IP 地址获取失败**
   - 确认 WiFi 或移动网络已连接
   - 检查网络接口状态
   - 查看模块日志

3. **服务无法启动**
   - 检查二进制文件权限
   - 确认数据目录可写
   - 查看详细日志

### 手动操作
- 停止服务：`su -c pkill -f openlist`
- 启动服务：`su -c /data/adb/modules/openlist/service.sh`
- 查看日志：`cat /data/adb/modules/openlist/service.log`

## 更新说明
- 支持通过 Magisk/KernelSU/APatch 更新检查
- 更新不会清除现有数据
- 可在安装时重新选择配置选项

## 更新日志

> 本次为模块更新，非 OpenList 官方二进制更新。

### v4.2.10.1

- **修复** WebUI 管理员账号密码框输不进字：不再用 `type=password`（部分 WebView 的密码管理器/自动填充会抢焦点，输入框直接失效），改 `type=text` + `-webkit-text-security:disc` 遮罩，管理员卡片加「显示密码」切换；Token 框同步处理
- **修复** 点「立即更新」只弹一句「更新失败」且没有任何原因：更新改成后台跑（`update-bg` 用 `setsid` 独立会话 + `update-status` 轮询），宿主 exec 返回/超时不会再掐断下载；失败原因优先显示 `error=`，没有就显示 stderr / 退出码，页面刷新还能接着上次的进度
- **调整** 版本号增加第四段：`v4.2.10.1` 表示「二进制还是 4.2.10，只是模块改了」，`versionCode` 用新公式 `主×1000000 + 次×10000 + 修×100 + 修订`（→ `4021001`），始终大于上一版，管理器的更新检查不会漏
- **修复** WebUI 更新提示文案与实际流程不符：下载、md5 校验、解压都在服务运行中完成，只在替换二进制前短暂停服务
- **重构** 「所有版本」列表只走 GitHub 官方 API（`per_page=100` 分页翻到底），去掉国内代理与 HTML 兜底；限流时明确报「GitHub 限流」，可把 PAT 写进模块目录 `.github_token`（60 → 5000 次/小时）
- **优化** 迁移页的二进制迁移与数据目录统一成点选胶囊，去掉多余输入框
- **修复** 重启后不自动启动：service.sh 原来先 `mkdir` 数据目录再等 `sys.boot_completed`，数据目录在 `/sdcard` 时会因 FUSE 未挂载直接退出；改为先等启动完成、外部存储可写再动目录
- **新增** WebUI「下载镜像」：下拉列出 15 个国内镜像并显示实测延迟（自动选择 / 直连 / 自定义），选择持久化到 `<数据目录>/mirror.conf`；自动模式按实测延迟从快到慢排（缓存 30 分钟）
- **优化** 无代理环境：API 失败时版本列表/最新版本用缓存兜底（`stale=1`），指定版本安装跳过 API 直接拼下载地址走镜像；下载过程显示「已下载 N MB」
- **优化** WebUI 打开速度：各区块并行加载、GitHub API 走 gzip（5.39 MB → 412 KB）、路径体检与版本列表本地缓存
- **新增** 安装界面可选数据迁移：更新安装时检测到旧数据且换了目录，会多一次音量键确认（音量+ 迁移并删源 / 音量- 跳过，90 秒无操作按跳过）；校验不过则旧数据原样保留

> 本次更新只测试到「WebUI 能正常用」这一步，没有做完整回归，可能还有没挖出来的隐藏 bug。遇到问题请到仓库提 issue。

### v4.1.10 (2026-02-22)

- **修复** versionCode 计算逻辑，支持三位版本号（v4.1.10 → 4110）
- **修复** 安装脚本占位符替换问题
- **修复** sed 替换时变量被错误展开的问题
- **优化** action.sh 启停服务的输出提示信息
- **改进** 移除冗余的占位符验证逻辑

## 数据迁移说明
1. 安装时可选择数据目录与二进制位置
2. 装好后也能在 WebUI 迁移页随时改：选目标目录 → 「开始迁移」
3. 迁移 = 移动：复制、校验文件数与 data.db 的 md5 全部通过后，才同步 `config.json` 路径并删除源目录
4. 二进制迁移同理，校验一致后删除旧文件，不会同时留两份
5. 迁移完成后 WebUI 自动刷新状态、路径体检与日志

## 征求意见：要不要把内嵌二进制砍掉？

想了两天，倾向是：**模块里不再放二进制**，安装时让用户选「在线下载对应架构」，模块体积能从一百多兆掉到十几 KB。

好处很直接：OpenList 发版不用再跟着打一百多兆的包，仓库和 Release 都轻，用户也只需要自己架构那一份。

但有个绕不过去的前提：Magisk 用户没有 WebUI，`ksu.exec` 那条路走不了，只能靠模块卡片的「操作」按钮或终端脚本更新、回退。要是安装时正好没网，或者哪天镜像全挂，模块里又没二进制，这台机器就起不来了。

所以大概有三个方向：

1. **纯在线**：包最小，但断网装不上，recovery 里刷机基本无解
2. **安装时二选一**：问一句「在线下载（小包）/ 用内置二进制（大包）」，那就得继续维护 full 包
3. **只留一份兜底**：内置 arm64（绝大多数机器），arm 走在线下载，体积能砍掉一半左右

目前我偏向 2，但 2 等于还要发 full 包，减负有限；3 更实际，代价是少数 32 位设备断网时装不了。

你们实际怎么用？有没有「断网刷机」这种场景？评论区或 issue 里说一声，我再定。

## 贡献
- 欢迎提交 Issue 和 Pull Request
- 问题反馈：[GitHub Issues](https://github.com/Alien-Et/OpenList-Magisk/issues)

## 许可证
本项目基于 [MIT 许可证](LICENSE) 发布。

## 文档

- [01. 整体架构](docs/01.整体架构.md)
- [02. control 命令](docs/02.control命令.md)
- [03. WebUI 界面](docs/03.WebUI界面.md)
- [04. 更新与回滚](docs/04.更新与回滚.md)
- [05. 迁移与路径](docs/05.迁移与路径.md)
- [06. 安装选项矩阵](docs/06.安装选项矩阵.md)
- [07. 总结](docs/07.总结.md)
