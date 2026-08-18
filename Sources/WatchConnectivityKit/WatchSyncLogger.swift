//
//  WatchSyncLogger.swift
//  WatchConnectivityKit
//

import Foundation

/// Diagnostic logging for sync. Replace with a silent logger or `os.Logger` in the app.
public protocol WatchSyncLogger: Sendable {
    func log(_ message: String)
}

/// Forwards messages to `print`.
public struct PrintWatchSyncLogger: WatchSyncLogger {
    public init() {}

    public func log(_ message: String) {
        print(message)
    }
}

/// Drops all messages.
public struct SilentWatchSyncLogger: WatchSyncLogger {
    public init() {}

    public func log(_ message: String) {}
}
