import Foundation

struct ServerInfo: Codable {
    let motd: String
    let name: String
    let totalArchives: Int
    let totalPagesRead: Int
    let version: String
    let versionDesc: String
    let versionName: String
    let dbExtensions: [DBExtension]

    enum CodingKeys: String, CodingKey {
        case motd, name
        case totalArchives = "total_archives"
        case totalPagesRead = "total_pages_read"
        case version
        case versionDesc = "version_desc"
        case versionName = "version_name"
        case dbExtensions = "db_extensions"
    }
}

struct DBExtension: Codable {
    let name: String
    let enabled: Bool
    let version: String
}

enum NetworkError: LocalizedError {
    case invalidURL
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "invalid_url")
        case .connectionFailed:
            String(localized: "connection_failed")
        }
    }
}

class NetworkService {
    static let shared = NetworkService()

    func testConnection(baseURL: String) async throws -> ServerInfo {
        LogManager.shared.log("GET /api/info")
        var urlString = baseURL
        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }

        guard let url = URL(string: urlString),
              url.scheme != nil else {
            throw NetworkError.invalidURL
        }

        let fullURL = url.appendingPathComponent("api/info")
        let (data, response) = try await URLSession.shared.data(from: fullURL)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.connectionFailed
        }

        if let envelope = try? JSONDecoder().decode(ApiEnvelope<ServerInfo>.self, from: data),
           let serverInfo = envelope.data {
            return serverInfo
        }

        return try JSONDecoder().decode(ServerInfo.self, from: data)
    }
}
