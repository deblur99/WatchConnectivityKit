//
//  UserDefaultsWatchSyncStore.swift
//  WatchConnectivityKit
//

import Foundation

/// Stores payload `Data` in `UserDefaults`, including an App Group suite.
///
/// If you need domain filtering or re-encoding, implement `WatchSyncDataStore` in the app.
public final class UserDefaultsWatchSyncStore: WatchSyncDataStore, @unchecked Sendable {
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    public init?(suiteName: String, key: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = defaults
        self.key = key
    }

    public func loadEncodedPayload() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return defaults.data(forKey: key)
    }

    @discardableResult
    public func saveEncodedPayload(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        lock.lock()
        defaults.set(data, forKey: key)
        lock.unlock()
        return true
    }
}
