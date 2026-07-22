import SwiftUI

struct SettingsView: View {
    @State private var baseURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var selectedRole: UserRole = .user
    @State private var refreshInterval: Double = 60
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var isTesting = false
    @State private var isLoggedIn = false
    @State private var showURLHint = false
    
    private enum ConnectionStatus {
        case idle, testing, success, failed(String)
    }
    
    var body: some View {
        Form {
            Section("服务器配置") {
                HStack(spacing: 4) {
                    TextField("服务器地址", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 270)

                    Button {
                        showURLHint.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showURLHint, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("输入规范")
                                .font(.headline)
                            Text("请输入完整服务器地址，须包含协议头：")
                                .font(.caption)
                            Text("格式：https://域名:端口号")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("示例：https://newapi.example.com:16666")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(width: 300)
                    }
                }
            }
            
            Section("登录") {
                LabeledContent("用户名") {
                    TextField("admin", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
                
                LabeledContent("密码") {
                    SecureField("输入密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
                
                HStack {
                    Button {
                        loginAndTest()
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isLoggedIn ? "重新登录" : "登录并测试连接")
                        }
                    }
                    .disabled(isTesting || baseURL.isEmpty || username.isEmpty || password.isEmpty)
                    
                    switch connectionStatus {
                    case .idle:
                        if isLoggedIn {
                            Label("已登录", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    case .testing:
                        Text("正在连接...")
                            .foregroundStyle(.secondary)
                    case .success:
                        Label("连接成功", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            
            Section("用户偏好") {
                LabeledContent("用户角色") {
                    Picker("", selection: $selectedRole) {
                        Text("管理员").tag(UserRole.admin)
                        Text("普通用户").tag(UserRole.user)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                
                LabeledContent("刷新间隔") {
                    HStack {
                        Slider(value: $refreshInterval, in: 30...300, step: 10) {
                            Text("刷新间隔")
                        }
                        Text("\(Int(refreshInterval))s")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                    .frame(width: 250)
                }
            }
            
            if isLoggedIn {
                Section {
                    Button("登出") {
                        logout()
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("⚙️ 设置")
        .onAppear {
            loadConfiguration()
        }
        .onChange(of: baseURL) { _, _ in saveBaseURL() }
        .onChange(of: selectedRole) { _, _ in saveRole() }
        .onChange(of: refreshInterval) { _, _ in saveRefreshInterval() }
    }
    
    private func loadConfiguration() {
        let config = AppConfiguration.shared
        baseURL = config.baseURL
        username = config.username
        selectedRole = config.role
        refreshInterval = config.refreshInterval
        isLoggedIn = !config.sessionCookie.isEmpty
    }
    
    private func saveBaseURL() {
        AppConfiguration.shared.baseURL = baseURL
    }
    
    private func saveRole() {
        AppConfiguration.shared.role = selectedRole
    }
    
    private func saveRefreshInterval() {
        AppConfiguration.shared.refreshInterval = refreshInterval
    }
    
    private func loginAndTest() {
        guard !baseURL.isEmpty, !username.isEmpty, !password.isEmpty else { return }
        
        isTesting = true
        connectionStatus = .testing
        
        // 先保存 baseURL
        AppConfiguration.shared.baseURL = baseURL
        
        Task {
            do {
                let userInfo = try await NewAPIClient.shared.login(username: username, password: password)
                connectionStatus = .success
                isLoggedIn = true
                // Auto-detect role from server response
                if (userInfo.role ?? 0) >= 10 {
                    selectedRole = .admin
                } else {
                    selectedRole = .user
                }
                AppConfiguration.shared.role = selectedRole
                AppConfiguration.shared.hasCompletedSetup = true
                // Clear password after successful login
                password = ""
            } catch {
                connectionStatus = .failed("登录失败：\(error.localizedDescription)")
                isLoggedIn = false
            }
            isTesting = false
        }
    }
    
    private func logout() {
        NewAPIClient.shared.logout()
        isLoggedIn = false
        connectionStatus = .idle
        password = ""
    }
}
