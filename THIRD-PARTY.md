# 第三方组件与许可

本模块（`Alien-Et/OpenList-Magisk`）自身的脚本、WebUI、文档以 **MIT** 许可发布，全文见 [`LICENSE`](LICENSE)。

模块安装包内**同时打包了上游 OpenList 的可执行文件**，它们不是本项目的代码，遵循各自的许可证。

---

## 1. OpenList 可执行文件

| 文件 | 架构 | 上游项目 | 许可证 |
| --- | --- | --- | --- |
| `openlist-arm` | arm (armv7 / armhf) | [OpenListTeam/OpenList](https://github.com/OpenListTeam/OpenList) | AGPL-3.0 |
| `openlist-arm64` | arm64 (aarch64) | [OpenListTeam/OpenList](https://github.com/OpenListTeam/OpenList) | AGPL-3.0 |

- 版本：**v4.2.10**（与 `module.prop` 的 `version` 一致）
- 来源：上游 Release 页面直接下载的官方 Linux ARM / ARM64 构建产物
- 修改情况：**未修改**，原样打包。本项目只提供 Magisk/KernelSU/APatch 的安装脚本、服务控制脚本（`service.sh` / `control.sh`）和 WebUI。
- 上游源码：<https://github.com/OpenListTeam/OpenList>
- 许可证全文：见同目录 [`LICENSE-AGPL-3.0.txt`](LICENSE-AGPL-3.0.txt)，或 <https://www.gnu.org/licenses/agpl-3.0.txt>

### AGPL-3.0 对本项目的实际影响

AGPL-3.0 是强 copyleft 许可证，主要要求：

1. 分发二进制时必须附带许可证副本并提供对应源码的获取方式 —— 本文档 + `LICENSE-AGPL-3.0.txt` + 上面的上游源码链接即为满足。
2. 如果修改了 OpenList 本体并通过网络提供服务，需要向使用者提供修改后的源码 —— 本模块不分发修改版，此条不涉及。
3. AGPL 的传染性只作用于 OpenList 自身（及其衍生作品），**不会**自动覆盖以独立进程方式调用它的安装脚本、控制脚本和 WebUI。因此本模块自身仍可用 MIT 发布。

如果你要基于本模块再分发，请注意：MIT 部分随意；打包进去的 `openlist-arm` / `openlist-arm64` 必须继续遵守 AGPL-3.0（保留许可证副本与源码链接）。

---

## 2. 其他

模块内不含其他第三方二进制。图标、截图、文档均为本项目原创。
