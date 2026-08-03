import Foundation
import Observation

/// User-configurable settings. Non-secret values live in UserDefaults;
/// secrets (API keys/tokens) live in the Keychain via KeychainStore but are
/// mirrored into stored properties here so SwiftUI's Observation tracking
/// picks up changes made from the Settings screen.
@Observable
final class SettingsStore {

    private enum Keys {
        static let notionDatabaseID = "notionDatabaseID"
        static let notionDatabaseDisplayName = "notionDatabaseDisplayName"
        static let useDeviceLocationForWeather = "useDeviceLocationForWeather"
        static let manualWeatherLocationName = "manualWeatherLocationName"
        static let manualWeatherLatitude = "manualWeatherLatitude"
        static let manualWeatherLongitude = "manualWeatherLongitude"
    }

    private let defaults: UserDefaults

    /// The Notion database (page ID, e.g. from the database URL) that
    /// thought-capture pages get created in. Configured in Settings rather
    /// than hardcoded so the inbox can change without a rebuild.
    var notionDatabaseID: String {
        didSet { defaults.set(notionDatabaseID, forKey: Keys.notionDatabaseID) }
    }

    /// Friendly name shown in Settings once the database has been resolved
    /// (e.g. "Inbox"), purely cosmetic.
    var notionDatabaseDisplayName: String {
        didSet { defaults.set(notionDatabaseDisplayName, forKey: Keys.notionDatabaseDisplayName) }
    }

    var useDeviceLocationForWeather: Bool {
        didSet { defaults.set(useDeviceLocationForWeather, forKey: Keys.useDeviceLocationForWeather) }
    }

    var manualWeatherLocationName: String {
        didSet { defaults.set(manualWeatherLocationName, forKey: Keys.manualWeatherLocationName) }
    }

    var manualWeatherLatitude: Double? {
        didSet { defaults.set(manualWeatherLatitude, forKey: Keys.manualWeatherLatitude) }
    }

    var manualWeatherLongitude: Double? {
        didSet { defaults.set(manualWeatherLongitude, forKey: Keys.manualWeatherLongitude) }
    }

    var openAIAPIKey: String {
        didSet {
            if openAIAPIKey.isEmpty {
                KeychainStore.remove(.openAIAPIKey)
            } else {
                KeychainStore.set(openAIAPIKey, for: .openAIAPIKey)
            }
        }
    }

    var notionToken: String {
        didSet {
            if notionToken.isEmpty {
                KeychainStore.remove(.notionToken)
            } else {
                KeychainStore.set(notionToken, for: .notionToken)
            }
        }
    }

    var isNotionConfigured: Bool {
        !notionToken.isEmpty && !notionDatabaseID.isEmpty
    }

    var isOpenAIConfigured: Bool {
        !openAIAPIKey.isEmpty
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notionDatabaseID = defaults.string(forKey: Keys.notionDatabaseID) ?? ""
        notionDatabaseDisplayName = defaults.string(forKey: Keys.notionDatabaseDisplayName) ?? ""
        useDeviceLocationForWeather = defaults.object(forKey: Keys.useDeviceLocationForWeather) as? Bool ?? true
        manualWeatherLocationName = defaults.string(forKey: Keys.manualWeatherLocationName) ?? ""
        manualWeatherLatitude = defaults.object(forKey: Keys.manualWeatherLatitude) as? Double
        manualWeatherLongitude = defaults.object(forKey: Keys.manualWeatherLongitude) as? Double
        openAIAPIKey = KeychainStore.get(.openAIAPIKey) ?? ""
        notionToken = KeychainStore.get(.notionToken) ?? ""
    }
}
