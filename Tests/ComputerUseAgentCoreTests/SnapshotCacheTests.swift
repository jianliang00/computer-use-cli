import ComputerUseAgentCore
import Foundation
import Testing

@Test
func snapshotElementCacheExpiresEntriesByTTL() throws {
    let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
    let cache = SnapshotElementCache<String>(
        policy: SnapshotCachePolicy(capacity: 8, timeToLive: 60),
        now: { clock.date }
    )

    cache.store(snapshotID: "snap-001", elements: ["ax-1": "element"])
    #expect(try cache.element(snapshotID: "snap-001", elementID: "ax-1") == "element")

    clock.date = Date(timeIntervalSince1970: 1_061)

    do {
        _ = try cache.element(snapshotID: "snap-001", elementID: "ax-1")
        Issue.record("expected snapshot to expire")
    } catch let error as SnapshotCacheError {
        #expect(error == .snapshotExpired("snap-001"))
    }
}

@Test
func snapshotElementCacheKeepsMostRecentSnapshotsWithinCapacity() throws {
    let clock = TestClock(date: Date(timeIntervalSince1970: 2_000))
    let cache = SnapshotElementCache<String>(
        policy: SnapshotCachePolicy(capacity: 2, timeToLive: 60),
        now: { clock.date }
    )

    cache.store(snapshotID: "snap-001", elements: ["ax-1": "one"])
    clock.date = Date(timeIntervalSince1970: 2_001)
    cache.store(snapshotID: "snap-002", elements: ["ax-1": "two"])
    clock.date = Date(timeIntervalSince1970: 2_002)
    cache.store(snapshotID: "snap-003", elements: ["ax-1": "three"])

    #expect(cache.snapshotIDs() == ["snap-002", "snap-003"])

    do {
        _ = try cache.element(snapshotID: "snap-001", elementID: "ax-1")
        Issue.record("expected oldest snapshot to be evicted")
    } catch let error as SnapshotCacheError {
        #expect(error == .snapshotExpired("snap-001"))
    }
}

private final class TestClock: @unchecked Sendable {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}
