import Foundation
import Observation

/// Orchestrates press-and-hold thought capture: buffers watch mic audio
/// while the button is held, transcribes and titles it entirely on-device
/// once released, then files it in Notion.
@Observable
final class ThoughtCaptureController {

    enum State: Equatable {
        case idle
        case listening
        case transcribing
        case savingToNotion
        case done
        case failed(String)
    }

    struct CapturedThought: Identifiable {
        let id = UUID()
        let title: String
        let transcript: String
        let date: Date
        let notionURL: URL?
    }

    private let ble: BLEManager
    private let notion: NotionClient
    private let manager = ThoughtCaptureManager()

    private(set) var state: State = .idle
    private(set) var recentCaptures: [CapturedThought] = []

    private var buttonListenerTask: Task<Void, Never>?
    private var audioForwardTask: Task<Void, Never>?

    init(ble: BLEManager, notion: NotionClient) {
        self.ble = ble
        self.notion = notion
        observeButtonEvents()
        Task { _ = await ThoughtCaptureManager.requestAuthorization() }
    }

    private func observeButtonEvents() {
        buttonListenerTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.ble.buttonEventStream() {
                switch event {
                case .holdStart:
                    await self.beginCapture()
                case .holdEnd:
                    await self.endCapture()
                case .talkStart, .talkEnd:
                    break // Owned by RealtimeVoiceController.
                }
            }
        }
    }

    private func beginCapture() async {
        guard state == .idle else { return }

        do {
            try manager.start()
        } catch ThoughtCaptureManager.CaptureError.notAuthorized {
            state = .failed("Enable Speech Recognition for CasioAI in iOS Settings.")
            return
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        ble.setSessionActive(true)
        state = .listening

        audioForwardTask = Task { [weak self] in
            guard let self else { return }
            for await frame in self.ble.audioFrameStream() {
                if Task.isCancelled { break }
                self.manager.append(pcm16: frame)
            }
        }
    }

    private func endCapture() async {
        guard state == .listening else { return }
        audioForwardTask?.cancel()
        audioForwardTask = nil
        ble.setSessionActive(false)
        state = .transcribing

        let transcript = await manager.finish()
        guard !transcript.isEmpty else {
            state = .idle
            return
        }

        let title = await TitleGenerator.generateTitle(for: transcript)

        state = .savingToNotion
        do {
            let url = try await notion.createInboxPage(title: title, body: transcript)
            recentCaptures.insert(
                CapturedThought(title: title, transcript: transcript, date: Date(), notionURL: url),
                at: 0
            )
            state = .done
        } catch {
            state = .failed(error.localizedDescription)
        }

        try? await Task.sleep(for: .seconds(2))
        state = .idle
    }
}
