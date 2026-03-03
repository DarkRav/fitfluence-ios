import Foundation

protocol DiagnosticsProviding: Sendable {
    func appVersion() -> String
    func appBuild() -> String
    func cacheSizeBytes(userSub: String) async -> Int
    func clearCache(userSub: String) async
}

struct DiagnosticsProvider: DiagnosticsProviding {
    private let bundle: Bundle
    private let cacheStore: CacheStore
    private let fileManager: FileManager

    init(
        bundle: Bundle = .main,
        cacheStore: CacheStore = CompositeCacheStore(),
        fileManager: FileManager = .default,
    ) {
        self.bundle = bundle
        self.cacheStore = cacheStore
        self.fileManager = fileManager
    }

    func appVersion() -> String {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    func appBuild() -> String {
        (bundle.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }

    func cacheSizeBytes(userSub: String) async -> Int {
        guard let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return 0
        }
        let namespaceURL = root
            .appendingPathComponent("fitfluence-cache", isDirectory: true)
            .appendingPathComponent(safeFileName(userSub), isDirectory: true)
        return directorySize(at: namespaceURL)
    }

    func clearCache(userSub: String) async {
        await cacheStore.clearAll(namespace: userSub)
        FFRemoteImageCache.clearAll()
    }

    private func safeFileName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let normalized = raw.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(normalized)
    }

    private func directorySize(at url: URL) -> Int {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
        ) else {
            return 0
        }

        var total = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += values?.fileSize ?? 0
            }
        }
        return total
    }
}
