import Foundation

func isVPNInterface(_ name: String) -> Bool {
    for prefix in ["utun", "ipsec", "ppp"] where name.hasPrefix(prefix) {
        let rest = name.dropFirst(prefix.count)
        return !rest.isEmpty && rest.allSatisfy(\.isNumber)
    }
    return false
}

enum RouteParser {
    /// Interface that carries the default route (`  interface: utun9`).
    static func defaultInterface(from output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                let iface = trimmed.dropFirst("interface:".count)
                    .trimmingCharacters(in: .whitespaces)
                if !iface.isEmpty { return iface }
            }
        }
        return nil
    }
}

enum NetstatParser {
    /// utun/ipsec/ppp interfaces that carry full-tunnel routes
    /// (default, or both 0/1 and 128.0/1 — WireGuard style).
    static func tunnelCandidates(from output: String) -> Set<String> {
        let lowerHalf = Set(["0/1", "0.0.0.0/1"])
        let upperHalf = Set(["128/1", "128.0/1", "128.0.0.0/1"])
        var defaults = Set<String>()
        var lowerHits = Set<String>()
        var upperHits = Set<String>()
        for line in output.split(separator: "\n") {
            guard line.first != " " else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4 else { continue }
            let destination = String(parts[0])
            let interface = String(parts[3])
            guard isVPNInterface(interface) else { continue }
            if destination == "default" {
                defaults.insert(interface)
            } else if lowerHalf.contains(destination) {
                lowerHits.insert(interface)
            } else if upperHalf.contains(destination) {
                upperHits.insert(interface)
            }
        }
        return defaults.union(lowerHits.intersection(upperHits))
    }
}

struct IfInfo {
    var ipv4: String?
    var globalIPv6: String?
    var mtu: String?
    var up: Bool
}

enum IfconfigParser {
    /// Interfaces with IPv4, MTU and UP status (127.* is ignored).
    static func parse(_ text: String) -> [String: IfInfo] {
        var result: [String: IfInfo] = [:]
        var current: String?
        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine)
            if let name = interfaceName(of: line) {
                current = name
                result[name] = IfInfo(ipv4: nil, globalIPv6: nil, mtu: mtu(of: line), up: isUp(of: line))
                continue
            }
            guard let cur = current, result[cur] != nil else { continue }
            if let ip = ipv4(of: line) {
                result[cur]?.ipv4 = ip
            }
            if result[cur]?.globalIPv6 == nil, let ip6 = ipv6(of: line) {
                result[cur]?.globalIPv6 = ip6
            }
        }
        return result
    }

    private static func interfaceName(of line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let name = String(line[..<colon])
        let rest = line[line.index(after: colon)...]
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/"), rest.hasPrefix("flags=") else {
            return nil
        }
        return name
    }

    private static func isUp(of line: String) -> Bool {
        guard let open = line.firstIndex(of: "<"),
              let close = line.firstIndex(of: ">"), open < close else { return false }
        let flags = line[line.index(after: open)..<close]
            .split(separator: ",").map(String.init)
        return flags.first == "UP" || flags.contains("UP")
    }

    private static func mtu(of line: String) -> String? {
        guard let range = line.range(of: " mtu ") else { return nil }
        let digits = line[range.upperBound...].prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    private static func ipv4(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("inet ") else { return nil }
        let ip = trimmed.dropFirst("inet ".count)
            .split(separator: " ").first.map(String.init) ?? ""
        let parts = ip.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return ip.hasPrefix("127.") ? nil : ip
    }

    /// Global IPv6 only — skip link-local, loopback, and unique-local.
    private static func ipv6(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("inet6 ") else { return nil }
        var ip = trimmed.dropFirst("inet6 ".count)
            .split(separator: " ").first.map(String.init) ?? ""
        if let pct = ip.firstIndex(of: "%") {
            ip = String(ip[..<pct])
        }
        let lower = ip.lowercased()
        if lower.hasPrefix("fe80") || lower == "::1"
            || lower.hasPrefix("fc") || lower.hasPrefix("fd") {
            return nil
        }
        return ip.isEmpty ? nil : ip
    }
}

/// Line-oriented editor for the binding keys under [BitTorrent].
/// Everything else in the file is left as-is.
enum IniEditor {
    static let interfaceKeys = ["Session\\Interface", "Session\\InterfaceName"]
    static let addressKey = "Session\\InterfaceAddress"

    static func normalizedLines(_ text: String) -> [Substring] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
    }

    static func binding(in text: String) -> (iface: String?, addr: String?) {
        var iface: String?
        var addr: String?
        var inSection = false
        for raw in normalizedLines(text) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inSection = line.lowercased() == "[bittorrent]"
                continue
            }
            guard inSection, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if interfaceKeys.contains(key), !value.isEmpty {
                iface = value
            } else if key == addressKey, !value.isEmpty {
                addr = value
            }
        }
        return (iface, addr)
    }

    static func applyBinding(interface: String, address: String?, to text: String) -> String {
        var lines = normalizedLines(text).map(String.init)

        var wanted: [(key: String, value: String)] =
            interfaceKeys.map { ($0, interface) }
        if let address { wanted.append((addressKey, address)) }

        var sectionStart: Int? = nil
        for (i, raw) in lines.enumerated()
        where raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "[bittorrent]" {
            sectionStart = i
            break
        }
        if sectionStart == nil {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("")
            }
            lines.append("[BitTorrent]")
            sectionStart = lines.count - 1
        }

        var sectionEnd = lines.count
        if let start = sectionStart {
            for i in (start + 1)..<lines.count where
                lines[i].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                sectionEnd = i
                break
            }
        }

        for entry in wanted {
            var replaced = false
            if let start = sectionStart {
                for i in (start + 1)..<sectionEnd {
                    let key = lines[i].split(separator: "=", maxSplits: 1,
                                             omittingEmptySubsequences: false)
                        .first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if key == entry.key {
                        lines[i] = "\(entry.key)=\(entry.value)"
                        replaced = true
                        break
                    }
                }
            }
            if !replaced {
                lines.insert("\(entry.key)=\(entry.value)", at: sectionEnd)
                sectionEnd += 1
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
