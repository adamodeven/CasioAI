import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "applewatch.side.right") {
                HomeView()
            }
            Tab("Talk", systemImage: "mic.fill") {
                TalkView()
            }
            Tab("Capture", systemImage: "text.badge.plus") {
                CaptureView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}
