# MacToys

一个轻量的 macOS 工具箱，把输入统计、端口转发和屏幕取色放进同一个原生窗口。

**macOS 14+ · SwiftUI / AppKit · 本机存储**

| 工具 | 功能 |
| --- | --- |
| **InputStats** | 字符 / 单词计数，键盘 / Fn 语音分类，今日图表、近期趋势、年度热力图和 CSV 导出 |
| **Portman** | TCP、SSH 本地 / 反向转发，CLI 与 GUI 共用后台，自动重连 |
| **Color Picker** | 系统放大镜取色，HEX / RGB / HSL，颜色历史、收藏、自定义全局快捷键 |

菜单栏左键打开紧凑统计面板，右键进入工具菜单。统计图表在可见时每 **5 分钟**刷新；输入采集与保存持续进行。弹窗宽度 460 点，随内容自动调整高度，并适配屏幕可用空间。

关闭主窗口后继续统计；退出 MacToys 会保存计数并停止输入监听。Portman 后台与已启用的转发独立运行，可通过 GUI 或 CLI 停止。

## 从源码构建

当前提供源码版本，尚无经过 Developer ID 签名、公证的通用安装包。

需要 macOS 14+、Swift 5.9+ 工具链（Xcode / Command Line Tools），以及 Python 3.9+。SSH 转发使用系统 OpenSSH；不需要第三方 Python 包。

```sh
git clone https://github.com/kennymckormick/MacToys.git
cd MacToys
./build.sh --install
open /Applications/MacToys.app
```

为了兼容原 InputStats，实际应用路径为 `/Applications/InputStats.app`，`MacToys.app` 是它的链接；可执行文件与 bundle ID 仍为 `InputStats` / `com.local.inputstats`。

**首次使用**需要在「系统设置 → 隐私与安全性」中为已安装的应用启用辅助功能及需要的输入监控权限，然后重启应用。应用不会自动重置系统授权。

构建默认复用钥匙串中已有的 `InputStats Self-Signed` 证书；没有该证书时生成本地 ad-hoc 签名版本。要在多次构建间保持稳定身份，可使用自己已有的代码签名证书：

```sh
SIGNING_IDENTITY='你的代码签名证书名称' ./build.sh --install
```

ad-hoc 签名不提供跨版本稳定的授权身份。安装器发现已有应用的签名要求改变时会停止；已有用户应继续使用最初授权的证书。证书与私钥不会随仓库分发。

Portman 源码随仓库及应用打包。已有 `portman` CLI 时优先复用；否则使用包内 Python 模块。可选安装 CLI：

```sh
python3 -m pip install ./Modules/Portman
portman -h
```

[Portman CLI 用法与运行边界](Modules/Portman/README.md)

## 屏幕取色

- 默认全局快捷键 **⌃⌥⌘C**（Control + Option + Command + C），关闭主窗口后仍可使用；退出应用后停止。
- 或从侧栏进入「屏幕取色」，点击「拾取屏幕颜色」；菜单栏图标右键也有入口。应用内菜单快捷键是 **⇧⌘P**。
- 启动时暂时隐藏工具箱，系统放大镜可以拾取屏幕上的颜色。点击选取，Esc 取消；空格可显示 RGB。取消不改动颜色历史或剪贴板。
- 默认自动复制 HEX 并打开颜色面板，可改为 RGB / HSL，或关闭自动复制、关闭取色后打开面板。
- 三种格式可单独复制；支持输入 3 / 6 位 HEX，以及系统颜色面板微调。
- 最近颜色自动去重，最多保存 24 个；收藏最多 64 个，和历史分开保存。右键色块可复制、收藏或移除。
- 点击快捷键按钮后按下新组合键即可修改；Esc 取消。注册失败会显示错误并保留原配置。
- 输出为不透明的 **8 位 sRGB**，超出 sRGB 范围的广色域分量会截取至有效范围；不提供 HDR / 原生 Display P3 格式。
- 取色使用 `NSColorSampler`，空闲不截图、不轮询；快捷键通过系统事件注册。只持久化颜色值和偏好，不保存屏幕图片。

