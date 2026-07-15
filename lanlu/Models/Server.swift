import Foundation
import SwiftData

@Model
final class Server {
    var name: String
    var baseURL: String
    var authMethod: String
    var authData: String?
    var lastUsedAt: Date?
    var createdAt: Date
    var cachedUsername: String?
    var cachedAvatarAssetId: Int?
    var cachedIsAdmin: Bool?

    init(name: String, baseURL: String, authMethod: String, authData: String? = nil) {
        self.name = name
        self.baseURL = baseURL
        self.authMethod = authMethod
        self.authData = authData
        self.createdAt = Date()
    }

    var authToken: String? {
        guard let data = authData?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["token"] as? String
    }

    var apiClient: APIClient {
        APIClient(baseURL: baseURL, token: authToken)
    }
}
