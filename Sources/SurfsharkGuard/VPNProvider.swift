import Foundation

enum VPNProvider: String, CaseIterable, Identifiable {
    case auto
    case surfshark
    case mullvad
    case proton
    case wireguard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .surfshark: return "Surfshark"
        case .mullvad: return "Mullvad"
        case .proton: return "Proton VPN"
        case .wireguard: return "Any WireGuard"
        }
    }

    var needles: [String] {
        switch self {
        case .auto:
            return ["surfshark", "mullvad", "protonvpn", "proton vpn", "wireguard"]
        case .surfshark:
            return ["surfshark"]
        case .mullvad:
            return ["mullvad"]
        case .proton:
            return ["protonvpn", "proton vpn"]
        case .wireguard:
            return ["wireguard"]
        }
    }

    var pgrepPattern: String {
        switch self {
        case .auto: return "surfshark|mullvad|proton|wireguard"
        case .surfshark: return "surfshark"
        case .mullvad: return "mullvad"
        case .proton: return "proton"
        case .wireguard: return "wireguard"
        }
    }

    func matches(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("surfsharkguard") || lower.contains("surfshark-guard") {
            return false
        }
        return needles.contains { lower.contains($0) }
    }

    func label(in lines: [String]) -> String? {
        let blob = lines.joined(separator: "\n").lowercased()
        if blob.contains("surfshark") { return "Surfshark" }
        if blob.contains("mullvad") { return "Mullvad" }
        if blob.contains("proton") { return "Proton VPN" }
        if blob.contains("wireguard") { return "WireGuard" }
        return title == "Auto" ? nil : title
    }
}
