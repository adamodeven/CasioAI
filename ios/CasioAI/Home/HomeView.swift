import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    connectionCard
                    if let status = environment.ble.watchStatus {
                        statusCard(status)
                    }
                    weatherCard
                }
                .padding()
            }
            .navigationTitle("CasioAI")
            .task {
                await environment.weather.refreshAndPush()
            }
        }
    }

    private var connectionCard: some View {
        let ble = environment.ble
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: connectionSymbol(ble.connectionState))
                    .font(.title2)
                    .foregroundStyle(connectionColor(ble.connectionState))
                VStack(alignment: .leading) {
                    Text("Watch")
                        .font(.headline)
                    Text(connectionLabel(ble.connectionState))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if case .disconnected = ble.connectionState {
                    Button("Scan") { ble.startScanning() }
                        .buttonStyle(.glass)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func statusCard(_ status: WatchProtocol.WatchStatus) -> some View {
        HStack(spacing: 20) {
            Label("\(status.batteryPercent)%", systemImage: batterySymbol(for: status))
            if status.flags.contains(.charging) {
                Label("Charging", systemImage: "bolt.fill")
            }
            Spacer()
            Text("fw \(status.firmwareVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var weatherCard: some View {
        let weather = environment.weather
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weather")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await weather.refreshAndPush() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.glass)
            }

            if let latest = weather.latest {
                HStack(spacing: 24) {
                    Label("\(latest.high)°", systemImage: "thermometer.sun")
                    Label("\(latest.low)°", systemImage: "thermometer.snowflake")
                }
                .font(.title3)
                Text("Synced to watch · \(latest.fetchedAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = weather.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                Text("Fetching…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func connectionSymbol(_ state: BLEManager.ConnectionState) -> String {
        switch state {
        case .connected: "checkmark.circle.fill"
        case .connecting, .scanning: "antenna.radiowaves.left.and.right"
        case .disconnected: "xmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func connectionColor(_ state: BLEManager.ConnectionState) -> Color {
        switch state {
        case .connected: .green
        case .connecting, .scanning: .blue
        case .disconnected: .secondary
        case .failed: .orange
        }
    }

    private func connectionLabel(_ state: BLEManager.ConnectionState) -> String {
        switch state {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .scanning: "Scanning…"
        case .disconnected: "Disconnected"
        case .failed(let message): message
        }
    }

    private func batterySymbol(for status: WatchProtocol.WatchStatus) -> String {
        if status.flags.contains(.lowBattery) { return "battery.25" }
        return status.batteryPercent > 60 ? "battery.100" : "battery.50"
    }
}
