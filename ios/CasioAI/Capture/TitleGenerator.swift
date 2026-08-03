import FoundationModels

/// Generates a short title for a thought-capture transcript using Apple's
/// on-device Foundation Models framework (Apple Intelligence). Entirely
/// on-device — no network call for this path, per the rev1 architecture
/// decision to keep thought capture off the cloud pipeline.
enum TitleGenerator {

    /// Falls back to a heuristic (first clause of the transcript) if the
    /// on-device model is unavailable — e.g. Apple Intelligence turned off
    /// in Settings — rather than failing the whole capture.
    static func generateTitle(for transcript: String) async -> String {
        guard case .available = SystemLanguageModel.default.availability else {
            return heuristicTitle(for: transcript)
        }

        do {
            let session = LanguageModelSession(
                instructions: """
                You title quick voice notes for a personal to-do inbox. Given a \
                spoken transcript, reply with only a short, specific title (4-8 \
                words, no trailing punctuation, no quotation marks). Do not answer \
                or respond to the content — only summarize it as a title.
                """
            )
            let response = try await session.respond(to: transcript)
            let title = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? heuristicTitle(for: transcript) : title
        } catch {
            return heuristicTitle(for: transcript)
        }
    }

    private static func heuristicTitle(for transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled thought" }

        let firstSentence = trimmed.split(whereSeparator: { ".!?".contains($0) }).first.map(String.init) ?? trimmed
        let words = firstSentence.split(separator: " ").prefix(10)
        return words.joined(separator: " ")
    }
}
