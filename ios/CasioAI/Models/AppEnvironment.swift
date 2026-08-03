import Observation

/// Root object holding the app's shared managers, injected once at launch
/// via `.environment(_:)` so any view can reach them without threading
/// dependencies through every initializer.
@Observable
final class AppEnvironment {
    let settings: SettingsStore
    let ble: BLEManager
    let notion: NotionClient
    let weather: WeatherClient
    let realtimeVoice: RealtimeVoiceController
    let thoughtCapture: ThoughtCaptureController
    let callRelay: CallRelayManager
    let musicRelay: MusicRelayManager

    init() {
        let settings = SettingsStore()
        let ble = BLEManager()
        let notion = NotionClient(settings: settings)
        let weather = WeatherClient(settings: settings, ble: ble)

        self.settings = settings
        self.ble = ble
        self.notion = notion
        self.weather = weather
        self.realtimeVoice = RealtimeVoiceController(settings: settings, ble: ble)
        self.thoughtCapture = ThoughtCaptureController(ble: ble, notion: notion)
        self.callRelay = CallRelayManager(ble: ble)
        self.musicRelay = MusicRelayManager(ble: ble)
    }
}
