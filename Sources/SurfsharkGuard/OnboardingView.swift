import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var state: GuardState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick setup").font(.title2.bold())
            Text("Four checks so “offline / check” is not a mystery. You can reopen this from the menu.")
                .font(.callout)
                .foregroundStyle(.secondary)

            checklist

            HStack {
                Button("Check now") {
                    Task { await state.checkNow() }
                }
                Button("Test Web UI login") {
                    Task { await state.testWebUILogin() }
                }
                .disabled(!state.webuiEnabled || state.webuiUser.isEmpty)
                Spacer()
                Button("Done") {
                    state.onboardingDone = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            if let result = state.loginTestResult {
                Text(result).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { Task { await state.checkNow() } }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(ok: vpnProcessOK, title: "VPN app is running",
                detail: vpnProcessOK
                    ? (state.snapshot?.tunnel?.vpnName ?? state.vpnProvider.title)
                    : "Open \(state.vpnProvider == .auto ? "Surfshark, Mullvad, Proton, or WireGuard" : state.vpnProvider.title)")
            row(ok: state.snapshot?.tunnel != nil, title: "Tunnel is up",
                detail: state.snapshot?.tunnel.map { $0.iface } ?? "Connect the VPN as a full tunnel")
            row(ok: localhostOK, title: "Web UI on this Mac",
                detail: localhostOK ? state.webuiURL : "Enable qBittorrent Web UI on 127.0.0.1")
            row(ok: loginOK, title: "Web UI login",
                detail: loginOK ? "OK" : (state.loginTestResult ?? "Click “Test Web UI login”"))
        }
    }

    private var vpnProcessOK: Bool {
        !(Detector.vpnProcesses(for: state.vpnProvider).isEmpty)
    }

    private var localhostOK: Bool {
        guard state.webuiEnabled, let url = URL(string: state.webuiURL),
              let host = url.host else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }

    private var loginOK: Bool {
        state.loginTestResult == "Login works"
    }

    private func row(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
