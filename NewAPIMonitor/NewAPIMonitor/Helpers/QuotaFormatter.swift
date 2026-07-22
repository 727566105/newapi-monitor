import Foundation

/// 配额数值格式化工具
enum QuotaFormatter {

    // MARK: - 简写格式（52K, 1.2M）

    /// 将配额数值格式化为简写形式
    /// - Parameter value: 原始配额值
    /// - Returns: 格式化后的字符串（如 "52K", "1.2M", "520"）
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
            // 如果是整千，显示为 "52K"；否则 "1.2K"
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

    /// 将配额数值格式化为带千分位分隔符的形式
    /// - Parameter value: 原始配额值
    /// - Returns: 格式化后的字符串（如 "52,000", "1,200,000"）
    static func full(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: - 百分比格式

    /// 计算并格式化使用百分比
    /// - Parameters:
    ///   - used: 已使用量
    ///   - granted: 总分配量
    /// - Returns: 百分比字符串（如 "52%"），无限额返回 "--"
    static func percentage(used: Int?, granted: Int?, unlimited: Bool?) -> String {
        guard unlimited != true,
              let granted = granted, granted > 0 else {
            return "--"
        }
        let used = used ?? 0
        let percent = Double(used) / Double(granted) * 100
        return String(format: "%.0f%%", percent)
    }

    /// 计算使用百分比的小数值（用于进度条）
    /// - Parameters:
    ///   - used: 已使用量
    ///   - granted: 总分配量
    ///   - unlimited: 是否无限额
    /// - Returns: 0.0~1.0 之间的值，无限额返回 nil
    static func progressValue(used: Int?, granted: Int?, unlimited: Bool?) -> Double? {
        guard unlimited != true,
              let granted = granted, granted > 0 else {
            return nil
        }
        let used = used ?? 0
        return min(Double(used) / Double(granted), 1.0)
    }
}
