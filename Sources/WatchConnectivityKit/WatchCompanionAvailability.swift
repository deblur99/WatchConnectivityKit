//
//  WatchCompanionAvailability.swift
//  WatchConnectivityKit
//

import Foundation

#if os(watchOS)
import WatchConnectivity

/// Whether the iPhone companion app can sync over WatchConnectivity.
public nonisolated enum WatchCompanionAvailability {
    public static var isPairedCompanionAvailable: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated else { return false }
        return session.isCompanionAppInstalled
    }
}
#endif
