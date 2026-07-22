import Foundation

/// 用户角色
enum UserRole: String, Codable, CaseIterable {
    case admin
    case user
    
    var displayName: String {
        switch self {
        case .admin: return "管理员"
        case .user: return "普通用户"
        }
    }
}

/// 状态栏显示模式
enum StatusBarDisplayMode: String, CaseIterable {
    case textOnly = "纯文本"
    case cycle = "轮播切换"

    var displayName: String { rawValue }
}

/// 纯文本模式下数字格式
enum QuotaTextFormat: String, CaseIterable {
    case abbreviated = "缩写"
    case full = "完整"

    var displayName: String { rawValue }
}

/// 时间段筛选
enum Period: String, CaseIterable {
    case realtime = "实时"
    case today = "今日"
    case sevenDays = "7天"
    case thirtyDays = "30天"

    /// 根据当前时间计算查询的起止时间戳
    func timeRange() -> (start: Int64, end: Int64) {
        let now = Int64(Date().timeIntervalSince1970)
        switch self {
        case .realtime:
            let startOfToday = Calendar.current.startOfDay(for: Date())
            return (Int64(startOfToday.timeIntervalSince1970), now)
        case .today:
            return (now - 86400, now)
        case .sevenDays:
            return (now - 86400 * 7, now)
        case .thirtyDays:
            return (now - 86400 * 30, now)
        }
    }

    var label: String {
        switch self {
        case .realtime: return "实时用量"
        case .today: return "今日用量"
        case .sevenDays: return "7天用量"
        case .thirtyDays: return "30天用量"
        }
    }
}

/// 应用配置，持久化到 UserDefaults
@Observable
final class AppConfiguration {
    static let shared = AppConfiguration()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Keys
    private enum Keys {
        static let baseURL = "app_base_url"
        static let sessionCookie = "app_session_cookie"
        static let userId = "app_user_id"
        static let username = "app_username"
        static let role = "app_role"
        static let refreshInterval = "app_refresh_interval"
        static let hasCompletedSetup = "app_has_completed_setup"
        static let statusBarDisplayMode = "app_status_bar_display_mode"
        static let selectedPeriod = "app_selected_period"
        static let quotaTextFormat = "app_quota_text_format"
    }
    
    // MARK: - Properties
    
    var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Keys.baseURL) }
    }
    
    /// 登录后获取的 session cookie
    var sessionCookie: String {
        didSet { defaults.set(sessionCookie, forKey: Keys.sessionCookie) }
    }
    
    /// 登录用户的数字 ID（用于 New-Api-User header）
    var userId: Int {
        didSet { defaults.set(userId, forKey: Keys.userId) }
    }
    
    /// 登录用户名
    var username: String {
        didSet { defaults.set(username, forKey: Keys.username) }
    }
    
    var role: UserRole {
        didSet { defaults.set(role.rawValue, forKey: Keys.role) }
    }
    
    var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }
    
    var hasCompletedSetup: Bool {
        didSet { defaults.set(hasCompletedSetup, forKey: Keys.hasCompletedSetup) }
    }

    var statusBarDisplayMode: StatusBarDisplayMode {
        didSet { defaults.set(statusBarDisplayMode.rawValue, forKey: Keys.statusBarDisplayMode) }
    }

    var selectedPeriod: Period {
        didSet { defaults.set(selectedPeriod.rawValue, forKey: Keys.selectedPeriod) }
    }

    var quotaTextFormat: QuotaTextFormat {
        didSet { defaults.set(quotaTextFormat.rawValue, forKey: Keys.quotaTextFormat) }
    }
    
    // MARK: - Computed
    
    /// 是否已配置（有服务器地址且已登录）
    var isConfigured: Bool {
        !baseURL.isEmpty && !sessionCookie.isEmpty
    }
    
    /// 是否已登录
    var isLoggedIn: Bool {
        !sessionCookie.isEmpty
    }
    
    // MARK: - Init
    
    private init() {
        let defaults = UserDefaults.standard
        self.baseURL = defaults.string(forKey: Keys.baseURL) ?? ""
        self.sessionCookie = defaults.string(forKey: Keys.sessionCookie) ?? ""
        self.userId = defaults.integer(forKey: Keys.userId)
        self.username = defaults.string(forKey: Keys.username) ?? ""
        self.role = UserRole(rawValue: defaults.string(forKey: Keys.role) ?? "") ?? .user
        let interval = defaults.double(forKey: Keys.refreshInterval)
        self.refreshInterval = interval == 0 ? 60 : interval
        self.hasCompletedSetup = defaults.bool(forKey: Keys.hasCompletedSetup)
        self.statusBarDisplayMode = StatusBarDisplayMode(rawValue: defaults.string(forKey: Keys.statusBarDisplayMode) ?? "") ?? .textOnly
        self.selectedPeriod = Period(rawValue: defaults.string(forKey: Keys.selectedPeriod) ?? "") ?? .realtime
        self.quotaTextFormat = QuotaTextFormat(rawValue: defaults.string(forKey: Keys.quotaTextFormat) ?? "") ?? .abbreviated
    }
    
    /// 清除登录状态
    func clearLogin() {
        sessionCookie = ""
        userId = 0
        username = ""
    }
}
