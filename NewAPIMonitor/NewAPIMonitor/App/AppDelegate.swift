import AppKit
import SwiftUI
import Combine

/// 后台数据刷新协调器 — 周期性拉取数据到 NewAPIClient.shared
/// MenuBarExtra 替换了旧的 NSStatusItem + NSPopover 方案
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var refreshCancellable: AnyCancellable?
    private var resignActiveCancellable: AnyCancellable?
    private var becomeActiveCancellable: AnyCancellable?
    private var periodChangeCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startTimers()

        // 前台/后台切换：暂停/恢复定时器
        resignActiveCancellable = NotificationCenter.default
            .publisher(for: NSApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.stopRefreshTimer()
            }

        becomeActiveCancellable = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.startTimers()
            }

        // 时间段变更时重新拉取数据
        periodChangeCancellable = NotificationCenter.default
            .publisher(for: .selectedPeriodChanged)
            .sink { [weak self] _ in
                Task { await self?.fetchAllData() }
            }
    }

    // MARK: - Timers

    private func startTimers() {
        stopRefreshTimer()

        let interval = AppConfiguration.shared.refreshInterval
        refreshCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.fetchAllData() }
            }

        // 立即获取一次
        Task { await fetchAllData() }
    }

    // MARK: - Data Fetching

    private func fetchAllData() async {
        await NewAPIClient.shared.fetchTokenUsage()
        await NewAPIClient.shared.fetchStat()
        await fetchPeriodQuota()
    }

    /// 获取当前选中时间段的用量，存入 client.quotaData
    private func fetchPeriodQuota() async {
        let config = AppConfiguration.shared
        guard !config.baseURL.isEmpty, config.userId > 0 else { return }

        let (start, end) = config.selectedPeriod.timeRange()

        let path = "/api/data/"
        var components = URLComponents(string: "\(config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))\(path)")
        components?.queryItems = [
            URLQueryItem(name: "start_timestamp", value: "\(start)"),
            URLQueryItem(name: "end_timestamp", value: "\(end)"),
            URLQueryItem(name: "page_size", value: "1000")
        ]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.setValue("\(config.userId)", forHTTPHeaderField: "New-Api-User")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            struct DataResponse: Codable { let data: [QuotaData]? }
            let response = try JSONDecoder().decode(DataResponse.self, from: data)
            if let items = response.data {
                // 存入 client 的 quotaData，供 MenuBarLabel 读取
                NewAPIClient.shared.quotaData = items
            }
        } catch {
            // 静默失败
        }
    }

    // MARK: - Lifecycle

    func stopRefreshTimer() {
        refreshCancellable?.cancel()
        refreshCancellable = nil
    }

    func restartRefreshTimer() {
        stopRefreshTimer()
        startTimers()
    }
}