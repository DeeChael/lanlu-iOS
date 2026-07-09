import Foundation

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

struct UserStatsData: Decodable {
    let favoriteCount: Int?
    let readCount: Int?
    let totalPagesRead: Int?
    let totalArchives: Int?
}

struct TrendPoint: Decodable {
    let date: String
    let count: Int

    var dateValue: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }
}

// MARK: - Search / Archive

struct ArchiveAsset: Codable, Sendable {
    let cover: Int?
}

struct SearchResultItem: Codable, Sendable {
    let type: String?
    let arcid: String
    let archivetype: String?
    let filename: String?
    let title: String?
    let description: String?
    let pagecount: Int?
    let progress: Int?
    let size: Int?
    let tags: String?
    let isnew: Bool?
    let isfavorite: Bool?
    let assets: ArchiveAsset?
    let releaseAt: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case type, arcid, archivetype, filename, title, description
        case pagecount, progress, size, tags, isnew, isfavorite, assets
        case releaseAt = "release_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
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

struct UserTrendData {
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
        var components = URLComponents()
        components.scheme = "https"
        components.path = "/api/user/trend"
        components.queryItems = [URLQueryItem(name: "days", value: "\(days)")]

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
        if let arr = try? JSONDecoder().decode([TrendPoint].self, from: data) {
            return UserTrendData(trend: arr)
        }
        throw AuthError.networkError(String(localized: "connection_failed"))
    }

    // MARK: - Search

    func search(favoriteOnly: Bool = false, untaggedOnly: Bool = false, filter: String? = nil, sortby: String = "created_at", order: String = "desc", dateFrom: String? = nil, dateTo: String? = nil, start: Int = 0, count: Int = 20) async throws -> SearchResponse {
        var urlString = baseURL
        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }

        guard var baseComponents = URLComponents(string: urlString) else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }

        baseComponents.path = (baseComponents.path.hasSuffix("/") ? "" : "/") + "api/search"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "start", value: "\(start)"),
            URLQueryItem(name: "count", value: "\(count)"),
            URLQueryItem(name: "sortby", value: sortby),
            URLQueryItem(name: "order", value: order),
        ]
        if favoriteOnly {
            items.append(URLQueryItem(name: "favoriteonly", value: "true"))
        }
        if untaggedOnly {
            items.append(URLQueryItem(name: "untaggedonly", value: "true"))
        }
        if let filter, !filter.isEmpty {
            items.append(URLQueryItem(name: "filter", value: filter))
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

        LogManager.shared.log("GET /api/search start=\(start) count=\(count) sortby=\(sortby)")

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

    func fetchFavorites(start: Int = 0, count: Int = 40) async throws -> SearchResponse {
        try await search(favoriteOnly: true, sortby: "updated_at", order: "desc", start: start, count: count)
    }

    func fetchHistory(start: Int = 0, count: Int = 40) async throws -> SearchResponse {
        try await search(favoriteOnly: false, sortby: "lastreadtime", order: "desc", start: start, count: count)
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
}
