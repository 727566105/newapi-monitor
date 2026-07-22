import Foundation

// MARK: - 通用 API 响应包装

struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let message: String?
    let data: T?
}

// MARK: - 分页 API 响应包装
// new-api v1.0.0-rc.11 返回格式：
// {"success":true, "message":"", "data":{"page":1, "page_size":20, "total":100, "items":[...]}}

struct PaginatedResponse<T: Codable>: Codable {
    let success: Bool
    let message: String?
    let data: PaginatedData<T>?

    /// 便捷属性：获取 items 数组
    var items: [T] {
        data?.items ?? []
    }

    /// 便捷属性：获取总数
    var total: Int {
        data?.total ?? 0
    }
}

/// 分页数据嵌套结构
struct PaginatedData<T: Codable>: Codable {
    let items: [T]?
    let page: Int?
    let pageSize: Int?
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case items, page, total
        case pageSize = "page_size"
    }
}
