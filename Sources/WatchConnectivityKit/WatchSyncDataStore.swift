//
//  WatchSyncDataStore.swift
//  WatchConnectivityKit
//

import Foundation

/// WatchConnectivity로 주고받을 바이너리 페이로드의 로컬 저장소.
///
/// 앱 타깃에서 App Group, 파일, 메모리 캐시 등으로 구현한다.
/// 이 모듈은 JSON 스키마나 도메인 모델을 알지 않는다.
public protocol WatchSyncDataStore: Sendable {
    /// 저장된 페이로드. 없으면 `nil`.
    func loadEncodedPayload() -> Data?

    /// 수신했거나 전송 대기 중인 페이로드를 저장한다.
    @discardableResult
    func saveEncodedPayload(_ data: Data) -> Bool
}
