import Testing
import Foundation
import SwiftProtobuf
@testable import GoogleTVKit

@Suite struct ProtobufTests {
    @Test func pairingRequestRoundTrip() throws {
        var msg = Polo_Wire_Protobuf_OuterMessage()
        msg.protocolVersion = 2
        msg.status = .ok
        msg.pairingRequest.serviceName = "atvremote"
        msg.pairingRequest.clientName = "iPhone"
        let decoded = try Polo_Wire_Protobuf_OuterMessage(serializedBytes: try msg.serializedData())
        #expect(decoded == msg)
        #expect(decoded.pairingRequest.serviceName == "atvremote")
    }

    @Test func optionsAndConfigurationRoundTrip() throws {
        var enc = Polo_Wire_Protobuf_Options.Encoding()
        enc.type = .hexadecimal
        enc.symbolLength = 6
        var msg = Polo_Wire_Protobuf_OuterMessage()
        msg.protocolVersion = 2
        msg.status = .ok
        msg.options.inputEncodings = [enc]
        msg.options.preferredRole = .input
        msg.configuration.encoding = enc
        msg.configuration.clientRole = .input
        #expect(try Polo_Wire_Protobuf_OuterMessage(serializedBytes: try msg.serializedData()) == msg)
    }

    @Test func keyInjectWireFormat() throws {
        var msg = Remote_RemoteMessage()
        msg.remoteKeyInject.keyCode = TVKey.dpadCenter.protoKeyCode
        msg.remoteKeyInject.direction = KeyDirection.short.proto
        // field 10 (len-delimited) { key_code=23, direction=3 }
        #expect([UInt8](try msg.serializedData()) == [0x52, 0x04, 0x08, 0x17, 0x10, 0x03])
    }

    @Test func pingResponseRoundTrip() throws {
        var req = Remote_RemoteMessage()
        req.remotePingRequest.val1 = 42
        let parsed = try Remote_RemoteMessage(serializedBytes: try req.serializedData())
        var resp = Remote_RemoteMessage()
        resp.remotePingResponse.val1 = parsed.remotePingRequest.val1
        #expect(try Remote_RemoteMessage(serializedBytes: try resp.serializedData()).remotePingResponse.val1 == 42)
    }

    @Test func volumeAndStartParse() throws {
        var m = Remote_RemoteMessage()
        m.remoteSetVolumeLevel.volumeLevel = 12
        m.remoteSetVolumeLevel.volumeMax = 100
        m.remoteSetVolumeLevel.volumeMuted = true
        let p = try Remote_RemoteMessage(serializedBytes: try m.serializedData())
        #expect(p.remoteSetVolumeLevel.volumeLevel == 12 && p.remoteSetVolumeLevel.volumeMuted)
        var s = Remote_RemoteMessage()
        s.remoteStart.started = true
        #expect(try Remote_RemoteMessage(serializedBytes: try s.serializedData()).remoteStart.started)
    }

    @Test func framedMessageThroughDecoder() throws {
        var m = Remote_RemoteMessage()
        m.remoteAppLinkLaunchRequest.appLink = "https://www.netflix.com/title"
        var dec = FrameDecoder()
        dec.append(VarintFraming.frame(try m.serializedData()))
        let frame = try #require(try dec.nextFrame())
        #expect(try Remote_RemoteMessage(serializedBytes: frame) == m)
    }
}
