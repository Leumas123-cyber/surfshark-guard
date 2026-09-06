import Foundation
import SwiftUI
import UserNotifications
import AppKit
import ServiceManagement

enum GuardStatus {
    case ok
    case wrongBinding
    case noTunnel

    var symbolName: String {
        switch self {
        case .ok: return "checkmark.shield.fill"
        case .wrongBinding: return "exclamationmark.shield.fill"
        case .noTunnel: return "shield.slash"
        }
    }

    var color: Color {
        switch self {
        case .ok: return .green
        case .wrongBinding: return .red
        case .noTunnel: return .orange
        }
    }

    var headline: String {
        switch self {
        case .ok: return "All sealed — qBittorrent is on the tunnel"
        case .wrongBinding: return "Wrong binding — leak risk"
        case .noTunnel: return "No Surfshark tunnel"
        }
    }
}

struct Snapshot {
    var tunnel: TunnelInfo?
    var qbRunning: Bool
    var qbInterface: String?
    var qbAddress: String?
    var configPath: String?
    var writeTarget: String
    var checkedAt: Date

    var status: GuardStatus {
        guard let tunnel = tunnel else { return .noTunnel }
        return qbInterface == tunnel.iface ? .ok : .wrongBinding
    }
}

@MainActor
final class GuardState: ObservableObject {
    static let shared = GuardState()

    @Published var snapshot: Snapshot?
    @Published var checking = false
    @Published var lastAction: String?
    @Published var lastError: String?
    private var lastNotifiedStatus: GuardStatus?

    @Published var autoWatch: Bool {
        didSet { defaults.set(autoWatch, forKey: "autoWatch"); rescheduleTimer() }
    }
    @Published var autoFix: Bool {
        didSet { defaults.set(autoFix, forKey: "autoFix") }
    }
    @Published var notifications: Bool {
        didSet { defaults.set(notifications, forKey: "notifications"); if notifications { askNotificationPermission() } }
    }
    @Published var watchInterval: Double {
        didSet { defaults.set(watchInterval, forKey: "watchInterval"); rescheduleTimer() }
    }
    @Published var webuiEnabled: Bool {
        didSet { defaults.set(webuiEnabled, forKey: "webuiEnabled") }
    }
    @Published var webuiURL: String {
        didSet { defaults.set(webuiURL, forKey: "webuiURL") }
    }
    @Published var webuiUser: String {
        didSet { defaults.set(webuiUser, forKey: "webuiUser") }
    }
    @Published var webuiPass: String {
        didSet { defaults.set(webuiPass, forKey: "webuiPass") }
    }

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var qBQuitObserver: Any?

