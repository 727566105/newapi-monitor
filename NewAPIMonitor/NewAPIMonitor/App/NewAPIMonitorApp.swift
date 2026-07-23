import SwiftUI
import Combine

@main
struct NewAPIMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appClient = NewAPIClient.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appClient)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
                .environment(appClient)
        }

        MenuBarExtra {
            MenuBarPopoverView()
                .environment(appClient)
        } label: {
            MenuBarLabel(client: appClient)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Dynamic menu bar label that updates based on display mode and data
private struct MenuBarLabel: View {
    let client: NewAPIClient

    @State private var cycleIndex = 0

    private var cachedPeriodQuota: Int {
        client.quotaData.reduce(0) { $0 + ($1.tokenUsed ?? 0) }
    }

    private var cachedPercentage: String {
        guard let usage = client.tokenUsage else { return "--" }
        if usage.unlimitedQuota { return "∞" }
        guard usage.totalGranted > 0 else { return "--" }
        let pct = Double(usage.totalUsed) / Double(usage.totalGranted) * 100
        return String(format: "%.0f%%", pct)
    }

    private var cachedRPM: Int {
        client.currentStat?.rpm ?? 0
    }

    var body: some View {
        let mode = AppConfiguration.shared.statusBarDisplayMode
        switch mode {
        case .textOnly:
            let fmt = AppConfiguration.shared.quotaTextFormat
            let value = fmt == .abbreviated
                ? QuotaFormatter.abbreviated(cachedPeriodQuota)
                : QuotaFormatter.full(cachedPeriodQuota)
            Text("\(value) token")
        case .cycle:
            let titles = [
                "🤖 \(QuotaFormatter.abbreviated(cachedPeriodQuota)) token",
                "🤖 \(cachedPercentage)",
                "🤖 \(cachedRPM) RPM"
            ]
            Text(titles[cycleIndex % titles.count])
                .onReceive(
                    Timer.publish(every: 3, on: .main, in: .common).autoconnect()
                ) { _ in
                    cycleIndex = (cycleIndex + 1) % titles.count
                }
        }
    }
}