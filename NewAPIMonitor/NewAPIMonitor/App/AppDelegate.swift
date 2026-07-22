import AppKit
import SwiftUI

/// 管理 macOS 菜单栏状态项和下拉弹窗
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var refreshTimer: Timer?
    var cycleTimer: Timer?

    /// 轮播索引：0=实时用量, 1=配额%, 2=RPM
    private var cycleIndex = 0
    /// 缓存的时间段用量
    private var cachedPeriodQuota: Int = 0
    /// 缓存的配额百分比
    private var cachedPercentage: String = "--"
    /// 缓存的 RPM
    private var cachedRPM: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        startTimers()
        NotificationCenter.default.addObserver(self,
            selector: #selector(onDisplayModeChanged),
            name: .statusBarDisplayModeChanged, object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(onPeriodChanged),
            name: .selectedPeriodChanged, object: nil)
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🤖 --"

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 450)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView()
                .environment(NewAPIClient.shared)
        )
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            Task {
                await NewAPIClient.shared.fetchTokenUsage()
                await NewAPIClient.shared.fetchStat()
            }
            popover.show(relativeTo: statusItem.button!.bounds, of: statusItem.button!, preferredEdge: .minY)
        }
    }

    // MARK: - Timers

    private func startTimers() {
        startRefreshTimer()
        startCycleTimer()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = AppConfiguration.shared.refreshInterval
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.fetchAllData() }
        }
        // 立即获取一次
        Task { await fetchAllData() }
    }

    private func startCycleTimer() {
        cycleTimer?.invalidate()
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.updateStatusBarTitle()
        }
    }

    // MARK: - Data Fetching

    private func fetchAllData() async {
        await NewAPIClient.shared.fetchTokenUsage()
        await NewAPIClient.shared.fetchStat()
        await fetchPeriodQuota()
        updateStatusBarTitle()
    }

    /// 获取当前选中时间段的用量
    private func fetchPeriodQuota() async {
        let config = AppConfiguration.shared
        guard !config.baseURL.isEmpty, config.userId > 0 else { return }

        let (start, end) = config.selectedPeriod.timeRange()

        let path = "/api/data/"
        var components = URLComponents(string: "\(config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))\(path)")
        components?.queryItems = [
            URLQueryItem(name: "start_timestamp", value: "\(start)"),
            URLQueryItem(name: "end_timestamp", value: "\(end)"),
            URLQueryItem(name: "page_size", value: "500")
        ]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.setValue("\(config.userId)", forHTTPHeaderField: "New-Api-User")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            struct DataResponse: Codable { let data: [QuotaData]? }
            let response = try JSONDecoder().decode(DataResponse.self, from: data)
            if let items = response.data {
                cachedPeriodQuota = items.reduce(0) { $0 + ($1.quota ?? 0) }
            }
        } catch {
            // 静默失败
        }
    }

    // MARK: - Status Bar Update

    func updateStatusBarTitle() {
        let mode = AppConfiguration.shared.statusBarDisplayMode

        // 更新缓存的百分比和 RPM
        if let usage = NewAPIClient.shared.tokenUsage {
            if usage.unlimitedQuota {
                cachedPercentage = "∞"
            } else if usage.totalGranted > 0 {
                let pct = Double(usage.totalUsed) / Double(usage.totalGranted) * 100
                cachedPercentage = String(format: "%.0f%%", pct)
            } else {
                cachedPercentage = "--"
            }
        }
        cachedRPM = NewAPIClient.shared.currentStat?.rpm ?? 0

        switch mode {
        case .textOnly:
            // 方案A：纯文本，支持缩写/完整切换
            let fmt = AppConfiguration.shared.quotaTextFormat
            let value = fmt == .abbreviated
                ? QuotaFormatter.abbreviated(cachedPeriodQuota)
                : QuotaFormatter.full(cachedPeriodQuota)
            statusItem.button?.title = "\(value) token"

        case .cycle:
            // 方案C：轮播切换（每3秒切换一个）
            let titles = [
                "🤖 \(QuotaFormatter.abbreviated(cachedPeriodQuota)) token",
                "🤖 \(cachedPercentage)",
                "🤖 \(cachedRPM) RPM"
            ]
            statusItem.button?.title = titles[cycleIndex]
            cycleIndex = (cycleIndex + 1) % titles.count
        }
    }

    // MARK: - Notification

    @objc private func onDisplayModeChanged() {
        cycleIndex = 0
        updateStatusBarTitle()
    }

    @objc private func onPeriodChanged() {
        Task {
            await fetchPeriodQuota()
            updateStatusBarTitle()
        }
    }

    // MARK: - Lifecycle

    func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        cycleTimer?.invalidate()
        cycleTimer = nil
    }

    func restartRefreshTimer() {
        stopRefreshTimer()
        startTimers()
    }
}