import Foundation

// MARK: - 用户信息（用于角色自动检测）
// 对应 new-api 后端 /api/user/self 返回的 User 对象
struct UserInfo: Codable {
    let id: Int?
    let username: String?
    let displayName: String?
    let role: Int?          // new-api: 100=Admin, 1=普通用户
    let status: Int?
    let email: String?
    let quota: Int?
    let usedQuota: Int?
    let requestCount: Int?
    let group: String?
    let affCode: String?
    let affCount: Int?
    let affQuota: Int?
    let affHistoryQuota: Int?
    let inviterId: Int?
    let setting: String?
    let sidebarModules: String?

    enum CodingKeys: String, CodingKey {
        case id, username, role, status, email, quota, group, setting
        case displayName = "display_name"
        case usedQuota = "used_quota"
        case requestCount = "request_count"
        case affCode = "aff_code"
        case affCount = "aff_count"
        case affQuota = "aff_quota"
        case affHistoryQuota = "aff_history_quota"
        case inviterId = "inviter_id"
        case sidebarModules = "sidebar_modules"
    }

    /// 是否为管理员（new-api 中 role >= 10 视为管理员）
    var isAdmin: Bool { (role ?? 0) >= 10 }
}
