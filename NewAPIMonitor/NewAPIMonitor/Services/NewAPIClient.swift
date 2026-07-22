import Foundation

@Observable
final class NewAPIClient {

    // MARK: - Singleton
    static let shared = NewAPIClient()

    // MARK: - Configuration (reference to singleton)
    private var configuration: AppConfiguration { AppConfiguration.shared }

    // MARK: - Published State
    var userInfo: UserInfo?
    var tokenUsage: TokenUsage?
    var currentStat: Stat?
    var recentLogs: [LogEntry] = []
    var models: [APIModel] = []
    var quotaData: [QuotaData] = []

    // MARK: - Error State
    var errorMessage: String?
    var isConfigured: Bool {
        !configuration.baseURL.isEmpty && !configuration.sessionCookie.isEmpty
    }

    // MARK: - Loading State
    var isLoadingUsage = false
    var isLoadingModels = false
    var isLoadingStats = false

    // MARK: - Timer
    private var refreshTimer: Timer?

    // MARK: - URLSession
    private let session: URLSession

    // MARK: - Init
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // 让 URLSession 自动处理 cookie 存储，以便提取 session cookie
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Base URL Helper
    private var apiBase: String {
        configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        var components = URLComponents(string: "\(apiBase)\(path)")
        components?.queryItems = queryItems
        return components?.url
    }

    /// 管理API请求（使用 URLSession 自动处理 cookie + New-Api-User header）
    private func makeRequest(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 旧版 new-api 需要 New-Api-User header
        if configuration.userId > 0 {
            request.setValue("\(configuration.userId)", forHTTPHeaderField: "New-Api-User")
        }

        // Cookie 由 URLSession 的 httpCookieStorage 自动处理，无需手动设置
        // 登录时 cookie 已自动存入共享存储

        request.httpBody = body
        return request
    }

