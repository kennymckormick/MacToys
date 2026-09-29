import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", chinese = "zh-Hans"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L("跟随系统")
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        if self != .system { return rawValue }
        return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("MacToys.appLanguageDidChange")
}

/// Shared by SwiftUI and AppKit; changing languages never recreates tool services.
final class Localization: ObservableObject {
    static let shared = Localization()
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: "app.language")
            lock.lock(); resolvedLanguage = language.resolved(); lock.unlock()
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
    }
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var resolvedLanguage: String
    var code: String { lock.lock(); defer { lock.unlock() }; return resolvedLanguage }
    var locale: Locale { Locale(identifier: code) }

    init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? (ProcessInfo.processInfo.environment["INPUTSTATS_TEST_HOME"] == nil
            ? .standard : UserDefaults(suiteName: "com.local.inputstats.tests")!)
        self.defaults = defaults
        let language = defaults.string(forKey: "app.language").flatMap(AppLanguage.init(rawValue:)) ?? .system
        self.language = language; resolvedLanguage = language.resolved()
    }

    func text(_ key: String, arguments: [CVarArg] = []) -> String {
        let format = code == "en" ? (Self.english[key] ?? key) : key
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }

    // Chinese keys keep the original interface wording and are the Chinese fallback.
    // English entries are checked for missing keys and matching format placeholders.
    static let english: [String: String] = [
        "统计数据读写失败：%@": "Could not read or save input counts: %@",
        "拒绝写入负数统计增量": "Refused to save a negative input delta",
        "无法打开文件": "Could not open the file",
        "%@ · 本机运行": "%@ · On-device",
        "%@ 正在运行。退出它后自动启用，避免重复反转。": "%@ is running. Reversal will resume when it quits.",
        "1 小时": "1 hour",
        "15 分钟": "15 minutes",
        "2 小时": "2 hours",
        "24 小时制": "24-hour",
        "30 分钟": "30 minutes",
        "4 小时": "4 hours",
        "5 分钟刷新 · 本机计数": "5-minute refresh · On-device",
        "Fn 按住、双击锁定与松开后的延迟上屏均会处理。其他语音快捷键可手动切换来源。应用未提供文本时，英文按键会标为估算；中文不使用拼音长度猜测。": "Recognizes Fn hold, double-tap, and delayed dictation text. Select a source manually for other voice shortcuts. When an app does not expose text, Latin keystrokes are estimated; Chinese input is not estimated from Pinyin.",
        "HEX 颜色输入": "HEX color",
        "MacToys · 输入统计、端口转发、屏幕取色、滚轮反转与防止休眠": "MacToys · Input Stats, Portman, Color Picker, Scroll Reversal, Keep Awake",
        "MacToys · 输入验证（临时数据）": "MacToys · Input test (temporary data)",
        "MacToys · 防止休眠已开启（右键可关闭）": "MacToys · Keep Awake is on (right-click to turn off)",
        "MacToys 工具箱": "MacToys toolbox",
        "Portman · 端口转发": "Portman · Port Forwarding",
        "Portman 暂不可用": "Portman is unavailable",
        "Portman 界面进程已退出，请重新连接。": "The Portman view has closed. Reconnect to continue.",
        "Portman 返回了无效地址。": "Portman returned an invalid address.",
        "SSH 主机": "SSH Hosts",
        "sRGB · 8 位": "sRGB · 8-bit",
        "一个汉字计一词 · 字母 / 数字连续串计一词 · 密码区域跳过": "Each CJK character or Latin/digit sequence counts as a word. Password fields are skipped.",
        "下载、演示或远程工作时，保持 Mac 唤醒。": "Keep your Mac awake during downloads, presentations, or remote work.",
        "今天": "Today",
        "从最近颜色移除": "Remove from Recents",
        "你的 Mac 工具箱": "Tools for your Mac",
        "保持唤醒": "Keep awake",
        "偏好与数据": "Preferences & data",
        "全局取色快捷键": "Global shortcut",
        "全选": "Select All",
        "全部计为语音": "Count all as voice",
        "全部计为键盘": "Count all as keyboard",
        "关于 MacToys": "About MacToys",
        "关闭此选项后，屏幕可按系统设置熄灭，Mac 继续运行。": "When off, the display can sleep while your Mac keeps running.",
        "关闭窗口后继续生效；菜单栏右键可快速开关。": "Stays active with the window closed. Right-click the menu bar icon to toggle.",
        "剪切": "Cut",
        "单词": "Words",
        "双指滚动和惯性滚动均不反转。": "Two-finger and momentum scrolling stay unchanged.",
        "反转垂直滚动": "Reverse vertical scrolling",
        "反转已暂停": "Reversal paused",
        "反转水平滚动": "Reverse horizontal scrolling",
        "反转鼠标滚轮": "Reverse mouse wheel",
        "取消": "Cancel",
        "取消收藏": "Unfavorite",
        "取消收藏当前颜色": "Unfavorite color",
        "取色": "Colors",
        "取色后打开颜色面板": "Show color panel after picking",
        "取色后自动复制": "Copy after picking",
        "只保存分钟级计数，不保存输入内容。原 InputStats 历史记录继续保留。": "Saves counts per minute, never your text. Existing InputStats history is kept.",
        "合计": "Total",
        "同时保持屏幕亮起": "Keep display awake too",
        "启动系统放大镜；点击取色，Esc 取消": "Click to pick a color with the system magnifier. Esc cancels.",
        "启用 30 秒验证窗口": "Enable 30-second input test",
        "命令行": "CLI",
        "复制": "Copy",
        "复制 %@": "Copy %@",
        "复制格式": "Copy format",
        "多": "More",
        "好": "OK",
        "字": "characters",
        "字母或数字 + ⌘ / ⌥ / ⌃；Esc 取消。": "Use a letter or digit with ⌘, ⌥, or ⌃. Esc cancels.",
        "字符": "Characters",
        "安全输入区域 · 已跳过": "Secure input · Skipped",
        "密码测试（应当完全跳过）": "Password test (must be skipped)",
        "导出失败": "Export failed",
        "导出每日统计": "Export daily counts",
        "将在 %@ 自动关闭": "Ends at %@",
        "拾取": "Pick",
        "少": "Less",
        "屏幕取色": "Color Picker",
        "工具": "Tools",
        "已关闭": "Off",
        "已关闭 · 使用系统休眠设置": "Off · Using system sleep settings",
        "已复制 %@": "Copied %@",
        "已拾取 %@": "Picked %@",
        "应用 HEX": "Apply HEX",
        "开始输入后，这里会显示统计趋势": "Start typing to see your activity",
        "快捷工具": "Quick tools",
        "快捷键未能注册（%@），可能已被占用。请更换组合键；仍可使用取色按钮。": "Could not register shortcut (%@). It may be in use. Choose another combination or use the pick button.",
        "快捷面板": "Quick Panel",
        "打开 MacToys": "Open MacToys",
        "打开主窗口": "Open window",
        "打开数据文件夹": "Open data folder",
        "把 ⌘V 粘贴计入输入": "Include ⌘V pastes",
        "拾取屏幕上的颜色，用在设计与代码中。": "Pick screen colors for your designs and code.",
        "拾取屏幕颜色": "Pick screen color",
        "拾取屏幕颜色…": "Pick Screen Color…",
        "拾取或复制的颜色会保留在这里，点击色块可再次查看。": "Picked and copied colors appear here. Click a swatch to select it.",
        "持续时间": "Duration",
        "按下组合键…": "Press shortcut…",
        "撤销": "Undo",
        "收藏": "Favorites",
        "收藏已满（64 个），请先移除不需要的颜色。": "Favorites are full (64 colors). Remove a color to add another.",
        "收藏当前颜色": "Favorite color",
        "数据操作失败": "Data operation failed",
        "数量": "Count",
        "无法写入剪贴板，请重试。": "Could not write to the clipboard. Try again.",
        "无法创建滚轮监听，请重试。": "Could not create the scroll listener. Try again.",
        "无法启用防止休眠（系统错误 %@），请重试。": "Could not enable Keep Awake (system error %@). Try again.",
        "无法连接 Portman 后台。请重试，或运行 portman daemon status 查看状态。": "Could not connect to Portman. Retry or run portman daemon status.",
        "无法连接滚轮监听，请检查辅助功能权限后重试。": "Could not connect the scroll listener. Check Accessibility permission and retry.",
        "旧版记录": "Legacy data",
        "时间": "Time",
        "时间格式": "Time format",
        "时间范围": "Time range",
        "普通输入（临时数据）": "Normal input (temporary data)",
        "暂停": "Pause",
        "暂停统计": "Pause counting",
        "暂停输入统计": "Pause Input Stats",
        "更改持续时间会重新计时。关闭窗口后继续生效；菜单栏右键可快速开关。": "Changing the duration restarts the timer. Stays active with the window closed; right-click the menu bar icon to toggle.",
        "最小化": "Minimize",
        "最近保留 24 个颜色，收藏单独保存于本机。HEX、RGB 和 HSL 使用 sRGB；超出其范围的广色域颜色会被截取到可表示范围。": "Keeps 24 recent colors. Favorites are saved separately on this Mac. HEX, RGB, and HSL use sRGB; wider-gamut colors are clipped to its range.",
        "最近颜色": "Recent",
        "未找到 Portman，请先安装或检查 ~/.local/bin/portman。": "Portman was not found. Install it or check ~/.local/bin/portman.",
        "未找到 Python 3，请安装 Portman 的运行环境。": "Python 3 was not found. Install the Portman runtime.",
        "本机 Portman 页面加载失败，请重新连接。": "The local Portman page failed to load. Reconnect to continue.",
        "本机数据": "Local data",
        "来源": "Source",
        "查看 %@": "View %@",
        "正在启动": "Starting",
        "正在录制": "Recording",
        "正在连接本机 Portman…": "Connecting to local Portman…",
        "此应用未提供文本 · 中文不估算": "No accessible text · CJK not estimated",
        "此应用未提供文本 · 按键估算": "No accessible text · Estimated keystrokes",
        "此操作会清空已保存和等待保存的全部计数，无法撤销。": "This deletes all saved and pending counts. It cannot be undone.",
        "此范围包含旧版的删除倒扣记录；历史数据保留原值，新版只累计新增输入。": "Includes legacy records that subtracted deletions. History is unchanged; new counts only include added text.",
        "每日合计": "Daily totals",
        "清空": "Clear",
        "清空…": "Clear…",
        "清空全部历史统计？": "Clear all input history?",
        "清空历史数据…": "Clear history…",
        "清空最近颜色": "Clear recent colors",
        "清空最近颜色？收藏会保留。": "Clear recent colors? Favorites will be kept.",
        "滚轮": "Scroll",
        "滚轮反转": "Scroll Reversal",
        "滚轮反转…": "Scroll Reversal…",
        "滚轮监听已暂停，请重试。": "The scroll listener is paused. Try again.",
        "滚轮监听未能启用，请重试。": "Could not enable the scroll listener. Try again.",
        "滚轮监听未能恢复，请重试。": "Could not resume the scroll listener. Try again.",
        "滚轮设置…": "Scroll Settings…",
        "点击星标收藏常用颜色。": "Click the star to save a favorite color.",
        "现有辅助功能授权未生效": "Accessibility permission is unavailable",
        "用于防止闲置休眠。手动睡眠、合盖与锁屏仍按 macOS 的设置处理。退出后结束，下次启动保持关闭。": "Prevents idle sleep. Manual sleep, lid close, and screen locking follow macOS settings. Quitting ends the session; it stays off after relaunch.",
        "界面测试 · 全局反转已关闭": "UI test · Global reversal disabled",
        "界面测试 · 监听已关闭": "UI test · Input monitoring disabled",
        "界面测试 · 系统防休眠已关闭": "UI test · System sleep prevention disabled",
        "登录时启动 MacToys": "Launch MacToys at login",
        "直到关闭": "Until turned off",
        "直到手动关闭或退出 MacToys": "Until turned off or MacToys quits",
        "窗口": "Window",
        "端口转发": "Port Forwarding",
        "等待可编辑输入区域": "Waiting for an editable field",
        "等待输入": "Waiting for input",
        "粘贴": "Paste",
        "统计": "Stats",
        "统计单位": "Metric",
        "统计尚未保存，已取消退出": "Counts are not saved. Quit cancelled.",
        "统计已暂停": "Counting paused",
        "统计视图每 5 分钟刷新，输入持续记录。": "Charts refresh every 5 minutes. Input is recorded continuously.",
        "继续": "Resume",
        "继续统计": "Resume counting",
        "继续输入统计": "Resume Input Stats",
        "编辑": "Edit",
        "自动 · Fn": "Auto · Fn",
        "自动识别 Fn（豆包 / 系统听写）": "Automatic Fn (Doubao / Dictation)",
        "菜单栏右键也可取色。使用放大镜时，空格显示 RGB，Esc 取消。": "Also available from the menu bar. In the magnifier, Space shows RGB; Esc cancels.",
        "触控板保持系统方向": "Trackpad follows system direction",
        "设置": "Settings",
        "设置…": "Settings…",
        "设置取色快捷键": "Set color picker shortcut",
        "词": "words",
        "语言": "Language",
        "语言 / Language": "Language",
        "语音": "Voice",
        "语音输入 · 按上屏文字统计": "Voice · Counting committed text",
        "请使用字母或数字，加上 ⌘、⌥、⌃ 中的至少一个修饰键。": "Use a letter or digit with at least one of ⌘, ⌥, or ⌃.",
        "请在系统设置的登录项中启用 MacToys。": "Enable MacToys in System Settings → Login Items.",
        "请输入 3 位或 6 位 HEX，例如 #F80 或 #FF8800。": "Enter a 3- or 6-digit HEX color, such as #F80 or #FF8800.",
        "请选择要反转的方向": "Select a direction to reverse",
        "调整颜色": "Adjust color",
        "调整鼠标滚轮，保留触控板的滚动方向。": "Reverse mouse wheel scrolling while keeping the trackpad direction.",
        "跟随系统": "System",
        "辅助功能授权未生效，请在系统设置中检查 MacToys 的权限。": "Accessibility permission is unavailable. Check MacToys in System Settings.",
        "输入来源": "Input source",
        "输入监听未连接，请点重试": "Input listener disconnected · Retry",
        "输入统计": "Input Stats",
        "输入统计、端口转发、屏幕取色、滚轮反转与防止休眠。关闭窗口后继续运行；退出 MacToys 会停止统计、快捷键、滚轮反转和防止休眠，Portman 的连接继续由后台管理。": "Input Stats, Port Forwarding, Color Picker, Scroll Reversal, and Keep Awake. Tools stay active with the window closed. Quitting stops counting, shortcuts, scroll reversal, and Keep Awake; Portman connections continue in the background.",
        "近 %@ 天": "%@ days",
        "近 N 天": "Recent days",
        "近一年": "Year",
        "近一年 · 颜色越深输入越多": "Past year · Darker means more input",
        "近期趋势：%@ 天": "Recent activity: %@ days",
        "这个快捷键未能注册（%@），已保留原设置。请换一个组合键。": "Could not register shortcut (%@). The previous shortcut was kept. Try another combination.",
        "这个颜色无法转换为 sRGB，请重新取色。": "Could not convert this color to sRGB. Pick another color.",
        "退出 MacToys": "Quit MacToys",
        "适用于普通滚轮鼠标。Magic Mouse、连续滚动及其他软件生成的滚动保持原样。方向相对于 macOS 当前设置反转。": "For standard wheel mice. Trackpads, Magic Mouse, continuous scrolling, and software-generated events keep their direction. Reversal is relative to macOS settings.",
        "通用": "General",
        "重新连接": "Reconnect",
        "重试": "Retry",
        "重试连接": "Reconnect",
        "键盘": "Keyboard",
        "键盘输入 · 按新增文字统计": "Keyboard · Counting added text",
        "长文档 · 按键估算": "Long document · Estimated keystrokes",
        "防休眠": "Awake",
        "防休眠时长无效。": "Invalid Keep Awake duration.",
        "防休眠设置…": "Keep Awake Settings…",
        "防止休眠": "Keep Awake",
        "防止休眠…": "Keep Awake…",
        "防止休眠已开启": "Keep Awake is on",
        "隐藏 MacToys": "Hide MacToys",
        "颜色面板": "Color Panel",
        "颜色预览 %@": "Color preview %@",
        "验证密码": "Test password",
        "验证文本": "Test text",
        "鼠标滚轮反转已启用": "Mouse wheel reversal is on",
    ]
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    Localization.shared.text(key, arguments: arguments)
}
