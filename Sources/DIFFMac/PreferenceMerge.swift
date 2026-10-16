import Foundation

enum PreferenceMerge {
    static func recentRepos(local: [RecentRepo], remote: [RecentRepo]) -> [RecentRepo] {
        merge(local: local, remote: remote, id: \.id, date: \.viewedAt)
    }

    static func savedPulls(local: [SavedPull], remote: [SavedPull]) -> [SavedPull] {
        merge(local: local, remote: remote, id: \.id, date: \.savedAt)
    }

    static func aiDrafts(local: [AIDraft], remote: [AIDraft]) -> [AIDraft] {
        merge(local: local, remote: remote, id: \.id, date: \.updatedAt)
    }

    private static func merge<T>(
        local: [T],
        remote: [T],
        id: KeyPath<T, String>,
        date: KeyPath<T, Date>
    ) -> [T] {
        var merged: [String: T] = Dictionary(uniqueKeysWithValues: local.map { ($0[keyPath: id], $0) })
        for item in remote {
            let key = item[keyPath: id]
            if let existing = merged[key], existing[keyPath: date] > item[keyPath: date] {
                continue
            }
            merged[key] = item
        }
        return merged.values.sorted { $0[keyPath: date] > $1[keyPath: date] }
    }
}
