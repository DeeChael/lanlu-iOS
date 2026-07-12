import Foundation
import UIKit

final class CacheManager {
    static let shared = CacheManager()

    private var archiveCache = NSCache<NSString, NSData>()
    private var coverCache = NSCache<NSString, NSData>()
    private var metaMemoryCache = NSCache<NSString, NSData>()

    private var imageCacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("image_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var metaCacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("meta_cache", isDirectory: true)
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
        let url = imageCacheDir.appendingPathComponent(id)
        try? data.write(to: url, options: .atomic)
    }

    func getCover(id: String) -> Data? {
        if let cached = coverCache.object(forKey: id as NSString) as? Data { return cached }
        let url = imageCacheDir.appendingPathComponent(id)
        return try? Data(contentsOf: url)
    }

    // MARK: - Metadata cache (memory + disk)

    private func metaDiskURL(key: String) -> URL {
        metaCacheDir.appendingPathComponent(key)
    }

    func cacheArchiveMetadata(arcid: String, data: Data) {
        metaMemoryCache.setObject(data as NSData, forKey: "meta_\(arcid)" as NSString)
        try? data.write(to: metaDiskURL(key: "meta_\(arcid)"), options: .atomic)
    }

    func getArchiveMetadata(arcid: String) -> Data? {
        let key = "meta_\(arcid)"
        if let cached = metaMemoryCache.object(forKey: key as NSString) as? Data { return cached }
        let url = metaDiskURL(key: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        metaMemoryCache.setObject(data as NSData, forKey: key as NSString)
        return data
    }

    func cacheTankoubonMetadata(tankoubonId: String, data: Data) {
        let key = "tmeta_\(tankoubonId)"
        metaMemoryCache.setObject(data as NSData, forKey: key as NSString)
        try? data.write(to: metaDiskURL(key: key), options: .atomic)
    }

    func getTankoubonMetadata(tankoubonId: String) -> Data? {
        let key = "tmeta_\(tankoubonId)"
        if let cached = metaMemoryCache.object(forKey: key as NSString) as? Data { return cached }
        let url = metaDiskURL(key: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        metaMemoryCache.setObject(data as NSData, forKey: key as NSString)
        return data
    }

    var metadataDiskCount: Int {
        (try? FileManager.default.contentsOfDirectory(at: metaCacheDir, includingPropertiesForKeys: nil).count) ?? 0
    }

    var imageDiskCount: Int {
        (try? FileManager.default.contentsOfDirectory(at: imageCacheDir, includingPropertiesForKeys: nil).count) ?? 0
    }

    var diskCacheSize: String {
        let dir = imageCacheDir
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return "0 KB" }
        let total = files.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return sum + size
        }
        if total < 1024 { return "\(total) B" }
        if total < 1024 * 1024 { return "\(total / 1024) KB" }
        return String(format: "%.1f MB", Double(total) / (1024.0 * 1024.0))
    }

    func clearAll() {
        archiveCache.removeAllObjects()
        coverCache.removeAllObjects()
        metaMemoryCache.removeAllObjects()

        let imgDir = imageCacheDir
        if let files = try? FileManager.default.contentsOfDirectory(at: imgDir, includingPropertiesForKeys: nil) {
            for url in files { try? FileManager.default.removeItem(at: url) }
        }
        let mDir = metaCacheDir
        if let files = try? FileManager.default.contentsOfDirectory(at: mDir, includingPropertiesForKeys: nil) {
            for url in files { try? FileManager.default.removeItem(at: url) }
        }
    }
}
