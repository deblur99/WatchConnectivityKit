//
//  PhoneWatchSyncService.swift
//  WatchConnectivityKit
//

#if os(iOS)

import Foundation
import WatchConnectivity

/// iPhone에서 Watch로 바이너리 페이로드를 전달한다.
///
/// 이 모듈은 Default Actor Isolation이 없어 `WCSessionDelegate`가 MainActor로
/// 추론되지 않는다. 앱 타깃(MainActor 기본)에서 import해도 모듈 경계로 안전하다.
///
/// `WCSession.default.delegate`를 이 인스턴스가 소유한다. 앱에서 다른 delegate를
/// 같이 쓰려면 이 서비스를 쓰지 말고 직접 `WCSession`을 다뤄야 한다.
public final class PhoneWatchSyncService: NSObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = PhoneWatchSyncService()

    private let stateLock = NSLock()
    private var dataStore: (any WatchSyncDataStore)?
    private var configuration = WatchSyncConfiguration.default
    private var logger: any WatchSyncLogger = PrintWatchSyncLogger()
    private var pendingPayload: Data?
    private var isActivationInProgress = false
    private var isActivationScheduled = false

    private override init() {
        super.init()
    }

    /// 앱 시작 시 저장소와 페이로드 키를 주입한다. Watch 쪽과 같은 `configuration`을 써야 한다.
    public func configure(
        dataStore: any WatchSyncDataStore,
        configuration: WatchSyncConfiguration = .default,
        logger: any WatchSyncLogger = PrintWatchSyncLogger()
    ) {
        stateLock.lock()
        self.dataStore = dataStore
        self.configuration = configuration
        self.logger = logger
        stateLock.unlock()
    }

    /// 포그라운드 진입 시 호출. 저장소 초기화와 겹치지 않게 짧게 미룬다.
    public func scheduleActivationAndPush() {
        guard WCSession.isSupported() else { return }

        if let data = currentStore()?.loadEncodedPayload(), !data.isEmpty {
            stateLock.lock()
            pendingPayload = data
            stateLock.unlock()
        }

        let session = WCSession.default
        if session.activationState == .activated {
            flushPendingIfPossible(session: session)
            return
        }

        stateLock.lock()
        let shouldSchedule = !isActivationScheduled && !isActivationInProgress
        if shouldSchedule { isActivationScheduled = true }
        let delay = configuration.activationDelay
        stateLock.unlock()
        guard shouldSchedule else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            self.isActivationScheduled = false
            self.stateLock.unlock()
            self.activateIfNeeded()
        }
    }

    /// 이미 인코딩된 페이로드를 Watch로 전송한다.
    public func pushEncodedPayload(_ data: Data) {
        guard WCSession.isSupported() else { return }
        guard currentCodec().dictionary(containing: data) != nil else { return }

        stateLock.lock()
        pendingPayload = data
        stateLock.unlock()

        let session = WCSession.default
        if session.activationState == .activated {
            flushPendingIfPossible(session: session)
        } else {
            scheduleActivationAndPush()
        }
    }

    public func pushStoredPayload() {
        guard let data = currentStore()?.loadEncodedPayload(), !data.isEmpty else { return }
        pushEncodedPayload(data)
    }

    // MARK: - Activation

    private func activateIfNeeded() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        session.delegate = self

        if session.activationState == .activated {
            flushPendingIfPossible(session: session)
            return
        }

        stateLock.lock()
        let shouldActivate = !isActivationInProgress
        if shouldActivate { isActivationInProgress = true }
        stateLock.unlock()
        guard shouldActivate else { return }

        log("⌚️ WCSession 활성화 요청")
        session.activate()
    }

    // MARK: - WCSessionDelegate

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        stateLock.lock()
        isActivationInProgress = false
        stateLock.unlock()

        if let error {
            log("⚠️ WCSession 활성화 실패: \(error.localizedDescription)")
            return
        }

        guard activationState == .activated else {
            log("⚠️ WCSession 활성화 상태=\(activationState.rawValue)")
            return
        }

        log("✅ WCSession 활성화 완료 — paired=\(session.isPaired), watchAppInstalled=\(session.isWatchAppInstalled), reachable=\(session.isReachable)")
        flushPendingIfPossible(session: session)
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        stateLock.lock()
        isActivationInProgress = false
        stateLock.unlock()
        scheduleActivationAndPush()
    }

    public func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.activationState == .activated else { return }
        log("⌚️ Watch 상태 변경 — paired=\(session.isPaired), installed=\(session.isWatchAppInstalled)")
        flushPendingIfPossible(session: session)
    }

    public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let codec = currentCodec()
        guard codec.isSyncRequest(message) else {
            replyHandler(codec.emptyReply())
            return
        }
        let payload: [String: Any]
        if let data = currentStore()?.loadEncodedPayload(),
           let context = codec.dictionary(containing: data) {
            payload = context
        } else {
            payload = codec.emptyReply()
        }
        log("⌚️ Watch sync 요청 응답 — keys=\(payload.keys.sorted())")
        replyHandler(payload)
    }

    // MARK: - Send

    private func flushPendingIfPossible(session: WCSession) {
        guard session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else {
            log("⚠️ Watch push 대기 — paired=\(session.isPaired), watchAppInstalled=\(session.isWatchAppInstalled)")
            return
        }

        stateLock.lock()
        let data = pendingPayload ?? currentStore()?.loadEncodedPayload()
        pendingPayload = nil
        stateLock.unlock()

        guard let data, !data.isEmpty else { return }
        sendPayload(data, session: session)
    }

    private func sendPayload(_ data: Data, session: WCSession) {
        let codec = currentCodec()
        guard let payload = codec.dictionary(containing: data) else {
            log("⚠️ Watch 전송 페이로드 생성 실패 (용량 초과 또는 빈 데이터, \(data.count) bytes)")
            return
        }

        do {
            try session.updateApplicationContext(payload)
            log("✅ Watch applicationContext 전송 (\(data.count) bytes)")
        } catch {
            log("⚠️ applicationContext 실패, transferUserInfo로 재시도: \(error.localizedDescription)")
            session.transferUserInfo(payload)
            log("✅ Watch transferUserInfo 큐잉")
        }
    }

    private func currentStore() -> (any WatchSyncDataStore)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        #if DEBUG
        if dataStore == nil {
            assertionFailure("PhoneWatchSyncService is not configured. Call configure(dataStore:) at launch.")
        }
        #endif
        return dataStore
    }

    private func currentCodec() -> WatchSyncCodec {
        stateLock.lock()
        let configuration = self.configuration
        stateLock.unlock()
        return WatchSyncCodec(configuration: configuration)
    }

    private func log(_ message: String) {
        stateLock.lock()
        let logger = self.logger
        stateLock.unlock()
        logger.log(message)
    }
}

#endif
