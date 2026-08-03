import CoreLocation
import Foundation
import Observation

/// Fetches the local daily high/low from Open-Meteo (no API key required)
/// and pushes it to the watch. Location comes from CoreLocation by default,
/// or a manually configured lat/lon in Settings.
@Observable
final class WeatherClient: NSObject {
    struct DailyTemperature {
        let low: Int
        let high: Int
        let fetchedAt: Date
    }

    enum WeatherError: LocalizedError {
        case noLocation
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noLocation: "No location available for weather lookup — enable Location Services or set one manually in Settings."
            case .invalidResponse: "Couldn't read weather data."
            }
        }
    }

    private let settings: SettingsStore
    private let ble: BLEManager
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    private(set) var latest: DailyTemperature?
    private(set) var lastError: String?

    init(settings: SettingsStore, ble: BLEManager) {
        self.settings = settings
        self.ble = ble
        super.init()
        locationManager.delegate = self
    }

    /// Fetches the daily hi/lo and pushes it to the watch. Call on launch,
    /// on app foreground, and once a day thereafter.
    func refreshAndPush() async {
        do {
            let coordinate = try await resolveCoordinate()
            let (low, high) = try await fetchDailyTemperature(latitude: coordinate.latitude, longitude: coordinate.longitude)
            latest = DailyTemperature(low: low, high: high, fetchedAt: Date())
            lastError = nil
            ble.pushTemperature(lowFahrenheit: low, highFahrenheit: high)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func resolveCoordinate() async throws -> CLLocationCoordinate2D {
        if !settings.useDeviceLocationForWeather,
           let lat = settings.manualWeatherLatitude, let lon = settings.manualWeatherLongitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return try await requestDeviceLocation()
    }

    private func requestDeviceLocation() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                locationManager.requestLocation()
            default:
                continuation.resume(throwing: WeatherError.noLocation)
                locationContinuation = nil
            }
        }
    }

    private func fetchDailyTemperature(latitude: Double, longitude: Double) async throws -> (low: Int, high: Int) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let daily = json["daily"] as? [String: Any],
            let highs = daily["temperature_2m_max"] as? [Double],
            let lows = daily["temperature_2m_min"] as? [Double],
            let high = highs.first, let low = lows.first
        else {
            throw WeatherError.invalidResponse
        }
        return (Int(low.rounded()), Int(high.rounded()))
    }
}

extension WeatherClient: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard locationContinuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            locationContinuation?.resume(throwing: WeatherError.noLocation)
            locationContinuation = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.first?.coordinate else { return }
        locationContinuation?.resume(returning: coordinate)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}
