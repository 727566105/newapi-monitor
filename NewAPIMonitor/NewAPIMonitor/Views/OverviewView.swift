import SwiftUI

struct OverviewView: View {
    @Environment(NewAPIClient.self) private var client

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 错误提示
                if let error = client.errorMessage {
                    ErrorBanner(message: error)
                }

                // 配额卡片
                HStack(spacing: 16) {
                    QuotaCard(
                        title: "已用配额",
                        value: client.tokenUsage.map { QuotaFormatter.abbreviated($0.totalUsed) } ?? "--",
                        color: .blue
                    )
                    QuotaCard(
                        title: "剩余配额",
                        value: client.tokenUsage.map { $0.unlimitedQuota ? "∞" : QuotaFormatter.abbreviated($0.totalAvailable) } ?? "--",
                        color: .green
                    )
                    QuotaCard(
                        title: "RPM",
                        value: "\(client.currentStat?.rpm ?? 0)",
                        color: .orange
                    )
                }

                // 配额进度条
                QuotaProgressSection(tokenUsage: client.tokenUsage)

                // 最近调用
                RecentCallsSection(logs: client.recentLogs, isLoading: client.isLoadingUsage)
            }
            .padding(24)
        }
        .navigationTitle("概览")
        .task {
            await client.fetchTokenUsage()
            await client.fetchStat()
            await client.fetchRecentLogs()
        }
        .refreshable {
            await client.fetchTokenUsage()
            await client.fetchStat()
            await client.fetchRecentLogs()
        }
    }
}

// MARK: - 配额卡片

struct QuotaCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 配额进度条

struct QuotaProgressSection: View {
    let tokenUsage: TokenUsage?

    private var percentage: Double? {
        tokenUsage?.usagePercentage.map { $0 / 100.0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("配额使用进度")
                .font(.headline)

            if tokenUsage?.unlimitedQuota == true {
                HStack {
                    Image(systemName: "infinity")
                        .foregroundStyle(.green)
                    Text("无限额度")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let pct = percentage {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: pct)
                        .progressViewStyle(.linear)
                        .tint(pct > 0.9 ? .red : pct > 0.7 ? .orange : .blue)

                    HStack {
                        Spacer()
                        Text(String(format: "%.1f%%", pct * 100))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("暂无配额数据")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 最近调用

struct RecentCallsSection: View {
    let logs: [LogEntry]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近调用")
                .font(.headline)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if logs.isEmpty {
                EmptyStateView(message: "暂无调用记录")
            } else {
                Table(logs.prefix(20)) {
                    TableColumn("模型") { log in
                        Text(log.modelName ?? "-")
                            .font(.subheadline)
                    }
                    TableColumn("Token") { log in
                        Text(log.tokenName ?? "-")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    TableColumn("配额") { log in
                        Text(QuotaFormatter.abbreviated(log.quota ?? 0))
                            .font(.subheadline)
                    }
                    TableColumn("时间") { log in
                        Text(DateHelper.formatDate(log.createdAt))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .tableStyle(.inset)
                .frame(minHeight: 200)
            }
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 错误横幅

struct ErrorBanner: View {
    let message: String
    @Environment(NewAPIClient.self) private var client

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
            Spacer()
            Button {
                client.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
