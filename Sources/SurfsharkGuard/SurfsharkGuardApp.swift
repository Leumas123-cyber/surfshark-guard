import SwiftUI

@main
struct SurfsharkGuardApp: App {
    @StateObject private var state = GuardState.shared

    var body: some Scene {
        MenuBarExtra {
            GuardView()
                .environmentObject(state)
        } label: {
            Image(systemName: state.snapshot?.status.symbolName ?? "shield")
        }
        .menuBarExtraStyle(.window)

        Window("Surfshark Guard — Settings", id: "sg-settings") {
            SettingsView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)
    }
}
