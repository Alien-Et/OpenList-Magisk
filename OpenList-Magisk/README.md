# OpenList Magisk/KernelSU/APatch 模块

[![Release](https://img.shields.io/github/v/release/Alien-Et/OpenList-Magisk)](https://github.com/Alien-Et/OpenList-Magisk/releases)
[![License](https://img.shields.io/github/license/Alien-Et/OpenList-Magisk)](https://github.com/Alien-Et/OpenList-Magisk/blob/main/LICENSE)

OpenList 模块将 [OpenList](https://github.com/OpenListTeam/OpenList) 文件服务器集成到 Android 系统中，通过 Magisk、KernelSU 或 APatch 以系统化方式运行，支持 ARM 和 ARM64 架构。

## 功能亮点

- **灵活安装选项**：支持三种安装位置
  - data/adb/openlist
  - 模块目录/bin
  - system/bin
- **数据目录可选**：支持两种数据存储位置
  - /data/adb/openlist/
  - /storage/emulated/0/Android/openlist/
- **密码定制**：提供初始密码设置选项
- **动态服务管理**：通过 Magisk/KernelSU/APatch 的"动作"按钮一键控制服务
- **WebUI 控制台**（KernelSU / APatch）：查看状态、启停、在线更新二进制、改下载配置、改管理员密码、迁移数据/二进制目录
- **命令行控制**：`control.sh` 三家通用，WebUI 和 action.sh 都调用它
- **智能网络适配**：自动识别 WiFi 和移动网络 IP
- **日志支持**：详细的运行日志记录

## 系统要求

- Android 设备（支持 ARM 或 ARM64 架构）
- Magisk v20.4 或更高版本，或 KernelSU，或 APatch
- Root 权限

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

### WebUI 控制台（KernelSU / APatch）

在 KernelSU 或 APatch 管理器里打开模块，点击 WebUI 入口即可：

- 状态：运行中/已停止、访问地址、PID、数据目录、架构
- 启停/重启服务
- 版本与更新：拉取 OpenList 官方 Release，按 CPU 架构选择 `android-arm64 / android-arm / android-amd64 / android-386`，下载后自动停止服务、替换二进制、重新启动（失败可用 `.bak` 回滚）
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
sh /data/adb/modules/openlist/control.sh update [--force] [--proxy URL]
sh /data/adb/modules/openlist/control.sh logs 200
sh /data/adb/modules/openlist/control.sh config-get
```

`update` 会依次尝试直连和内置 GitHub 代理，可用 `GH_PROXY` 环境变量或 `--proxy` 指定。

### 访问方式
- Web 界面访问：`http://<设备IP>:5244`
- 初始密码：查看数据目录下的 `初始密码.txt`

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

## 数据迁移说明
1. 在安装时选择新的数据目录
2. 手动将现有数据迁移到新目录
3. 更新 config.json 中的相关路径

## 贡献
- 欢迎提交 Issue 和 Pull Request
- 问题反馈：[GitHub Issues](https://github.com/Alien-Et/OpenList-Magisk/issues)

## 许可证
本项目基于 [MIT 许可证](LICENSE) 发布。