交互参考 [PowerToys Color Picker](https://learn.microsoft.com/en-us/windows/powertoys/color-picker) 的取色、复制与历史流程，以及 [System Color Picker](https://sindresorhus.com/system-color-picker) 的原生取色和快捷键形式。实现使用 [Apple NSColorSampler](https://developer.apple.com/documentation/appkit/nscolorsampler)。

## 统计口径与边界

**字符**：新增的 Unicode 字素，包括空格、标点、换行；组合 emoji 计 1。删除不扣除，删后重打计为新的输入。

**单词**：每个汉字计 1；连续字母 / 数字串计 1。扩展一个已有英文单词不重复计数。

计数来自焦点可编辑区域的文本变化。英文终端等不能提供可编辑文本的控件退回按键估算，并在状态栏明确显示。中文在这些控件中不猜测汉字数量；超过 65,536 UTF-16 单元的文本也不整篇扫描。不是所有应用都暴露 IME 的临时组合状态；可识别的选中拼音会等上屏后统计，特殊编辑器的组合输入仍可能有误差。

默认排除可识别的 ⌘V 粘贴，可在设置开启；Fn 听写期间由输入法送入的转写会按语音处理。上下文菜单、自动补全、语音流式改写和其他程序直接修改文本不能始终与人工输入严格区分。Fn 是分类线索，不是录音状态的官方接口；其他快捷键可手动切换来源。

旧版存在删除倒扣，原数据库中已有的负值不会被悄悄改写。涉及旧版修正的时间范围会显示说明。仅凭历史计数无法还原当时真实输入量。

## 数据与资源占用

- 输入统计仅保存分钟级计数：`~/Library/Application Support/InputStats/stats.sqlite`。输入文本只在内存中用于差分，不写进日志、数据库或网络。
- 颜色历史与收藏保存在本机偏好中；不保存屏幕截图。
- Portman 配置位于 `~/.local/state/portman`。管理 API 仅监听 loopback，使用私有 token 校验；网络流量只用于用户配置的转发。
- 普通空闲状态不轮询全文；输入事件与 AX 通知触发合并采样，Fn 听写期间使用临时补充采样。AX 读取有超时与文本长度上限。
- 隐藏统计页面停止图表刷新；离开 Portman 页面或关闭 / 最小化主窗口会销毁 WebView。WebKit 可能保留可复用的 GPU 进程。
- 更新先正常退出、保存计数，再备份旧应用并原子替换。应用备份位于 `~/Library/Application Support/MacToys/Backups/`。

实测数据、方法与限制见 [资源检查](docs/performance.md)，功能回归见 [验证记录](docs/verification.md)。

## 开发

```sh
swift run -c release --scratch-path .build-mactoys SelfCheck
bash scripts/check-color-picker.sh
(cd Modules/Portman && python3 -m unittest discover -s tests -v)
node --check Modules/Portman/portman/static/app.js
```

`python3 scripts/ui-fixture.py` 使用独立 bundle ID、临时数据库和独立 Portman 状态，默认禁用真实输入监听。测试输出、应用包、统计数据库、收款资料及签名密钥均不提交到仓库。

| 目录 | 内容 |
| --- | --- |
| `Sources/InputStatsCore` | 计数、Fn 状态机、时间聚合、颜色格式 |
| `Sources/InputStatsStorage` | SQLite 事务、历史迁移、失败恢复 |
| `Sources/InputStats` | 原生宿主、系统监听、统计、取色和 WebKit 集成 |
| `Modules/Portman` | Python CLI / 后台、Web GUI、隔离集成测试 |
| `scripts` | 构建辅助、身份保持安装、图标和验证工具 |

[架构说明](docs/architecture.md) · [版本记录](CHANGELOG.md)

## 支持项目

如果 MacToys 对你有帮助，欢迎 Star、反馈问题或贡献改进。

赞助入口准备中；收款页面开通后会在这里公布。
