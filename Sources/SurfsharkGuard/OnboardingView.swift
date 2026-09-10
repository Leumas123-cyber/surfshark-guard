import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var state: GuardState
    @Environment(\.dismiss) private var dismiss
    @State private var isTestingLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: completedCount == 4
                      ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(completedCount == 4 ? Color.green : Color.blue)
                    .scaleEffect(completedCount == 4 ? 1.05 : 1)
                    .animation(.easeInOut(duration: 0.2), value: completedCount)
                VStack(alignment: .leading, spacing: 2) {
                    Text(completedCount == 4 ? "You’re ready" : "Quick setup")
                        .font(.title2.bold())
                    Text("Complete these checks for reliable protection.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(completedCount), total: 4)
                    .tint(completedCount == 4 ? .green : .blue)
                    .animation(.easeInOut(duration: 0.25), value: completedCount)
                Text("\(completedCount) of 4 checks complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            checklist

            HStack {
                Button {
                    Task { await state.checkNow() }
                } label: {
                    if state.checking {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Checking…")
                        }
                    } else {
                        Label("Check now", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(state.checking)

                Button {
                    Task {
                        isTestingLogin = true
                        await state.testWebUILogin()
                        isTestingLogin = false
                    }
                } label: {
                    if isTestingLogin {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Testing…")
                        }
                    } else {
                        Label("Test Web UI", systemImage: "network")
                    }
                }
                .disabled(!state.webuiEnabled || state.webuiUser.isEmpty
                          || isTestingLogin)
                Spacer()
                Button {
                    state.onboardingDone = true
                    dismiss()
                } label: {
                    Label(completedCount == 4 ? "Done" : "Finish later",
                          systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }

            if let result = state.loginTestResult {
                Label(result, systemImage: loginOK
                      ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(loginOK ? Color.green : Color.orange)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(22)
        .frame(width: 500, height: 520)
        .onAppear { Task { await state.checkNow() } }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 9) {
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

    private var completedCount: Int {
        [vpnProcessOK, state.snapshot?.tunnel != nil, localhostOK, loginOK]
            .filter { $0 }.count
    }

    private var vpnProcessOK: Bool {
        state.snapshot?.tunnel?.vpnRunning == true
    }

    private var localhostOK: Bool {
        state.webuiEnabled && WebUIURLValidator.validated(state.webuiURL) != nil
    }

    private var loginOK: Bool {
        state.loginTestResult == "Login works"
    }

    private func row(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ok ? Color.green : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ok ? Color.green.opacity(0.07)
                      : Color.primary.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ok ? Color.green.opacity(0.16) : Color.clear,
                        lineWidth: 1)
        }
    }
}
