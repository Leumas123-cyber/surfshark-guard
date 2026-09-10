import SwiftUI
import AppKit

struct GuardView: View {
    @EnvironmentObject private var state: GuardState
    @Environment(\.openWindow) private var openWindow
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusCard

            if !state.onboardingDone {
                banner(
                    title: "Finish setup",
                    message: "A quick checklist makes sure protection is ready.",
                    symbol: "list.bullet.clipboard",
                    color: .blue
                ) {
                    openSettingsOrOnboarding("sg-onboarding")
                }
            }
            if let update = state.updateAvailable {
                banner(
                    title: "Version \(update.latest) is available",
                    message: "Open the verified GitHub release page.",
                    symbol: "arrow.down.app",
                    color: .blue,
                    action: state.openLatestRelease
                )
            }

            primaryActions
            quickControls

            DisclosureGroup(isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 9) {
                    detailRows
                    if let hint = state.snapshot?.ipv6Hint {
                        Label(hint, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let tunnel = state.snapshot?.tunnel {
                        evidence(tunnel)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Connection details", systemImage: "network")
                    .font(.callout.weight(.medium))
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )

            footer
            bottomBar
        }
        .padding(14)
        .frame(width: 420)
        .onAppear {
            if !state.onboardingDone {
                openSettingsOrOnboarding("sg-onboarding")
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                    .frame(width: 54, height: 54)
                Image(systemName: statusSymbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .scaleEffect(state.checking ? 0.92 : 1)
                    .animation(.easeInOut(duration: 0.18),
                               value: state.checking)
                    .animation(.easeInOut(duration: 0.18),
                               value: statusSymbol)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.title3.bold())
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            ProgressView()
                .controlSize(.small)
                .opacity(state.checking ? 1 : 0)
                .frame(width: 16, height: 16)
                .animation(.easeInOut(duration: 0.15), value: state.checking)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(statusColor.opacity(0.09))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(statusColor.opacity(0.18), lineWidth: 1)
        }
    }

    private var statusTitle: String {
        guard let status = state.snapshot?.status else { return "Ready to protect" }
        switch status {
        case .ok: return "Protected"
        case .wrongBinding: return "Action needed"
        case .noTunnel: return "VPN disconnected"
        }
    }

    private var statusSymbol: String {
        state.snapshot?.status.symbolName ?? "shield"
    }
    private var statusColor: Color {
        state.snapshot?.status.color ?? .secondary
    }
    private var statusText: String {
        guard let snap = state.snapshot else { return "Run the first connection check." }
        let time = snap.checkedAt.formatted(date: .omitted, time: .shortened)
        return "\(snap.status.headline) · checked \(time)"
    }

    private var primaryActions: some View {
        HStack(spacing: 8) {
            if state.snapshot?.status == .wrongBinding {
                Button {
                    Task { await state.quitQBittorrentAndFix() }
                } label: {
                    Label("Quit qBittorrent & fix", systemImage: "shield.checkered")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(state.checking)
                .help("Gracefully quits qBittorrent, then applies the safe VPN binding")
            }

            Button {
                Task { await state.checkNow() }
            } label: {
                HStack(spacing: 6) {
                    if state.checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(state.checking ? "Checking…" : "Check now")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(state.checking)
        }
        .controlSize(.large)
    }

    private var quickControls: some View {
        HStack(spacing: 10) {
            compactToggle("Watch", symbol: "eye", isOn: $state.autoWatch)
            compactToggle("Auto-fix", symbol: "wand.and.stars",
                          isOn: $state.autoFix)
        }
    }

    private func compactToggle(_ title: String, symbol: String,
                               isOn: Binding<Bool>) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(isOn.wrappedValue ? Color.blue : Color.secondary)
            Text(title).font(.callout.weight(.medium))
            Spacer(minLength: 4)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func banner(title: String, message: String, symbol: String,
                        color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.08))
        )
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

    private var bottomBar: some View {
        HStack {
            Button {
                openSettingsOrOnboarding("sg-settings")
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit Surfshark Guard")
        }
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
    @State private var checkingUpdate = false
    @State private var testingWebUI = false

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
                    Button {
                        Task {
                            checkingUpdate = true
                            await state.checkForUpdate()
                            checkingUpdate = false
                        }
                    } label: {
                        if checkingUpdate {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Checking…")
                            }
                        } else {
                            Label("Check now", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(checkingUpdate)
                    if state.updateAvailable != nil {
                        Button("Open download page", action: state.openLatestRelease)
                    }
                }
                Text(state.updateCheckMessage ?? "Current version \(UpdateCheck.currentVersion()). Looks at the public GitHub latest release only — no Sparkle, no auto-install.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("qBittorrent Web UI (for live fix)") {
                Toggle("Use Web UI", isOn: $state.webuiEnabled)
                Group {
                    TextField("URL", text: $state.webuiURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("User", text: $state.webuiUser)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $state.webuiPass)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button {
                            Task {
                                testingWebUI = true
                                await state.testWebUILogin()
                                testingWebUI = false
                            }
                        } label: {
                            if testingWebUI {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Testing…")
                                }
                            } else {
                                Label("Test connection", systemImage: "network")
                            }
                        }
                        .disabled(state.webuiUser.isEmpty || testingWebUI)

                        if let result = state.loginTestResult {
                            Label(result, systemImage: result == "Login works"
                                  ? "checkmark.circle.fill"
                                  : "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(result == "Login works"
                                                 ? Color.green : Color.orange)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                }
                .disabled(!state.webuiEnabled)
                if state.webuiEnabled,
                   WebUIURLValidator.validated(state.webuiURL) == nil {
                    Label("Use localhost, 127.0.0.1, or ::1.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("In qBittorrent: Preferences → Web UI. Keep it on 127.0.0.1 — nothing leaves this Mac. The password is stored in the macOS Keychain, not in UserDefaults.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 680)
        .animation(.easeInOut(duration: 0.2), value: state.loginTestResult)
        .animation(.easeInOut(duration: 0.2), value: state.webuiEnabled)
    }
}
