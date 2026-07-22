import Foundation

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
    let ip: String?
    let other: String?

    enum CodingKeys: String, CodingKey {
        case id, content, username, quota, group, type, ip, other
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
