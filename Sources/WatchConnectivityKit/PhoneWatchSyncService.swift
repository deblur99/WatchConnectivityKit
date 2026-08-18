//
//  PhoneWatchSyncService.swift
//  WatchConnectivityKit
//

#if os(iOS)

import Foundation
import WatchConnectivity

/// Sends a binary payload from iPhone to Watch.
///
/// This module has no default actor isolation, so `WCSessionDelegate` is not
/// inferred as MainActor. Importing it from an app target (MainActor by default)
/// is safe across the module boundary.
///
/// This instance owns `WCSession.default.delegate`. If the app needs another
/// delegate, do not use this service; talk to `WCSession` directly.
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

    /// Injects the store and payload keys at launch. Watch must use the same `configuration`.
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

    /// Call when entering the foreground. Delays briefly so it does not overlap store setup.
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

    /// Sends an already encoded payload to Watch.
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

        log("⌚️ Requesting WCSession activation")
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
            log("⚠️ WCSession activation failed: \(error.localizedDescription)")
            return
        }

        guard activationState == .activated else {
            log("⚠️ WCSession activation state=\(activationState.rawValue)")
            return
        }

        log("✅ WCSession activated — paired=\(session.isPaired), watchAppInstalled=\(session.isWatchAppInstalled), reachable=\(session.isReachable)")
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
        log("⌚️ Watch state changed — paired=\(session.isPaired), installed=\(session.isWatchAppInstalled)")
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
        log("⌚️ Watch sync request reply — keys=\(payload.keys.sorted())")
        replyHandler(payload)
    }

    // MARK: - Send

    private func flushPendingIfPossible(session: WCSession) {
        guard session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else {
            log("⚠️ Watch push waiting — paired=\(session.isPaired), watchAppInstalled=\(session.isWatchAppInstalled)")
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
            log("⚠️ Failed to build Watch payload (over size limit or empty, \(data.count) bytes)")
            return
        }

        do {
            try session.updateApplicationContext(payload)
            log("✅ Sent Watch applicationContext (\(data.count) bytes)")
        } catch {
            log("⚠️ applicationContext failed, retrying with transferUserInfo: \(error.localizedDescription)")
            session.transferUserInfo(payload)
            log("✅ Queued Watch transferUserInfo")
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
