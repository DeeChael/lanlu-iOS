import Foundation

actor AsyncSemaphore {
    private enum WaiterState {
        case pending(CheckedContinuation<Void, Never>)
        case cancelled
    }

    private var count: Int
    private var waiters: [UUID: WaiterState] = [:]
    private var order: [UUID] = []

    init(limit: Int) { count = limit }

    func wait() async {
        if count > 0 { count -= 1; return }
        let id = UUID()
        order.append(id)
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                if case .cancelled = waiters[id] {
                    c.resume()
                } else {
                    waiters[id] = .pending(c)
                }
            }
        } onCancel: {
            Task { await cancelWaiter(id: id) }
        }
    }

    private func cancelWaiter(id: UUID) {
        switch waiters[id] {
        case .pending(let c):
            waiters.removeValue(forKey: id)
            order.removeAll { $0 == id }
            c.resume()
        case .cancelled, .none:
            waiters[id] = .cancelled
        }
    }

    func signal() {
        while let id = order.first {
            order.removeFirst()
            switch waiters.removeValue(forKey: id) {
            case .pending(let c):
                c.resume()
                return
            case .cancelled, .none:
                continue
            }
        }
        count += 1
    }
}

// MARK: - API Models

struct ApiEnvelope<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
}

struct LoginSuccessData: Decodable {
    let user: UserData
    let token: TokenData
}

struct TotpRequiredData: Decodable {
    let requiresTotp: Bool
    let challengeId: String
    let methods: [String]
}

struct UserData: Decodable {
    let id: Int
    let username: String
    let isAdmin: Bool
    let avatarAssetId: Int?
}

struct TokenData: Decodable {
    let id: Int
    let name: String
    let token: String?
    let prefix: String?
}

struct UserInfoData: Decodable {
    let user: UserData
}

struct TOTPStatusData: Decodable {
    let enabled: Bool
    let recoveryCodesRemaining: Int
    let credentialName: String?
}

enum PasswordChangeResult {
    case changed
    case requiresStepUp
}

struct UserStatsData: Codable {
    let favoriteCount: Int?
    let readCount: Int?
    let totalPagesRead: Int?
    let totalArchives: Int?
}

struct TrendPoint: Codable {
    let date: String
    let count: Int

    var dateValue: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }
}

