import Foundation

struct APIModel: Codable, Identifiable {
    let id: Int
    var modelName: String
    let description: String?
    let icon: String?
    let tags: String?              // API returns a plain string like "glm", not an array
    let vendorId: Int?
    var status: Int                // 1=启用, 0=禁用 — var 以支持乐观更新
    let boundChannels: [BoundChannel]?
    let enableGroups: [String]?
    let quotaTypes: [Int]?
    let createdTime: Int64?
    let updatedTime: Int64?
    let endpoints: String?         // JSON string like "[\"openai\",\"anthropic\"]"
    let syncOfficial: Int?
    let nameRule: Int?

    enum CodingKeys: String, CodingKey {
        case id, description, icon, tags, status, endpoints
        case modelName = "model_name"
        case vendorId = "vendor_id"
        case boundChannels = "bound_channels"
        case enableGroups = "enable_groups"
        case quotaTypes = "quota_types"
        case createdTime = "created_time"
        case updatedTime = "updated_time"
        case syncOfficial = "sync_official"
        case nameRule = "name_rule"
    }

    var isEnabled: Bool {
        get { status == 1 }
        set { status = newValue ? 1 : 0 }
    }
}

/// Bound channel object from the API
struct BoundChannel: Codable {
    let name: String?
    let type: Int?
}
