# OpenList Magisk/KernelSU/APatch 模块

[![Release](https://img.shields.io/github/v/release/Alien-Et/OpenList-Magisk)](https://github.com/Alien-Et/OpenList-Magisk/releases)
[![License](https://img.shields.io/github/license/Alien-Et/OpenList-Magisk)](https://github.com/Alien-Et/OpenList-Magisk/blob/main/LICENSE)

## 测试版说明
注意：当前v4.1.10.1为测试版，主要增加 WEBUI 功能，解决了 main 分支 actions 点击异常的 bug。**
> **

### 兼容性说明
- **Magisk 用户**：可能没有 WEBUI 入口，需要自行下载 `ksuwebui` 应用辅助
- **KernelSU 用户**：请自行测试，如有问题到 ISSUE 反馈
- **APatch 用户**：已测试，基本功能正常

### WEBUI 功能说明
- **已实现**：服务状态显示、启停控制、密码修改、网络信息显示、进程 PID 显示、实时日志监控
- **未实现**：WEBUI 回退 OpenList 版本、WEBUI 升级 OpenList 版本（下次一定）

### 已知问题
- WEBUI 面板启动或关闭程序并不会更新管理器的 module.prop 文件
- WEBUI 功能尚未完全完善，后续会持续优化

## 项目介绍

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
- **自动数据迁移**：切换数据目录时自动迁移重要数据文件
- **密码定制**：提供初始密码设置选项
- **动态服务管理**：通过 Magisk/KernelSU 的"动作"按钮一键控制服务
- **智能网络适配**：自动识别 WiFi 和移动网络 IP，双卡设备显示各卡独立 IP
- **现代化 Web UI**：精美的管理界面，支持服务控制、网络信息显示等
- **实时日志监控**：实时跟踪和显示服务运行日志
- **日志支持**：详细的运行日志记录

## 截图展示

| 安装界面 | KernelSU WiFi 网络 | KernelSU 移动网络 |
|---------|------------------|------------------|
| ![安装界面](install-interface.jpg) | ![KernelSU WiFi 网络](kernelsu-wifi.jpg) | ![KernelSU 移动网络](kernelsu-mobile-network.jpg) |

## 系统要求

- Android 设备（支持 ARM 或 ARM64 架构）
- Magisk v20.4 或更高版本，或 KernelSU，或 APatch
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
   - 等待安装完成（数据迁移会自动执行）
   - 重启设备

## 使用说明

### 服务管理
- 系统启动后自动运行
- 通过 Magisk/KernelSU/APatch "动作"按钮控制服务
- 服务状态显示在 module.prop：
  - 运行中：显示访问地址和数据目录
  - 已停止：显示启动提示

### Web UI 管理
- 通过 Root 管理器的文件浏览器打开 `webroot/index.html`
- 功能包括：
  - 服务状态显示
  - 服务启停控制
  - 密码修改和重置
  - 网络模式和 IP 地址显示
  - 进程 PID 显示
  - 运行日志查看

### 访问方式
- Web 界面访问：`http://<设备IP>:5244`
- 初始密码：查看数据目录下的 `初始密码.txt`

### 数据存储
- 默认数据目录：`/data/adb/openlist/`
- 日志文件位置：与数据目录相同
- 密码文件：`初始密码.txt`

## 数据迁移

模块支持自动数据迁移功能，确保在切换数据目录时不会丢失重要数据：

### 自动迁移逻辑

**触发条件**：
- 安装时选择与之前不同的数据目录
- 源目录存在需要迁移的数据文件
- 目标目录尚未有数据文件

**迁移流程**：
1. **检测源目录**：检查源目录是否存在需要迁移的数据文件
2. **检测目标目录**：确保目标目录不存在相同的数据文件
3. **创建目标目录**：如果目标目录不存在，自动创建
4. **执行迁移**：复制重要数据文件到目标目录
5. **验证迁移**：检查文件是否成功复制
6. **删除旧目录**：迁移成功后，强制删除整个源目录（包括所有文件）

**迁移的文件**：
- `data.db` - 主数据文件
- `data.db-shm` - 共享内存文件
- `data.db-wal` - 预写日志文件
- `初始密码.txt` - 密码文件

**注意**：迁移完成后，旧目录会被完全删除，包括其中未被迁移的其他文件。如有需要保留的文件，请提前备份。

### 迁移场景说明

**场景1**：从 `/data/adb/openlist` 迁移到 `/sdcard/Android/openlist`
- 检测 `/data/adb/openlist` 目录是否存在数据文件
- 确保 `/sdcard/Android/openlist` 目录为空
- 复制数据文件到新目录
- 删除整个 `/data/adb/openlist` 目录

**场景2**：从 `/sdcard/Android/openlist` 迁移到 `/data/adb/openlist`
- 检测 `/sdcard/Android/openlist` 目录是否存在数据文件
- 确保 `/data/adb/openlist` 目录为空
- 复制数据文件到新目录
- 删除整个 `/sdcard/Android/openlist` 目录

**场景3**：目标目录已有数据
- 检测到目标目录已有数据文件
- 跳过迁移操作，避免覆盖现有数据
- 旧目录保持不变

**场景4**：源目录无数据
- 检测到源目录没有需要迁移的数据文件
- 跳过迁移操作

### 手动迁移

如果自动迁移失败，可手动执行以下步骤：

1. **复制数据文件**：
   - 从源目录复制 `data.db`、`data.db-shm`、`data.db-wal` 和 `初始密码.txt` 到新目录

2. **更新配置**：
   - 确保新目录的权限正确
   - 重启设备使新配置生效

3. **验证迁移**：
   - 检查服务是否正常运行
   - 确认数据是否完整保留

4. **清理旧目录**：
   - 确认迁移成功后，手动删除旧目录

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

4. **Web UI 无法正常显示**
   - 确认模块已正确安装
   - 检查 webroot 目录是否存在
   - 重启设备后重试

### 手动操作
- 停止服务：`su -c pkill -f openlist`
- 启动服务：`su -c /data/adb/modules/openlist/service.sh`
- 查看日志：`cat /data/adb/modules/openlist/service.log`

## 更新说明
- 支持通过 Magisk/KernelSU/APatch 更新检查
- 更新不会清除现有数据
- 可在安装时重新选择配置选项

## 更新日志管理策略

### 自动更新机制
- **触发条件**：当模块未进行人为功能更新时
- **执行流程**：
  1. `Auto.yml` 工作流每4小时自动运行一次
  2. 检测 OpenList 官方最新版本
  3. 自动同步上游二进制文件和更新日志
  4. 生成对应版本的模块包并发布
- **版本格式**：保持与 OpenList 官方版本一致（如：v4.1.10）
- **适用场景**：仅同步官方更新，无模块自身功能改动

### 手动更新机制
- **触发条件**：当模块进行人为功能更新时
- **执行流程**：
  1. 手动创建带后缀的版本标签（如：v4.1.10-1 或 v4.1.10.1）
  2. `manual-build.yml` 工作流响应标签推送
  3. 基于本地代码构建模块包并发布
  4. **人工编写** 更新日志，详细说明模块自身功能改动
- **版本格式**：
  - 预发布版本：`vX.Y.Z-1`（如：v4.1.10-1）
  - 正式版本：`vX.Y.Z.1`（如：v4.1.10.1）
- **适用场景**：模块功能增强、Bug 修复、配置优化等

### 更新日志编写规范
- **主要方式**：人工手写，确保内容准确、详细
- **内容要求**：
  - 清晰描述模块自身功能变更
  - 突出新增特性和修复的问题
  - 说明兼容性影响和使用注意事项
- **维护位置**：`OpenList-Magisk/CHANGELOG.md` 文件

## 更新日志

### v4.1.10.1 (2026-02-24)
- **新增** 现代化 Web UI 功能，支持服务状态显示、启停控制、密码修改、网络信息显示等
- **修复** GitHub Actions 工作流配置，支持 4 位版本号格式
- **优化** 版本代码计算逻辑，确保 4 位版本号正确处理
- **改进** 工作流执行流程，提高构建稳定性

### v4.1.10-1 (2026-02-23)
- **修复** 服务重启时页面卡住的问题
- **新增** 实时日志监控功能，自动跟踪和显示服务运行日志
- **新增** 双卡设备 IP 地址分别显示功能，不再挤在一起
- **优化** 服务控制函数，添加超时保护和错误处理
- **优化** 网络检测逻辑，提高 IP 地址获取成功率

### v4.1.10 (2026-02-22)
- **修复** versionCode 计算逻辑，支持三位版本号 (v4.1.10 → 4110)
- **修复** 安装脚本占位符替换问题
- **修复** sed 替换时变量被错误展开的问题
- **优化** action.sh 启停服务的输出提示信息
- **改进** 移除冗余的占位符验证逻辑
- **新增** 自动数据迁移功能，切换数据目录时自动迁移重要文件
- **新增** 现代化 Web UI，支持服务控制、网络信息显示等
- **修复** 运行状态检测逻辑，确保正确显示服务状态
- **修复** 网络模式检测和 IP 地址获取逻辑
- **修复** 密码修改和重置功能

## 贡献
- 欢迎提交 Issue 和 Pull Request
- 问题反馈：[GitHub Issues](https://github.com/Alien-Et/OpenList-Magisk/issues)

## 许可证
本项目基于 [MIT 许可证](LICENSE) 发布。
