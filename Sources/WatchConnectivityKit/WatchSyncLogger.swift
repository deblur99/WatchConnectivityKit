//
//  WatchSyncLogger.swift
//  WatchConnectivityKit
//

import Foundation

/// 동기화 과정의 진단 로그. 앱에서 침묵·os.Logger 등으로 바꿀 수 있다.
public protocol WatchSyncLogger: Sendable {
    func log(_ message: String)
}

/// `print`로 그대로 출력한다.
public struct PrintWatchSyncLogger: WatchSyncLogger {
    public init() {}

    public func log(_ message: String) {
        print(message)
    }
}

/// 아무 것도 출력하지 않는다.
public struct SilentWatchSyncLogger: WatchSyncLogger {
    public init() {}

    public func log(_ message: String) {}
}