    private init() {
        autoWatch = defaults.object(forKey: "autoWatch") as? Bool ?? true
        autoFix = defaults.object(forKey: "autoFix") as? Bool ?? false
        notifications = defaults.object(forKey: "notifications") as? Bool ?? true
        watchInterval = defaults.object(forKey: "watchInterval") as? Double ?? 15
        webuiEnabled = defaults.bool(forKey: "webuiEnabled")
        webuiURL = defaults.string(forKey: "webuiURL") ?? "http://127.0.0.1:8080"
        webuiUser = defaults.string(forKey: "webuiUser") ?? ""
        webuiPass = defaults.string(forKey: "webuiPass") ?? ""

        qBQuitObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  app.bundleIdentifier?.lowercased().contains("qbittorrent") == true
            else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await self?.checkNow(notifyAbout: false)
                if self?.autoFix == true { await self?.attemptFix(automatic: true) }
            }
        }

        Task { await checkNow() }
        rescheduleTimer()
    }

    func start() {
        Task { await checkNow() }
        rescheduleTimer()
        if notifications { askNotificationPermission() }
    }

    func checkNow(notifyAbout: Bool = true) async {
        checking = true
        defer { checking = false }

        let snap = await gather()
        let previous = snapshot?.status
        snapshot = snap

        if notifyAbout, previous != nil, previous != snap.status,
           notifications, snap.status != .ok {
            notifyProblem(snap)
        }
        lastNotifiedStatus = snap.status
    }

    private func gather() async -> Snapshot {
        await Task.detached(priority: .userInitiated) {
            let tunnel = Detector.detect()
            let (existing, target) = QBittorrent.findConfig()
            var iface: String?
            var addr: String?
            if let path = existing, let text = try? String(contentsOfFile: path,
                                                            encoding: .utf8) {
                (iface, addr) = IniEditor.binding(in: text)
            }
            return Snapshot(
                tunnel: tunnel,
                qbRunning: Detector.qbittorrentRunning(),
                qbInterface: iface,
                qbAddress: addr,
                configPath: existing,
                writeTarget: target,
                checkedAt: Date()
            )
        }.value
    }

    func attemptFix(automatic: Bool) async {
        guard let snap = snapshot else { return }
        guard let tunnel = snap.tunnel else {
            lastError = "No tunnel — connect Surfshark first."
            return
        }

        if webuiEnabled, !webuiUser.isEmpty {
            guard let url = URL(string: webuiURL) else {
                lastError = "Invalid Web UI URL: \(webuiURL)"
                return
            }
            let ui = QBWebUI(baseURL: url, user: webuiUser, password: webuiPass)
            if await ui.login() {
                let address = snap.qbAddress == tunnel.ip ? snap.qbAddress : nil
                if await ui.setInterface(tunnel.iface, address: address) {
                    lastAction = "Web UI: binding set live to \(tunnel.iface) ✓"
                    lastError = nil
                    await checkNow()
                    return
                }
            }
            lastError = "Web UI login failed (check URL / user / password)."
        }

        if snap.qbRunning {
            lastError = "qBittorrent is still running — quit it (button below) or enable the Web UI."
            if automatic { postNotification("Surfshark Guard — action needed",
                                            "qBittorrent is on the wrong binding. Quit the app so the fix can apply.") }
            return
        }

        do {
            let lines = try QBittorrent.writeBinding(
                interface: tunnel.iface, tunnelIP: tunnel.ip,
                oldAddress: snap.qbAddress)
            lastAction = "Binding written: " + lines.joined(separator: ", ")
            lastError = nil
            if automatic {
                postNotification("Surfshark Guard — binding fixed",
                                 "qBittorrent is quit — binding is now \(tunnel.iface). Start it again.")
            }
            await checkNow()
        } catch {
            lastError = "Could not write the config: \(error.localizedDescription)"
        }
    }

    func quitQBittorrentAndFix() async {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier?.lowercased().contains("qbittorrent") == true
                || $0.localizedName?.lowercased().contains("qbittorrent") == true
        }
        guard !apps.isEmpty else {
            await attemptFix(automatic: false)
            return
        }
        lastAction = "Quitting qBittorrent…"
        apps.forEach { _ = $0.terminate() }
        for _ in 0..<20 where !Detector.qbittorrentRunning() { break }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if !Detector.qbittorrentRunning() {
            await checkNow(notifyAbout: false)
            await attemptFix(automatic: false)
        }
    }

    var loginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLoginItem(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            objectWillChange.send()
        } catch {
            lastError = "Could not set login item: \(error.localizedDescription) " +
                        "(copy the app to /Applications, don’t launch from .build)"
        }
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard autoWatch else { return }
        timer = Timer.scheduledTimer(withTimeInterval: watchInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                await self?.checkNow()
                if self?.autoFix == true, self?.snapshot?.status == .wrongBinding {
                    await self?.attemptFix(automatic: true)
                }
            }
        }
    }

    private func askNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
            _, _ in
        }
    }

    private func notifyProblem(_ snap: Snapshot) {
        let text: String
        switch snap.status {
        case .wrongBinding:
            text = "qBittorrent is on \(snap.qbInterface ?? "no interface"), the tunnel is \(snap.tunnel?.iface ?? "?")"
        case .noTunnel:
            text = "No Surfshark tunnel — don’t start torrents now."
        case .ok:
            return
        }
        postNotification("Surfshark Guard", text)
    }

    private func postNotification(_ title: String, _ body: String) {
        guard notifications, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
