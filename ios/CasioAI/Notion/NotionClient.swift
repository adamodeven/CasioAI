import Foundation

/// Creates thought-capture pages in the user's configured Notion database.
/// The database's title-property name is discovered from its schema rather
/// than assumed to be "Name", since that's user-defined per database.
final class NotionClient {
    struct NotionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let settings: SettingsStore
    private let notionVersion = "2022-06-28"
    private var cachedTitleProperty: (databaseID: String, propertyName: String)?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    @discardableResult
    func createInboxPage(title: String, body: String) async throws -> URL? {
        guard settings.isNotionConfigured else {
            throw NotionError(message: "Notion isn't configured yet — add a token and database in Settings.")
        }

        let databaseID = settings.notionDatabaseID
        let titleProperty = try await titlePropertyName(for: databaseID)

        let payload: [String: Any] = [
            "parent": ["database_id": databaseID],
            "properties": [
                titleProperty: [
                    "title": [["text": ["content": String(title.prefix(2000))]]]
                ]
            ],
            "children": paragraphBlocks(for: body),
        ]

        let request = try makeRequest(path: "pages", method: "POST", body: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let urlString = json["url"] as? String
        else { return nil }
        return URL(string: urlString)
    }

    /// Fetches the database schema to resolve the display name once, then
    /// caches it so Settings can show something friendlier than a raw ID.
    func resolveDatabaseDisplayName(for databaseID: String) async throws -> String {
        let request = try makeRequest(path: "databases/\(databaseID)", method: "GET", body: nil)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let titleArray = json["title"] as? [[String: Any]]
        else {
            throw NotionError(message: "Couldn't read the Notion database.")
        }
        let plain = titleArray.compactMap { $0["plain_text"] as? String }.joined()
        return plain.isEmpty ? "Untitled database" : plain
    }

    private func titlePropertyName(for databaseID: String) async throws -> String {
        if let cached = cachedTitleProperty, cached.databaseID == databaseID {
            return cached.propertyName
        }

        let request = try makeRequest(path: "databases/\(databaseID)", method: "GET", body: nil)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let properties = json["properties"] as? [String: Any]
        else {
            throw NotionError(message: "Couldn't read the Notion database schema.")
        }

        for (name, definition) in properties {
            if let dict = definition as? [String: Any], dict["type"] as? String == "title" {
                cachedTitleProperty = (databaseID, name)
                return name
            }
        }

        throw NotionError(message: "Couldn't find a title property on the configured Notion database.")
    }

    private func paragraphBlocks(for body: String) -> [[String: Any]] {
        // Notion caps rich_text content at 2000 characters per block and
        // 100 children per create-page request; long transcripts are split
        // across multiple paragraph blocks and truncated at that cap.
        let chunkSize = 2000
        var blocks: [[String: Any]] = []
        var remaining = Substring(body)
        while !remaining.isEmpty, blocks.count < 100 {
            let chunk = remaining.prefix(chunkSize)
            blocks.append([
                "object": "block",
                "type": "paragraph",
                "paragraph": [
                    "rich_text": [["type": "text", "text": ["content": String(chunk)]]]
                ],
            ])
            remaining = remaining.dropFirst(chunk.count)
        }
        return blocks
    }

    private func makeRequest(path: String, method: String, body: [String: Any]?) throws -> URLRequest {
        guard let url = URL(string: "https://api.notion.com/v1/\(path)") else {
            throw NotionError(message: "Invalid Notion API URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(settings.notionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw NotionError(message: message ?? "Notion API error (\(http.statusCode)).")
        }
    }
}
