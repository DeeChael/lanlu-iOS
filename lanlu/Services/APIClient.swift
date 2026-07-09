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
