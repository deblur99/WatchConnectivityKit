//
//  WatchCompanionSyncService.swift
//  WatchConnectivityKit
//

#if os(watchOS)

import Foundation
import WatchConnectivity

/// Receives a payload from the iPhone companion and writes it to local storage.
///
/// This instance owns `WCSession.default.delegate`.
public final class WatchCompanionSyncService: NSObject, WCSessionDelegate, @unchecked Sendable {
    public static let shared = WatchCompanionSyncService()

    private let stateLock = NSLock()
    private var dataStore: (any WatchSyncDataStore)?
    private var configuration = WatchSyncConfiguration.default
    private var logger: any WatchSyncLogger = PrintWatchSyncLogger()
    private var payloadUpdatedHandler: (@MainActor @Sendable () -> Void)?
    private var activationContinuations: [CheckedContinuation<Bool, Never>] = []

    /// Reloads Watch UI. Runs on the MainActor only.
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

    /// Injects the store and payload keys at launch. iPhone must use the same `configuration`.
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
            log("⌚️ Requesting Watch WCSession activation")
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
            log("⚠️ Watch WCSession activation timed out")
            return
        }

        guard WatchCompanionAvailability.isPairedCompanionAvailable else {
            log("⚠️ Companion app is not installed — skipping WatchConnectivity sync")
            return
        }

        let session = WCSession.default

        if let context = receivedContext(from: session), applyPayloadIfNeeded(context) {
            log("✅ Applied payload from receivedApplicationContext")
            notifyPayloadUpdated()
            return
        }

        guard session.isReachable else {
            log("⚠️ iPhone unreachable — applicationContext is also empty")
            return
        }

        log("⌚️ Requesting payload from iPhone via sendMessage")
        let request = currentCodec().syncRequest()
        await withCheckedContinuation { continuation in
            session.sendMessage(request, replyHandler: { [weak self] reply in
                guard let self else {
                    continuation.resume()
                    return
                }
                if self.applyPayloadIfNeeded(reply) {
                    log("✅ Applied payload from sendMessage reply")
                    self.notifyPayloadUpdated()
                } else {
                    log("⚠️ sendMessage reply has no payload — keys=\(reply.keys.sorted())")
                }
                continuation.resume()
            }, errorHandler: { [weak self] error in
                self?.log("⚠️ iPhone sync request failed: \(error.localizedDescription)")
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
            log("⚠️ Watch WCSession activation failed: \(error.localizedDescription)")
            resumeActivationWaiters(success: false)
            return
        }

        let ok = activationState == .activated
        log("✅ Watch WCSession activated (companionInstalled=\(session.isCompanionAppInstalled), reachable=\(session.isReachable))")
        resumeActivationWaiters(success: ok)

        guard ok else { return }
        if let context = receivedContext(from: session), applyPayloadIfNeeded(context) {
            log("✅ Applied applicationContext payload right after activation")
            notifyPayloadUpdated()
        }
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard !applicationContext.isEmpty else { return }
        if applyPayloadIfNeeded(applicationContext) {
            log("✅ Applied payload from didReceiveApplicationContext")
            notifyPayloadUpdated()
        }
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard !userInfo.isEmpty else { return }
        if applyPayloadIfNeeded(userInfo) {
            log("✅ Applied payload from didReceiveUserInfo")
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
