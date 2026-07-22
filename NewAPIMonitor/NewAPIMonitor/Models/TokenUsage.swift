import Foundation

/// 配额使用信息（从 /api/user/self 的 quota/used_quota 构建）
struct TokenUsage {
    /// 总授予配额
    let totalGranted: Int
    /// 已使用配额
    let totalUsed: Int
    /// 剩余配额
    var totalAvailable: Int { totalGranted - totalUsed }
    /// 是否无限额（quota 为极大值时视为无限）
    var unlimitedQuota: Bool { totalGranted > 1_000_000_000_000 }

    /// 使用百分比（0~100），无限额返回 nil
    var usagePercentage: Double? {
        guard !unlimitedQuota, totalGranted > 0 else { return nil }
        return Double(totalUsed) / Double(totalGranted) * 100
    }

    /// 格式化的百分比字符串
    var usagePercentageString: String {
        guard let percent = usagePercentage else { return "--" }
        return String(format: "%.0f%%", percent)
    }
}
