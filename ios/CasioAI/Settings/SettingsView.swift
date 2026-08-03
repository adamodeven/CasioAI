import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isResolvingDatabaseName = false
    @State private var resolveError: String?

    var body: some View {
        @Bindable var settings = environment.settings

        NavigationStack {
            Form {
                Section {
                    SecureField("sk-...", text: $settings.openAIAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("OpenAI")
                } footer: {
                    Text("Used for live voice conversations (Realtime API). Stored on-device in the Keychain only.")
                }

                Section {
                    SecureField("Integration token", text: $settings.notionToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Database ID", text: $settings.notionDatabaseID)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    HStack {
                        if !settings.notionDatabaseDisplayName.isEmpty {
                            Text(settings.notionDatabaseDisplayName)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(isResolvingDatabaseName ? "Checking…" : "Verify") {
                            resolveDatabaseName()
                        }
                        .buttonStyle(.glass)
                        .disabled(settings.notionToken.isEmpty || settings.notionDatabaseID.isEmpty || isResolvingDatabaseName)
                    }

                    if let resolveError {
                        Text(resolveError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Notion")
                } footer: {
                    Text("Thought-capture pages are created in this database. Find the database ID in its share URL — the 32-character segment before any \"?\".")
                }

                Section {
                    Toggle("Use current location", isOn: $settings.useDeviceLocationForWeather)
                    if !settings.useDeviceLocationForWeather {
                        TextField("Latitude", text: optionalDoubleBinding($settings.manualWeatherLatitude))
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        TextField("Longitude", text: optionalDoubleBinding($settings.manualWeatherLongitude))
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                } header: {
                    Text("Weather")
                } footer: {
                    Text("Daily high/low is fetched from Open-Meteo (no account needed) and pushed to the watch.")
                }

                Section {
                    watchConnectionRow
                } header: {
                    Text("Watch")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var watchConnectionRow: some View {
        let ble = environment.ble
        return HStack {
            Text(connectionLabel(ble.connectionState))
                .foregroundStyle(.secondary)
            Spacer()
            if case .disconnected = ble.connectionState {
                Button("Scan") { ble.startScanning() }
                    .buttonStyle(.glass)
            } else if case .connected = ble.connectionState {
                Button("Disconnect", role: .destructive) { ble.disconnect() }
            }
        }
    }

    private func connectionLabel(_ state: BLEManager.ConnectionState) -> String {
        switch state {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .scanning: "Scanning…"
        case .disconnected: "Not connected"
        case .failed(let message): message
        }
    }

    private func optionalDoubleBinding(_ source: Binding<Double?>) -> Binding<String> {
        Binding<String>(
            get: { source.wrappedValue.map { String($0) } ?? "" },
            set: { source.wrappedValue = Double($0) }
        )
    }

    private func resolveDatabaseName() {
        isResolvingDatabaseName = true
        resolveError = nil
        Task {
            do {
                let name = try await environment.notion.resolveDatabaseDisplayName(for: environment.settings.notionDatabaseID)
                environment.settings.notionDatabaseDisplayName = name
            } catch {
                resolveError = error.localizedDescription
            }
            isResolvingDatabaseName = false
        }
    }
}
