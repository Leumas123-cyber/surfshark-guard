import SwiftUI
import AppKit

struct GuardView: View {
    @EnvironmentObject private var state: GuardState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            detailRows
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
        .onAppear { state.start() }
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
        guard let snap = state.snapshot else { return "Noch nicht geprüft…" }
        let time = snap.checkedAt.formatted(date: .omitted, time: .shortened)
        return "\(snap.status.headline) · geprüft \(time)"
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 5) {
            row("Tunnel", tunnelText)
            row("qBittorrent", qbtText)
            if let path = state.snapshot?.configPath ?? state.snapshot?.writeTarget {
                row("Konfiguration", abbreviated(path))
            }
            row("Bindung", bindingText)
        }
        .font(.callout)
    }

    private var tunnelText: String {
        guard let t = state.snapshot?.tunnel else {
            return "keiner — Surfshark verbinden!"
        }
        var text = "\(t.iface)"
        if let ip = t.ip { text += " · \(ip)" }
        text += t.wireGuard ? " · WireGuard" : ""
        return text
    }

    private var qbtText: String {
        state.snapshot.map { $0.qbRunning ? "läuft" : "läuft nicht" } ?? "–"
    }

    private var bindingText: some View {
        let snap = state.snapshot
        let text: String
        let color: Color?
        if let s = snap {
            var t = s.qbInterface ?? "KEINE („Beliebige Schnittstelle“)"
            if let addr = s.qbAddress { t += " · IP \(addr)" }
            if s.status == .wrongBinding {
                t += "  ←  Tunnel ist \(s.tunnel?.iface ?? "?")"
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
                Text("weitere VPN-Interfaces: " + tunnel.otherCandidates.joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var toggles: some View {
        HStack(spacing: 14) {
            Toggle("Überwachen", isOn: $state.autoWatch)
            Toggle("Auto-Fix", isOn: $state.autoFix)
            Toggle("Meldungen", isOn: $state.notifications)
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button {
                Task { await state.checkNow() }
            } label: {
                Label("Jetzt prüfen", systemImage: "arrow.clockwise")
            }
            Button {
                Task { await state.quitQBittorrentAndFix() }
            } label: {
                Label("qB beenden & binden", systemImage: "link")
            }
            .disabled(state.snapshot?.status == .ok)
            Button {
                openWindow(id: "sg-settings")
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    for window in NSApp.windows
                    where window.identifier?.rawValue.contains("sg-settings") == true {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                }
            } label: {
                Label("Einstellungen", systemImage: "gear")
            }
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Surfshark Guard beenden")
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

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct SettingsView: View {
    @EnvironmentObject private var state: GuardState

    var body: some View {
        Form {
            Section("Überwachung") {
                Toggle("Bei Anmeldung starten", isOn: Binding(
                    get: { state.loginItemEnabled },
                    set: { state.setLoginItem($0) }))
                Picker("Intervall", selection: $state.watchInterval) {
                    Text("10 s").tag(10.0)
                    Text("15 s").tag(15.0)
                    Text("30 s").tag(30.0)
                    Text("60 s").tag(60.0)
                }
                .pickerStyle(.segmented)
                Text("„Überwachen“ prüft Tunnel und Bindung im Hintergrund; bei Problemen kommt eine macOS-Meldung.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Automatischer Fix") {
                Toggle("Bindung automatisch korrigieren", isOn: $state.autoFix)
                Text("Live über die Web-UI (unten), sonst in der Konfigurationsdatei, sobald qBittorrent beendet ist — dessen Beenden wird nie erzwungen.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("qBittorrent Web-UI (für Live-Korrektur)") {
                Toggle("Web-UI nutzen", isOn: $state.webuiEnabled)
                TextField("URL", text: $state.webuiURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Benutzer", text: $state.webuiUser)
                    .textFieldStyle(.roundedBorder)
                SecureField("Passwort", text: $state.webuiPass)
                    .textFieldStyle(.roundedBorder)
                Text("In qBittorrent: Einstellungen → Web-UI aktivieren. Läuft nur auf 127.0.0.1 — nichts verlässt den Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }
}
