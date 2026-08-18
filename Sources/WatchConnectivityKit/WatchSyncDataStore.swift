//
//  WatchSyncDataStore.swift
//  WatchConnectivityKit
//

import Foundation

/// Local storage for the binary payload exchanged over WatchConnectivity.
///
/// Implement this in the app target with App Group, files, or an in-memory cache.
/// This module does not know about JSON schemas or domain models.
public protocol WatchSyncDataStore: Sendable {
    /// Stored payload, or `nil` if none.
    func loadEncodedPayload() -> Data?

    /// Saves a payload received from the companion or queued for send.
    @discardableResult
    func saveEncodedPayload(_ data: Data) -> Bool
}
