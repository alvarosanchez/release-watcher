import SwiftUI

struct SettingsView: View {
    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes = 30
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Stepper(value: $refreshIntervalMinutes, in: 5...240, step: 5) {
                Text("Refresh every \(refreshIntervalMinutes) minutes")
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .disabled(true)

            Text("Launch at login is scaffolded in settings, but not wired yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360)
    }
}
