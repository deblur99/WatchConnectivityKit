//
//  WatchCompanionSyncService.swift
//  WatchConnectivityKit
//

#if os(watchOS)

import Foundation
import WatchConnectivity

/// iPhone companion으로부터 페이로드를 받아 로컬 저장소에 저장한다.
///
/// `WCSession.default.delegate`를 이 인스턴스가 소유한다.
public final class WatchCompanionSyncService: NSObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = WatchCompanionSyncService()

    private let stateLock = NSLock()
    private var dataStore: (any WatchSyncDataStore)?
    private var configuration = WatchSyncConfiguration.default
    private var logger: any WatchSyncLogger = PrintWatchSyncLogger()
    private var payloadUpdatedHandler: (@MainActor @Sendable () -> Void)?
    private var activationContinuations: [CheckedContinuation<Bool, Never>] = []

    /// Watch UI 갱신용. MainActor에서만 실행된다.
    public var onPayloadUpdated: (@MainActor @Sendable () -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return payloadUpdatedHandler
        }
        set {
            stateLock.lock()
            payloadUpdatedHandler = newValue
            stateLock.unlock()
        }
    }

    private override init() {
        super.init()
    }

    /// 앱 시작 시 저장소와 페이로드 키를 주입한다. iPhone 쪽과 같은 `configuration`을 써야 한다.
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

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .notActivated {
            session.activate()
            log("⌚️ Watch WCSession 활성화 요청")
        }
    }

    public func waitUntilActivated(timeoutNanoseconds: UInt64 = 3_000_000_000) async -> Bool {
        let session = WCSession.default
        if session.activationState == .activated { return true }

        activate()

        return await withCheckedContinuation { continuation in
            stateLock.lock()
            activationContinuations.append(continuation)
            stateLock.unlock()

            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                resumeActivationWaiters(success: WCSession.default.activationState == .activated)
            }
        }
    }

    public func requestSyncFromCompanion() async {
        let activated = await waitUntilActivated()
        guard activated else {
            log("⚠️ Watch WCSession 활성화 타임아웃")
            return
        }

        guard WatchCompanionAvailability.isPairedCompanionAvailable else {
            log("⚠️ companion 앱 미설치 — WatchConnectivity 동기화 생략")
            return
        }

        let session = WCSession.default

        if let context = receivedContext(from: session), applyPayloadIfNeeded(context) {
            log("✅ receivedApplicationContext에서 페이로드 적용")
            notifyPayloadUpdated()
            return
        }

        guard session.isReachable else {
            log("⚠️ iPhone unreachable — applicationContext도 비어 있음")
            return
        }

        log("⌚️ iPhone에 sendMessage로 페이로드 요청")
        let request = currentCodec().syncRequest()
        await withCheckedContinuation { continuation in
            session.sendMessage(request, replyHandler: { [weak self] reply in
                guard let self else {
                    continuation.resume()
                    return
                }
                if self.applyPayloadIfNeeded(reply) {
                    log("✅ sendMessage 응답으로 페이로드 적용")
                    self.notifyPayloadUpdated()
                } else {
                    log("⚠️ sendMessage 응답에 페이로드 없음 — keys=\(reply.keys.sorted())")
                }
                continuation.resume()
            }, errorHandler: { [weak self] error in
                self?.log("⚠️ iPhone 동기화 요청 실패: \(error.localizedDescription)")
                continuation.resume()
            })
        }
    }

    // MARK: - WCSessionDelegate

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            log("⚠️ Watch WCSession 활성화 실패: \(error.localizedDescription)")
            resumeActivationWaiters(success: false)
            return
        }

        let ok = activationState == .activated
        log("✅ Watch WCSession 활성화 완료 (companionInstalled=\(session.isCompanionAppInstalled), reachable=\(session.isReachable))")
        resumeActivationWaiters(success: ok)

        guard ok else { return }
        if let context = receivedContext(from: session), applyPayloadIfNeeded(context) {
            log("✅ 활성화 직후 applicationContext 페이로드 적용")
            notifyPayloadUpdated()
        }
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard !applicationContext.isEmpty else { return }
        if applyPayloadIfNeeded(applicationContext) {
            log("✅ didReceiveApplicationContext 페이로드 적용")
            notifyPayloadUpdated()
        }
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard !userInfo.isEmpty else { return }
        if applyPayloadIfNeeded(userInfo) {
            log("✅ didReceiveUserInfo 페이로드 적용")
            notifyPayloadUpdated()
        }
    }

    // MARK: - Private

    @discardableResult
    private func applyPayloadIfNeeded(_ payload: [String: Any]) -> Bool {
        guard let data = currentCodec().encodedPayload(from: payload), !data.isEmpty else { return false }
        return currentStore()?.saveEncodedPayload(data) == true
    }

    private func receivedContext(from session: WCSession) -> [String: Any]? {
        guard session.activationState == .activated else { return nil }
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return nil }
        return context
    }

    private func notifyPayloadUpdated() {
        let handler: (@MainActor @Sendable () -> Void)?
        stateLock.lock()
        handler = payloadUpdatedHandler
        stateLock.unlock()
        guard let handler else { return }
        Task { @MainActor in
            handler()
        }
    }

    private func resumeActivationWaiters(success: Bool) {
        stateLock.lock()
        let waiters = activationContinuations
        activationContinuations.removeAll()
        stateLock.unlock()
        waiters.forEach { $0.resume(returning: success) }
    }

    private func currentStore() -> (any WatchSyncDataStore)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        #if DEBUG
        if dataStore == nil {
            assertionFailure("WatchCompanionSyncService is not configured. Call configure(dataStore:) at launch.")
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
