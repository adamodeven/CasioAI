import CoreBluetooth
import Foundation

/// The custom GATT profile spoken between the phone app (central) and the
/// watch module (peripheral). This is the contract the Phase 2 firmware
/// must implement — UUIDs and payload layouts here are the source of truth
/// on both sides.
///
/// All multi-byte integers are little-endian. All UUIDs below are
/// provisional 128-bit UUIDs generated for this project; they only need to
/// match between firmware and app, not to be registered with the Bluetooth SIG.
enum WatchProtocol {

    /// Primary service advertised by the watch.
    static let serviceUUID = CBUUID(string: "6A58E000-0001-4000-8000-00805F9B34FB")

    enum Characteristic {
        /// Central -> Peripheral, write. Relays call state changes so the watch
        /// can show/vibrate for an incoming call, and answer/reject locally.
        /// Payload: `CallEvent` (1 byte state + up to 32 bytes UTF-8 caller name).
        static let callState = CBUUID(string: "6A58E000-0010-4000-8000-00805F9B34FB")

        /// Peripheral -> Central, notify. Watch button press requests an
        /// answer/reject action for the current call.
        /// Payload: 1 byte, `CallCommand` raw value.
        static let callCommand = CBUUID(string: "6A58E000-0011-4000-8000-00805F9B34FB")

        /// Peripheral -> Central, notify. Music transport command from the watch.
        /// Payload: 1 byte, `MusicCommand` raw value.
        static let musicCommand = CBUUID(string: "6A58E000-0020-4000-8000-00805F9B34FB")

        /// Central -> Peripheral, write, no response. Time/date sync.
        /// Payload: `TimeSync` (8 bytes: Int64 unix seconds, UTC) + 1 byte UTC offset
        /// in 15-minute increments (signed).
        static let timeSync = CBUUID(string: "6A58E000-0030-4000-8000-00805F9B34FB")

        /// Central -> Peripheral, write, no response. Daily hi/lo temperature.
        /// Payload: `TemperaturePush` (2 bytes: Int8 lo, Int8 hi, whole degrees F).
        static let temperature = CBUUID(string: "6A58E000-0031-4000-8000-00805F9B34FB")

        /// Peripheral -> Central, indicate. Button/gesture events (press-and-hold
        /// start/stop for thought capture, single press for voice Q&A, etc).
        /// Payload: 1 byte, `ButtonEvent` raw value.
        static let buttonEvent = CBUUID(string: "6A58E000-0040-4000-8000-00805F9B34FB")

        /// Peripheral -> Central, notify (streamed). Raw audio frames captured
        /// on the watch mic, sent in ~160-byte chunks while a capture session
        /// is open (started by a `.holdStart`/`.talkStart` ButtonEvent, ended by
        /// `.holdEnd`/`.talkEnd`). Codec/sample-rate: TBD in firmware phase,
        /// tracked as an open item — see AudioFrameHeader below for the
        /// negotiated format tag.
        static let audioStream = CBUUID(string: "6A58E000-0050-4000-8000-00805F9B34FB")

        /// Central -> Peripheral, write, no response. Battery/status poll
        /// response is read, not pushed; kept here for symmetry.
        /// Peripheral -> Central, read + notify. Payload: `WatchStatus`.
        static let status = CBUUID(string: "6A58E000-0060-4000-8000-00805F9B34FB")

        /// Central -> Peripheral, write, no response. Explicit hint for the
        /// firmware's connection-interval policy: the phone tells the watch
        /// when it's entering/leaving an active session (voice capture,
        /// incoming call, active music control) so firmware can request a
        /// tight interval only for that window and fall back to a loose one
        /// otherwise. This is the primary battery-life lever called out in
        /// the spec — the app is expected to write this promptly on every
        /// transition, not just at connect time.
        /// Payload: 1 byte, `SessionMode` raw value.
        static let sessionMode = CBUUID(string: "6A58E000-0070-4000-8000-00805F9B34FB")
    }

    enum SessionMode: UInt8 {
        case idle = 0
        case active = 1
    }

    enum CallState: UInt8 {
        case idle = 0
        case incoming = 1
        case active = 2
    }

    enum CallCommand: UInt8 {
        case answer = 0
        case reject = 1
    }

    enum MusicCommand: UInt8 {
        case playPause = 0
        case next = 1
        case previous = 2
        case volumeUp = 3
        case volumeDown = 4
    }

    enum ButtonEvent: UInt8 {
        /// Short press: start/stop a live voice Q&A turn.
        case talkStart = 0
        case talkEnd = 1
        /// Press-and-hold: thought capture.
        case holdStart = 2
        case holdEnd = 3
    }

    /// Bit flags packed into `WatchStatus.flags`.
    struct WatchStatusFlags: OptionSet {
        let rawValue: UInt8
        static let charging = WatchStatusFlags(rawValue: 1 << 0)
        static let lowBattery = WatchStatusFlags(rawValue: 1 << 1)
        static let alarmVibrate = WatchStatusFlags(rawValue: 1 << 2)
        static let alarmBeep = WatchStatusFlags(rawValue: 1 << 3)
    }

    struct WatchStatus {
        /// 0-100.
        let batteryPercent: UInt8
        let flags: WatchStatusFlags
        let firmwareVersion: UInt8

        init?(data: Data) {
            guard data.count >= 3 else { return nil }
            batteryPercent = data[data.startIndex]
            flags = WatchStatusFlags(rawValue: data[data.startIndex + 1])
            firmwareVersion = data[data.startIndex + 2]
        }
    }

    struct CallEvent {
        let state: CallState
        let callerName: String

        var encoded: Data {
            var data = Data([state.rawValue])
            let nameBytes = Array(callerName.utf8.prefix(32))
            data.append(contentsOf: nameBytes)
            return data
        }
    }

    struct TimeSync {
        let date: Date
        let utcOffsetMinutes: Int

        var encoded: Data {
            var data = Data()
            var seconds = Int64(date.timeIntervalSince1970).littleEndian
            withUnsafeBytes(of: &seconds) { data.append(contentsOf: $0) }
            let quarterHours = Int8(clamping: utcOffsetMinutes / 15)
            data.append(UInt8(bitPattern: quarterHours))
            return data
        }
    }

    struct TemperaturePush {
        let lowFahrenheit: Int
        let highFahrenheit: Int

        var encoded: Data {
            Data([
                UInt8(bitPattern: Int8(clamping: lowFahrenheit)),
                UInt8(bitPattern: Int8(clamping: highFahrenheit)),
            ])
        }
    }

    /// Prefixed onto every notified audio-stream packet so the firmware/app
    /// stay in sync on format even if it changes across firmware revisions.
    struct AudioFrameHeader {
        /// 0 = reserved, 1 = 16kHz mono 16-bit PCM (initial target — cheap for
        /// the MCU to produce, and both Speech and OpenAI Realtime accept it).
        static let formatPCM16Mono16k: UInt8 = 1
        let format: UInt8
        let sequence: UInt16
    }
}
