import ApplicationServices
import Foundation

public final class SnapshotElementCache<Element>: @unchecked Sendable {
    private struct Entry {
        var createdAt: Date
        var elements: [String: Element]
        var elementIDsByIndex: [Int: String]
        var appBundleIdentifier: String?
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
        elements: [String: Element],
        elementIDsByIndex: [Int: String] = [:],
        appBundleIdentifier: String? = nil
    ) {
        lock.lock()
        snapshots[snapshotID] = Entry(
            createdAt: now(),
            elements: elements,
            elementIDsByIndex: elementIDsByIndex,
            appBundleIdentifier: appBundleIdentifier
        )
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

    public func element(
        snapshotID requestedSnapshotID: String?,
        elementID: String?,
        elementIndex: Int?,
        appBundleIdentifier: String? = nil
    ) throws -> Element {
        lock.lock()
        pruneExpiredLocked()
        defer {
            lock.unlock()
        }

        let snapshotID: String
        if let requestedSnapshotID {
            snapshotID = requestedSnapshotID
        } else if let appBundleIdentifier,
                  let latestSnapshotID = snapshots
            .filter({ _, entry in entry.appBundleIdentifier == appBundleIdentifier })
            .max(by: { lhs, rhs in lhs.value.createdAt < rhs.value.createdAt })?.key {
            snapshotID = latestSnapshotID
        } else if let latestSnapshotID = snapshots.max(by: { lhs, rhs in
            lhs.value.createdAt < rhs.value.createdAt
        })?.key {
            snapshotID = latestSnapshotID
        } else {
            throw SnapshotCacheError.snapshotExpired("")
        }

        guard let snapshot = snapshots[snapshotID] else {
            throw SnapshotCacheError.snapshotExpired(snapshotID)
        }

        if let appBundleIdentifier,
           let actualBundleIdentifier = snapshot.appBundleIdentifier,
           actualBundleIdentifier != appBundleIdentifier {
            throw SnapshotCacheError.snapshotAppMismatch(
                snapshotID: snapshotID,
                expectedBundleID: appBundleIdentifier,
                actualBundleID: actualBundleIdentifier
            )
        }

        if let elementID {
            guard let element = snapshot.elements[elementID] else {
                throw SnapshotCacheError.elementNotFound(snapshotID: snapshotID, elementID: elementID)
            }

            return element
        }

        if let elementIndex {
            guard let elementID = snapshot.elementIDsByIndex[elementIndex] else {
                throw SnapshotCacheError.elementIndexNotFound(snapshotID: snapshotID, elementIndex: elementIndex)
            }

            guard let element = snapshot.elements[elementID] else {
                throw SnapshotCacheError.elementNotFound(snapshotID: snapshotID, elementID: elementID)
            }

            return element
        }

        throw SnapshotCacheError.snapshotExpired(snapshotID)
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
    case elementIndexNotFound(snapshotID: String, elementIndex: Int)
    case snapshotAppMismatch(snapshotID: String, expectedBundleID: String, actualBundleID: String)

    public var errorDescription: String? {
        switch self {
        case let .snapshotExpired(snapshotID):
            "snapshot \(snapshotID) has expired"
        case let .elementNotFound(snapshotID, elementID):
            "element \(elementID) was not found in snapshot \(snapshotID)"
        case let .elementIndexNotFound(snapshotID, elementIndex):
            "element index \(elementIndex) was not found in snapshot \(snapshotID)"
        case let .snapshotAppMismatch(snapshotID, expectedBundleID, actualBundleID):
            "snapshot \(snapshotID) belongs to \(actualBundleID), not \(expectedBundleID)"
        }
    }
}

public typealias MacOSSnapshotElementCache = SnapshotElementCache<AXUIElement>
