import Foundation

struct TunnelInfo {
    var iface: String
    var ip: String?
    var mtu: String?
    var wireGuard: Bool
    var surfsharkRunning: Bool
    var why: [String]
    /// Other VPN interfaces that have IPv4 (display only).
    var otherCandidates: [String]
}

enum Shell {
    static func run(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        let deadline = Date().addingTimeInterval(5)
        do {
            try process.run()
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                process.terminate()
                return ""
            }
        } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum Detector {
    /// Live process list — must be re-read on every check, not cached.
    static func surfsharkProcesses() -> [String] {
        let out = Shell.run("/usr/bin/pgrep", ["-ifl", "surfshark"])
        return out.split(separator: "\n")
            .map(String.init)
            .filter { line in
                let lower = line.lowercased()
                return !lower.contains("surfshark-guard") && !lower.contains("surfsharkguard")
            }
    }

    /// Pick the Surfshark tunnel interface. Order: default route, then
    /// WireGuard full-tunnel routes 0/1 + 128.0/1, then (if Surfshark is
    /// running and exactly one VPN interface has IPv4) that interface.
    static func detect() -> TunnelInfo? {
        let ifaces = IfconfigParser.parse(
            Shell.run("/sbin/ifconfig", ["-a"]))
        let procs = surfsharkProcesses()
        let running = !procs.isEmpty
        let wgHint = procs.contains { $0.lowercased().contains("wireguard") }

        let vpnIfaces = ifaces.filter { isVPNInterface($0.key) && $0.value.ipv4 != nil }
        let defaultIface = RouteParser.defaultInterface(
            from: Shell.run("/sbin/route", ["-n", "get", "default"]))
        let routed = NetstatParser.tunnelCandidates(
            from: Shell.run("/usr/sbin/netstat", ["-rn", "-f", "inet"]))

        var why: [String] = []
        var chosen: String?

        if let def = defaultIface, vpnIfaces[def] != nil {
            chosen = def
            why.append("Default-Route liegt auf \(def)")
        } else {
            let withIP = routed.filter { vpnIfaces[$0] != nil }.sorted()
            if let first = withIP.first {
                chosen = first
                why.append("Full-Tunnel-Routen (0/1, 128.0/1) über \(first)")
            }
        }

        if chosen == nil, running, vpnIfaces.count == 1 {
            chosen = vpnIfaces.keys.first
            why.append("einziges VPN-Interface mit IPv4 (Surfshark läuft)")
        }

        guard let iface = chosen else { return nil }

        why.append(running ? "Surfshark-Prozess läuft"
                           : "ACHTUNG: kein Surfshark-Prozess gefunden")
        if wgHint { why.append("WireGuard-Systemerweiterung aktiv") }

        return TunnelInfo(
            iface: iface,
            ip: vpnIfaces[iface]?.ipv4,
            mtu: vpnIfaces[iface]?.mtu,
            wireGuard: wgHint,
            surfsharkRunning: running,
            why: why,
            otherCandidates: vpnIfaces.keys.filter { $0 != iface }.sorted()
        )
    }

    static func qbittorrentRunning() -> Bool {
        let out = Shell.run("/usr/bin/pgrep", ["-ifl", "qbittorrent"])
        return out.split(separator: "\n").contains { line in
            let lower = line.lowercased()
            return lower.contains("qbittorrent") && !lower.contains("surfshark")
        }
    }
}
