import Foundation

/// 配额数值格式化工具
enum QuotaFormatter {

    // MARK: - 简写格式（52K, 1.2M）

    /// 将配额数值格式化为简写形式
    static func abbreviated(_ value: Int) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""

        if absValue >= 1_000_000_000 {
            let formatted = Double(absValue) / 1_000_000_000
            return "\(sign)\(String(format: "%.1f", formatted))B"
        } else if absValue >= 1_000_000 {
            let formatted = Double(absValue) / 1_000_000
            return "\(sign)\(String(format: "%.1f", formatted))M"
        } else if absValue >= 1_000 {
            let formatted = Double(absValue) / 1_000
            if formatted == floor(formatted) {
                return "\(sign)\(Int(formatted))K"
            } else {
                return "\(sign)\(String(format: "%.1f", formatted))K"
            }
        } else {
            return "\(sign)\(absValue)"
        }
    }

    // MARK: - 完整格式（带千分位）

    static func full(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    // MARK: - 百分比格式

    static func percentage(used: Int?, granted: Int?, unlimited: Bool?) -> String {
        guard unlimited != true,
              let granted = granted, granted > 0 else {
            return "--"
        }
        let used = used ?? 0
        let percent = Double(used) / Double(granted) * 100
        return String(format: "%.0f%%", percent)
    }

    static func progressValue(used: Int?, granted: Int?, unlimited: Bool?) -> Double? {
        guard unlimited != true,
              let granted = granted, granted > 0 else {
            return nil
        }
        let used = used ?? 0
        return min(Double(used) / Double(granted), 1.0)
    }
}