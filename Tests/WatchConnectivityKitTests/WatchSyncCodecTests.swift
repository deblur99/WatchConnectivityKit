import Foundation
import Testing
@testable import WatchConnectivityKit

struct WatchSyncCodecTests {
    @Test func payloadRoundTrip() {
        let data = Data("payload-json".utf8)
        let codec = WatchSyncCodec()
        let payload = codec.dictionary(containing: data)
        #expect(payload != nil)
        #expect(codec.encodedPayload(from: payload!) == data)
    }

    @Test func emptyReplyMarksNoPayload() {
        let codec = WatchSyncCodec()
        let reply = codec.emptyReply()
        #expect(codec.encodedPayload(from: reply) == nil)
    }

    @Test func customKeysAreIsolatedFromDefaults() {
        let data = Data("custom".utf8)
        let custom = WatchSyncCodec(
            configuration: WatchSyncConfiguration(
                payloadKey: "myPayload",
                requestSyncKey: "myRequest",
                emptyKey: "myEmpty"
            )
        )
        let defaults = WatchSyncCodec()

        let payload = custom.dictionary(containing: data)!
        #expect(payload["myPayload"] as? Data == data)
        #expect(defaults.encodedPayload(from: payload) == nil)
        #expect(custom.encodedPayload(from: payload) == data)

        #expect(custom.isSyncRequest(["myRequest": true]))
        #expect(!defaults.isSyncRequest(["myRequest": true]))
        #expect(defaults.isSyncRequest(["requestSync": true]))
    }

    @Test func oversizedPayloadIsRejected() {
        let codec = WatchSyncCodec(
            configuration: WatchSyncConfiguration(maxPayloadBytes: 8)
        )
        #expect(codec.dictionary(containing: Data("123456789".utf8)) == nil)
        #expect(codec.dictionary(containing: Data("12345678".utf8)) != nil)
        #expect(codec.dictionary(containing: Data()) == nil)
    }
}

struct UserDefaultsWatchSyncStoreTests {
    @Test func roundTrip() {
        let defaults = UserDefaults(suiteName: "WatchConnectivityKit.tests.\(UUID().uuidString)")!
        let store = UserDefaultsWatchSyncStore(defaults: defaults, key: "payload")
        let data = Data("hello".utf8)

        #expect(store.loadEncodedPayload() == nil)
        #expect(store.saveEncodedPayload(data))
        #expect(store.loadEncodedPayload() == data)
        #expect(!store.saveEncodedPayload(Data()))
    }
}
