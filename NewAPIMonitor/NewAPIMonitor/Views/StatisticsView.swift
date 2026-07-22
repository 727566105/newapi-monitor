import SwiftUI
import Charts

struct StatisticsView: View {
    @Environment(NewAPIClient.self) private var client
    
    @State private var selectedRange: Period = .realtime
    @State private var selectedModelFilter: String = "全部模型"
    @State private var quotaData: [QuotaData] = []
    @State private var isLoading = false
@State private var errorMessage: String?
    
    // MARK: - Aggregated Data
    
    private var availableModels: [String] {
        let models = Set(quotaData.compactMap { $0.modelName })
        return ["全部模型"] + models.sorted()
    }
    
    private var filteredData: [QuotaData] {
        if selectedModelFilter == "全部模型" {
            return quotaData
        }
        return quotaData.filter { $0.modelName == selectedModelFilter }
    }
    
    private var chartData: [ChartEntry] {
        switch selectedRange {
        case .realtime, .today:
            // 1天：保留小时粒度
            return filteredData.map { entry in
                ChartEntry(
                    date: Date(timeIntervalSince1970: TimeInterval(entry.createdAt)),
                    quota: entry.tokenUsed ?? 0,
                    label: DateHelper.formatTimeOnly(entry.createdAt)
                )
            }.sorted { $0.date < $1.date }
        case .sevenDays, .thirtyDays:
            // 7天/30天：按日聚合
            let daily = DateHelper.aggregateByDay(filteredData)
            return daily.map { entry in
                ChartEntry(
                    date: entry.date,
                    quota: entry.tokenUsed,
                    label: entry.dateString
                )
            }.sorted { $0.date < $1.date }
        }
    }
    
    private var detailData: [DetailEntry] {
        switch selectedRange {
        case .realtime, .today:
            return filteredData.map { entry in
                DetailEntry(
                    date: DateHelper.formatTimeOnly(entry.createdAt),
                    model: entry.modelName ?? "未知",
                    quota: entry.tokenUsed ?? 0,
                    count: entry.count ?? 0,
                    tokenUsed: entry.tokenUsed ?? 0
                )
            }
        case .sevenDays, .thirtyDays:
            let daily = DateHelper.aggregateByDay(filteredData)
            return daily.map { entry in
                DetailEntry(
                    date: entry.dateString,
                    model: "全部",
                    quota: entry.tokenUsed,
                    count: entry.count,
                    tokenUsed: entry.tokenUsed
                )
            }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with time range and model filter
            HStack {
                Text("📈 统计")
                    .font(.title2.bold())
                
                Spacer()
                
                // Time range picker
                Picker("时间段", selection: $selectedRange) {
                    ForEach(Period.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .onChange(of: selectedRange) { _, _ in
                    Task { await loadData() }
                }
                
                // Model filter
                Picker("模型", selection: $selectedModelFilter) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .frame(width: 160)
            }
            
            // Error banner
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button("重试") {
                        Task { await loadData() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            
            if isLoading && quotaData.isEmpty {
                Spacer()
                ProgressView("加载统计数据...")
                Spacer()
            } else if quotaData.isEmpty && errorMessage == nil {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("暂无统计数据")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("选择时间范围后点击刷新")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                // Chart
                chartSection
                
                Divider()
                
                // Detail table
                detailTableSection
            }
        }
        .padding()
        .task {
            await loadData()
        }
    }
    
    // MARK: - Chart Section
    
    @ViewBuilder
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("用量趋势")
                .font(.headline)
            
            if chartData.isEmpty {
                Text("所选范围内无数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(chartData) { entry in
                    BarMark(
                        x: .value("时间", entry.label),
                        y: .value("配额", entry.quota)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    
                    LineMark(
                        x: .value("时间", entry.label),
                        y: .value("配额", entry.quota)
                    )
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    
                    PointMark(
                        x: .value("时间", entry.label),
                        y: .value("配额", entry.quota)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(30)
                }
                .frame(height: 250)
                .chartYAxisLabel("配额")
            }
        }
    }
    
    // MARK: - Detail Table Section
    
    @ViewBuilder
    private var detailTableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("用量明细")
                .font(.headline)
            
            Table(detailData) {
                TableColumn("时间") { entry in
                    Text(entry.date)
                        .font(.caption)
                }
                .width(min: 80, ideal: 100)
                
                TableColumn("模型") { entry in
                    Text(entry.model)
                        .font(.caption)
                }
                .width(min: 100, ideal: 150)
                
                TableColumn("配额") { entry in
                    Text(QuotaFormatter.abbreviated(entry.quota))
                        .font(.caption)
                }
                .width(min: 60, ideal: 80)
                
                TableColumn("调用次数") { entry in
                    Text("\(entry.count)")
                        .font(.caption)
                }
                .width(min: 60, ideal: 80)
                
                TableColumn("Token 用量") { entry in
                    Text(QuotaFormatter.abbreviated(entry.tokenUsed))
                        .font(.caption)
                }
                .width(min: 80, ideal: 100)
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadData() async {
        guard !AppConfiguration.shared.baseURL.isEmpty else {
            errorMessage = "请先配置服务器地址"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let (start, end) = selectedRange.timeRange()
        await client.fetchQuotaData(startTimestamp: start, endTimestamp: end)
        quotaData = client.quotaData
        
        if let error = client.errorMessage {
            errorMessage = error
        }
        
        isLoading = false
    }
}

// MARK: - Supporting Types

private struct ChartEntry: Identifiable {
    let id = UUID()
    let date: Date
    let quota: Int
    let label: String
}

private struct DetailEntry: Identifiable {
    let id = UUID()
    let date: String
    let model: String
    let quota: Int
    let count: Int
    let tokenUsed: Int
}
