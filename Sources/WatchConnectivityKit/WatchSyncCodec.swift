//
//  WatchSyncCodec.swift
//  WatchConnectivityKit
//

import Foundation

/// WatchConnectivity 딕셔너리 ↔ `Data` 변환.
public struct WatchSyncCodec: Sendable {
    public let configuration: WatchSyncConfiguration

    public init(configuration: WatchSyncConfiguration = .default) {
        self.configuration = configuration
    }

    public func encodedPayload(from dictionary: [String: Any]) -> Data? {
        if dictionary[configuration.emptyKey] as? Bool == true { return nil }
        return dictionary[configuration.payloadKey] as? Data
    }

    /// 용량 한도를 넘기면 `nil`.
    public func dictionary(containing data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        guard data.count <= configuration.maxPayloadBytes else { return nil }
        return [configuration.payloadKey: data]
    }

    public func emptyReply() -> [String: Any] {
        [configuration.emptyKey: true]
    }

    public func syncRequest() -> [String: Any] {
        [configuration.requestSyncKey: true]
    }

    public func isSyncRequest(_ message: [String: Any]) -> Bool {
        message[configuration.requestSyncKey] as? Bool == true
    }
}
