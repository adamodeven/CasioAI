import Foundation

/// Thin WebSocket wrapper around the OpenAI Realtime API for low-latency
/// spoken conversation. Session audio format is fixed to `pcm16` (24kHz
/// mono, matching the API's expectation); the watch's native 16kHz frames
/// are upsampled by AudioResampling before being appended here.
///
/// NOTE: the Realtime API's event schema has moved fast since launch. This
/// targets the GA `gpt-realtime` model and its documented session/event
/// names as of this writing — re-check field names against OpenAI's current
/// Realtime API reference before first run in case anything's shifted.
actor OpenAIRealtimeClient {

    enum Event {
        case connected
        case audioDelta(Data) // PCM16 @ 24kHz
        case transcriptDelta(String)
        case responseCompleted
        case error(String)
        case disconnected
    }

    private static let endpoint = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime")!
    private static let sampleRateHz: Double = 24_000

    private var task: URLSessionWebSocketTask?
    private var eventContinuation: AsyncStream<Event>.Continuation?

    func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    func connect(apiKey: String) {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        let webSocketTask = session.webSocketTask(with: request)
        task = webSocketTask
        webSocketTask.resume()

        configureSession()
        listen()
        eventContinuation?.yield(.connected)
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        eventContinuation?.yield(.disconnected)
        eventContinuation?.finish()
    }

    /// Append a chunk of watch mic audio (already resampled to 24kHz PCM16)
    /// to the server-side input buffer for the current turn.
    func appendInputAudio(pcm16At24kHz data: Data) {
        send([
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString(),
        ])
    }

    /// Call when the watch reports talk end: commit whatever's been
    /// buffered and ask the model for a spoken response. Turn detection is
    /// driven by the watch's press-and-release, not server VAD, since the
    /// hardware gesture is the more reliable signal here.
    func commitAndRespond() {
        send(["type": "input_audio_buffer.commit"])
        send([
            "type": "response.create",
            "response": ["modalities": ["audio", "text"]],
        ])
    }

    /// Cancel any in-flight response, e.g. if the user starts a new talk
    /// turn before the previous one finished playing.
    func cancelResponse() {
        send(["type": "response.cancel"])
    }

    private func configureSession() {
        send([
            "type": "session.update",
            "session": [
                "modalities": ["audio", "text"],
                "voice": "alloy",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                // Manual turn-taking: the watch button, not server VAD, marks
                // when a turn starts/ends.
                "turn_detection": NSNull(),
                "instructions": "You are a quick, concise voice assistant on a smartwatch companion app. Keep answers short — a sentence or two — unless asked for more detail.",
            ],
        ])
    }

    private func send(_ payload: [String: Any]) {
        guard let task, JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        task.send(.data(data)) { [weak self] error in
            if let error {
                self?.eventContinuation?.yield(.error(error.localizedDescription))
            }
        }
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                Task { await self.handleError(error) }
            case .success(let message):
                Task { await self.handleMessage(message) }
                Task { await self.listenAgain() }
            }
        }
    }

    private func listenAgain() {
        listen()
    }

    private func handleError(_ error: Error) {
        eventContinuation?.yield(.error(error.localizedDescription))
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let raw): data = raw
        case .string(let text): data = Data(text.utf8)
        @unknown default: return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "response.audio.delta":
            if let base64 = json["delta"] as? String, let audio = Data(base64Encoded: base64) {
                eventContinuation?.yield(.audioDelta(audio))
            }
        case "response.audio_transcript.delta":
            if let delta = json["delta"] as? String {
                eventContinuation?.yield(.transcriptDelta(delta))
            }
        case "response.done":
            eventContinuation?.yield(.responseCompleted)
        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown Realtime API error"
            eventContinuation?.yield(.error(message))
        default:
            break
        }
    }

    static var targetSampleRateHz: Double { sampleRateHz }
}
