import SwiftUI
import AppKit

struct GuardView: View {
    @EnvironmentObject private var state: GuardState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !state.onboardingDone {
                Button {
                    openSettingsOrOnboarding("sg-onboarding")
                } label: {
                    Label("Finish setup…", systemImage: "list.bullet.clipboard")
                }
                .buttonStyle(.bordered)
            }
            if let update = state.updateAvailable {
                Button(action: state.openLatestRelease) {
                    Label("Version \(update.latest) available", systemImage: "arrow.down.app")
                }
                .buttonStyle(.bordered)
            }
            Divider()
            detailRows
            if let hint = state.snapshot?.ipv6Hint {
                Label(hint, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let tunnel = state.snapshot?.tunnel {
                evidence(tunnel)
            }
            Divider()
            toggles
            buttons
            footer
        }
        .padding(12)
        .frame(width: 400)
        .onAppear {
            state.start()
            if !state.onboardingDone {
                openSettingsOrOnboarding("sg-onboarding")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: statusSymbol)
                .font(.system(size: 22))
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Surfshark Guard").font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.checking { ProgressView().controlSize(.small) }
        }
    }

    private var statusSymbol: String {
        state.snapshot?.status.symbolName ?? "shield"
    }
    private var statusColor: Color {
        state.snapshot?.status.color ?? .secondary
    }
    private var statusText: String {
        guard let snap = state.snapshot else { return "Not checked yet…" }
        let time = snap.checkedAt.formatted(date: .omitted, time: .shortened)
        return "\(snap.status.headline) · checked \(time)"
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 5) {
            row("Tunnel", tunnelText)
            row("qBittorrent", qbtText)
            if state.webuiEnabled {
                row("Web UI", webUIText)
            }
            if let path = state.snapshot?.configPath ?? state.snapshot?.writeTarget {
                row("Config", abbreviated(path))
            }
            row("Binding", bindingText)
        }
        .font(.callout)
    }

    private var tunnelText: String {
        guard let t = state.snapshot?.tunnel else {
            return "none — connect the VPN!"
        }
        var text = "\(t.iface)"
        if let ip = t.ip { text += " · \(ip)" }
        if let name = t.vpnName { text += " · \(name)" }
        else if t.wireGuard { text += " · WireGuard" }
        return text
    }

    private var qbtText: String {
        state.snapshot.map { $0.qbRunning ? "running" : "not running" } ?? "–"
    }

    private var webUIText: some View {
        let status = state.snapshot?.webUI ?? .unused
        let color: Color = {
            switch status {
            case .online: return .green
            case .offline: return .orange
            case .unused: return .secondary
            }
        }()
        return Text(status.menuLabel).foregroundColor(color)
    }

    private var bindingText: some View {
        let snap = state.snapshot
        let text: String
        let color: Color?
        if let s = snap {
            var t = s.qbInterface ?? "NONE (“Any interface”)"
            if let addr = s.qbAddress { t += " · IP \(addr)" }
            if let src = s.bindingSource { t += " · \(src)" }
            if s.status == .wrongBinding {
                t += "  ←  tunnel is \(s.tunnel?.iface ?? "?")"
            }
            text = t
            color = s.status == .ok ? .green : (s.status == .wrongBinding ? .red : nil)
        } else {
            text = "–"
            color = nil
        }
        if let color {
            return Text(text).foregroundColor(color)
        }
        return Text(text)
    }

    private func row(_ label: String, _ value: String) -> some View {
        row(label, Text(value))
    }

    private func row<V: View>(_ label: String, _ value: V) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 105, alignment: .leading)
            value
            Spacer(minLength: 0)
        }
    }

    private func evidence(_ tunnel: TunnelInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(tunnel.why, id: \.self) { reason in
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Text(reason).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !tunnel.otherCandidates.isEmpty {
                Text("other VPN interfaces: " + tunnel.otherCandidates.joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var toggles: some View {
        HStack(spacing: 14) {
            Toggle("Watch", isOn: $state.autoWatch)
            Toggle("Auto-fix", isOn: $state.autoFix)
            Toggle("Pause if down", isOn: $state.pauseOnDrop)
            Toggle("Alerts", isOn: $state.notifications)
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button {
                Task { await state.checkNow() }
            } label: {
                Label("Check now", systemImage: "arrow.clockwise")
            }
            Button {
                Task { await state.quitQBittorrentAndFix() }
            } label: {
                Label("Quit qB & bind", systemImage: "link")
            }
            .disabled(state.snapshot?.status == .ok)
            Button {
                openSettingsOrOnboarding("sg-settings")
            } label: {
                Label("Settings", systemImage: "gear")
            }
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Surfshark Guard")
        }
        .labelStyle(.titleAndIcon)
        .font(.callout)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let action = state.lastAction {
                Label(action, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            if let error = state.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
    }

    private func openSettingsOrOnboarding(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            for window in NSApp.windows
            where window.identifier?.rawValue.contains(id) == true {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct SettingsView: View {
    @EnvironmentObject private var state: GuardState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("VPN") {
                Picker("Provider", selection: $state.vpnProvider) {
                    ForEach(VPNProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                Text("Auto picks Surfshark, Mullvad, Proton VPN, or a WireGuard tunnel. Unofficial — not affiliated with any of them.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Watching") {
                Toggle("Open at login", isOn: Binding(
                    get: { state.loginItemEnabled },
                    set: { state.setLoginItem($0) }))
                Button("Open setup checklist") {
                    state.onboardingDone = false
                    openWindow(id: "sg-onboarding")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Picker("Interval", selection: $state.watchInterval) {
                    Text("5 s").tag(5.0)
                    Text("10 s").tag(10.0)
                    Text("15 s").tag(15.0)
                    Text("30 s").tag(30.0)
                }
                .pickerStyle(.segmented)
                Text("Watch runs route/ifconfig on a timer and also when the network path changes. Default 5 s, never a tight loop.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Automatic fix") {
                Toggle("Fix binding automatically", isOn: $state.autoFix)
                Toggle("Pause torrents if the VPN drops", isOn: $state.pauseOnDrop)
                Text("Live via the Web UI below, otherwise in the config file once qBittorrent has quit — it is never force-quit. Pause uses the Web UI (qB 4 pause / qB 5 stop).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Check GitHub Releases on launch", isOn: $state.checkUpdates)
                HStack {
                    Button("Check now") {
                        Task { await state.checkForUpdate() }
                    }
                    if state.updateAvailable != nil {
                        Button("Open download page", action: state.openLatestRelease)
                    }
                }
                Text(state.updateCheckMessage ?? "Current version \(UpdateCheck.currentVersion()). Looks at the public GitHub latest release only — no Sparkle, no auto-install.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("qBittorrent Web UI (for live fix)") {
                Toggle("Use Web UI", isOn: $state.webuiEnabled)
                TextField("URL", text: $state.webuiURL)
                    .textFieldStyle(.roundedBorder)
                TextField("User", text: $state.webuiUser)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $state.webuiPass)
                    .textFieldStyle(.roundedBorder)
                Text("In qBittorrent: Preferences → Web UI. Keep it on 127.0.0.1 — nothing leaves this Mac. The password is stored in the macOS Keychain, not in UserDefaults.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 720)
    }
}
