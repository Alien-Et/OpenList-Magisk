# 纯在线包更新日志

这个文件只用于 **`openlist-magisk-online.zip`**（不含任何二进制的纯在线包）。
四个架构包（arm / arm64 / amd64 / 386）的更新日志来自上游 OpenList 官方 Release，不在这里。

> 维护方式：改好本文件和代码 → Actions 里手动运行「发布纯在线包」，填入版本号（如 `v4.2.11`），
> `update.json` 和 online 包内的 `module.prop` 由 CI 自动改写，不用手改。
> 同一个版本号如果架构包已经发过，online 包会直接补到那个 Release 里。

---

## v4.2.10

首个纯在线包。

- 安装包不含二进制，安装时按设备架构（arm / arm64 / amd64 / 386）自动下载对应版本
- 下载走 `releases/latest/...` 之外的固定路径，并用上游 `md5-android.txt` 校验
- 直连失败自动切 15 个国内镜像，全部失败才中止，并打印手动下载地址与放置路径
- 也支持提前把 `openlist-android-<arch>.tar.gz` 放进 Download 目录离线安装
- 下载的二进制版本号与模块版本严格对齐，不会出现「模块 v4.2.10、二进制 v4.2.11」的错配