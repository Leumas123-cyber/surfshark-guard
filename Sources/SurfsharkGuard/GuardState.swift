import Foundation
import SwiftUI
import UserNotifications
import AppKit
import ServiceManagement
import Network

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
        case .noTunnel: return "No VPN tunnel"
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
    var webUI: WebUIReachability
    var bindingSource: String?
    var ipv6Hint: String?
    var lastPaused: Bool
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
        didSet { defaults.set(autoWatch, forKey: "autoWatch"); rescheduleTimer(); startPathMonitor() }
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
        didSet {
            guard !isHydrating else { return }
            if webuiPass.isEmpty {
                KeychainStore.deletePassword()
            } else {
                _ = KeychainStore.savePassword(webuiPass)
            }
        }
    }
    @Published var vpnProvider: VPNProvider {
        didSet { defaults.set(vpnProvider.rawValue, forKey: "vpnProvider") }
    }
    @Published var pauseOnDrop: Bool {
        didSet { defaults.set(pauseOnDrop, forKey: "pauseOnDrop") }
    }
    @Published var onboardingDone: Bool {
        didSet { defaults.set(onboardingDone, forKey: "onboardingDone") }
    }
    @Published var checkUpdates: Bool {
        didSet { defaults.set(checkUpdates, forKey: "checkUpdates") }
    }
    @Published var updateAvailable: UpdateInfo?
    @Published var updateCheckMessage: String?
    @Published var loginTestResult: String?

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var qBQuitObserver: Any?
    private var powerObserver: Any?
    private var pathMonitor: NWPathMonitor?
    private var pathDebounce: DispatchWorkItem?
    private var isHydrating = true
    private var didCheckUpdate = false

    private init() {
        autoWatch = defaults.object(forKey: "autoWatch") as? Bool ?? true
        autoFix = defaults.object(forKey: "autoFix") as? Bool ?? false
        notifications = defaults.object(forKey: "notifications") as? Bool ?? true
        watchInterval = defaults.object(forKey: "watchInterval") as? Double ?? 5
        webuiEnabled = defaults.bool(forKey: "webuiEnabled")
        webuiURL = defaults.string(forKey: "webuiURL") ?? "http://127.0.0.1:8080"
        webuiUser = defaults.string(forKey: "webuiUser") ?? ""
        webuiPass = KeychainStore.migrateFromUserDefaults(defaults)
        vpnProvider = VPNProvider(rawValue: defaults.string(forKey: "vpnProvider") ?? "") ?? .auto
        pauseOnDrop = defaults.object(forKey: "pauseOnDrop") as? Bool ?? true
        onboardingDone = defaults.bool(forKey: "onboardingDone")
        checkUpdates = defaults.object(forKey: "checkUpdates") as? Bool ?? true
        isHydrating = false

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

        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rescheduleTimer() }
        }

        Task { await checkNow() }
        rescheduleTimer()
        startPathMonitor()
        scheduleUpdateCheck()
    }

    func start() {
        Task { await checkNow() }
        rescheduleTimer()
        startPathMonitor()
        if notifications { askNotificationPermission() }
        scheduleUpdateCheck()
    }

    func scheduleUpdateCheck() {
        guard checkUpdates, !didCheckUpdate else { return }
        didCheckUpdate = true
        Task { await checkForUpdate() }
    }

    func checkForUpdate() async {
        updateCheckMessage = nil
        let current = UpdateCheck.currentVersion()
        guard let latest = await UpdateCheck.fetchLatest() else {
            updateCheckMessage = "Could not reach GitHub Releases"
            return
        }
        let tag = UpdateCheck.normalize(latest.tag)
        if UpdateCheck.isNewer(latest.tag, than: current) {
            updateAvailable = UpdateInfo(latest: tag, current: current, htmlURL: latest.htmlURL)
            updateCheckMessage = "Version \(tag) is available (you have \(current))"
        } else {
            updateAvailable = nil
            updateCheckMessage = "You’re on \(current) — latest is \(tag)"
        }
    }

    func openLatestRelease() {
        NSWorkspace.shared.open(updateAvailable?.htmlURL ?? UpdateCheck.releasesPage)
    }

    func checkNow(notifyAbout: Bool = true) async {
        if checking { return }
        checking = true
        defer { checking = false }

        let snap = await gather()
        let previous = snapshot?.status
        snapshot = snap

        if previous != nil, previous != .noTunnel, snap.status == .noTunnel {
            await pauseTorrentsIfNeeded()
        }
        if autoFix, snap.status == .wrongBinding {
            await attemptFix(automatic: true)
        }

        if notifyAbout, previous != nil, previous != snap.status,
           notifications, snap.status != .ok {
            notifyProblem(snap)
        }
        lastNotifiedStatus = snap.status
    }

    private func gather() async -> Snapshot {
        let probeURL = webuiEnabled ? URL(string: webuiURL) : nil
        let enabled = webuiEnabled
        let user = webuiUser
        let pass = webuiPass
        let provider = vpnProvider
        return await Task.detached(priority: .utility) {
            let ifconfigText = Shell.run("/sbin/ifconfig", ["-a"])
            let tunnel = Detector.detect(provider: provider)
            let (existing, target) = QBittorrent.findConfig()
            var iface: String?
            var addr: String?
            var source: String? = nil
            if let path = existing, let text = try? String(contentsOfFile: path,
                                                            encoding: .utf8) {
                (iface, addr) = IniEditor.binding(in: text)
                if iface != nil { source = "ini" }
            }
            var webUI: WebUIReachability = .unused
            if enabled, let probeURL {
                webUI = await QBWebUI.probe(baseURL: probeURL)
                if webUI == .online, !user.isEmpty {
                    let ui = QBWebUI(baseURL: probeURL, user: user, password: pass)
                    if await ui.login(), let live = await ui.currentBinding() {
                        iface = live.iface
                        addr = live.addr ?? addr
                        source = "web UI"
                    }
                }
            }
            return Snapshot(
                tunnel: tunnel,
                qbRunning: Detector.qbittorrentRunning(),
                qbInterface: iface,
                qbAddress: addr,
                configPath: existing,
                writeTarget: target,
                webUI: webUI,
                bindingSource: source,
                ipv6Hint: Detector.ipv6Hint(ifconfigText: ifconfigText, tunnel: tunnel?.iface),
                lastPaused: false,
                checkedAt: Date()
            )
        }.value
    }

    func attemptFix(automatic: Bool) async {
        guard let snap = snapshot else { return }
        guard let tunnel = snap.tunnel else {
            lastError = "No tunnel — connect the VPN first."
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
        for _ in 0..<20 {
            if !Detector.qbittorrentRunning() { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
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

    /// Never tighter than 5 s. Low Power Mode stretches the gap so route/ifconfig
    /// is not a tight loop.
    private var effectiveWatchInterval: TimeInterval {
        let floor: TimeInterval = 5
        let base = max(watchInterval, floor)
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return max(base, 15) }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: return max(base, 30)
        default: return base
        }
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard autoWatch else { return }
        let interval = effectiveWatchInterval
        let scheduled = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                await self?.checkNow()
            }
        }
        scheduled.tolerance = min(2, interval * 0.3)
        timer = scheduled
    }

    private func startPathMonitor() {
        pathMonitor?.cancel()
        guard autoWatch else {
            pathMonitor = nil
            return
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pathDebounce?.cancel()
                let work = DispatchWorkItem {
                    Task { @MainActor in
                        await self.checkNow()
                    }
                }
                self.pathDebounce = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        pathMonitor = monitor
    }

    func testWebUILogin() async {
        loginTestResult = nil
        guard let url = URL(string: webuiURL) else {
            loginTestResult = "Invalid URL"
            return
        }
        let ui = QBWebUI(baseURL: url, user: webuiUser, password: webuiPass)
        if await ui.login() {
            loginTestResult = "Login works"
        } else {
            loginTestResult = "Login failed — check user / password / Web UI"
        }
    }

    private func pauseTorrentsIfNeeded() async {
        guard pauseOnDrop, webuiEnabled, !webuiUser.isEmpty,
              let url = URL(string: webuiURL) else { return }
        let ui = QBWebUI(baseURL: url, user: webuiUser, password: webuiPass)
        guard await ui.login() else { return }
        if await ui.pauseAllTorrents() {
            lastAction = "VPN dropped — paused all torrents"
            if var snap = snapshot { snap.lastPaused = true; snapshot = snap }
            postNotification("Surfshark Guard — torrents paused",
                             "The VPN tunnel went down, so qBittorrent was paused.")
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
            text = "No VPN tunnel — torrents should stay paused."
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
