# Mac 工具箱可行性与第一版设计

结论：可行。已经实现同一个原生 MacToys 窗口管理 InputStats 和 Portman；保留两个模块的适合各自工作的实现方式。

Microsoft PowerToys 的产品形态是集中入口加可独立使用的工具模块，具体系统功能面向 Windows；这里采用相同的组织方式，使用 macOS 原生接口重新实现宿主。参考 [Microsoft PowerToys 概览](https://learn.microsoft.com/en-us/windows/powertoys/) 与 [模块开发指南](https://microsoft.github.io/PowerToys/development/new-powertoy/)。

## 已实现

- **原生宿主**：AppKit 管生命周期、状态栏和窗口，SwiftUI 管统计及设置。没有引入 Electron 运行时。
- **InputStats 模块**：沿用受信任签名，CGEvent 被动监听只做分发；后台 AX 读取合并输入变化，SQLite 事务保存。普通空闲没有周期性扫描。
- **Portman 模块**：通过现有 CLI 发现本机服务，在原生 WKWebView 内提供完整管理界面。GUI / CLI 共用配置、认证和后台；关闭页面销毁 WebView，不停止已启用连接。
- **Color Picker 模块（0.2）**：`NSColorSampler` 按需调用系统放大镜；采样完成后转换为 8 位 sRGB，输出 HEX / RGB / HSL。最近颜色和收藏使用有界本机偏好保存。Carbon 只注册一个全局快捷键；快捷键录制使用临时局部事件监听，结束、取消、离开页面或应用失去焦点时清理。
- **权限独立于品牌**：保留旧 InputStats 的 bundle ID、签名和路径，MacToys 提供新入口。已实测旧权限有效。
- **扩展入口**：`ToolsModel.Tool` 描述模块名称、符号和页面；新工具可加原生页面或复用本机后台，不需要一起常驻轮询。

技术依据：[CGEventTapOptions.listenOnly](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions/listenonly)、[AXObserverCreate](https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate)、[AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)、[WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)、[Apple 代码签名 Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。

## 为什么这样整合

输入采集是全局系统功能，适合原生代码，并需要保留已有系统授权。Portman 已有可用的本机 API、SSH 管理、测试和 CLI；把现有管理页装入系统 WebKit 能保留这些能力，避免再维护一套端口状态。

菜单栏快速统计不加载 Portman。主窗口打开 Portman 页才连接后台并创建 WebView；离开、关闭或最小化窗口会释放页面。Portman 后台独立持续运行，符合原有 CLI 使用方式。

## 第一版范围与以后

第一版是本机可运行的工具集，不是可任意安装第三方代码的插件市场。后续可以按相同接口接入用户已有工具，增加每个模块的启停与快捷键设置；涉及系统权限的模块应独立声明需求。

如果以后给其他机器分发，需要固定正式签名身份、打包 Python 运行时或改造 Portman 的分发方式，并做 Developer ID 签名及公证；本机版本复用已有自签名证书即可。Apple 的发行说明见 [Signing Mac Software with Developer ID](https://developer.apple.com/developer-id/)。
