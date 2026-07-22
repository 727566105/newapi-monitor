import AppKit
import SwiftUI

/// 管理 macOS 菜单栏状态项和下拉弹窗
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        startRefreshTimer()
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
            // 刷新数据
            Task {
                await NewAPIClient.shared.fetchTokenUsage()
                await NewAPIClient.shared.fetchStat()
            }
            popover.show(relativeTo: statusItem.button!.bounds, of: statusItem.button!, preferredEdge: .minY)
        }
    }

    // MARK: - Refresh Timer

    private func startRefreshTimer() {
        let interval = AppConfiguration.shared.refreshInterval
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                await NewAPIClient.shared.fetchTokenUsage()
                self?.updateStatusBarTitle()
            }
        }
    }

    func updateStatusBarTitle() {
        let client = NewAPIClient.shared
        guard let usage = client.tokenUsage else {
            statusItem.button?.title = "🤖 --"
            return
        }

        if usage.unlimitedQuota == true {
            statusItem.button?.title = "🤖 --"
        } else {
            let granted = usage.totalGranted
            let used = usage.totalUsed
            if granted > 0 {
                let percent = Double(used) / Double(granted) * 100
                statusItem.button?.title = String(format: "🤖 %.0f%%", percent)
            } else {
                statusItem.button?.title = "🤖 --"
            }
        }
    }

    func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func restartRefreshTimer() {
        stopRefreshTimer()
        startRefreshTimer()
    }
}
