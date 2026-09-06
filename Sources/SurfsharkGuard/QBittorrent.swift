import Foundation

enum QBittorrent {
    static func configCandidates() -> [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Preferences/qBittorrent/qBittorrent.ini",
            "\(home)/Library/Application Support/qBittorrent/qBittorrent.ini",
            "\(home)/.config/qBittorrent/qBittorrent.ini",
        ]
    }

    static let fm = FileManager.default

    /// Returns (existing config or nil, write target for a fix).
    /// If several ini files exist, the newest wins. If none exist yet,
    /// prefer the directory that already has a lockfile or ipc-socket.
    static func findConfig() -> (existing: String?, writeTarget: String) {
        let cands = configCandidates()
        var existing: [(date: Date, path: String)] = []
        for path in cands where fm.fileExists(atPath: path) {
            let attrs = try? fm.attributesOfItem(atPath: path)
            let date = attrs?[.modificationDate] as? Date ?? .distantPast
            existing.append((date, path))
        }
        if let newest = existing.sorted(by: { $0.date > $1.date }).first {
            return (newest.path, newest.path)
        }
        for path in cands {
            let dir = (path as NSString).deletingLastPathComponent
            if fm.fileExists(atPath: dir + "/lockfile") ||
               fm.fileExists(atPath: dir + "/ipc-socket") {
                return (nil, path)
            }
        }
        return (nil, cands[0])
    }

    static func readBinding() -> (iface: String?, addr: String?) {
        guard let path = findConfig().existing,
              let text = try? String(contentsOfFile: path, encoding: .utf8)
        else { return (nil, nil) }
        return IniEditor.binding(in: text)
    }

    /// Write the binding: timestamped backup, then atomic replace.
    /// An old bind address that belonged to the previous interface is
    /// moved to the current tunnel IP.
    @discardableResult
    static func writeBinding(interface: String, tunnelIP: String?,
                             oldAddress: String?) throws -> [String] {
        let target = findConfig().writeTarget
        let old = (try? String(contentsOfFile: target, encoding: .utf8)) ?? ""
        let backupPath = target + ".bak-" + timestamp()
        if !old.isEmpty {
            try old.write(toFile: backupPath, atomically: true, encoding: .utf8)
        }

        var address: String? = nil
        if let oldAddress, let tunnelIP, oldAddress != tunnelIP {
            address = tunnelIP
        } else if let oldAddress {
            address = oldAddress
        }

        let newText = IniEditor.applyBinding(interface: interface,
                                             address: address, to: old)
        try newText.write(toFile: target, atomically: true, encoding: .utf8)
        var written = ["Session\\Interface=\(interface)",
                       "Session\\InterfaceName=\(interface)"]
        if let address { written.append("Session\\InterfaceAddress=\(address)") }
        if !old.isEmpty { written.append("Backup: \((backupPath as NSString).lastPathComponent)") }
        return written
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
