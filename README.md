# WatchConnectivityKit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A Swift package for syncing a binary payload between an iPhone app and its watchOS companion over WatchConnectivity.

The package does not know about your domain model. You inject a store and the dictionary keys used on the wire.

The Swift module cannot be named `WatchConnectivity` because that is Apple’s framework. `import WatchConnectivity` must keep referring to `WCSession`.

This package owns `WCSession.default.delegate`. If the app needs other WatchConnectivity features, do not use these services; talk to `WCSession` directly.

## Requirements

- iOS 15+
- watchOS 9+
- macOS 13+ (codec and store unit tests only; the WatchConnectivity services compile on iOS and watchOS)
- Swift 6

## Installation

Add the package in Xcode (**File → Add Package Dependencies**) or in `Package.swift`:

```swift
.package(url: "https://github.com/deblur99/WatchConnectivityKit.git", from: "1.0.0")
```

Link `WatchConnectivityKit` to **both** the iOS app target and the watchOS app target.

## Usage

### 1. Provide a store

Payloads are `Data`. For App Group `UserDefaults`, use `UserDefaultsWatchSyncStore`:

```swift
import WatchConnectivityKit

let store = UserDefaultsWatchSyncStore(
    suiteName: "group.com.example.app",
    key: "watchPayload"
)
```

If you need to filter or decode a domain model, implement `WatchSyncDataStore` yourself.

### 2. Use the same configuration on iPhone and Watch

Both sides must use the same keys. Keep existing keys if you already shipped a payload format.

```swift
let configuration = WatchSyncConfiguration(
    payloadKey: "payload",
    requestSyncKey: "requestSync",
    emptyKey: "empty"
)
```

### 3. iPhone

```swift
#if os(iOS)
PhoneWatchSyncService.shared.configure(
    dataStore: store,
    configuration: configuration
)

func applicationDidBecomeActive(_ application: UIApplication) {
    PhoneWatchSyncService.shared.scheduleActivationAndPush()
}

func publish(_ data: Data) {
    PhoneWatchSyncService.shared.pushEncodedPayload(data)
}
#endif
```

### 4. Watch

```swift
#if os(watchOS)
WatchCompanionSyncService.shared.configure(
    dataStore: store,
    configuration: configuration
)
WatchCompanionSyncService.shared.activate()
WatchCompanionSyncService.shared.onPayloadUpdated = {
    // Reload UI
}

await WatchCompanionSyncService.shared.requestSyncFromCompanion()
#endif
```

Use `WatchCompanionAvailability.isPairedCompanionAvailable` to see whether the iPhone companion is present. The value is valid only after `WCSession` has activated.

## License

MIT. See [LICENSE](LICENSE).
