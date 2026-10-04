# 安装 MacToys

[English](installing.md) · **简体中文**

需要 macOS 14 或更新版本。M1 及更新的 Apple 芯片选择 **arm64**，Intel Mac 选择 **x86_64**。可在苹果菜单 → 关于本机中确认。

1. 从 [GitHub Releases](https://github.com/kennymckormick/MacToys/releases/latest) 下载对应的 DMG。
2. 打开后将 **MacToys.app** 拖入 **Applications（应用程序）**，然后推出磁盘映像。
3. 从应用程序文件夹打开 MacToys。本版本**尚未通过 Apple 公证**。如果系统阻止打开，在尝试打开后，前往**系统设置 → 隐私与安全性 → 仍要打开**，仅在信任下载来源时放行。受组织管理的 Mac 可能不允许放行。[苹果操作说明](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)
4. 首次启动打开「设置 → 开始使用」。输入统计和滚轮反转需要**辅助功能**及系统请求的**输入监控**权限。在系统设置中启用 MacToys，再退出并重新打开。如果列表中没有应用，点 **+** 添加已安装的 MacToys。

待办、笔记、目标、端口转发和防止休眠不需要以上权限。应用不会自行更改系统安全设置。关闭窗口后仍在菜单栏运行；使用「退出 MacToys」结束运行。

已内置 Python、Portman 和离线笔记编辑器，无需安装 Xcode、命令行开发工具、Homebrew、Python、pip 或 Node.js。选择对应架构后无需 Rosetta。SSH 隧道使用 macOS 自带的 OpenSSH，仍需你自己的主机、密钥或登录凭证。

## 升级与数据

先退出应用，再替换为新版。待办、笔记、目标和统计保存在 `~/Library/Application Support/InputStats`，替换应用不会删除数据。GitHub 私有仓库备份是可选项。

当前使用 ad-hoc 签名，更新后签名可能变化，macOS 可能要求重新授予权限。这些下载没有 Developer ID 签名和 Apple 公证票据。

如果曾通过源码安装为 `InputStats.app`，并用 `MacToys.app` 作为符号链接，请继续用原签名执行 `./build.sh --install`。迁移到 DMG 时，先备份、退出旧应用，移除旧应用及其链接，再安装新版并重新授权；保留数据文件夹。避免同时保留两个访问同一数据的应用实例。

## 命令行与校验

无需修改 shell 配置即可使用内置 CLI：

```sh
/Applications/MacToys.app/Contents/MacOS/portman -h
```

下载同一 Release 的 `.sha256` 文件，与 DMG 放在一起，例如运行：

```sh
shasum -a 256 -c MacToys-0.7.1-arm64-unnotarized.dmg.sha256
```

输出应为 `OK`。配套 JSON 记录源码提交、Python 版本、架构和签名状态。校验值用于检查文件完整性，不能替代 Developer ID 签名。