// MARK: - Search / Archive

    struct ArchiveAsset: Codable, Hashable, Sendable {
    let cover: Int?
}

    struct SearchResultItem: Codable, Hashable, Sendable {
        let type: String?
        let arcid: String?
        let tankoubonId: String?
        let archivetype: String?
        let filename: String?
        let title: String?
        let description: String?
        let summary: String?
        let pagecount: Int?
        let archiveCount: Int?
        var progress: Int?
        let size: Int?
        let tags: String?
        let isnew: Bool?
        let isfavorite: Bool?
        let favoritetime: Int?
        let lastreadtime: Int?
        let assets: ArchiveAsset?
        let children: [String]?
        let releaseAt: String?
        let createdAt: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case type, arcid, archivetype, filename, title, description, summary, children
            case pagecount, progress, size, tags, isnew, isfavorite, assets
            case favoritetime, lastreadtime
            case tankoubonId = "tankoubon_id"
            case archiveCount = "archive_count"
            case releaseAt = "release_at"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try? c.decode(String.self, forKey: .type)
            arcid = try? c.decode(String.self, forKey: .arcid)
            tankoubonId = try? c.decode(String.self, forKey: .tankoubonId)
            archivetype = try? c.decode(String.self, forKey: .archivetype)
            filename = try? c.decode(String.self, forKey: .filename)
            title = try? c.decode(String.self, forKey: .title)
            description = try? c.decode(String.self, forKey: .description)
            summary = try? c.decode(String.self, forKey: .summary)
            pagecount = Self.decodeInt(from: c, forKey: .pagecount)
            archiveCount = Self.decodeInt(from: c, forKey: .archiveCount)
            progress = Self.decodeInt(from: c, forKey: .progress)
            size = Self.decodeInt(from: c, forKey: .size)
            tags = try? c.decode(String.self, forKey: .tags)
            isnew = try? c.decode(Bool.self, forKey: .isnew)
            isfavorite = try? c.decode(Bool.self, forKey: .isfavorite)
            favoritetime = Self.decodeInt(from: c, forKey: .favoritetime)
            lastreadtime = Self.decodeInt(from: c, forKey: .lastreadtime)
            assets = try? c.decode(ArchiveAsset.self, forKey: .assets)
            children = try? c.decode([String].self, forKey: .children)
            releaseAt = try? c.decode(String.self, forKey: .releaseAt)
            createdAt = try? c.decode(String.self, forKey: .createdAt)
            updatedAt = try? c.decode(String.self, forKey: .updatedAt)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try? c.encode(type, forKey: .type)
            try? c.encode(arcid, forKey: .arcid)
            try? c.encode(tankoubonId, forKey: .tankoubonId)
            try? c.encode(archivetype, forKey: .archivetype)
            try? c.encode(filename, forKey: .filename)
            try? c.encode(title, forKey: .title)
            try? c.encode(description, forKey: .description)
            try? c.encode(summary, forKey: .summary)
            try? c.encode(pagecount, forKey: .pagecount)
            try? c.encode(archiveCount, forKey: .archiveCount)
            try? c.encode(progress, forKey: .progress)
            try? c.encode(size, forKey: .size)
            try? c.encode(tags, forKey: .tags)
            try? c.encode(isnew, forKey: .isnew)
            try? c.encode(isfavorite, forKey: .isfavorite)
            try? c.encode(favoritetime, forKey: .favoritetime)
            try? c.encode(lastreadtime, forKey: .lastreadtime)
            try? c.encode(assets, forKey: .assets)
            try? c.encode(children, forKey: .children)
            try? c.encode(releaseAt, forKey: .releaseAt)
            try? c.encode(createdAt, forKey: .createdAt)
            try? c.encode(updatedAt, forKey: .updatedAt)
        }

        init(
            type: String? = nil,
            arcid: String? = nil,
            tankoubonId: String? = nil,
            archivetype: String? = nil,
            filename: String? = nil,
            title: String? = nil,
            description: String? = nil,
            summary: String? = nil,
            pagecount: Int? = nil,
            archiveCount: Int? = nil,
            progress: Int? = nil,
            size: Int? = nil,
            tags: String? = nil,
            isnew: Bool? = nil,
            isfavorite: Bool? = nil,
            favoritetime: Int? = nil,
            lastreadtime: Int? = nil,
            assets: ArchiveAsset? = nil,
            children: [String]? = nil,
            releaseAt: String? = nil,
            createdAt: String? = nil,
            updatedAt: String? = nil
        ) {
            self.type = type
            self.arcid = arcid
            self.tankoubonId = tankoubonId
            self.archivetype = archivetype
            self.filename = filename
            self.title = title
            self.description = description
            self.summary = summary
            self.pagecount = pagecount
            self.archiveCount = archiveCount
            self.progress = progress
            self.size = size
            self.tags = tags
            self.isnew = isnew
            self.isfavorite = isfavorite
            self.favoritetime = favoritetime
            self.lastreadtime = lastreadtime
            self.assets = assets
            self.children = children
            self.releaseAt = releaseAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        private static func decodeInt(from container: KeyedDecodingContainer<SearchResultItem.CodingKeys>, forKey key: SearchResultItem.CodingKeys) -> Int? {
            if let int = try? container.decode(Int.self, forKey: key) { return int }
            if let str = try? container.decode(String.self, forKey: key), let int = Int(str) { return int }
            return nil
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(arcid)
            hasher.combine(tankoubonId)
        }

        static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
            lhs.arcid == rhs.arcid && lhs.tankoubonId == rhs.tankoubonId
        }

        var displayId: String { arcid ?? tankoubonId ?? UUID().uuidString }
    }

struct SearchResponse: Decodable {
    let data: [SearchResultItem]?
    let recordsTotal: Int?
    let recordsFiltered: Int?
    let page: Int?
    let pageSize: Int?
}

struct AutocompleteSuggestion: Decodable {
    let value: String
    let label: String
    let display: String?
}

struct UserTrendData: Codable {
    let trend: [TrendPoint]
    let mostActiveDate: String?
    let activeDays: Int?
    let maxCount: Int?

