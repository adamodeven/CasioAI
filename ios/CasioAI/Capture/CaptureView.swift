import SwiftUI

struct CaptureView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let capture = environment.thoughtCapture

        NavigationStack {
            List {
                Section {
                    statusRow(for: capture.state)
                } header: {
                    Text("Status")
                }

                if !capture.recentCaptures.isEmpty {
                    Section("Recent") {
                        ForEach(capture.recentCaptures) { thought in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(thought.title)
                                    .font(.headline)
                                Text(thought.transcript)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(thought.date, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Capture")
            .overlay {
                if capture.recentCaptures.isEmpty && capture.state == .idle {
                    ContentUnavailableView(
                        "Press and hold the watch button",
                        systemImage: "mic.badge.plus",
                        description: Text("Speak your thought, release, and it lands in your Notion inbox with an AI-generated title.")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func statusRow(for state: ThoughtCaptureController.State) -> some View {
        HStack(spacing: 12) {
            statusIcon(for: state)
            Text(statusText(for: state))
                .font(.body.weight(.medium))
        }
        .padding(.vertical, 4)
    }

    private func statusIcon(for state: ThoughtCaptureController.State) -> some View {
        let (symbol, color): (String, Color) = switch state {
        case .idle: ("mic.slash", .secondary)
        case .listening: ("waveform", .red)
        case .transcribing: ("text.bubble", .blue)
        case .savingToNotion: ("arrow.up.doc", .blue)
        case .done: ("checkmark.circle.fill", .green)
        case .failed: ("exclamationmark.triangle.fill", .orange)
        }
        return Image(systemName: symbol)
            .foregroundStyle(color)
            .symbolEffect(.pulse, isActive: state == .listening)
    }

    private func statusText(for state: ThoughtCaptureController.State) -> String {
        switch state {
        case .idle: "Idle"
        case .listening: "Listening…"
        case .transcribing: "Transcribing on-device…"
        case .savingToNotion: "Saving to Notion…"
        case .done: "Saved"
        case .failed(let message): message
        }
    }
}
