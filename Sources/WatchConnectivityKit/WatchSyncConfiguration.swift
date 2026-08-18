//
//  WatchSyncConfiguration.swift
//  WatchConnectivityKit
//

import Foundation

/// WatchConnectivity payload keys and size limits for iPhone ↔ Watch sync.
///
/// Use app-specific keys so they do not collide with an already shipped payload.
/// iPhone and Watch must use the **same** configuration.
public struct WatchSyncConfiguration: Sendable, Equatable {
    /// Key for the binary payload in `applicationContext`, `userInfo`, and `sendMessage` replies.
    public var payloadKey: String
    /// Key Watch uses when asking iPhone for the latest data.
    public var requestSyncKey: String
    /// Key set in a reply when there is nothing to send.
    public var emptyKey: String
    /// Recommended `updateApplicationContext` cap. Larger payloads are not sent.
    public var maxPayloadBytes: Int
    /// Delay before `WCSession.activate()` after launch, so it does not overlap App Group setup.
    public var activationDelay: TimeInterval

    public init(
        payloadKey: String = "payload",
        requestSyncKey: String = "requestSync",
        emptyKey: String = "empty",
        maxPayloadBytes: Int = 65_536,
        activationDelay: TimeInterval = 1.0
    ) {
        self.payloadKey = payloadKey
        self.requestSyncKey = requestSyncKey
        self.emptyKey = emptyKey
        self.maxPayloadBytes = maxPayloadBytes
        self.activationDelay = activationDelay
    }

    public static let `default` = WatchSyncConfiguration()
}
