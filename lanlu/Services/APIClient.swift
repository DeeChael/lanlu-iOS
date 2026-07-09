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
                throw AuthError.invalidCredentials
            }
            self.token = loginData.token.token
            return loginData

        case 202:
            let envelope = try JSONDecoder().decode(ApiEnvelope<TotpRequiredData>.self, from: data)
            guard let totpData = envelope.data else {
                throw AuthError.networkError(String(localized: "connection_failed"))
            }
            throw AuthError.totpRequired(challengeId: totpData.challengeId, methods: totpData.methods)

        case 401:
            throw AuthError.invalidCredentials

        default:
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
    }

    // MARK: - Auth: TOTP Verify

    func verifyTOTP(challengeId: String, code: String) async throws -> LoginSuccessData {
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
                throw AuthError.invalidCredentials
            }
            return userInfo.user

        case 401:
            throw AuthError.tokenExpired

        default:
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
    }

    // MARK: - User Stats

    func fetchStats() async throws -> UserStatsData {
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