    // MARK: - Generic Request
    private func request<T: Codable>(_ type: T.Type, url: URL, method: String = "GET", body: Data? = nil) async throws -> T {
        let req = makeRequest(url: url, method: method, body: body)
        let (data, response) = try await session.data(for: req)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                let raw = String(data: data, encoding: .utf8) ?? "无法解码"
                print("[NewAPIClient] 解码失败，原始响应: \(raw.prefix(500))")
                print("[NewAPIClient] 解码错误: \(error)")

                var debugInfo = error.localizedDescription
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .dataCorrupted(let context):
                        debugInfo = "数据损坏(\(context.codingPath.map(\.stringValue).joined(separator: "."))): \(context.debugDescription)"
                    case .keyNotFound(let key, let context):
                        debugInfo = "缺少字段 '\(key.stringValue)' (\(context.codingPath.map(\.stringValue).joined(separator: ".")))"
                    case .typeMismatch(let type, let context):
                        debugInfo = "类型不匹配: 期望 \(type) (\(context.codingPath.map(\.stringValue).joined(separator: ".")))"
                    case .valueNotFound(let type, let context):
                        debugInfo = "值为空: 期望 \(type) (\(context.codingPath.map(\.stringValue).joined(separator: ".")))"
                    @unknown default:
                        break
                    }
                }
                let preview = raw.prefix(300)
                throw APIError.decodingError("\(debugInfo)\n响应: \(preview)")
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode)
        default:
            throw APIError.unexpectedStatus(httpResponse.statusCode)
        }
    }

    // MARK: - API: Login
    func login(username: String, password: String) async throws -> UserInfo {
        guard !configuration.baseURL.isEmpty else { throw APIError.invalidResponse }
        guard let url = makeURL(path: "/api/user/login") else { throw APIError.invalidResponse }

        let body = try JSONEncoder().encode(["username": username, "password": password])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.serverError(httpResponse.statusCode)
        }

        // 解析登录响应
        struct LoginResponse: Codable {
            let success: Bool
            let message: String?
            let data: UserInfo?
        }

        let loginResp: LoginResponse
        do {
            loginResp = try JSONDecoder().decode(LoginResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "无法解码"
            throw APIError.decodingError("无法解析登录响应：\(raw)")
        }

        guard loginResp.success else {
            throw APIError.decodingError(loginResp.message ?? "登录失败")
        }

        guard let user = loginResp.data else {
            let raw = String(data: data, encoding: .utf8) ?? "无法解码"
            throw APIError.decodingError("登录响应中无用户数据：\(raw)")
        }

        // 提取 session cookie — 尝试多种方式
        // 方式1: 从 HTTP 响应头提取
        if let setCookieHeader = httpResponse.allHeaderFields["Set-Cookie"] as? String {
            if let sessionPart = setCookieHeader.split(separator: ";").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("session=") }) {
                let cookieValue = sessionPart.trimmingCharacters(in: .whitespaces)
                AppConfiguration.shared.sessionCookie = String(cookieValue)
            }
        }

        // 方式2: 从 URLSession 的 cookie 存储中提取
        if AppConfiguration.shared.sessionCookie.isEmpty {
            if let cookies = session.configuration.httpCookieStorage?.cookies(for: url) {
                if let sessionCookie = cookies.first(where: { $0.name == "session" }) {
                    AppConfiguration.shared.sessionCookie = "session=\(sessionCookie.value)"
                }
            }
        }

        // 方式3: 如果还是没有，手动从响应头字段遍历
        if AppConfiguration.shared.sessionCookie.isEmpty {
            for (key, value) in httpResponse.allHeaderFields {
                if key.description.lowercased() == "set-cookie" {
                    let headerValue = "\(value)"
                    if let sessionPart = headerValue.split(separator: ";").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("session=") }) {
                        let cookieValue = sessionPart.trimmingCharacters(in: .whitespaces)
                        AppConfiguration.shared.sessionCookie = String(cookieValue)
                        break
                    }
                }
            }
        }

        // 保存用户信息
        self.userInfo = user
        AppConfiguration.shared.username = username
        AppConfiguration.shared.userId = user.id ?? 0

        // 自动检测角色
        if (user.role ?? 0) >= 10 {
            AppConfiguration.shared.role = .admin
        } else {
            AppConfiguration.shared.role = .user
        }

        // 从用户信息构建 TokenUsage
        updateTokenUsageFromUserInfo(user)

        return user
    }

    // MARK: - API: User Info (Role Detection)
    @discardableResult
    func fetchUserInfo() async throws -> UserInfo {
        guard isConfigured else { throw APIError.unauthorized }
        guard let url = makeURL(path: "/api/user/self") else { throw APIError.invalidResponse }

        do {
            let response: APIResponse<UserInfo> = try await request(APIResponse<UserInfo>.self, url: url)
            if let user = response.data {
                self.userInfo = user
                // 自动检测角色
                if (user.role ?? 0) >= 10 {
                    AppConfiguration.shared.role = .admin
                } else {
                    AppConfiguration.shared.role = .user
                }
                // 更新配额信息
                updateTokenUsageFromUserInfo(user)
                return user
            } else {
                throw APIError.decodingError("用户数据为空")
            }
        } catch APIError.forbidden {
            // 非 Admin，降级为 User
            AppConfiguration.shared.role = .user
            throw APIError.forbidden
        } catch {
            self.errorMessage = "获取用户信息失败：\(error.localizedDescription)"
            throw error
        }
    }

    /// 从 UserInfo 构建 TokenUsage（因为 /api/usage/token/ 需要 sk- token）
    private func updateTokenUsageFromUserInfo(_ user: UserInfo) {
        let quota = user.quota ?? 0
        let usedQuota = user.usedQuota ?? 0

        self.tokenUsage = TokenUsage(
            totalGranted: quota,
            totalUsed: usedQuota
        )
    }

    // MARK: - API: Token Usage
    // 使用 /api/user/self 获取配额信息，而不是 /api/usage/token/（后者需要 sk- token）
    func fetchTokenUsage() async {
        guard isConfigured else { return }
        isLoadingUsage = true
        defer { isLoadingUsage = false }

        do {
            let user = try await fetchUserInfo()
            updateTokenUsageFromUserInfo(user)
            self.errorMessage = nil
        } catch {
            self.errorMessage = "获取配额信息失败：\(error.localizedDescription)"
        }
    }

    // MARK: - API: Stat
    func fetchStat() async {
        guard isConfigured else { return }

        let path = configuration.role == .admin ? "/api/log/stat" : "/api/log/self/stat"
        guard let url = makeURL(path: path) else { return }

        do {
            let response: APIResponse<Stat> = try await request(APIResponse<Stat>.self, url: url)
            self.currentStat = response.data
        } catch {
            self.errorMessage = "获取统计信息失败：\(error.localizedDescription)"
        }
    }

    // MARK: - API: Recent Logs
    func fetchRecentLogs(page: Int = 1, pageSize: Int = 20) async {
        guard isConfigured else { return }

        let path = configuration.role == .admin ? "/api/log/" : "/api/log/self"
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ]
        guard let url = makeURL(path: path, queryItems: queryItems) else { return }

        do {
            let response: PaginatedResponse<LogEntry> = try await request(PaginatedResponse<LogEntry>.self, url: url)
            self.recentLogs = response.items
        } catch {
            self.errorMessage = "获取日志失败：\(error.localizedDescription)"
        }
    }

    // MARK: - API: Models
    func fetchModels(status: String = "all") async {
        guard isConfigured else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }

        let queryItems = [
            URLQueryItem(name: "status", value: status),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: "100")
        ]
        guard let url = makeURL(path: "/api/models/", queryItems: queryItems) else { return }

        do {
            let response: PaginatedResponse<APIModel> = try await request(PaginatedResponse<APIModel>.self, url: url)
            self.models = response.items
        } catch {
            self.errorMessage = "获取模型列表失败：\(error.localizedDescription)"
        }
    }

    func searchModels(keyword: String, status: String = "all") async {
        guard isConfigured else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }

        let queryItems = [
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "status", value: status)
        ]
        guard let url = makeURL(path: "/api/models/search", queryItems: queryItems) else { return }

        do {
            let response: PaginatedResponse<APIModel> = try await request(PaginatedResponse<APIModel>.self, url: url)
            self.models = response.items
        } catch {
            self.errorMessage = "搜索模型失败：\(error.localizedDescription)"
        }
    }

    // MARK: - API: Toggle Model Status
    func toggleModelStatus(_ model: APIModel) async {
        guard isConfigured else { return }

        let newStatus = model.status == 1 ? 0 : 1

        // 乐观更新
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            models[index].status = newStatus
        }

        guard let url = makeURL(path: "/api/models/?status_only=true") else { return }

        do {
            let body = try JSONEncoder().encode(["id": model.id, "status": newStatus])
            let response: APIResponse<EmptyData> = try await request(APIResponse<EmptyData>.self, url: url, method: "PUT", body: body)
            if response.success != true {
                // 回滚
                if let index = models.firstIndex(where: { $0.id == model.id }) {
                    models[index].status = model.status
                }
                self.errorMessage = "模型状态切换失败：\(response.message ?? "未知错误")"
            }
        } catch {
            // 回滚
            if let index = models.firstIndex(where: { $0.id == model.id }) {
                models[index].status = model.status
            }
            self.errorMessage = "模型状态切换失败：\(error.localizedDescription)"
        }
    }

    // MARK: - API: Quota Data (Hourly)
    func fetchQuotaData(startTimestamp: Int64, endTimestamp: Int64) async {
        guard isConfigured else { return }
        isLoadingStats = true
        defer { isLoadingStats = false }

        let path = configuration.role == .admin ? "/api/data/" : "/api/data/self"
        let queryItems = [
            URLQueryItem(name: "start_timestamp", value: "\(startTimestamp)"),
            URLQueryItem(name: "end_timestamp", value: "\(endTimestamp)")
        ]
        guard let url = makeURL(path: path, queryItems: queryItems) else { return }

        do {
            let response: APIResponse<[QuotaData]> = try await request(APIResponse<[QuotaData]>.self, url: url)
            self.quotaData = response.data ?? []
        } catch {
            self.errorMessage = "获取统计数据失败：\(error.localizedDescription)"
        }
    }

    // MARK: - API: Test Connection
    func testConnection() async -> Bool {
        guard let url = makeURL(path: "/api/user/self") else { return false }

        do {
            let _: APIResponse<UserInfo> = try await request(APIResponse<UserInfo>.self, url: url)
            return true
        } catch {
            self.errorMessage = "连接测试失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Logout
    func logout() {
        AppConfiguration.shared.sessionCookie = ""
        AppConfiguration.shared.username = ""
        AppConfiguration.shared.userId = 0
        AppConfiguration.shared.hasCompletedSetup = false
        self.userInfo = nil
        self.tokenUsage = nil
        self.currentStat = nil
        self.recentLogs = []
        self.models = []
        self.quotaData = []
        self.errorMessage = nil
        stopRefreshTimer()
    }

    // MARK: - Refresh All
    func refreshAll() async {
        guard isConfigured else { return }

        async let _ = fetchTokenUsage()
        async let _ = fetchStat()
        async let _ = fetchRecentLogs()
    }

    // MARK: - Timer Management
    func startRefreshTimer() {
        stopRefreshTimer()
        let interval = configuration.refreshInterval
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.fetchTokenUsage()
                await self.fetchStat()
            }
        }
    }

    func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Usage Percentage
    var usagePercentage: String {
        tokenUsage?.usagePercentageString ?? "--"
    }

    var usagePercentageValue: Double? {
        guard let pct = tokenUsage?.usagePercentage else { return nil }
        return pct / 100.0
    }
}

// MARK: - Error Types
enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case serverError(Int)
    case unexpectedStatus(Int)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无效的响应"
        case .unauthorized: return "认证失败，请检查用户名和密码"
        case .forbidden: return "无权限访问"
        case .notFound: return "资源不存在"
        case .serverError(let code): return "服务器错误 (\(code))"
        case .unexpectedStatus(let code): return "未知错误 (\(code))"
        case .decodingError(let msg): return "数据解析失败：\(msg)"
        }
    }
}

// MARK: - Empty Data Helper
private struct EmptyData: Codable {}
