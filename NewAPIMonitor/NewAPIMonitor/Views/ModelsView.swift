import SwiftUI

struct ModelsView: View {
    @Environment(NewAPIClient.self) private var client
    
    @State private var searchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var statusFilter: ModelStatusFilter = .all
    @State private var toastMessage: String?
    @State private var showToast = false
    
    enum ModelStatusFilter: String, CaseIterable {
        case all = "全部"
        case enabled = "已启用"
        case disabled = "已禁用"
        
        var apiValue: String {
            switch self {
            case .all: return "all"
            case .enabled: return "enabled"
            case .disabled: return "disabled"
            }
        }
    }
    
    var filteredModels: [APIModel] {
        let models = client.models
        switch statusFilter {
        case .all: return models
        case .enabled: return models.filter { $0.status == 1 }
        case .disabled: return models.filter { $0.status == 0 }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索模型...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit { Task { await performSearch() } }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .frame(maxWidth: 300)
                
                Spacer()
                
                // Status filter
                Picker("状态", selection: $statusFilter) {
                    ForEach(ModelStatusFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                // Refresh
                Button {
                    Task { await client.fetchModels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding()
            
            Divider()
            
            // Error banner
            if let error = client.errorMessage {
                ErrorBanner(message: error)
            }
            
            // Loading
            if client.isLoadingModels && client.models.isEmpty {
                Spacer()
                ProgressView("加载模型列表...")
                Spacer()
            } else if filteredModels.isEmpty {
                Spacer()
                emptyStateView
                Spacer()
            } else {
                // Model list
                List(filteredModels) { model in
                    ModelRow(model: model) { toggledModel in
                        await toggleModelStatus(toggledModel)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("🤖 模型管理")
        .task {
            if client.models.isEmpty {
                await client.fetchModels()
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await performSearch()
            }
        }
        .overlay {
            if showToast, let message = toastMessage {
                ToastView(message: message, isShowing: $showToast)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube.box")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暂无模型数据")
                .font(.headline)
                .foregroundStyle(.secondary)
            if searchText.isEmpty && statusFilter == .all {
                Text("请确认后端已配置模型")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    private func performSearch() async {
        if searchText.isEmpty {
            await client.fetchModels()
        } else {
            await client.searchModels(keyword: searchText)
        }
    }
    
    private func toggleModelStatus(_ model: APIModel) async {
        let previousError = client.errorMessage
        let newStatus = model.status == 1 ? 0 : 1
        
        // toggleModelStatus handles optimistic update + rollback internally
        await client.toggleModelStatus(model)
        
        // Check if the toggle succeeded by comparing error state
        if client.errorMessage != nil && client.errorMessage != previousError {
            toastMessage = "切换失败：\(client.errorMessage ?? "未知错误")"
        } else {
            toastMessage = newStatus == 1 ? "\(model.modelName) 已启用" : "\(model.modelName) 已禁用"
        }
        
        showToast = true
        // Auto-dismiss toast
        Task {
            try? await Task.sleep(for: .seconds(2))
            showToast = false
        }
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: APIModel
    let onToggle: (APIModel) async -> Void
    
    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(model.status == 1 ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            
            // Model info
            VStack(alignment: .leading, spacing: 2) {
                Text(model.modelName)
                    .font(.body)
                    .fontWeight(.medium)
                if let desc = model.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Tags (API returns a comma-separated string like "glm" or "glm,chat")
            if let tags = model.tags, !tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(tags.split(separator: ",").map(String.init).prefix(3), id: \.self) { tag in
                        Text(tag.trimmingCharacters(in: .whitespaces))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            
            // Toggle
            Toggle("", isOn: Binding(
                get: { model.status == 1 },
                set: { _ in Task { await onToggle(model) } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String
    @Binding var isShowing: Bool
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: message.contains("失败") ? "exclamationmark.triangle" : "checkmark.circle")
                Text(message)
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .cornerRadius(10)
            .shadow(radius: 4)
            .padding(.bottom, 20)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: isShowing)
    }
}
