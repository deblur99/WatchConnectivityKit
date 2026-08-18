//
//  WatchCompanionAvailability.swift
//  WatchConnectivityKit
//

import Foundation

#if os(watchOS)
import WatchConnectivity

/// iPhone companion 앱과 WatchConnectivity 동기화가 가능한지 판별한다.
public nonisolated enum WatchCompanionAvailability {
    public static var isPairedCompanionAvailable: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated else { return false }
        return session.isCompanionAppInstalled
    }
}
#endif
