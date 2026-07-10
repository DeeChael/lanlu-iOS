import Foundation
import UIKit

final class CacheManager {
    static let shared = CacheManager()

    private var archiveCache = NSCache<NSString, NSData>()
    private var coverCache = NSCache<NSString, NSData>()
    private var metaCache = NSCache<NSString, NSData>()

    private var diskCacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("image_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

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
        let url = diskCacheDir.appendingPathComponent(id)
        try? data.write(to: url, options: .atomic)
    }

    func getCover(id: String) -> Data? {
        if let cached = coverCache.object(forKey: id as NSString) as? Data { return cached }
        let url = diskCacheDir.appendingPathComponent(id)
        return try? Data(contentsOf: url)
    }

    var metadataCacheCount: Int { metaCacheCount }
    private var metaCacheCount = 0

    func cacheArchiveMetadata(arcid: String, data: Data) {
        metaCache.setObject(data as NSData, forKey: "meta_\(arcid)" as NSString)
        metaCacheCount += 1
    }

    func getArchiveMetadata(arcid: String) -> Data? {
        metaCache.object(forKey: "meta_\(arcid)" as NSString) as? Data
    }

    func cacheTankoubonMetadata(tankoubonId: String, data: Data) {
        metaCache.setObject(data as NSData, forKey: "tmeta_\(tankoubonId)" as NSString)
        metaCacheCount += 1
    }

    func getTankoubonMetadata(tankoubonId: String) -> Data? {
        metaCache.object(forKey: "tmeta_\(tankoubonId)" as NSString) as? Data
    }

    var diskCacheCount: Int {
        (try? FileManager.default.contentsOfDirectory(at: diskCacheDir, includingPropertiesForKeys: nil).count) ?? 0
    }

    var diskCacheSize: String {
        let dir = diskCacheDir
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return "0 KB" }
        let total = files.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return sum + size
        }
        if total < 1024 { return "\(total) B" }
        if total < 1024 * 1024 { return "\(total / 1024) KB" }
        return String(format: "%.1f MB", Double(total) / (1024.0 * 1024.0))
    }

    var allCachesCount: Int {
        diskCacheCount + metadataCacheCount
    }

    func clearAll() {
        archiveCache.removeAllObjects()
        coverCache.removeAllObjects()
        metaCache.removeAllObjects()
        metaCacheCount = 0
        let dir = diskCacheDir
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in files { try? FileManager.default.removeItem(at: url) }
        }
    }
}
