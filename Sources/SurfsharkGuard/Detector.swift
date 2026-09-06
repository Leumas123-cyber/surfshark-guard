import Foundation

struct TunnelInfo {
    var iface: String
    var ip: String?
    var mtu: String?
    var wireGuard: Bool
    var vpnRunning: Bool
    var vpnName: String?
    var why: [String]
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
    static func vpnProcesses(for provider: VPNProvider) -> [String] {
        let out = Shell.run("/usr/bin/pgrep", ["-ifl", provider.pgrepPattern])
        return out.split(separator: "\n")
            .map(String.init)
            .filter { provider.matches($0) }
    }

    static func detect(provider: VPNProvider = .auto) -> TunnelInfo? {
        let ifaces = IfconfigParser.parse(
            Shell.run("/sbin/ifconfig", ["-a"]))
        let procs = vpnProcesses(for: provider)
        let running = !procs.isEmpty
        let vpnName = provider.label(in: procs)
        let wgHint = procs.contains { $0.lowercased().contains("wireguard") }
            || provider == .wireguard

        let vpnIfaces = ifaces.filter { isVPNInterface($0.key) && $0.value.ipv4 != nil }
        let defaultIface = RouteParser.defaultInterface(
            from: Shell.run("/sbin/route", ["-n", "get", "default"]))
        let routed = NetstatParser.tunnelCandidates(
            from: Shell.run("/usr/sbin/netstat", ["-rn", "-f", "inet"]))

        var why: [String] = []
        var chosen: String?

        if let def = defaultIface, vpnIfaces[def] != nil {
            chosen = def
            why.append("Default route is on \(def)")
        } else {
            let withIP = routed.filter { vpnIfaces[$0] != nil }.sorted()
            if let first = withIP.first {
                chosen = first
                why.append("Full-tunnel routes (0/1, 128.0/1) via \(first)")
            }
        }

        if chosen == nil, running, vpnIfaces.count == 1 {
            chosen = vpnIfaces.keys.first
            why.append("only VPN interface with IPv4 (\(vpnName ?? provider.title) is running)")
        }

        guard let iface = chosen else { return nil }

        if running {
            why.append("\(vpnName ?? "VPN") process is running")
        } else if provider == .wireguard || provider == .auto {
            why.append("WARNING: no matching VPN process found")
        } else {
            why.append("WARNING: no \(provider.title) process found")
        }
        if wgHint { why.append("WireGuard-style tunnel or extension") }

        return TunnelInfo(
            iface: iface,
            ip: vpnIfaces[iface]?.ipv4,
            mtu: vpnIfaces[iface]?.mtu,
            wireGuard: wgHint,
            vpnRunning: running,
            vpnName: vpnName,
            why: why,
            otherCandidates: vpnIfaces.keys.filter { $0 != iface }.sorted()
        )
    }

    /// Global IPv6 still on Wi‑Fi/Ethernet while a VPN tunnel is up.
    static func ipv6Hint(ifconfigText: String = Shell.run("/sbin/ifconfig", ["-a"]),
                         tunnel: String?) -> String? {
        guard tunnel != nil else { return nil }
        let ifaces = IfconfigParser.parse(ifconfigText)
        let leaks = ifaces
            .filter { name, info in
                !isVPNInterface(name) && name.hasPrefix("en") && info.globalIPv6 != nil
            }
            .sorted { $0.key < $1.key }
        guard let first = leaks.first, let ip = first.value.globalIPv6 else { return nil }
        return "\(first.key) still has IPv6 \(ip) — possible leak"
    }

    static func qbittorrentRunning() -> Bool {
        let out = Shell.run("/usr/bin/pgrep", ["-ifl", "qbittorrent"])
        return out.split(separator: "\n").contains { line in
            let lower = line.lowercased()
            return lower.contains("qbittorrent") && !lower.contains("surfshark")
        }
    }
}
