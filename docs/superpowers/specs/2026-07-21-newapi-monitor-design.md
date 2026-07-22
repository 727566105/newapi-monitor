# NewAPI Monitor — macOS 原生客户端设计文档

> 日期：2026-07-21
> 状态：修订版 v2（已整合规范审查反馈）
> 目标：开发 macOS 原生客户端，接入 new-api 后端，实现用量查询、模型开关、统计展示及菜单栏状态显示

---

## 1. 项目概述

### 1.1 背景
[new-api](https://github.com/QuantumNous/new-api) 是一个基于 Go + Gin 的开源 API 管理平台，提供大模型 API 的代理、计费、监控等能力。本项目为其开发 macOS 原生客户端，方便用户在桌面端快速查看用量、管理模型状态、分析使用趋势。

### 1.2 核心功能
1. **大模型调用用量查询** — 查询并展示模型调用的配额使用情况
2. **模型启用状态开关** — 管理员可启用/禁用模型
3. **用量统计展示** — 按时间维度（1天/7天/30天）展示用量趋势图表和明细表格
4. **菜单栏状态显示** — 在 macOS 顶部状态栏实时显示用量百分比

### 1.3 角色支持
- **Admin**：可访问所有功能，包括模型管理
- **User**：仅可查看自身用量和统计，模型管理页隐藏
- **角色自动检测**：应用通过 `/api/user/self` 端点自动检测用户角色，无需手动选择。若检测失败，回退为手动选择模式。当 Admin API 返回 403 时，自动隐藏 Admin 专属页面。

### 1.4 首次启动流程
首次启动时，`baseURL` 和 `token` 为空，应用将：
1. 不显示主界面内容，而是模态弹出设置页
2. 用户配置服务器地址和 Token 后，点击"测试连接"
3. 连接成功后自动检测角色并进入主界面
4. 连接失败则停留在设置页，显示错误提示

---

## 2. 技术架构

### 2.1 技术栈
| 层级 | 技术选型 | 说明 |
|------|---------|------|
| UI 框架 | SwiftUI | macOS 14+ 原生 |
| 图表 | Swift Charts | macOS 14+ 内置 |
| 网络层 | URLSession + async/await | 原生，无第三方依赖 |
| 状态管理 | @Observable (Observation 框架) | Swift 5.9+，macOS 14+ |
| 数据持久化 | UserDefaults | 轻量配置存储 |
| 菜单栏 | NSStatusItem + NSPopover | AppKit 桥接 |

> **最低系统要求**：macOS 14.0 (Sonoma)+，Xcode 15+，Swift 5.9+
> 
> 选择 macOS 14+ 的原因：`@Observable` 宏是 Swift 5.9 Observation 框架的核心，相比 `@ObservableObject` + `@Published` 更简洁高效，避免手动 `objectWillChange.send()` 调用。macOS 14 是当前主流版本，覆盖绝大多数用户。

### 2.2 架构图

```
┌─────────────────────────────────────────────────┐
│                  macOS App                       │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ Menu Bar │  │  Window  │  │  Background   │  │
│  │  Status  │  │  (HUD)   │  │   Timer       │  │
│  │ 🤖 52%   │  │          │  │  (60s poll)   │  │
│  └────┬─────┘  └────┬─────┘  └───────┬───────┘  │
│       │              │                │          │
│       └──────────────┼────────────────┘          │
│                      │                           │
│              ┌───────┴───────┐                    │
│              │ NewAPIClient  │                    │
│              │  (Singleton)  │                    │
│              │  @Observable  │                    │
│              └───────┬───────┘                    │
│                      │                           │
│              ┌───────┴───────┐                    │
│              │  URLSession   │                    │
│              └───────┬───────┘                    │
└──────────────────────┼──────────────────────────┘
                       │ HTTPS
              ┌────────┴────────┐
              │   new-api 后端   │
              │  (用户自配置URL)  │
              └─────────────────┘
```

### 2.3 应用类型
macOS 菜单栏 + 窗口混合应用：
- **菜单栏常驻**：显示实时用量百分比，点击弹出下拉详情
- **主窗口**：通过菜单栏"打开主窗口"或 Dock 图标打开
  - 使用 NavigationSplitView 侧边栏布局
  - 窗口风格为标准 macOS 窗口（带标题栏），非浮动面板
  - 关闭窗口后应用不退出，可通过 Dock 或菜单栏重新打开
- **Dock 图标**：应用在 Dock 中显示，点击可唤起主窗口

### 2.4 依赖注入
`NewAPIClient` 作为全局单例，通过 SwiftUI Environment 传递：
```swift
@main
struct NewAPIMonitorApp: App {
    @State private var apiClient = NewAPIClient()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(apiClient)
        }
    }
}
```
菜单栏 Popover 通过 `NSHostingController` 创建时手动注入：
```swift
let rootView = MenuBarPopoverView().environment(apiClient)
popover.contentViewController = NSHostingController(rootView: rootView)
```

---

## 3. API 层设计

### 3.1 认证方式
- Bearer Token：所有请求携带 `Authorization: Bearer <token>` 头
- Token 由用户在设置页配置
- Token 变更时，取消所有进行中的请求，使用新 Token 重新发起

### 3.2 API 端点映射

#### 用户信息（角色检测）
| 端点 | 角色 | 说明 |
|------|------|------|
| `GET /api/user/self` | Both | 获取当前用户信息，含 `role` 字段（1=Admin, 2=User） |

#### 用量查询
| 端点 | 角色 | 说明 |
|------|------|------|
| `GET /api/log/self/stat` | User | 当前用户聚合统计（quota, rpm, tpm） |
| `GET /api/log/stat` | Admin | 全局聚合统计 |
| `GET /api/usage/token/` | Both | 当前认证 Token 的配额信息（total_granted, total_used, total_available, unlimited_quota）。此端点基于请求中的 Bearer Token 自动识别用户，无需额外参数 |
| `GET /api/log/self` | User | 当前用户日志分页查询 |
| `GET /api/log/` | Admin | 全局日志分页查询 |

> **关于 `/api/usage/token/`**：该端点通过请求中的 Bearer Token 自动识别用户身份，返回该 Token 对应的配额使用情况。无需传递 token ID 参数。返回的 `total_granted` 为分配总额，`total_used` 为已使用量，`total_available` 为剩余可用量。

#### 模型管理
| 端点 | 角色 | 说明 |
|------|------|------|
| `GET /api/models/?status=all` | Admin | 获取所有模型（含启用/禁用状态） |
| `GET /api/models/search` | Admin | 按关键词/厂商/状态搜索模型 |
| `PUT /api/models/?status_only=true` | Admin | 切换模型状态。Body: `{"id": N, "status": 0/1}`。此为 new-api 后端的实际 API 设计，使用 query param `status_only=true` 标识仅更新状态 |

#### 用量统计
| 端点 | 角色 | 说明 |
|------|------|------|
| `GET /api/data/self` | User | 当前用户小时粒度数据（最多1个月） |
| `GET /api/data/` | Admin | 全局小时粒度数据 |
| `GET /api/data/flow/self` | User | 当前用户流量明细 |
| `GET /api/data/flow/` | Admin | 全局流量明细 |

### 3.3 数据结构

#### UserInfo（角色检测）
```swift
struct UserInfo: Codable {
    let id: Int
    let username: String
    let displayName: String?
    let role: Int           // 1=Admin, 2=User
    let status: Int?
    
    var isAdmin: Bool { role == 1 }
    
    enum CodingKeys: String, CodingKey {
        case id, username, role, status
        case displayName = "display_name"
    }
}
```

#### Model
```swift
struct APIModel: Codable, Identifiable {
    let id: Int
    let modelName: String
    let description: String?
    let icon: String?
    let tags: [String]?
    let vendorId: Int?
    var status: Int          // 1=启用, 0=禁用 — var 以支持乐观更新
    let boundChannels: [Int]?
    let enableGroups: [String]?
    let quotaTypes: [Int]?
    let createdTime: Int64?
    let updatedTime: Int64?
    
    enum CodingKeys: String, CodingKey {
        case id, description, icon, tags, status
        case modelName = "model_name"
        case vendorId = "vendor_id"
        case boundChannels = "bound_channels"
        case enableGroups = "enable_groups"
        case quotaTypes = "quota_types"
        case createdTime = "created_time"
        case updatedTime = "updated_time"
    }
}
```

#### LogEntry
```swift
struct LogEntry: Codable, Identifiable {
    let id: Int
    let userId: Int?
    let createdAt: Int64
    let type: Int           // 0-7
    let content: String?
    let username: String?
    let tokenName: String?
    let modelName: String?
    let quota: Int?
    let promptTokens: Int?
    let completionTokens: Int?
    let useTime: Int?
    let isStream: Bool?
    let channel: Int?
    let channelName: String?
    let tokenId: Int?
    let group: String?
    let requestId: String?
    
    enum CodingKeys: String, CodingKey {
        case id, content, username, quota, group
        case userId = "user_id"
        case createdAt = "created_at"
        case tokenName = "token_name"
        case modelName = "model_name"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case useTime = "use_time"
        case isStream = "is_stream"
        case channel = "channel"
        case channelName = "channel_name"
        case tokenId = "token_id"
        case requestId = "request_id"
    }
}
```

#### QuotaData（小时粒度）
```swift
struct QuotaData: Codable, Identifiable {
    let id: Int             // 数据库行 ID，Identifiable 用于列表渲染
    let userId: Int?
    let username: String?
    let modelName: String?
    let createdAt: Int64     // 小时截断的时间戳
    let useGroup: String?
    let tokenId: Int?
    let channelId: Int?
    let tokenUsed: Int?
    let count: Int?
    let quota: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, username, quota, count
        case userId = "user_id"
        case modelName = "model_name"
        case createdAt = "created_at"
        case useGroup = "use_group"
        case tokenId = "token_id"
        case channelId = "channel_id"
        case tokenUsed = "token_used"
    }
}
```

#### TokenUsage
```swift
struct TokenUsage: Codable {
    let totalGranted: Int?      // 分配总额
    let totalUsed: Int?         // 已使用量
    let totalAvailable: Int?    // 剩余可用量
    let unlimitedQuota: Bool?   // 是否无限额
    
    enum CodingKeys: String, CodingKey {
        case totalGranted = "total_granted"
        case totalUsed = "total_used"
        case totalAvailable = "total_available"
        case unlimitedQuota = "unlimited_quota"
    }
}
```

#### Stat
```swift
struct Stat: Codable {
    let quota: Int     // 当前统计周期内的已使用配额（非总额，与 TokenUsage.totalUsed 不同）
    let rpm: Int       // 每分钟请求数
    let tpm: Int       // 每分钟 Token 数
}
```

> **Stat.quota 与 TokenUsage 的关系**：`Stat.quota` 是 `/api/log/stat` 返回的统计周期内已消耗配额，`TokenUsage.totalUsed` 是 Token 级别的累计已用配额，`TokenUsage.totalGranted` 是分配总额。概览页的"已用配额"来自 `TokenUsage.totalUsed`，"剩余配额"来自 `TokenUsage.totalAvailable`，进度条百分比 = `totalUsed / totalGranted`。

#### 通用响应包装
```swift
struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let message: String?
    let data: T?
}

struct PaginatedResponse<T: Codable>: Codable {
    let success: Bool
    let message: String?
    let data: [T]?
    let total: Int?
}
```

### 3.4 分页参数
日志和模型列表端点支持分页，统一使用以下查询参数：
| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `page` | Int | 1 | 页码（从 1 开始） |
| `page_size` | Int | 10 | 每页条数 |

概览页"最近调用"默认请求 `page=1&page_size=20`。

---

## 4. 页面设计

### 4.1 导航结构
```
NavigationSplitView
├── Sidebar
│   ├── ⚙️ 设置 (Settings)
│   ├── 📊 概览 (Overview)
│   ├── 🤖 模型管理 (Models) [Admin only — 角色检测后动态显示]
│   └── 📈 统计 (Statistics)
└── Detail
    └── [对应页面内容]
```

### 4.2 设置页 (Settings)
**功能**：配置后端连接和用户偏好

| 字段 | 类型 | 说明 |
|------|------|------|
| 服务器地址 | TextField | new-api 后端 URL（如 `https://api.example.com`） |
| API Token | SecureField | Bearer Token |
| 用户角色 | Text (只读) | 自动检测显示，无需手动选择。检测失败时显示 Picker 供手动选择 |
| 刷新间隔 | Slider | 30s ~ 300s，默认 60s |
| 连接测试 | Button | 点击验证配置是否正确，同时检测角色 |

**布局**：
```
┌─────────────────────────────────────┐
│  ⚙️ 设置                            │
│                                     │
│  服务器地址                          │
│  ┌─────────────────────────────┐    │
│  │ https://api.example.com     │    │
│  └─────────────────────────────┘    │
│                                     │
│  API Token                          │
│  ┌─────────────────────────────┐    │
│  │ ••••••••••••••••            │    │
│  └─────────────────────────────┘    │
│                                     │
│  用户角色    Admin ✓ (自动检测)      │
│                                     │
│  刷新间隔    ──●──────── 60s        │
│                                     │
│  [🔗 测试连接]                      │
│                                     │
│  ✅ 连接成功 · 角色: Admin           │
└─────────────────────────────────────┘
```

### 4.3 概览页 (Overview)
**功能**：展示当前用量概览和最近调用记录

**布局**：
```
┌─────────────────────────────────────┐
│  📊 概览                            │
│                                     │
│  ┌──────────┐ ┌──────────┐ ┌─────┐ │
│  │ 已用配额  │ │ 剩余配额  │ │ RPM │ │
│  │  52,000  │ │  48,000  │ │ 120 │ │
│  └──────────┘ └──────────┘ └─────┘ │
│                                     │
│  配额使用进度                        │
│  ████████████░░░░░░░░ 52%          │
│  (无限额时显示: ∞ 无限额度)          │
│                                     │
│  最近调用                           │
│  ┌─────────────────────────────────┐│
│  │ 模型        │ Token   │ 配额    ││
│  │ gpt-4o      │ sk-xxx  │ 1,200  ││
│  │ claude-3.5  │ sk-yyy  │ 800    ││
│  │ ...         │ ...     │ ...    ││
│  └─────────────────────────────────┘│
│                                     │
│  ── 离线状态 ──                     │
│  ⚠️ 无法连接到服务器，请检查网络设置  │
│                                     │
│  ── 空数据状态 ──                   │
│  📭 暂无调用记录                    │
└─────────────────────────────────────┘
```

**无限额处理**：
- `unlimitedQuota == true` 时：进度条替换为 `∞ 无限额度` 文本标签
- "已用配额"正常显示已使用量，"剩余配额"显示 `∞`
- 菜单栏显示 `🤖 --`

**离线/空数据状态**：
- 网络不可达时：页面顶部显示黄色警告横幅 `⚠️ 无法连接到服务器`
- 无数据时：表格区域显示空状态占位 `📭 暂无调用记录`

**数据来源**：
- 配额数据：`/api/usage/token/` → TokenUsage
- RPM/TPM：`/api/log/self/stat` (User) / `/api/log/stat` (Admin) → Stat
- 最近调用：`/api/log/self` (User) / `/api/log/` (Admin) → [LogEntry]，page=1, page_size=20

### 4.4 模型管理页 (Models) — Admin Only
**功能**：查看和切换模型启用/禁用状态

**布局**：
```
┌─────────────────────────────────────┐
│  🤖 模型管理                        │
│                                     │
│  🔍 [搜索模型...]    [状态 ▾]       │
│                                     │
│  ┌─────────────────────────────────┐│
│  │ 🟢 gpt-4o          [●  启用]   ││
│  │ 🟢 claude-3.5      [●  启用]   ││
│  │ 🔴 gemini-pro      [○  禁用]   ││
│  │ 🟢 deepseek-v3     [●  启用]   ││
│  │ ...                            ││
│  └─────────────────────────────────┘│
│                                     │
│  ── 空状态 ──                       │
│  📭 暂无模型数据                    │
└─────────────────────────────────────┘
```

**交互**：
- Toggle 切换时调用 `PUT /api/models/?status_only=true`
- 乐观更新 UI，失败时回滚并显示 Toast 提示
- 搜索使用 `GET /api/models/search`，**300ms 防抖**（避免每次按键触发请求）
- 空模型列表时显示 `📭 暂无模型数据`

### 4.5 统计页 (Statistics)
**功能**：按时间维度展示用量趋势

**布局**：
```
┌─────────────────────────────────────┐
│  📈 统计                            │
│                                     │
│  [1天] [7天] [30天]    [模型 ▾]     │
│                                     │
│  用量趋势                           │
│  ┌─────────────────────────────────┐│
│  │     📊 折线图/柱状图            ││
│  │  52K│    ╱╲                     ││
│  │  40K│   ╱  ╲   ╱╲              ││
│  │  28K│  ╱    ╲ ╱  ╲             ││
│  │  16K│ ╱      ╳    ╲            ││
│  │   4K│╱            ╲            ││
│  │     └──────────────────         ││
│  │      7/15 7/17 7/19 7/21       ││
│  └─────────────────────────────────┘│
│                                     │
│  用量明细                           │
│  ┌─────────────────────────────────┐│
│  │ 日期       │ 模型     │ 配额    ││
│  │ 2026-07-21 │ gpt-4o  │ 12,000 ││
│  │ 2026-07-21 │ claude  │  8,000 ││
│  │ ...        │ ...     │ ...    ││
│  └─────────────────────────────────┘│
│                                     │
│  ── 离线状态 ──                     │
│  ⚠️ 无法连接到服务器                │
│                                     │
│  ── 空数据状态 ──                   │
│  📭 暂无统计数据                    │
└─────────────────────────────────────┘
```

**数据来源与聚合策略**：
- `/api/data/self` (User) / `/api/data/` (Admin) → [QuotaData]
- **1天视图**：保留小时粒度，X 轴按小时展示（24 个数据点）
- **7天视图**：按日聚合，X 轴按天展示（7 个数据点）
- **30天视图**：按日聚合，X 轴按天展示（30 个数据点）
- **模型筛选**：客户端侧过滤（从已获取的 QuotaData 中按 modelName 筛选），无需额外 API 调用

**图表类型**：
- 默认使用 **折线图** (`LineMark`) 展示趋势
- 可通过工具栏按钮切换为 **柱状图** (`BarMark`) 展示对比

---

### 4.6 菜单栏下拉 (Menu Bar Popover)
**功能**：快速查看用量概览

**布局**：
```
┌──────────────────────┐
│  🤖 NewAPI Monitor   │
│                      │
│  配额使用  52%       │
│  ████████░░░░░░░░    │
│                      │
│  已用    52,000      │
│  总额    100,000     │
│  RPM     120        │
│                      │
│  [打开主窗口]        │
│  [设置...]          │
└──────────────────────┘

── 无限额时 ──
┌──────────────────────┐
│  🤖 NewAPI Monitor   │
│                      │
│  配额使用  ∞         │
│  无限额度            │
│                      │
│  已用    52,000      │
│  总额    无限制      │
│  RPM     120        │
│                      │
│  [打开主窗口]        │
│  [设置...]          │
└──────────────────────┘
```

**数据来源**：`/api/usage/token/` → TokenUsage
**无限额处理**：`unlimited_quota=true` 时菜单栏显示 `🤖 --`，下拉中进度条替换为 `∞ 无限额度`，总额显示"无限制"

---

## 5. 数据刷新与错误处理

### 5.1 刷新策略
| 页面/组件 | 触发方式 | 间隔 |
|-----------|---------|------|
| 菜单栏 | 后台 Timer | 可配置，默认 60s |
| 概览页 | 页面可见时 + 手动刷新 | 进入页面时 |
| 模型管理 | 进入页面 + 手动刷新 | 进入页面时 |
| 统计页 | 手动刷新 | 切换时间范围时 |

**后台 Timer 实现**：使用 `Task` + `AsyncTimerSequence`，在 `NewAPIClient` 中管理生命周期。应用进入后台时暂停，回到前台时恢复。

### 5.2 错误处理
| 错误类型 | 显示方式 | 说明 |
|---------|---------|------|
| 网络错误 | 页面顶部 Inline Banner（黄色） | "⚠️ 无法连接到服务器，请检查网络设置" |
| 认证错误 | Inline Banner（红色）+ 自动弹出设置 | 401 时提示检查 Token |
| 权限错误 | 自动隐藏 Admin 页面 + Toast | 403 时自动切换为 User 模式 |
| 服务器错误 | Inline Banner（红色） | "❌ 服务器错误 (500)" |
| 模型切换失败 | Toast 提示 + UI 回滚 | 乐观更新失败时回滚 |

### 5.3 配置持久化 (UserDefaults)
```swift
@Observable
class AppConfiguration {
    var baseURL: String = ""
    var token: String = ""
    var role: UserRole = .user       // 自动检测后设置
    var refreshInterval: TimeInterval = 60  // 默认 60s
    var isFirstLaunch: Bool = true   // 首次启动标记
    
    enum UserRole: Int, Codable {
        case user = 2
        case admin = 1
    }
}
```

---

## 6. 项目结构

```
NewAPIMonitor/
├── NewAPIMonitorApp.swift          # App 入口 + @NSApplicationDelegateAdaptor
├── AppDelegate.swift               # NSStatusItem + NSPopover 管理
├── Models/
│   ├── UserInfo.swift              # 用户信息（含角色）
│   ├── APIModel.swift
│   ├── LogEntry.swift
│   ├── QuotaData.swift
│   ├── TokenUsage.swift
│   ├── Stat.swift
│   ├── APIResponse.swift
│   └── AppConfiguration.swift
├── Services/
│   └── NewAPIClient.swift          # API 客户端（全局单例，@Observable）
├── Views/
│   ├── ContentView.swift           # NavigationSplitView 主框架
│   ├── SettingsView.swift
│   ├── OverviewView.swift
│   ├── ModelsView.swift            # Admin only
│   ├── StatisticsView.swift
│   ├── MenuBarPopoverView.swift
│   └── OnboardingView.swift        # 首次启动引导
├── Helpers/
│   ├── DateHelper.swift            # 时间戳转换、聚合
│   └── QuotaFormatter.swift        # 配额格式化（52K, 1.2M 等）
└── Assets.xcassets/
```

---

## 7. 关键实现细节

### 7.1 菜单栏实现
```swift
// AppDelegate.swift
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var apiClient: NewAPIClient?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🤖 --"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 360)
        popover.behavior = .transient
        // contentViewController 在 apiClient 注入后设置
    }
    
    func setupPopover(with apiClient: NewAPIClient) {
        self.apiClient = apiClient
        let rootView = MenuBarPopoverView().environment(apiClient)
        popover.contentViewController = NSHostingController(rootView: rootView)
    }
    
    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: statusItem.button!.bounds, 
                       of: statusItem.button!, preferredEdge: .minY)
        }
    }
}
```

### 7.2 App 入口与 AppDelegate 连接
```swift
// NewAPIMonitorApp.swift
@main
struct NewAPIMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var apiClient = NewAPIClient()
    
    init() {
        // 连接完成后注入 apiClient 到 AppDelegate
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(apiClient)
                .onAppear {
                    appDelegate.setupPopover(with: apiClient)
                }
        }
    }
}
```

### 7.3 用量百分比计算
```swift
var usagePercentage: String {
    guard let usage = tokenUsage,
          usage.unlimitedQuota != true else {
        return "--"
    }
    guard let granted = usage.totalGranted, granted > 0 else {
        return "--"
    }
    let used = usage.totalUsed ?? 0
    let percent = Double(used) / Double(granted) * 100
    return String(format: "%.0f%%", percent)
}

var menuBarTitle: String {
    guard let usage = tokenUsage,
          usage.unlimitedQuota != true else {
        return "🤖 --"
    }
    guard let granted = usage.totalGranted, granted > 0 else {
        return "🤖 --"
    }
    let used = usage.totalUsed ?? 0
    let percent = Double(used) / Double(granted) * 100
    return "🤖 \(Int(percent))%"
}
```

### 7.4 小时粒度数据聚合
```swift
// QuotaData 按小时粒度返回，客户端按日聚合
struct DailyUsage: Identifiable {
    let id = UUID()
    let date: Date
    let quota: Int
    let count: Int
    let tokenUsed: Int
}

func aggregateByDay(_ data: [QuotaData]) -> [DailyUsage] {
    Dictionary(grouping: data) { item in
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(item.createdAt)))
    }.map { date, items in
        DailyUsage(
            date: date,
            quota: items.reduce(0) { $0 + ($1.quota ?? 0) },
            count: items.reduce(0) { $0 + ($1.count ?? 0) },
            tokenUsed: items.reduce(0) { $0 + ($1.tokenUsed ?? 0) }
        )
    }.sorted { $0.date < $1.date }
}

// 1天视图保留小时粒度
struct HourlyUsage: Identifiable {
    let id = UUID()
    let hour: Date        // 小时截断的时间
    let quota: Int
    let count: Int
    let tokenUsed: Int
}

func groupByHour(_ data: [QuotaData]) -> [HourlyUsage] {
    data.map { item in
        HourlyUsage(
            hour: Date(timeIntervalSince1970: TimeInterval(item.createdAt)),
            quota: item.quota ?? 0,
            count: item.count ?? 0,
            tokenUsed: item.tokenUsed ?? 0
        )
    }.sorted { $0.hour < $1.hour }
}
```

### 7.5 模型切换乐观更新
```swift
// NewAPIClient 中
func toggleModelStatus(_ model: Binding<APIModel>) async {
    let originalStatus = model.wrappedValue.status
    let newStatus = originalStatus == 1 ? 0 : 1
    
    // 乐观更新
    model.wrappedValue.status = newStatus
    
    do {
        try await updateModelStatus(id: model.wrappedValue.id, status: newStatus)
    } catch {
        // 回滚
        model.wrappedValue.status = originalStatus
        // 显示 Toast
        lastError = "模型状态切换失败：\(error.localizedDescription)"
    }
}
```

### 7.6 角色自动检测
```swift
func detectRole() async {
    do {
        let userInfo: UserInfo = try await request(endpoint: "/api/user/self")
        self.userRole = userInfo.isAdmin ? .admin : .user
        self.roleDetected = true
    } catch {
        // 检测失败，回退为手动模式
        self.roleDetected = false
    }
}

// 403 自动降级
func handleResponse(_ response: URLResponse) {
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
        // 自动降级为 User 模式
        self.userRole = .user
        self.showAdminPages = false
    }
}
```

### 7.7 配额格式化
```swift
enum QuotaFormatter {
    static func format(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        } else {
            return "\(value)"
        }
    }
}
```

### 7.8 搜索防抖
```swift
// ModelsView.swift
@State private var searchText = ""
@State private var searchDebounceTask: Task<Void, Never>?

var body: some View {
    // ...
    .onChange(of: searchText) { _, newValue in
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await apiClient.searchModels(keyword: newValue)
        }
    }
}
```

---

## 8. 最低系统要求
- macOS 14.0 (Sonoma)+
- Xcode 15+
- Swift 5.9+

---

## 9. 后续扩展
- 通知提醒：配额使用超过阈值时推送系统通知
- 多账户：支持配置多个 new-api 实例
- 国际化：中英文切换
- 快捷键：全局快捷键打开主窗口

> **注**：Dark/Light 模式已由 SwiftUI 自动支持，无需额外适配。
