# OpenList Magisk/KernelSU/APatch 模块

[![Release](https://img.shields.io/github/v/release/Alien-Et/OpenList-Magisk)](https://github.com/Alien-Et/OpenList-Magisk/releases)
[![License](https://img.shields.io/github/license/Alien-Et/OpenList-Magisk)](https://github.com/Alien-Et/OpenList-Magisk/blob/main/LICENSE)

OpenList Magisk 模块将 [OpenList](https://github.com/OpenListTeam/OpenList) 文件服务器集成到 Android 系统中，通过 Magisk、KernelSU 或 APatch 以系统化方式运行，支持 ARM 和 ARM64 架构。

## 功能亮点

- **多框架支持**：同时兼容 Magisk、KernelSU 和 APatch
- **浏览器划词与磁力链接 115 离线下载（OpenListHelper 伴侣应用）**：原生接入系统划词菜单与 Magnet 协议关联，支持划选纯文本、直接点击超链接或长按分享链接一键唤起半屏弹窗并提交至本地 OpenList 115 离线下载
- **配置与 Token 自动同步及存储自动重连**：服务启动自动从数据库提取 OpenList API Token 并剥离类型后缀，网络就绪后自动重连 115 等云存储，零手动配置
- **灵活安装选项**：支持三种安装位置
  - data/adb/openlist
  - 模块目录/bin
  - system/bin
- **数据目录可选**：支持两种数据存储位置
  - /data/adb/openlist/
  - /storage/emulated/0/Android/openlist/
- **密码定制**：提供初始密码设置选项
- **动态服务管理**：通过 Magisk/KernelSU 的"动作"按钮一键控制服务
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
     - 选择是否修改默认密码为 admin

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
- 初始密码：查看数据目录下的 `初始密码.txt`

### 浏览器 115 离线下载（OpenListHelper 伴侣应用）

模块内置轻量级伴侣应用 `OpenListHelper`（包名：`io.openlist.helper`），无需后台常驻进程与剪贴板监听，支持以下三种便捷触发方式快速唤起半屏离线弹窗：

#### 浏览器三种触发方式
1. **纯文本磁力/Hash**：长按划选文字（磁力链接 `magnet:?xt=...` 或 40 位 Hex / 32 位 Base32 InfoHash）-> 点击系统划词菜单 **“115 离线”**。
2. **超链接形式的磁力链接 (`<a href="magnet:...">`)**：直接**点击磁力超链接**即可直接唤起半屏确认弹窗。
3. **长按磁力超链接分享**：长按磁力超链接 -> 点击 **“共享链接”**（或“分享链接”）-> 选择 **“OpenList 115 离线”** 唤起半屏确认弹窗。

#### 交互流程与离线投递
1. **唤起半屏弹窗**：通过上述任意一种方式触发后，系统底部将弹出离线确认半屏弹窗（预览磁力与文件特征）。
2. **确认目标路径**：确认或选择目标虚拟路径（默认 `/115/影视/`，预设可选 `/115/`，或直接自定义输入）。
3. **一键投递执行**：点击“立即离线”，伴侣应用将调用本地 OpenList（`http://127.0.0.1:5244/api/fs/add_offline_download`），通过 `115 Open` 驱动投递至云端离线下载，并通过 Toast 反馈提交状态。

#### 离线配置文件（`offline.conf`）与开机自动恢复
配置文件位于 OpenList 数据目录：`$DATA_DIR/offline.conf`（如 `/data/adb/openlist/offline.conf`）。

每次 OpenList 守护服务启动时，`service.sh` 脚本会自动完成：
- 从 OpenList 数据库（`$DATA_DIR/data.db`）自动读取当前有效 API Token（并自动清洗 SQLite 连续记录中的类型后缀）并写入 `TOKEN=` 字段。
- 动态获取当前运行端口并更新 `PORT=` 字段。
- 自动将完整配置安全桥接至伴侣应用私有目录 `/data/data/io.openlist.helper/files/offline.conf`，实现**完全免手动配置 Token**。
- 开机网络与 DNS 就绪后，后台自动调用 OpenList API (`POST /api/admin/storage/load_all`) 重载所有存储驱动，避免开机初始无网络导致的 `115 Open` 等云存储初始化失败。

配置字段定义：
```ini
# OpenList 115 离线下载伴侣配置
HOST=127.0.0.1                          # OpenList 监听主机
PORT=5244                               # OpenList 运行端口（服务启动时动态探测并更新）
TOKEN=openlist-xxxx...                  # OpenList API Token（服务启动时自动从数据库提取）
PATH=/115/影视/                          # 默认目标虚拟路径
TOOL=115 Open                           # 离线下载驱动名称（固定为 115 Open）
DELETE_POLICY=delete_on_upload_succeed  # 下载成功后的清理策略
PRESET_PATHS=/115/影视/,/115/            # 半屏弹窗预设路径快速选择列表（逗号分隔）
```
升级模块与服务重启会自动保留用户对 `PATH`、`DELETE_POLICY` 和 `PRESET_PATHS` 的自定义修改。

### 数据存储
- 默认数据目录：`/data/adb/openlist/`
- 日志文件位置：与数据目录相同
- 密码文件：`初始密码.txt`

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

### v4.1.10 (2026-02-22)
- **修复** versionCode 计算逻辑，支持三位版本号 (v4.1.10 → 4110)
- **修复** 安装脚本占位符替换问题
- **修复** sed 替换时变量被错误展开的问题
- **优化** action.sh 启停服务的输出提示信息
- **改进** 移除冗余的占位符验证逻辑

## 数据迁移说明
1. 在安装时选择新的数据目录
2. 手动将现有数据迁移到新目录
3. 更新 config.json 中的相关路径

## 贡献
- 欢迎提交 Issue 和 Pull Request
- 问题反馈：[GitHub Issues](https://github.com/Alien-Et/OpenList-Magisk/issues)

## 许可证
本项目基于 [MIT 许可证](LICENSE) 发布。
