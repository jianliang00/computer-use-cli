import ApplicationServices
import Foundation

public final class SnapshotElementCache<Element>: @unchecked Sendable {
    private struct Entry {
        var createdAt: Date
        var elements: [String: Element]
    }

    private let policy: SnapshotCachePolicy
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var snapshots: [String: Entry] = [:]

    public init(
        policy: SnapshotCachePolicy = SnapshotCachePolicy(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.policy = policy
        self.now = now
    }

    public func store(
        snapshotID: String,
        elements: [String: Element]
    ) {
        lock.lock()
        snapshots[snapshotID] = Entry(createdAt: now(), elements: elements)
        pruneExpiredLocked()
        pruneCapacityLocked()
        lock.unlock()
    }

    public func element(
        snapshotID: String,
        elementID: String
    ) throws -> Element {
        lock.lock()
        pruneExpiredLocked()
        defer {
            lock.unlock()
        }

        guard let snapshot = snapshots[snapshotID] else {
            throw SnapshotCacheError.snapshotExpired(snapshotID)
        }

        guard let element = snapshot.elements[elementID] else {
            throw SnapshotCacheError.elementNotFound(snapshotID: snapshotID, elementID: elementID)
        }

        return element
    }

    public func snapshotIDs() -> [String] {
        lock.lock()
        pruneExpiredLocked()
        let ids = snapshots
            .sorted { lhs, rhs in lhs.value.createdAt < rhs.value.createdAt }
            .map(\.key)
        lock.unlock()
        return ids
    }

    private func pruneExpiredLocked() {
        let cutoff = now().addingTimeInterval(-policy.timeToLive)
        snapshots = snapshots.filter { _, entry in
            entry.createdAt >= cutoff
        }
    }

    private func pruneCapacityLocked() {
        let ordered = snapshots.sorted { lhs, rhs in
            lhs.value.createdAt < rhs.value.createdAt
        }

        let overflow = ordered.count - policy.capacity
        guard overflow > 0 else {
            return
        }

        for (snapshotID, _) in ordered.prefix(overflow) {
            snapshots.removeValue(forKey: snapshotID)
        }
    }
}

public enum SnapshotCacheError: Error, LocalizedError, Equatable, Sendable {
    case snapshotExpired(String)
    case elementNotFound(snapshotID: String, elementID: String)

    public var errorDescription: String? {
        switch self {
        case let .snapshotExpired(snapshotID):
            "snapshot \(snapshotID) has expired"
        case let .elementNotFound(snapshotID, elementID):
            "element \(elementID) was not found in snapshot \(snapshotID)"
        }
    }
}

public typealias MacOSSnapshotElementCache = SnapshotElementCache<AXUIElement>