    init(trend: [TrendPoint]) {
        self.trend = trend
        self.activeDays = trend.filter { $0.count > 0 }.count
        let maxPoint = trend.max(by: { $0.count < $1.count })
        if let mp = maxPoint, mp.count > 0 {
            mostActiveDate = mp.date
            maxCount = mp.count
        } else {
            mostActiveDate = nil
            maxCount = 0
        }
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError, Equatable {
    case totpRequired(challengeId: String, methods: [String])
    case invalidCredentials
    case tokenExpired
    case networkError(String)
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .totpRequired: return "totp_required"
        case .invalidCredentials: return String(localized: "invalid_credentials")
        case .tokenExpired: return String(localized: "token_expired")
        case .networkError(let msg): return msg
        case .invalidCode: return String(localized: "invalid_code")
        }
    }
}

// MARK: - APIClient

class APIClient {
    let baseURL: String
    var token: String?

    init(baseURL: String, token: String? = nil) {
        self.baseURL = baseURL
        self.token = token
    }

    // MARK: - Auth: Password Login

    func login(username: String, password: String) async throws -> LoginSuccessData {
        LogManager.shared.log("POST /api/auth/login (user: \(username))")
        let url = try makeURL("/api/auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "username": username,
            "password": password,
            "tokenName": "lanlu-ios"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        switch httpResponse.statusCode {
        case 200:
            let envelope = try JSONDecoder().decode(ApiEnvelope<LoginSuccessData>.self, from: data)
            guard let loginData = envelope.data else {
                LogManager.shared.log("Login failed: empty data")
                throw AuthError.invalidCredentials
            }
            self.token = loginData.token.token
            LogManager.shared.log("Login success (user: \(loginData.user.username))")
            return loginData

        case 202:
            let envelope = try JSONDecoder().decode(ApiEnvelope<TotpRequiredData>.self, from: data)
            guard let totpData = envelope.data else {
                throw AuthError.networkError(String(localized: "connection_failed"))
            }
            LogManager.shared.log("Login requires TOTP")
            throw AuthError.totpRequired(challengeId: totpData.challengeId, methods: totpData.methods)

        case 401:
            LogManager.shared.log("Login failed: invalid credentials")
            throw AuthError.invalidCredentials

        default:
            LogManager.shared.log("Login failed: HTTP \(httpResponse.statusCode)")
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
    }

    // MARK: - Auth: TOTP Verify

    func verifyTOTP(challengeId: String, code: String) async throws -> LoginSuccessData {
        LogManager.shared.log("POST /api/auth/login/totp/verify")
        let url = try makeURL("/api/auth/login/totp/verify")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "challengeId": challengeId,
            "code": code
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        switch httpResponse.statusCode {
        case 200:
            let envelope = try JSONDecoder().decode(ApiEnvelope<LoginSuccessData>.self, from: data)
            guard let loginData = envelope.data else {
                throw AuthError.invalidCode
            }
            self.token = loginData.token.token
            return loginData

        case 401:
            throw AuthError.invalidCode

        default:
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
    }

    // MARK: - Auth: Verify Token (me)

    func verifyToken() async throws -> UserData {
        LogManager.shared.log("GET /api/auth/me")
        let url = try makeURL("/api/auth/me")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        switch httpResponse.statusCode {
        case 200:
            let envelope = try JSONDecoder().decode(ApiEnvelope<UserInfoData>.self, from: data)
            guard let userInfo = envelope.data else {
                LogManager.shared.log("Token verify: empty data")
                throw AuthError.invalidCredentials
            }
            LogManager.shared.log("Token valid (user: \(userInfo.user.username))")
            return userInfo.user

        case 401:
            LogManager.shared.log("Token expired")
            throw AuthError.tokenExpired

        default:
            LogManager.shared.log("Token verify failed: HTTP \(httpResponse.statusCode)")
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
    }

    // MARK: - Account Security

    func changeUsername(_ username: String) async throws -> UserData {
        LogManager.shared.log("POST /api/auth/username")
        let url = try makeURL("/api/auth/username")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["newUsername": username])
        applyAuthHeader(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        guard httpResponse.statusCode == 200 else {
            throw AuthError.networkError(apiMessage(from: data))
        }

        let envelope = try JSONDecoder().decode(ApiEnvelope<UserInfoData>.self, from: data)
        guard let user = envelope.data?.user else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        return user
    }

    func changePassword(currentPassword: String, newPassword: String) async throws -> PasswordChangeResult {
        LogManager.shared.log("POST /api/auth/password")
        let url = try makeURL("/api/auth/password")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "currentPassword": currentPassword,
            "newPassword": newPassword
        ])
        applyAuthHeader(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        switch httpResponse.statusCode {
        case 200:
            return .changed
        case 428:
            return .requiresStepUp
        default:
            throw AuthError.networkError(apiMessage(from: data))
        }
    }

    func verifyStepUpPassword(_ password: String) async throws {
        try await verifyStepUp(path: "/api/auth/step-up/password", body: ["password": password])
    }

    func verifyStepUpTOTP(_ code: String) async throws {
        try await verifyStepUp(path: "/api/auth/step-up/totp", body: ["code": code])
    }

    func fetchTOTPStatus() async throws -> TOTPStatusData {
        LogManager.shared.log("GET /api/auth/totp/status")
        let url = try makeURL("/api/auth/totp/status")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        guard httpResponse.statusCode == 200 else {
            throw AuthError.networkError(apiMessage(from: data))
        }

        let envelope = try JSONDecoder().decode(ApiEnvelope<TOTPStatusData>.self, from: data)
        guard let status = envelope.data else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        return status
    }

    private func verifyStepUp(path: String, body: [String: String]) async throws {
        LogManager.shared.log("POST \(path)")
        let url = try makeURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        applyAuthHeader(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        guard httpResponse.statusCode == 200 else {
            throw AuthError.networkError(apiMessage(from: data))
        }
    }

    // MARK: - User Stats

    func fetchStats() async throws -> UserStatsData {
        LogManager.shared.log("GET /api/user/stats")
        let url = try makeURL("/api/user/stats")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        print("[API] /api/user/stats status: \(httpResponse.statusCode)")
        print("[API] /api/user/stats body: \(String(data: data, encoding: .utf8) ?? "nil")")

        guard httpResponse.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        if let envelope = try? JSONDecoder().decode(ApiEnvelope<UserStatsData>.self, from: data),
           let stats = envelope.data {
            return stats
        }
        if let stats = try? JSONDecoder().decode(UserStatsData.self, from: data) {
            return stats
        }
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let inner = (raw["data"] as? [String: Any]) ?? raw
            return UserStatsData(
                favoriteCount: inner["favoriteCount"] as? Int,
                readCount: inner["readCount"] as? Int,
                totalPagesRead: inner["totalPagesRead"] as? Int ?? inner["total_pages_read"] as? Int,
                totalArchives: inner["totalArchives"] as? Int ?? inner["total_archives"] as? Int
            )
        }
        throw AuthError.networkError(String(localized: "connection_failed"))
    }

    func fetchTrend(days: Int = 30) async throws -> UserTrendData {
        LogManager.shared.log("GET /api/user/trend?days=\(days)")

        var urlString = baseURL
        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }

        guard var baseComponents = URLComponents(string: urlString) else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }

        baseComponents.path = (baseComponents.path.hasSuffix("/") ? "" : "/") + "api/user/trend"
        baseComponents.queryItems = [URLQueryItem(name: "days", value: "\(days)")]

        guard let url = baseComponents.url else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        print("[API] /api/user/trend status: \(httpResponse.statusCode)")
        print("[API] /api/user/trend body: \(String(data: data, encoding: .utf8) ?? "nil")")

        guard httpResponse.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        if let envelope = try? JSONDecoder().decode(ApiEnvelope<[TrendPoint]>.self, from: data),
           let points = envelope.data {
            return UserTrendData(trend: points)
        }
        if let points = try? JSONDecoder().decode([TrendPoint].self, from: data) {
            return UserTrendData(trend: points)
        }
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let arr = raw["data"] as? [[String: Any]] {
                let points = arr.compactMap { item -> TrendPoint? in
                    guard let date = item["date"] as? String, let count = item["count"] as? Int else {
                        return nil
                    }
                    return TrendPoint(date: date, count: count)
                }
                return UserTrendData(trend: points)
            }
        }
        throw AuthError.networkError(String(localized: "connection_failed"))
    }

