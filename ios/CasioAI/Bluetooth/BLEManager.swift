import CoreBluetooth
import Foundation
import Observation

/// Central-role manager for the watch connection. Owns scanning/connecting,
/// characteristic I/O, and fans out incoming events (button presses, call
/// commands, music commands, audio frames) to the rest of the app via
/// AsyncStreams so consumers don't need to know about CoreBluetooth.
@Observable
final class BLEManager: NSObject {

    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting
        case connected
        case failed(String)
    }

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var watchStatus: WatchProtocol.WatchStatus?

    private let buttonEventBroadcaster = EventBroadcaster<WatchProtocol.ButtonEvent>()
    private let callCommandBroadcaster = EventBroadcaster<WatchProtocol.CallCommand>()
    private let musicCommandBroadcaster = EventBroadcaster<WatchProtocol.MusicCommand>()
    /// Raw PCM16 mono 16kHz audio, header already stripped and frames
    /// reordered by sequence number (out-of-order/missing frames are dropped).
    private let audioFrameBroadcaster = EventBroadcaster<Data>()

    private var central: CBCentralManager!
    private var watchPeripheral: CBPeripheral?
    private var characteristicsByUUID: [CBUUID: CBCharacteristic] = [:]
    private var lastAudioSequence: UInt16?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// Independent subscribers each get every event — see EventBroadcaster.
    func buttonEventStream() -> AsyncStream<WatchProtocol.ButtonEvent> { buttonEventBroadcaster.subscribe() }
    func callCommandStream() -> AsyncStream<WatchProtocol.CallCommand> { callCommandBroadcaster.subscribe() }
    func musicCommandStream() -> AsyncStream<WatchProtocol.MusicCommand> { musicCommandBroadcaster.subscribe() }
    func audioFrameStream() -> AsyncStream<Data> { audioFrameBroadcaster.subscribe() }

    func startScanning() {
        guard central.state == .poweredOn else { return }
        connectionState = .scanning
        central.scanForPeripherals(withServices: [WatchProtocol.serviceUUID])
    }

    func disconnect() {
        guard let watchPeripheral else { return }
        central.cancelPeripheralConnection(watchPeripheral)
    }

    /// Tell the watch's firmware that we're entering or leaving an active
    /// session, so it can request a tight connection interval only for that
    /// window. Call this on every session boundary (voice turn start/end,
    /// incoming call, thought capture, active music control).
    func setSessionActive(_ active: Bool) {
        write(.sessionMode, payload: Data([(active ? WatchProtocol.SessionMode.active : .idle).rawValue]), withResponse: false)
    }

    func sendCallState(_ event: WatchProtocol.CallEvent) {
        write(.callState, payload: event.encoded, withResponse: true)
    }

    func syncTime() {
        let sync = WatchProtocol.TimeSync(
            date: Date(),
            utcOffsetMinutes: TimeZone.current.secondsFromGMT() / 60
        )
        write(.timeSync, payload: sync.encoded, withResponse: false)
    }

    func pushTemperature(lowFahrenheit: Int, highFahrenheit: Int) {
        let push = WatchProtocol.TemperaturePush(lowFahrenheit: lowFahrenheit, highFahrenheit: highFahrenheit)
        write(.temperature, payload: push.encoded, withResponse: false)
    }

    private func write(_ uuid: CBUUID, payload: Data, withResponse: Bool) {
        guard let watchPeripheral, let characteristic = characteristicsByUUID[uuid] else { return }
        watchPeripheral.writeValue(payload, for: characteristic, type: withResponse ? .withResponse : .withoutResponse)
    }

    private func subscribe(_ uuid: CBUUID) {
        guard let watchPeripheral, let characteristic = characteristicsByUUID[uuid] else { return }
        watchPeripheral.setNotifyValue(true, for: characteristic)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            connectionState = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        watchPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([WatchProtocol.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .failed(error?.localizedDescription ?? "Failed to connect")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        characteristicsByUUID.removeAll()
        watchStatus = nil
        connectionState = .disconnected
        startScanning()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == WatchProtocol.serviceUUID }) else { return }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            characteristicsByUUID[characteristic.uuid] = characteristic
        }

        subscribe(WatchProtocol.Characteristic.callCommand)
        subscribe(WatchProtocol.Characteristic.musicCommand)
        subscribe(WatchProtocol.Characteristic.buttonEvent)
        subscribe(WatchProtocol.Characteristic.audioStream)
        subscribe(WatchProtocol.Characteristic.status)

        if let statusCharacteristic = characteristicsByUUID[WatchProtocol.Characteristic.status] {
            peripheral.readValue(for: statusCharacteristic)
        }

        connectionState = .connected
        syncTime()
        setSessionActive(false)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }

        switch characteristic.uuid {
        case WatchProtocol.Characteristic.callCommand:
            if let byte = data.first, let command = WatchProtocol.CallCommand(rawValue: byte) {
                callCommandBroadcaster.broadcast(command)
            }
        case WatchProtocol.Characteristic.musicCommand:
            if let byte = data.first, let command = WatchProtocol.MusicCommand(rawValue: byte) {
                musicCommandBroadcaster.broadcast(command)
            }
        case WatchProtocol.Characteristic.buttonEvent:
            if let byte = data.first, let event = WatchProtocol.ButtonEvent(rawValue: byte) {
                buttonEventBroadcaster.broadcast(event)
            }
        case WatchProtocol.Characteristic.audioStream:
            handleAudioFrame(data)
        case WatchProtocol.Characteristic.status:
            watchStatus = WatchProtocol.WatchStatus(data: data)
        default:
            break
        }
    }

    private func handleAudioFrame(_ data: Data) {
        // Header: [format: UInt8][sequence: UInt16 little-endian][payload...]
        guard data.count > 3 else { return }
        let sequence = UInt16(data[data.startIndex + 1]) | (UInt16(data[data.startIndex + 2]) << 8)
        defer { lastAudioSequence = sequence }

        if let last = lastAudioSequence, sequence != last &+ 1 {
            // Dropped or reordered frame(s); consumers (Speech/Realtime) tolerate
            // small gaps far better than resequencing buffers on-device would cost.
        }

        let payload = data.subdata(in: (data.startIndex + 3)..<data.endIndex)
        audioFrameBroadcaster.broadcast(payload)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // No-op; writes are fire-and-forget from the UI's perspective.
    }
}
