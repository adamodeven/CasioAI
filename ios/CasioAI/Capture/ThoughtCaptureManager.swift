import Speech
import AVFoundation

/// Wraps on-device speech recognition for a single capture session. Audio
/// arrives incrementally (from the watch, via BLE) and is fed straight into
/// `SFSpeechAudioBufferRecognitionRequest` so transcription is essentially
/// done by the time the user releases the button.
final class ThoughtCaptureManager {
    enum CaptureError: Error {
        case notAuthorized
        case recognizerUnavailable
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    private var latestTranscript = ""
    private var finalResultContinuation: CheckedContinuation<String, Never>?

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Begin a new capture session. Call `append` for each incoming audio
    /// chunk, then `finish()` to get the final transcript.
    func start() throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw CaptureError.notAuthorized
        }
        guard let recognizer, recognizer.isAvailable else {
            throw CaptureError.recognizerUnavailable
        }

        latestTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.latestTranscript = result.bestTranscription.formattedString
                if result.isFinal {
                    self.resolveFinalResult()
                }
            }
            if error != nil {
                self.resolveFinalResult()
            }
        }
    }

    func append(pcm16 data: Data) {
        guard let request, let buffer = makeBuffer(from: data) else { return }
        request.append(buffer)
    }

    /// Ends the audio stream and awaits the final transcription result.
    func finish() async -> String {
        request?.endAudio()
        return await withCheckedContinuation { continuation in
            self.finalResultContinuation = continuation
        }
    }

    private func resolveFinalResult() {
        finalResultContinuation?.resume(returning: latestTranscript)
        finalResultContinuation = nil
        task = nil
        request = nil
    }

    private func makeBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(data.count / 2)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let channelData = buffer.int16ChannelData else { return nil }
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            channelData[0].update(from: samples.baseAddress!, count: Int(frameCount))
        }
        return buffer
    }
}