    // MARK: - Search

    func search(favoriteOnly: Bool = false, untaggedOnly: Bool = false, groupbyTanks: Bool = false, filter: String? = nil, tags: String? = nil, sortby: String = "created_at", order: String = "desc", dateFrom: String? = nil, dateTo: String? = nil, page: Int = 1, pageSize: Int = 20) async throws -> SearchResponse {
        var urlString = baseURL
        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }

        guard var baseComponents = URLComponents(string: urlString) else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }

        baseComponents.path = (baseComponents.path.hasSuffix("/") ? "" : "/") + "api/search"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            URLQueryItem(name: "sortby", value: sortby),
            URLQueryItem(name: "order", value: order),
        ]
        if favoriteOnly {
            items.append(URLQueryItem(name: "favoriteonly", value: "true"))
        }
        if untaggedOnly {
            items.append(URLQueryItem(name: "untaggedonly", value: "true"))
        }
        if groupbyTanks {
            items.append(URLQueryItem(name: "groupby_tanks", value: "true"))
        }
        if let filter, !filter.isEmpty {
            items.append(URLQueryItem(name: "filter", value: filter))
        }
        if let tags, !tags.isEmpty {
            items.append(URLQueryItem(name: "tags", value: tags))
        }
        if let dateFrom, !dateFrom.isEmpty {
            items.append(URLQueryItem(name: "date_from", value: dateFrom))
        }
        if let dateTo, !dateTo.isEmpty {
            items.append(URLQueryItem(name: "date_to", value: dateTo))
        }
        baseComponents.queryItems = items

        guard let url = baseComponents.url else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)

        LogManager.shared.log("GET /api/search page=\(page) pageSize=\(pageSize) sortby=\(sortby)")

        let (data, response) = try await URLSession.shared.data(for: request)
        let bodyStr = String(data: data, encoding: .utf8) ?? "nil"
        print("[API] /api/search status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        print("[API] /api/search body: \(bodyStr.prefix(500))")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        if httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(SearchResponse.self, from: data)
        }
        throw AuthError.networkError(String(localized: "connection_failed"))
    }

    func fetchHistory(page: Int = 1, pageSize: Int = 40) async throws -> SearchResponse {
        try await search(favoriteOnly: false, sortby: "lastread", order: "desc", page: page, pageSize: pageSize)
    }

    // MARK: - Autocomplete

    func autocomplete(query: String, limit: Int = 10) async throws -> [AutocompleteSuggestion] {
        var urlString = baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard var baseComponents = URLComponents(string: urlString) else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        baseComponents.path = (baseComponents.path.hasSuffix("/") ? "" : "/") + "api/tags/autocomplete"
        baseComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        guard let url = baseComponents.url else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        struct AutoCompleteEnvelope: Decodable { let suggestions: [AutocompleteSuggestion]? }
        struct AutoCompleteResponse: Decodable { let data: AutoCompleteEnvelope? }

        if let wrapper = try? JSONDecoder().decode(AutoCompleteResponse.self, from: data),
           let list = wrapper.data?.suggestions {
            return list
        }
        if let wrapper = try? JSONDecoder().decode(AutoCompleteEnvelope.self, from: data),
           let list = wrapper.suggestions {
            return list
        }
        return []
    }

    // MARK: - Categories

    struct TagTranslationData: Decodable {
        let lang: String
        let map: [String: String]
    }

    func fetchTagTranslations(arcid: String? = nil, tankoubonId: String? = nil) async throws -> [String: String] {
        var urlString = baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard var components = URLComponents(string: urlString) else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        components.path = (components.path.hasSuffix("/") ? "" : "/") + "api/tags/translations"
        var queryItems: [URLQueryItem] = []
        if let arcid { queryItems.append(URLQueryItem(name: "arcid", value: arcid)) }
        if let tankoubonId { queryItems.append(URLQueryItem(name: "tankoubon_id", value: tankoubonId)) }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        let envelope = try JSONDecoder().decode(ApiEnvelope<TagTranslationData>.self, from: data)
        return envelope.data?.map ?? [:]
    }

    struct CategoryItem: Codable, Sendable {
        let id: Int
        let catid: String
        let name: String
        let scanPath: String?
        let description: String?
        let icon: String?
        let sortOrder: Int?
        let enabled: Bool?
        let plugins: [String]?
        let coverAssetId: Int?
        let archiveCount: Int?
        let createdAt: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, catid, name, icon, enabled, plugins, description
            case scanPath = "scan_path"
            case sortOrder = "sort_order"
            case coverAssetId = "cover_asset_id"
            case archiveCount = "archive_count"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    struct CategoriesResponse: Decodable {
        let operation: String?
        let success: Int?
        let data: [CategoryItem]?
    }

    func fetchCategories() async throws -> [CategoryItem] {
        let url = try makeURL("/api/categories")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        if let result = try? JSONDecoder().decode(CategoriesResponse.self, from: data),
           let items = result.data {
            return items
        }
        if let result = try? JSONDecoder().decode(ApiEnvelope<[CategoryItem]>.self, from: data),
           let items = result.data {
            return items
        }
        return []
    }

    // MARK: - Archive Metadata

    struct ArchiveMetadataAsset: Codable {
        let key: String?
        let value: Int?
    }

    struct ArchiveMetadata: Codable {
        let arcid: String?
        let title: String?
        let description: String?
        let tags: [String]?
        let assets: [ArchiveMetadataAsset]?
        let pagecount: Int?
        var progress: Int?
        let filename: String?
        let fileSize: Int?
        let archivetype: String?
        let isnew: Bool?
        var isfavorite: Bool?
        let thumbnailHash: String?
        let capabilities: [String]?

        var coverAssetId: Int? {
            assets?.first(where: { $0.key == "cover" })?.value
        }

        enum CodingKeys: String, CodingKey {
            case arcid, title, description, tags, assets, pagecount, progress, filename
            case fileSize = "file_size"
            case archivetype, isnew, isfavorite
            case thumbnailHash = "thumbnail_hash"
            case capabilities
        }
    }

    struct TankoubonMetadata: Codable {
        let tankoubonId: String?
        let title: String?
        let description: String?
        let tags: [String]?
        let assets: [ArchiveMetadataAsset]?
        let pagecount: Int?
        let progress: Int?
        let archiveCount: Int?
        let isnew: Bool?
        var isfavorite: Bool?
        let children: [TankoubonChild]?

        var coverAssetId: Int? {
            assets?.first(where: { $0.key == "cover" })?.value
        }

        enum CodingKeys: String, CodingKey {
            case title, description, tags, assets, pagecount, progress, children, isnew, isfavorite
            case tankoubonId = "tankoubon_id"
            case archiveCount = "archive_count"
        }
    }

    struct TankoubonChild: Codable {
        let entityType: String?
        let entityId: String?
        let volumeNo: Int?
        let orderIndex: Int?

        enum CodingKeys: String, CodingKey {
            case entityType = "entity_type"
            case entityId = "entity_id"
            case volumeNo = "volume_no"
            case orderIndex = "order_index"
        }
    }

    struct PageFile: Decodable {
        let id: String?
        let type: String?
        let title: String?
        let path: String?
        let metadata: PageFileMetadata?
        let defaultSource: PageFileSource?

        enum CodingKeys: String, CodingKey {
            case id, type, title, path, metadata
            case defaultSource = "default_source"
        }
    }

    struct PageFileSource: Decodable {
        let id: String?
        let path: String?
        let type: String?
        let title: String?
        let metadata: PageFileMetadata?
    }

    struct PageFileMetadata: Decodable {
        let title: String?
        let description: String?
        let thumbAssetId: Int

        enum CodingKeys: String, CodingKey {
            case title, description
            case thumbAssetId = "thumb_asset_id"
        }
    }

    struct FilesResponse: Decodable {
        let pages: [PageFile]?
    }

    func fetchArchiveMetadata(arcid: String, forceRefresh: Bool = false) async throws -> ArchiveMetadata {
        if !forceRefresh, let cached = CacheManager.shared.getArchiveMetadata(arcid: arcid) {
            return try JSONDecoder().decode(ArchiveMetadata.self, from: cached)
        }
        var urlString = baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard var components = URLComponents(string: urlString) else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        components.path = (components.path.hasSuffix("/") ? "" : "/") + "api/archives/\(arcid)/metadata"
        guard let url = components.url else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        let meta = try JSONDecoder().decode(ArchiveMetadata.self, from: data)
        CacheManager.shared.cacheArchiveMetadata(arcid: arcid, data: data)
        return meta
    }

    func fetchTankoubonMetadata(tankoubonId: String, forceRefresh: Bool = false) async throws -> TankoubonMetadata {
        if !forceRefresh, let cached = CacheManager.shared.getTankoubonMetadata(tankoubonId: tankoubonId) {
            return try JSONDecoder().decode(TankoubonMetadata.self, from: cached)
        }
        var urlString = baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard var components = URLComponents(string: urlString) else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        components.path = (components.path.hasSuffix("/") ? "" : "/") + "api/tankoubons/\(tankoubonId)/metadata"
        guard let url = components.url else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        let meta = try JSONDecoder().decode(TankoubonMetadata.self, from: data)
        CacheManager.shared.cacheTankoubonMetadata(tankoubonId: tankoubonId, data: data)
        return meta
    }

    struct ArchivedInItem: Decodable {
        let tankoubonId: String
        let title: String?
        let description: String?
        let tags: String?
        let assets: ArchiveAsset?
        let children: [String]?
        let archiveCount: Int?
        let pagecount: Int?
        let progress: Int?
        let isnew: Bool?
        let isfavorite: Bool?

        enum CodingKeys: String, CodingKey {
            case title, description, tags, assets, children, pagecount, progress, isnew, isfavorite
            case tankoubonId = "tankoubon_id"
            case archiveCount = "archive_count"
        }

        var asSearchResultItem: SearchResultItem {
            SearchResultItem(
                type: "tankoubon",
                arcid: nil,
                tankoubonId: tankoubonId,
                archivetype: nil,
                filename: nil,
                title: title,
                description: description,
                summary: nil,
                pagecount: pagecount,
                archiveCount: archiveCount,
                progress: progress,
                size: nil,
                tags: tags,
                isnew: isnew,
                isfavorite: isfavorite,
                favoritetime: nil,
                lastreadtime: nil,
                assets: assets,
                children: children,
                releaseAt: nil,
                createdAt: nil,
                updatedAt: nil
            )
        }
    }

    struct ArchivedInResponse: Decodable {
        let result: [ArchivedInItem]
    }

    func fetchFiles(arcid: String) async throws -> [PageFile] {
        var urlString = baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard var components = URLComponents(string: urlString) else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        components.path = (components.path.hasSuffix("/") ? "" : "/") + "api/archives/\(arcid)/files"
        guard let url = components.url else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        let bodyStr = String(data: data, encoding: .utf8) ?? "nil"
        print("[API] fetchFiles \(arcid): status \((response as? HTTPURLResponse)?.statusCode ?? 0) body \(bodyStr.prefix(300))")
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("[API] fetchFiles failed: status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        if let result = try? JSONDecoder().decode(FilesResponse.self, from: data),
           let pages = result.pages { print("[API] fetchFiles decoded \(pages.count) pages"); return pages }
        if let envelope = try? JSONDecoder().decode(ApiEnvelope<FilesResponse>.self, from: data),
           let result = envelope.data, let pages = result.pages { print("[API] fetchFiles envelope decoded \(pages.count) pages"); return pages }
        print("[API] fetchFiles decode failed, raw: \(bodyStr.prefix(200))")
        return (try? JSONDecoder().decode([PageFile].self, from: data)) ?? []
    }

    func fetchArchivedIn(arcid: String) async throws -> [ArchivedInItem] {
        var urlString = baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard var components = URLComponents(string: urlString) else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        components.path = (components.path.hasSuffix("/") ? "" : "/") + "api/archives/\(arcid)/tankoubons"
        guard let url = components.url else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        let result = try JSONDecoder().decode(ArchivedInResponse.self, from: data)
        return result.result
    }

    func fetchPageImage(arcid: String, path: String) async throws -> Data {
        LogManager.shared.log("[API] fetchPageImage arcid=\(arcid) path=\(path)")
        var urlString = baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard var components = URLComponents(string: urlString) else {
            LogManager.shared.log("[API] fetchPageImage invalid URL: \(urlString)")
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        components.path = (components.path.hasSuffix("/") ? "" : "/") + "api/archives/\(arcid)/page"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components.url else {
            LogManager.shared.log("[API] fetchPageImage components failed for arcid=\(arcid) path=\(path)")
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        LogManager.shared.log("[API] fetchPageImage url=\(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            LogManager.shared.log("[API] fetchPageImage no HTTP response for \(url.absoluteString)")
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        LogManager.shared.log("[API] fetchPageImage status=\(httpResponse.statusCode) size=\(data.count) for arcid=\(arcid) path=\(path)")
        guard httpResponse.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        return data
    }

    func fetchAsset(assetId: Int) async throws -> Data {
        var urlString = baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard let url = URL(string: urlString)?.appendingPathComponent("api/assets/\(assetId)") else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuthHeader(&req)
        let (d, r) = try await URLSession.shared.data(for: req)
        guard let h = r as? HTTPURLResponse, h.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        return d
    }

    func updateProgress(arcid: String, page: Int) async throws {
        var urlString = baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard var components = URLComponents(string: urlString) else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        components.path = (components.path.hasSuffix("/") ? "" : "/") + "api/archives/\(arcid)/progress/\(page)"
        guard let url = components.url else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        applyAuthHeader(&request)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
    }

    // MARK: - Favorites

    func favoriteArchive(arcid: String) async throws {
        guard let url = try? makeURL("/api/archives/\(arcid)/favorite") else { return }
        var req = URLRequest(url: url); req.httpMethod = "PUT"
        applyAuthHeader(&req); _ = try await URLSession.shared.data(for: req)
    }

    func unfavoriteArchive(arcid: String) async throws {
        guard let url = try? makeURL("/api/archives/\(arcid)/favorite") else { return }
        var req = URLRequest(url: url); req.httpMethod = "DELETE"
        applyAuthHeader(&req); _ = try await URLSession.shared.data(for: req)
    }

    func favoriteTankoubon(tankoubonId: String) async throws {
        guard let url = try? makeURL("/api/tankoubons/\(tankoubonId)/favorite") else { return }
        var req = URLRequest(url: url); req.httpMethod = "PUT"
        applyAuthHeader(&req); _ = try await URLSession.shared.data(for: req)
    }

    func unfavoriteTankoubon(tankoubonId: String) async throws {
        guard let url = try? makeURL("/api/tankoubons/\(tankoubonId)/favorite") else { return }
        var req = URLRequest(url: url); req.httpMethod = "DELETE"
        applyAuthHeader(&req); _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - Recommendations

    struct RecommendationsResponse: Decodable {
        let scene: String?
        let data: [SearchResultItem]?
    }

    func fetchRecommendations(count: Int = 20, categoryId: Int? = nil, scene: String = "discover", archiveId: String? = nil, tankoubonId: String? = nil) async throws -> [SearchResultItem] {
        var urlString = baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard var components = URLComponents(string: urlString) else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        components.path = (components.path.hasSuffix("/") ? "" : "/") + "api/recommendations"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "scene", value: scene),
            URLQueryItem(name: "count", value: "\(count)"),
        ]
        if let categoryId {
            items.append(URLQueryItem(name: "category_id", value: "\(categoryId)"))
        }
        if let archiveId {
            items.append(URLQueryItem(name: "archive_id", value: archiveId))
        }
        if let tankoubonId {
            items.append(URLQueryItem(name: "tankoubon_id", value: tankoubonId))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }

        print("[API] GET \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeader(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        let rawBody = String(data: data, encoding: .utf8) ?? "nil"
        print("[API] recommendations status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        print("[API] recommendations body: \(rawBody.prefix(500))")
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        do {
            let result = try JSONDecoder().decode(RecommendationsResponse.self, from: data)
            if let items = result.data { return items }
        } catch {
            print("[API] recommendations decode error: \(error)")
        }
        if let envelope = try? JSONDecoder().decode(ApiEnvelope<[SearchResultItem]>.self, from: data),
           let items = envelope.data {
            return items
        }
        throw AuthError.networkError(String(localized: "connection_failed"))
    }

    // MARK: - Helpers

    private func makeURL(_ path: String) throws -> URL {
        var urlString = baseURL
        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }
        guard let url = URL(string: urlString)?.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path) else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        return url
    }

    private func applyAuthHeader(_ request: inout URLRequest) {
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func apiMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? String,
           !message.isEmpty {
            return message
        }
        return String(localized: "connection_failed")
    }
}
