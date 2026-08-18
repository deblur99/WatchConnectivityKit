//
//  UserDefaultsWatchSyncStore.swift
//  WatchConnectivityKit
//

import Foundation

/// `UserDefaults`(App Group suite 포함)에 페이로드 `Data`를 그대로 저장한다.
///
/// 도메인 모델 필터·재인코딩이 필요하면 앱에서 `WatchSyncDataStore`를 직접 구현한다.
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
