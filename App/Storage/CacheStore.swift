import Foundation

protocol CacheStore: Sendable {
    func get<T: Codable & Sendable>(_ key: String, as type: T.Type, namespace: String) async -> T?
    func set(_ key: String, value: some Codable & Sendable, namespace: String, ttl: TimeInterval?) async
    func remove(_ key: String, namespace: String) async
    func clearAll(namespace: String) async
}

struct CacheValueEnvelope<T: Codable & Sendable>: Codable, Sendable {
    let value: T
    let storedAt: Date
    let expiresAt: Date?

    init(value: T, ttl: TimeInterval?) {
        self.value = value
        storedAt = Date()
        if let ttl {
            expiresAt = Date().addingTimeInterval(ttl)
        } else {
            expiresAt = nil
        }
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}

actor MemoryCacheStore: CacheStore {
    private var storage: [String: Data] = [:]

    func get<T: Codable & Sendable>(_ key: String, as _: T.Type, namespace: String) async -> T? {
        let scopedKey = scopedKey(key, namespace: namespace)
        guard let data = storage[scopedKey] else { return nil }

        guard let decoded = try? JSONDecoder().decode(CacheValueEnvelope<T>.self, from: data) else {
            storage[scopedKey] = nil
            return nil
        }

        if decoded.isExpired {
            storage[scopedKey] = nil
            return nil
        }

        return decoded.value
    }

    func set(_ key: String, value: some Codable & Sendable, namespace: String, ttl: TimeInterval?) async {
        let envelope = CacheValueEnvelope(value: value, ttl: ttl)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        storage[scopedKey(key, namespace: namespace)] = data
    }

    func remove(_ key: String, namespace: String) async {
        storage[scopedKey(key, namespace: namespace)] = nil
    }

    func clearAll(namespace: String) async {
        let prefix = "\(namespace)::"
        storage.keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { storage[$0] = nil }
    }

    private func scopedKey(_ key: String, namespace: String) -> String {
        "\(namespace)::\(key)"
    }
}

actor DiskCacheStore: CacheStore {
    private let baseURL: URL
    private let fileManager: FileManager

    init(
        baseURL: URL? = nil,
        fileManager: FileManager = .default,
    ) {
        self.fileManager = fileManager

        if let baseURL {
            self.baseURL = baseURL
        } else {
            let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.baseURL = root.appendingPathComponent("fitfluence-cache", isDirectory: true)
        }

        Self.ensureDirectoryExists(at: self.baseURL, using: fileManager)
    }

    func get<T: Codable & Sendable>(_ key: String, as _: T.Type, namespace: String) async -> T? {
        let url = fileURL(for: key, namespace: namespace)
        guard let data = try? Data(contentsOf: url) else { return nil }

        guard let decoded = try? JSONDecoder().decode(CacheValueEnvelope<T>.self, from: data) else {
            try? fileManager.removeItem(at: url)
            return nil
        }

        if decoded.isExpired {
            try? fileManager.removeItem(at: url)
            return nil
        }

        return decoded.value
    }

    func set(_ key: String, value: some Codable & Sendable, namespace: String, ttl: TimeInterval?) async {
        let envelope = CacheValueEnvelope(value: value, ttl: ttl)
        guard let data = try? JSONEncoder().encode(envelope) else { return }

        let namespaceURL = namespaceDirectoryURL(namespace)
        if !fileManager.fileExists(atPath: namespaceURL.path) {
            try? fileManager.createDirectory(at: namespaceURL, withIntermediateDirectories: true)
        }

        let targetURL = fileURL(for: key, namespace: namespace)
        let tmpURL = namespaceURL.appendingPathComponent(UUID().uuidString + ".tmp")

        do {
            try data.write(to: tmpURL, options: .atomic)
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: tmpURL, to: targetURL)
        } catch {
            try? fileManager.removeItem(at: tmpURL)
        }
    }

    func remove(_ key: String, namespace: String) async {
        try? fileManager.removeItem(at: fileURL(for: key, namespace: namespace))
    }

    func clearAll(namespace: String) async {
        try? fileManager.removeItem(at: namespaceDirectoryURL(namespace))
    }

    nonisolated private static func ensureDirectoryExists(at url: URL, using fileManager: FileManager) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func namespaceDirectoryURL(_ namespace: String) -> URL {
        baseURL.appendingPathComponent(safeFilename(namespace), isDirectory: true)
    }

    private func fileURL(for key: String, namespace: String) -> URL {
        namespaceDirectoryURL(namespace)
            .appendingPathComponent(safeFilename(key))
            .appendingPathExtension("json")
    }

    private func safeFilename(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let normalized = raw.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(normalized)
    }
}

actor CompositeCacheStore: CacheStore {
    private let memory: CacheStore
    private let disk: CacheStore

    init(memory: CacheStore = MemoryCacheStore(), disk: CacheStore = DiskCacheStore()) {
        self.memory = memory
        self.disk = disk
    }

    func get<T: Codable & Sendable>(_ key: String, as _: T.Type, namespace: String) async -> T? {
        if let inMemory: T = await memory.get(key, as: T.self, namespace: namespace) {
            return inMemory
        }

        guard let fromDisk: T = await disk.get(key, as: T.self, namespace: namespace) else {
            return nil
        }

        await memory.set(key, value: fromDisk, namespace: namespace, ttl: nil)
        return fromDisk
    }

    func set(_ key: String, value: some Codable & Sendable, namespace: String, ttl: TimeInterval?) async {
        await memory.set(key, value: value, namespace: namespace, ttl: ttl)
        await disk.set(key, value: value, namespace: namespace, ttl: ttl)
    }

    func remove(_ key: String, namespace: String) async {
        await memory.remove(key, namespace: namespace)
        await disk.remove(key, namespace: namespace)
    }

    func clearAll(namespace: String) async {
        await memory.clearAll(namespace: namespace)
        await disk.clearAll(namespace: namespace)
    }
}
