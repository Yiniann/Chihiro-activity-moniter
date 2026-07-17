import SwiftUI

@main
struct ChihiroMonitorApp: App {
    @StateObject private var monitor = ActivityMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(monitor)
        } label: {
            Label(
                monitor.publicSlots.isEmpty ? "Chihiro Activity" : "Chihiro Activity · \(monitor.publicSlots.count)",
                systemImage: monitor.isPaused ? "pause.circle" : (monitor.connectionState == .connected ? "waveform.circle.fill" : "waveform.circle")
            )
        }
        .menuBarExtraStyle(.window)

        Window("Chihiro 活动监测", id: "dashboard") {
            DashboardShellView()
                .environmentObject(monitor)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1040, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(monitor)
                .frame(width: 520, height: 410)
        }
    }
}
