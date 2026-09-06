import SwiftUI
import AppKit

@main
struct SurfsharkGuardApp: App {
    @StateObject private var state = GuardState.shared

    var body: some Scene {
        MenuBarExtra {
            GuardView()
                .environmentObject(state)
        } label: {
            Image(systemName: state.snapshot?.status.symbolName ?? "shield")
                .help(state.menuBarTooltip)
                .onAppear { StatusItemTooltip.apply(state.menuBarTooltip) }
                .onChange(of: state.menuBarTooltip) { text in
                    StatusItemTooltip.apply(text)
                }
        }
        .menuBarExtraStyle(.window)

        Window("Surfshark Guard — Settings", id: "sg-settings") {
            SettingsView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)

        Window("Surfshark Guard — Setup", id: "sg-onboarding") {
            OnboardingView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)
    }
}

/// SwiftUI `.help` on a MenuBarExtra label is flaky; set the real status-item tooltip.
enum StatusItemTooltip {
    static func apply(_ text: String) {
        func walk(_ view: NSView?) {
            guard let view else { return }
            if let button = view as? NSStatusBarButton {
                button.toolTip = text
            }
            view.subviews.forEach { walk($0) }
        }
        for window in NSApp.windows {
            walk(window.contentView)
            if let item = window.value(forKey: "statusItem") as? NSStatusItem {
                item.button?.toolTip = text
            }
        }
    }
}
