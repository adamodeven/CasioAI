import AVFoundation

/// Streams incoming PCM16 24kHz mono audio (Realtime API responses) out
/// through the phone's current audio route — speaker or a connected
/// Bluetooth headset — via a standard AVAudioEngine player node. Buffers are
/// scheduled as they arrive so playback starts before the full response has
/// finished generating.
final class AudioPlaybackEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat

    init(sampleRateHz: Double) {
        format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRateHz, channels: 1, interleaved: true)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
        try session.setActive(true)
        try engine.start()
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func enqueue(pcm16 data: Data) {
        guard let buffer = makeBuffer(from: data) else { return }
        player.scheduleBuffer(buffer)
    }

    private func makeBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(data.count / 2)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        guard let channelData = buffer.int16ChannelData else { return nil }
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            channelData[0].update(from: samples.baseAddress!, count: Int(frameCount))
        }
        return buffer
    }
}
