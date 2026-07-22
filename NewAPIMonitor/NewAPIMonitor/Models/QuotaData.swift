import Foundation

/// 小时粒度用量数据（来自 /api/data/ 或 /api/data/self）
struct QuotaData: Codable, Identifiable {
    let id: Int
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
