import Foundation

enum DateHelper {

    // MARK: - Cached Formatters

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f
    }()

    // MARK: - Timestamp Conversion

    /// Convert Unix timestamp (seconds) to Date
    static func dateFromTimestamp(_ timestamp: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    /// Convert Date to Unix timestamp (seconds)
    static func timestampFromDate(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970)
    }

    /// Format a Unix timestamp as a date string
    static func formatDate(_ timestamp: Int64) -> String {
        dateTimeFormatter.string(from: dateFromTimestamp(timestamp))
    }

    /// Format a Unix timestamp as a date-only string
    static func formatDateOnly(_ timestamp: Int64) -> String {
        dateOnlyFormatter.string(from: dateFromTimestamp(timestamp))
    }

    /// Format a Unix timestamp as a time-only string
    static func formatTimeOnly(_ timestamp: Int64) -> String {
        timeOnlyFormatter.string(from: dateFromTimestamp(timestamp))
    }

    // MARK: - Time Range Helpers

    /// Get the start of today as a timestamp
    static func startOfToday() -> Int64 {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return timestampFromDate(startOfDay)
    }

    /// Get the timestamp for N days ago from now
    static func daysAgo(_ days: Int) -> Int64 {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: -days, to: Date())!
        return timestampFromDate(calendar.startOfDay(for: date))
    }

    /// Get the timestamp for the start of the current hour
    static func startOfCurrentHour() -> Int64 {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: Date())
        let startOfHour = calendar.date(from: components)!
        return timestampFromDate(startOfHour)
    }

    // MARK: - Aggregation

    /// Aggregate hourly QuotaData into daily buckets
    static func aggregateByDay(_ data: [QuotaData]) -> [DailyUsage] {
        let calendar = Calendar.current
        return Dictionary(grouping: data) { item in
            calendar.startOfDay(for: dateFromTimestamp(item.createdAt))
        }.map { date, items in
            DailyUsage(
                date: date,
                quota: items.reduce(0) { $0 + ($1.quota ?? 0) },
                count: items.reduce(0) { $0 + ($1.count ?? 0) },
                tokenUsed: items.reduce(0) { $0 + ($1.tokenUsed ?? 0) }
            )
        }.sorted { $0.date < $1.date }
    }

    /// Keep hourly granularity (for 1-day view), just sort by time
    static func hourlyData(_ data: [QuotaData]) -> [HourlyUsage] {
        data.map { item in
            HourlyUsage(
                date: dateFromTimestamp(item.createdAt),
                modelName: item.modelName ?? "unknown",
                quota: item.quota ?? 0,
                count: item.count ?? 0,
                tokenUsed: item.tokenUsed ?? 0
            )
        }.sorted { $0.date < $1.date }
    }

    /// Aggregate QuotaData by model name
    static func aggregateByModel(_ data: [QuotaData]) -> [ModelUsage] {
        Dictionary(grouping: data) { $0.modelName ?? "unknown" }
            .map { model, items in
                ModelUsage(
                    modelName: model,
                    quota: items.reduce(0) { $0 + ($1.quota ?? 0) },
                    count: items.reduce(0) { $0 + ($1.count ?? 0) },
                    tokenUsed: items.reduce(0) { $0 + ($1.tokenUsed ?? 0) }
                )
            }
            .sorted { $0.quota > $1.quota }
    }
}

// MARK: - Aggregated Data Types

struct DailyUsage: Identifiable {
    let id = UUID()
    let date: Date
    let quota: Int
    let count: Int
    let tokenUsed: Int

    var dateString: String {
        DateHelper.shortDateFormatter.string(from: date)
    }
}

struct HourlyUsage: Identifiable {
    let id = UUID()
    let date: Date
    let modelName: String
    let quota: Int
    let count: Int
    let tokenUsed: Int

    var timeString: String {
        DateHelper.timeOnlyFormatter.string(from: date)
    }
}

struct ModelUsage: Identifiable {
    let id = UUID()
    let modelName: String
    let quota: Int
    let count: Int
    let tokenUsed: Int
}
