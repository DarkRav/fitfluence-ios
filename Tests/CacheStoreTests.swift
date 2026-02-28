@testable import FitfluenceApp
import XCTest

final class CacheStoreTests: XCTestCase {
    func testMemoryCacheSetGetRemove() async {
        let store = MemoryCacheStore()
        await store.set("program.details:p1", value: SampleValue(id: "p1"), namespace: "u1", ttl: nil)

        let cached: SampleValue? = await store.get("program.details:p1", as: SampleValue.self, namespace: "u1")
        XCTAssertEqual(cached, SampleValue(id: "p1"))

        await store.remove("program.details:p1", namespace: "u1")
        let missing: SampleValue? = await store.get("program.details:p1", as: SampleValue.self, namespace: "u1")
        XCTAssertNil(missing)
    }

    func testMemoryCacheNamespaceSeparation() async {
        let store = MemoryCacheStore()
        await store.set("program.details:p1", value: SampleValue(id: "u1-value"), namespace: "u1", ttl: nil)
        await store.set("program.details:p1", value: SampleValue(id: "u2-value"), namespace: "u2", ttl: nil)

        let u1: SampleValue? = await store.get("program.details:p1", as: SampleValue.self, namespace: "u1")
        let u2: SampleValue? = await store.get("program.details:p1", as: SampleValue.self, namespace: "u2")

        XCTAssertEqual(u1?.id, "u1-value")
        XCTAssertEqual(u2?.id, "u2-value")

        await store.clearAll(namespace: "u1")
        let u1AfterClear: SampleValue? = await store.get("program.details:p1", as: SampleValue.self, namespace: "u1")
        let u2StillThere: SampleValue? = await store.get("program.details:p1", as: SampleValue.self, namespace: "u2")

        XCTAssertNil(u1AfterClear)
        XCTAssertEqual(u2StillThere?.id, "u2-value")
    }

    func testDiskCacheSetGetAndTTLExpiry() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fitfluence-cache-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = DiskCacheStore(baseURL: tempDir)
        await store.set("catalog.list:q=", value: SampleValue(id: "cached"), namespace: "u1", ttl: 0.1)

        let immediate: SampleValue? = await store.get("catalog.list:q=", as: SampleValue.self, namespace: "u1")
        XCTAssertEqual(immediate?.id, "cached")

        try await Task.sleep(for: .milliseconds(150))

        let expired: SampleValue? = await store.get("catalog.list:q=", as: SampleValue.self, namespace: "u1")
        XCTAssertNil(expired)
    }

    func testCompositeReadsFromDiskIntoMemory() async {
        let memory = MemoryCacheStore()
        let disk = MemoryCacheStore()
        let store = CompositeCacheStore(memory: memory, disk: disk)

        await disk.set("workout.details:w1", value: SampleValue(id: "from-disk"), namespace: "u1", ttl: nil)

        let first: SampleValue? = await store.get("workout.details:w1", as: SampleValue.self, namespace: "u1")
        XCTAssertEqual(first?.id, "from-disk")

        // Remove from disk, should still be returned from memory after warmup.
        await disk.remove("workout.details:w1", namespace: "u1")
        let second: SampleValue? = await store.get("workout.details:w1", as: SampleValue.self, namespace: "u1")
        XCTAssertEqual(second?.id, "from-disk")
    }
}

private struct SampleValue: Codable, Equatable {
    let id: String
}
