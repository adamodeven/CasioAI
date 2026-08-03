import SwiftUI

struct TalkView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let voice = environment.realtimeVoice

        NavigationStack {
            ZStack {
                Color.clear.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    transcriptCard(voice.liveTranscript)

                    Spacer()

                    GlassEffectContainer {
                        VStack(spacing: 16) {
                            statusPill(voice: voice)

                            talkButton(voice: voice)
                        }
                    }

                    if let error = voice.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle("Talk")
        }
    }

    @ViewBuilder
    private func transcriptCard(_ text: String) -> some View {
        if !text.isEmpty {
            ScrollView {
                Text(text)
                    .font(.title3)
                    .multilineTextAlignment(.leading)
                    .padding()
            }
            .frame(maxHeight: 240)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            Text("Press and hold the watch button, or tap below, to talk to Claude.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    private func statusPill(voice: RealtimeVoiceController) -> some View {
        Text(voice.isTalking ? "Listening…" : "Ready")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
    }

    private func talkButton(voice: RealtimeVoiceController) -> some View {
        Button {
            if voice.isTalking {
                voice.endTurnFromApp()
            } else {
                voice.beginTurnFromApp()
            }
        } label: {
            Image(systemName: voice.isTalking ? "waveform" : "mic.fill")
                .font(.system(size: 32, weight: .semibold))
                .frame(width: 96, height: 96)
        }
        .buttonStyle(.glassProminent)
        .clipShape(.circle)
        .symbolEffect(.variableColor.iterative, isActive: voice.isTalking)
    }
}
