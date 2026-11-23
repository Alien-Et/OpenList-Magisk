# OpenList Magisk/KernelSU/APatch 模块

[![Release](https://img.shields.io/github/v/release/Alien-Et/OpenList-Magisk?label=release&sort=semver)](https://github.com/Alien-Et/OpenList-Magisk/releases)
[![License](https://img.shields.io/github/license/Alien-Et/OpenList-Magisk?label=license)](https://github.com/Alien-Et/OpenList-Magisk/blob/main/LICENSE)
[![Bundled binary](https://img.shields.io/badge/bundled%20openlist-AGPL--3.0-orange)](https://github.com/Alien-Et/OpenList-Magisk/blob/main/THIRD-PARTY.md)
[![Arch](https://img.shields.io/badge/arch-arm%20%7C%20arm64-blueviolet)](#系统要求)
[![Platform](https://img.shields.io/badge/platform-Magisk%20%7C%20KernelSU%20%7C%20APatch-success)](#系统要求)

> 第一次用？先看 **[安装包与更新通道说明](https://github.com/Alien-Et/OpenList-Magisk/discussions/39)** —— 5 个包怎么选、两条更新通道有什么区别，都在那里。

> **许可提示**：本模块的脚本、WebUI 与文档使用 **MIT** 许可（见 [LICENSE](LICENSE)）；安装包内打包的 OpenList 可执行文件（`openlist-arm` / `openlist-arm64`）来自上游 [OpenListTeam/OpenList](https://github.com/OpenListTeam/OpenList)，使用 **AGPL-3.0**（见 [THIRD-PARTY.md](THIRD-PARTY.md) 与 [LICENSE-AGPL-3.0.txt](LICENSE-AGPL-3.0.txt)）。

OpenList 模块将 [OpenList](https://github.com/OpenListTeam/OpenList) 文件服务器集成到 Android 系统中，通过 Magisk、KernelSU 或 APatch 以系统化方式运行，支持 ARM 和 ARM64 架构。

## 功能亮点

- **灵活安装选项**：支持三种安装位置
  - data/adb/openlist
  - 模块目录/bin
  - system/bin
- **数据目录可选**：支持两种数据存储位置
  - /data/adb/openlist/
  - /storage/emulated/0/Android/openlist/
- **账号初始化**：首次打开网页按向导设置管理员账号
- **动态服务管理**：通过 Magisk/KernelSU/APatch 的"动作"按钮一键控制服务
- **WebUI 控制台**（KernelSU / APatch）：查看状态、启停、在线更新二进制、改下载配置、改管理员账号、存储启停、离线任务、迁移数据/二进制目录、路径自检
- **命令行控制**：`control.sh` 三家通用，WebUI 也调用它
- **界面**：毛玻璃 + 大圆角，自动/浅色/深色主题
- **智能网络适配**：自动识别 WiFi 和移动网络 IP
- **日志支持**：详细的运行日志记录

## 系统要求

- Android 设备（arm / arm64 / x86 / x86_64 四种架构都支持）
- Magisk v20.4 或更高版本，或 KernelSU，或 APatch
- Root 权限

## 安装包怎么选

一共 5 个包，按架构挑一个，装完就跟着自己那条通道更新：

| 包名 | 内含二进制 | 适合谁 |
|---|---|---|
| `openlist-magisk-vX-arm64.zip` | arm64 | **绝大多数手机，首选** |
| `openlist-magisk-vX-arm.zip` | arm | 只有 arm32 的老设备 |
| `openlist-magisk-vX-amd64.zip` | amd64 | x86_64 设备 |
| `openlist-magisk-vX-386.zip` | 386 | x86 设备 |
| `openlist-magisk-online.zip` | 无 | 想省流量，安装时现下（约 76 KB） |

全部挂在同一个 `vX.Y.Z` Release 下：4 个架构包跟上游走，`online` 手动触发构建。

包里没有对应架构的二进制时，安装脚本会自动在线下载，不会装失败。

## online 包是什么：提前体验版

`openlist-magisk-online.zip` 和其它 4 个包是**同一个模块的两种装法**：

| | 4 个架构包 | online 包 |
|---|---|---|
| 谁发版 | CI 全自动 | **我手动触发** |
| 跟着谁走 | 上游 OpenList 官方 Release | 模块自身的脚本 / WebUI 改动 |
| 包内二进制 | 自带，离线可装 | **无**，安装时下载约 55 MB |
| 版本号 | 上游版本号 | 我填的版本号 |

- **online 是提前体验版**：模块功能改了就发，装了它立刻能用上，不用等上游 OpenList 发新版
- **代价是没有二进制**：装的时候要联网下载，或装完在 WebUI 里点「立即更新」
- **4 个架构包全自动**：只跟上游走，所以架构包用户要等上游发版才能拿到新功能
- 想提前用可以改装 online 包，但那之后更新就跟着 online 通道走；想回去重装一个架构包

## 二进制获取顺序

1. 包内 `$MODROOT/openlist-<arch>`
2. `/sdcard/Download/openlist-android-<arch>.tar.gz`（提前放好可离线装）
3. 在线下载（直连 + 国内镜像，带 md5 校验，版本与模块版本严格一致）
4. 全失败 → 中止并打印手动下载地址

## 安装步骤

1. **下载模块**
   - 从 [GitHub Releases](https://github.com/Alien-Et/OpenList-Magisk/releases) 挑一个包（见上表）
   - ARM64 设备拿 `openlist-magisk-vX-arm64.zip`；不确定架构用 `openlist-magisk-online.zip`（约 76 KB，安装时自动识别并下载）

2. **安装配置**
   - 打开 Magisk 管理器、KernelSU 管理器 或 APatch 管理器
   - 选择"从本地安装"
   - 进入安装配置界面：
     - 选择二进制文件安装位置
     - 选择数据目录存储位置
     - 更新安装时如果检测到旧数据，会多问一句要不要一起迁过来
   - 包里没有对应架构的二进制时会自动在线下载，装的时候别断网

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

### WebUI 控制台（KernelSU / APatch）

在 KernelSU 或 APatch 管理器里打开模块，点击 WebUI 入口即可：

- 状态：运行中/已停止、访问地址、PID、数据目录、架构
- 启停/重启服务
- 版本与更新：拉取 OpenList 官方 Release，按 CPU 架构选择 `android-arm64 / android-arm / android-amd64 / android-386`，下载后停止服务、替换二进制、重新启动（失败自动用 `.bak` 回滚）；下载可选镜像，进度实时显示
- 下载配置：修改 `offline.conf` 的端口、Token、目标路径、离线引擎、删除策略
- 管理员账号：改用户名、改密码（走 OpenList 管理 API，在线生效，不重启）
- 存储：列表、启用/禁用、全部重载
- 离线任务：查看进行中的任务、取消
- 迁移数据目录 / 二进制路径
- 查看和清空 `service.log`

> Magisk 没有 `webroot` WebUI 机制，看不到这个入口，请用"动作"按钮或下面的命令行。

### 命令行控制（Magisk / KernelSU / APatch 通用）

```sh
sh /data/adb/modules/openlist/control.sh status
sh /data/adb/modules/openlist/control.sh start|stop|restart
sh /data/adb/modules/openlist/control.sh check
sh /data/adb/modules/openlist/control.sh update --force          # 更新二进制
sh /data/adb/modules/openlist/control.sh update --tag v4.2.9    # 回退到指定版本（不查 API）
sh /data/adb/modules/openlist/control.sh logs 200
sh /data/adb/modules/openlist/control.sh config-get
sh /data/adb/modules/openlist/control.sh mirror-rank            # 看镜像实测排序
```

`update` 先试直连，再按实测延迟顺序试国内镜像；镜像偏好（自动 / 直连 / 指定）在 WebUI 里选，存到 `<数据目录>/mirror.conf`。
WebUI 里点更新走的是 `update-bg`（后台跑）+ `update-status`（轮询），宿主超时不会把下载掐断。

### 访问方式
- Web 界面访问：`http://<设备IP>:5244`
- 首次打开会进入安装向导，按提示设置管理员账号和密码
- 完成向导前，WebUI 里存储、离线任务、设置会提示「还没有管理员账号」

### 数据存储
- 默认数据目录：`/data/adb/openlist/`
- 日志文件位置：与数据目录相同
- **卸载默认保留数据**：只清理二进制。要连数据一起删，卸载前执行
  `touch /data/adb/modules/openlist/.delete_data_on_uninstall`，或卸载后手动 `rm -rf`

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
- 版本列表只走 GitHub 官方 API；遇到 403 限流时可在模块目录放一个 `.github_token`（一行 PAT）把额度从 60 次/小时提到 5000

## 更新日志

> 本次为模块更新，非 OpenList 官方二进制更新。

### v4.2.10 (2026-11-23)

- 修复 WebUI 管理员账号密码框输不进字（改用文字遮罩，不再用 `type=password`）
- 修复「立即更新」只显示一句「更新失败」：更新改为后台执行 + 轮询，失败会带具体原因
- 新增安装包内随附 `LICENSE`（MIT）、`LICENSE-AGPL-3.0.txt`（AGPL-3.0 全文）与 `THIRD-PARTY.md`，README 顶部补许可提示
- 重构 产物拆成 5 个：4 个单架构包（arm64 / arm / amd64 / 386，各带自己的 `updateJson`）+ 1 个不含二进制的 `online.zip`（约 76 KB）
- 新增 安装时四级回退取二进制：包内 → Download 目录 → 在线下载（复用 `control.sh` 的镜像列表与 md5 校验）→ 中止并给手动指引；下载的二进制版本与模块版本严格对齐

> 本次更新只测试到「WebUI 能正常用」这一步，没有做完整回归，可能还有没挖出来的隐藏 bug。遇到问题请到仓库提 issue。

## 数据迁移说明
1. 安装时可选择数据目录与二进制位置；更新安装时若检测到旧数据且换了目录，安装界面会多问一次「音量+ 迁移 / 音量- 跳过」（默认跳过，迁移失败不删源）
2. 装好后也能在 WebUI 迁移页随时改：选目标目录 → 「开始迁移」
3. 迁移 = 移动：复制、校验文件数与 data.db 的 md5 全部通过后，才同步 `config.json` 路径并删除源目录
4. 二进制迁移同理，校验一致后删除旧文件，不会同时留两份
5. 迁移完成后 WebUI 自动刷新状态、路径体检与日志

## 贡献
- 欢迎提交 Issue 和 Pull Request
- 问题反馈：[GitHub Issues](https://github.com/Alien-Et/OpenList-Magisk/issues)

## 许可证
模块自身的脚本、WebUI 与文档基于 [MIT 许可证](../LICENSE) 发布。

模块内打包的 `openlist` 二进制来自 [OpenList 官方 Release](https://github.com/OpenListTeam/OpenList/releases)，遵循上游 **AGPL-3.0** 许可证，对应源码见 [OpenListTeam/OpenList](https://github.com/OpenListTeam/OpenList)。

安装包内随附 [LICENSE](LICENSE)（MIT 副本）、[LICENSE-AGPL-3.0.txt](LICENSE-AGPL-3.0.txt)（AGPL-3.0 全文）与 [THIRD-PARTY.md](THIRD-PARTY.md)（第三方组件说明）。

## 文档

- [01. 整体架构](../docs/01.整体架构.md)
- [02. control 命令](../docs/02.control命令.md)
- [03. WebUI 界面](../docs/03.WebUI界面.md)
- [04. 更新与回滚](../docs/04.更新与回滚.md)
- [05. 迁移与路径](../docs/05.迁移与路径.md)
- [06. 安装选项矩阵](../docs/06.安装选项矩阵.md)
- [07. 总结](../docs/07.总结.md)
