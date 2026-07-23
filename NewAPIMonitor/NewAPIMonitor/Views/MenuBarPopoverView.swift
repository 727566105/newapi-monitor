import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(NewAPIClient.self) private var client
    @Environment(\.openSettings) private var openSettings

    @State private var periodQuota: Int = 0
    @State private var periodCount: Int = 0
    @State private var isLoadingPeriod = false

    private var selectedPeriod: Binding<Period> {
        Binding(
            get: { AppConfiguration.shared.selectedPeriod },
            set: { newValue in
                AppConfiguration.shared.selectedPeriod = newValue
                NotificationCenter.default.post(name: .selectedPeriodChanged, object: nil)
            }
        )
    }

    private var periodLabel: String {
        AppConfiguration.shared.selectedPeriod.label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("🤖 NewAPI Monitor")
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Time period selector
            Picker("时间段", selection: selectedPeriod) {
                ForEach(Period.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: AppConfiguration.shared.selectedPeriod) { _, _ in
                Task { await loadPeriodData() }
            }

            // Period quota usage
            if isLoadingPeriod {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline) {
                        Text(periodLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(QuotaFormatter.full(periodQuota))
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("token")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("调用 \(periodCount) 次")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Current total quota usage
            if let usage = client.tokenUsage {
                if usage.unlimitedQuota {
                    // Unlimited quota
                    HStack {
                        Text("配额使用")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("∞ 无限额度")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                } else {
                    let used = usage.totalUsed
                    let granted = usage.totalGranted
                    let percent = granted > 0 ? Double(used) / Double(granted) : 0

                    HStack {
                        Text("配额使用")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(QuotaFormatter.percentage(used: used, granted: granted, unlimited: false))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    ProgressView(value: percent)
                        .progressViewStyle(.linear)
                        .tint(percent > 0.9 ? .red : percent > 0.7 ? .orange : .blue)
                }

                // Detail numbers
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(QuotaFormatter.abbreviated(usage.totalUsed))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    Spacer()
                    VStack(alignment: .center, spacing: 4) {
                        Text("总额")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if usage.unlimitedQuota {
                            Text("无限制")
                                .font(.caption)
                                .fontWeight(.medium)
                        } else {
                            Text(QuotaFormatter.abbreviated(usage.totalGranted))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("RPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let stat = client.currentStat {
                            Text("\(stat.rpm)")
                                .font(.caption)
                                .fontWeight(.medium)
                        } else {
                            Text("--")
                                .font(.caption)
                        }
                    }
                }
            } else if client.isLoadingUsage {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
            } else {
                Text("未连接")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Divider()

            // Error message
            if let error = client.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            // Buttons
            HStack(spacing: 12) {
                Button {
                    NSApp.activate()
                    if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                } label: {
                    Text("打开主窗口")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button {
                    NSApp.activate()
                    if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                    openSettings()
                } label: {
                    Text("设置...")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 280)
        .task {
            await loadPeriodData()
        }
    }

    // MARK: - Period Data Loading

    private func loadPeriodData() async {
        guard !AppConfiguration.shared.baseURL.isEmpty,
              AppConfiguration.shared.userId > 0 else { return }

        guard !isLoadingPeriod else { return }
        isLoadingPeriod = true
        defer { isLoadingPeriod = false }

        let (start, end) = selectedPeriod.wrappedValue.timeRange()

        let path = AppConfiguration.shared.role == .admin ? "/api/data/" : "/api/data/self"
        let queryItems = [
            URLQueryItem(name: "start_timestamp", value: "\(start)"),
            URLQueryItem(name: "end_timestamp", value: "\(end)"),
            URLQueryItem(name: "page_size", value: "1000")
        ]
        guard var components = URLComponents(string: "\(AppConfiguration.shared.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))\(path)") else { return }
        components.queryItems = queryItems
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        if AppConfiguration.shared.userId > 0 {
            request.setValue("\(AppConfiguration.shared.userId)", forHTTPHeaderField: "New-Api-User")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            struct DataResponse: Codable {
                let data: [QuotaData]?
            }
            let response = try JSONDecoder().decode(DataResponse.self, from: data)
            if let items = response.data {
                periodQuota = items.reduce(0) { $0 + ($1.tokenUsed ?? 0) }
                periodCount = items.reduce(0) { $0 + ($1.count ?? 0) }
            }
        } catch {
            // Silently fail for popover - don't show errors
            periodQuota = 0
            periodCount = 0
        }
    }
}

// Notification names (selectedPeriodChanged retained for AppDelegate Combine sink)
extension Notification.Name {
    static let selectedPeriodChanged = Notification.Name("selectedPeriodChanged")
}