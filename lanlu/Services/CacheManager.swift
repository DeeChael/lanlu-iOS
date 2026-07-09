import Foundation
import UIKit

final class CacheManager {
    static let shared = CacheManager()
    private var archiveCache = NSCache<NSString, NSData>()
    private var coverCache = NSCache<NSString, NSData>()

    func cacheArchive(_ archive: SearchResultItem) {
        guard let id = archive.arcid else { return }
        if let data = try? JSONEncoder().encode(archive) {
            archiveCache.setObject(data as NSData, forKey: id as NSString)
        }
    }

    func getArchive(id: String) -> SearchResultItem? {
        guard let data = archiveCache.object(forKey: id as NSString) as? Data else { return nil }
        return try? JSONDecoder().decode(SearchResultItem.self, from: data)
    }

    func cacheCover(id: String, data: Data) {
        coverCache.setObject(data as NSData, forKey: id as NSString)
    }

    func getCover(id: String) -> Data? {
        coverCache.object(forKey: id as NSString) as? Data
    }

    func clearAll() {
        archiveCache.removeAllObjects()
        coverCache.removeAllObjects()
    }
}
