import Foundation
import Observation

/// Orchestrates a live voice Q&A turn: watch button press starts it, watch
/// mic audio streams in over BLE, OpenAI Realtime streams a spoken response
/// back out through the phone's speaker/connected BT audio.
@Observable
final class RealtimeVoiceController {
    private let settings: SettingsStore
    private let ble: BLEManager
    private let client = OpenAIRealtimeClient()
    private var playback: AudioPlaybackEngine?

    private(set) var isConnected = false
    private(set) var isTalking = false
    private(set) var liveTranscript = ""
    private(set) var lastError: String?

    private var buttonListenerTask: Task<Void, Never>?
    private var eventListenerTask: Task<Void, Never>?
    private var audioForwardTask: Task<Void, Never>?

    init(settings: SettingsStore, ble: BLEManager) {
        self.settings = settings
        self.ble = ble
        observeButtonEvents()
    }

    /// Manual trigger for the in-app "Talk" button, mirroring what a watch
    /// button press would do — useful for testing without firmware attached.
    func beginTurnFromApp() {
        Task { await startTurn() }
    }

    func endTurnFromApp() {
        Task { await endTurn() }
    }

    private func observeButtonEvents() {
        buttonListenerTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.ble.buttonEventStream() {
                switch event {
                case .talkStart:
                    await self.startTurn()
                case .talkEnd:
                    await self.endTurn()
                case .holdStart, .holdEnd:
                    break // Owned by ThoughtCaptureController.
                }
            }
        }
    }

    private func startTurn() async {
        guard !isTalking else { return }
        guard settings.isOpenAIConfigured else {
            lastError = "Add an OpenAI API key in Settings before starting a voice conversation."
            return
        }

        lastError = nil
        liveTranscript = ""

        if !isConnected {
            await client.connect(apiKey: settings.openAIAPIKey)
            isConnected = true
            startEventListener()
        }

        ble.setSessionActive(true)
        isTalking = true

        do {
            let engine = AudioPlaybackEngine(sampleRateHz: OpenAIRealtimeClient.targetSampleRateHz)
            try engine.start()
            playback = engine
        } catch {
            lastError = "Couldn't start audio playback: \(error.localizedDescription)"
        }

        audioForwardTask = Task { [weak self] in
            guard let self else { return }
            for await frame in self.ble.audioFrameStream() {
                if Task.isCancelled { break }
                let resampled = AudioResampling.resample(pcm16: frame, fromHz: 16_000, toHz: OpenAIRealtimeClient.targetSampleRateHz)
                await self.client.appendInputAudio(pcm16At24kHz: resampled)
            }
        }
    }

    private func endTurn() async {
        guard isTalking else { return }
        isTalking = false
        audioForwardTask?.cancel()
        audioForwardTask = nil
        await client.commitAndRespond()
        ble.setSessionActive(false)
    }

    private func startEventListener() {
        eventListenerTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.client.events() {
                self.handle(event)
            }
        }
    }

    private func handle(_ event: OpenAIRealtimeClient.Event) {
        switch event {
        case .connected:
            break
        case .audioDelta(let data):
            playback?.enqueue(pcm16: data)
        case .transcriptDelta(let text):
            liveTranscript += text
        case .responseCompleted:
            break
        case .error(let message):
            lastError = message
        case .disconnected:
            isConnected = false
            playback?.stop()
            playback = nil
        }
    }
}
