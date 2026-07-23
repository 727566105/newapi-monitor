# NewAPI Monitor

> macOS 原生 NewAPI 配额监控客户端 — 菜单栏实时追踪 API 用量、RPM 和模型状态

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 📸 预览

| 菜单栏弹窗 | 主窗口仪表盘 |
|:---:|:---:|
| 点击菜单栏图标查看用量概览、切换时间段 | 完整仪表盘、模型管理、统计数据 |

---

## ✨ 功能

- **菜单栏实时监控** — 支持纯文本 / 轮播切换两种显示模式，配额、百分比、RPM 一目了然
- **多时间段统计** — 实时 / 今日 / 7天 / 30天，灵活切换
- **配额使用追踪** — 已用 / 总额 / 百分比进度条，超额预警
- **模型管理** — 查看所有模型状态，一键启用/禁用
- **调用日志** — 浏览最近 API 调用记录
- **用量图表** — 按小时/天/模型维度聚合统计
- **角色适配** — 自动识别管理员/普通用户，展示对应数据
- **安全登录** — Cookie-based Session 认证，自动管理

## 📥 下载

| 版本 | 下载 |
|------|------|
| **macOS 26** | [NewAPIMonitor-macOS26.dmg](https://github.com/727566105/newapi-monitor/releases/latest/download/NewAPIMonitor-macOS26.dmg) |

> 安装：打开 DMG，将 `NewAPIMonitor.app` 拖入 `Applications` 文件夹即可。

## 🛠 从源码构建

```bash
# 1. 克隆仓库
git clone https://github.com/727566105/newapi-monitor.git
cd newapi-monitor/NewAPIMonitor

# 2. 构建 Release
xcodebuild -project NewAPIMonitor.xcodeproj \
  -scheme NewAPIMonitor \
  -destination 'platform=macOS' \
  -configuration Release \
  build

# 3. 打包 DMG（可选）
APP_PATH="$(xcodebuild -project NewAPIMonitor.xcodeproj -scheme NewAPIMonitor -showBuildSettings | grep -m1 'BUILT_PRODUCTS_DIR' | cut -d= -f2 | xargs)/NewAPIMonitor.app"
TMP=$(mktemp -d)
cp -R "$APP_PATH" "$TMP/"
ln -s /Applications "$TMP/Applications"
hdiutil create -volname "NewAPIMonitor" -srcfolder "$TMP" -format UDZO NewAPIMonitor-macOS26.dmg
rm -rf "$TMP"
```

## 🏗 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | SwiftUI + AppKit |
| 数据流 | `@Observable` (Observation 框架) |
| 菜单栏 | `MenuBarExtra` + `.menuBarExtraStyle(.window)` |
| 定时器 | Combine `Timer.publish` |
| 网络层 | `URLSession` + Cookie 自动管理 |
| 持久化 | `UserDefaults` (via `@Observable` + `didSet`) |
| 弹窗 | `NSPopover` → `MenuBarExtra`（macOS 26 迁移） |

## 📂 项目结构

```
NewAPIMonitor/
├── App/
│   ├── NewAPIMonitorApp.swift    # @main 入口 + MenuBarExtra 场景
│   └── AppDelegate.swift         # 后台数据刷新协调器
├── Services/
│   └── NewAPIClient.swift        # API 客户端（登录、配额、统计、模型）
├── Models/
│   ├── AppConfiguration.swift    # 应用配置（UserDefaults 持久化）
│   ├── UserInfo.swift            # 用户信息模型
│   ├── TokenUsage.swift          # 配额使用模型
│   ├── Stat.swift                # 统计模型
│   ├── APIModel.swift            # API 模型
│   ├── LogEntry.swift            # 日志条目
│   ├── QuotaData.swift           # 配额数据
│   └── APIResponse.swift         # 通用 API 响应
├── Views/
│   ├── ContentView.swift         # 主窗口导航
│   ├── OverviewView.swift        # 仪表盘概览
│   ├── ModelsView.swift          # 模型管理
│   ├── StatisticsView.swift      # 统计图表
│   ├── SettingsView.swift        # 设置页面
│   └── MenuBarPopoverView.swift  # 菜单栏弹窗
└── Helpers/
    ├── QuotaFormatter.swift      # 配额数值格式化
    └── DateHelper.swift          # 日期工具
```

## 🔄 macOS 26 兼容性

本版本已全面适配 macOS 26，清理了所有弃用 API：

| 弃用 API | 替换方案 |
|----------|----------|
| `NSStatusBar.system.statusItem(withLength:)` | `MenuBarExtra` |
| `NSPopover` + `NSHostingController` | `MenuBarExtra(.window)` |
| `NSApp.activate(ignoringOtherApps:)` | `NSApp.activate()` |
| `Timer.scheduledTimer` | Combine `Timer.publish` |
| `NumberFormatter` | `IntegerFormatStyle` |
| `NotificationCenter` selector 模式 | Combine `NotificationCenter.publisher` |

## 📄 License

MIT License