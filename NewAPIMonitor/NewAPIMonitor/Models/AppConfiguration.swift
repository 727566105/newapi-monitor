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
    }
    
    /// 清除登录状态
    func clearLogin() {
        sessionCookie = ""
        userId = 0
        username = ""
    }
}
