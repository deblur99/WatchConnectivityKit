//
//  WatchSyncConfiguration.swift
//  WatchConnectivityKit
//

import Foundation

/// iPhone ↔ Watch 동기화에 쓰는 WatchConnectivity 페이로드 키와 전송 한도.
///
/// 앱마다 다른 키를 써야 이미 배포된 페이로드와 충돌하지 않는다.
/// iPhone·Watch 양쪽이 **같은 설정**을 써야 한다.
public struct WatchSyncConfiguration: Sendable, Equatable {
    /// `applicationContext` / `userInfo` / `sendMessage` reply에 넣는 바이너리 페이로드 키.
    public var payloadKey: String
    /// Watch가 iPhone에 최신 데이터를 요청할 때 쓰는 키.
    public var requestSyncKey: String
    /// 보낼 데이터가 없을 때 reply에 넣는 키.
    public var emptyKey: String
    /// `updateApplicationContext` 권장 상한. 초과하면 전송하지 않는다.
    public var maxPayloadBytes: Int
    /// 런치 직후 `WCSession.activate()`를 미루는 시간. App Group 초기화와 겹치지 않게 한다.
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
