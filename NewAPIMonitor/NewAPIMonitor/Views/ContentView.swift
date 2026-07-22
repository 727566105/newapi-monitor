import SwiftUI

struct ContentView: View {
    @Environment(NewAPIClient.self) private var client
    @State private var selectedPage: Page = .overview

    enum Page: String, CaseIterable, Identifiable {
        case settings = "设置"
        case overview = "概览"
        case models = "模型管理"
        case statistics = "统计"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .settings: return "gearshape"
            case .overview: return "chart.pie"
            case .models: return "cpu"
            case .statistics: return "chart.bar"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedPage) {
            ForEach(visiblePages) { page in
                Label(page.rawValue, systemImage: page.icon)
                    .tag(page)
            }
        }
        .navigationTitle("NewAPI Monitor")
        .listStyle(.sidebar)
    }

    private var visiblePages: [Page] {
        Page.allCases.filter { page in
            if page == .models && AppConfiguration.shared.role != .admin {
                return false
            }
            return true
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedPage {
        case .settings:
            SettingsView()
        case .overview:
            OverviewView()
        case .models:
            if AppConfiguration.shared.role == .admin {
                ModelsView()
            } else {
                Text("无权限访问")
                    .foregroundStyle(.secondary)
            }
        case .statistics:
            StatisticsView()
        }
    }
}

#Preview {
    ContentView()
        .environment(NewAPIClient.shared)
}
