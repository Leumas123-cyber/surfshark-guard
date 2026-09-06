import Foundation
import Security

final class ProbeBox: @unchecked Sendable {
    var status: WebUIReachability = .unused
    var closed: WebUIReachability = .unused
}

@main
struct Selftest {
static func main() {
var failed = 0
func expect(_ cond: Bool, _ name: String, _ detail: String = "") {
    if cond {
        print("  ok  \(name)")
    } else {
        failed += 1
        print("  FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    }
}

let fixtureRoute = """
       route to: default
destination: default
       mask: default
  interface: utun9
      flags: <UP,DONE,CLONING,STATIC,GLOBAL>
"""

let fixtureNetstat = """
Routing tables

Internet:
Destination        Gateway            Flags               Netif Expire
default            192.168.1.1        UGScg                en0
0/1                10.8.0.1           UGSc                utun3
128.0/1            10.8.0.1           UGSc                utun3
10.8/10            10.8.0.1           UGSc                utun3
"""

let fixtureIfconfig = """
utun3: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1380
	inet 10.8.0.2 --> 10.8.0.1 netmask 255.255.255.255
utun9: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1380
	inet 10.14.0.2 --> 10.14.0.2 netmask 0xffff0000
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	ether aa:bb:cc:dd:ee:ff
	inet 192.168.1.42 netmask 0xffffff00 broadcast 192.168.1.255
	inet6 fe80::1%en0 prefixlen 64 scopeid 0x4
	inet6 2001:db8::5 prefixlen 64
lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
	inet 127.0.0.1 netmask 0xff000000
	inet6 ::1 prefixlen 128
"""

let fixtureIni = """
[AutoRun]
enabled=false

[BitTorrent]
Session\\Port=8999
Session\\DefaultSelectionMode=...

[Network]
Cookies=true
"""

print("== parsers ==")
expect(isVPNInterface("utun14") && isVPNInterface("ipsec0") && isVPNInterface("ppp1"), "vpn prefixes")
expect(!isVPNInterface("en0") && !isVPNInterface("utunx") && !isVPNInterface("utun"), "reject non-vpn")
expect(RouteParser.defaultInterface(from: fixtureRoute) == "utun9", "route parser")
expect(RouteParser.defaultInterface(from: "no interface here") == nil, "route parser empty")
expect(NetstatParser.tunnelCandidates(from: fixtureNetstat) == ["utun3"], "netstat full-tunnel only")
let ifaces = IfconfigParser.parse(fixtureIfconfig)
expect(ifaces["utun9"]?.ipv4 == "10.14.0.2" && ifaces["utun9"]?.mtu == "1380", "ifconfig utun9")
expect(ifaces["lo0"]?.ipv4 == nil, "ignore 127.0.0.1")
expect(ifaces["en0"]?.globalIPv6 == "2001:db8::5", "global ipv6")
expect(ifaces["lo0"]?.globalIPv6 == nil, "ignore ::1")
expect(Detector.ipv6Hint(ifconfigText: fixtureIfconfig, tunnel: "utun9")?.contains("en0") == true, "ipv6 leak hint")
expect(Detector.ipv6Hint(ifconfigText: fixtureIfconfig, tunnel: nil) == nil, "no ipv6 hint without tunnel")
expect(IfconfigParser.parse("").isEmpty, "empty ifconfig")

let (iface, addr) = IniEditor.binding(in: "[BitTorrent]\nSession\\Interface=utun7\nSession\\InterfaceName=utun7\n")
expect(iface == "utun7" && addr == nil, "ini read")
expect(IniEditor.binding(in: "[Network]\nSession\\Interface=en0\n").iface == nil, "ini ignores other section")
let applied = IniEditor.applyBinding(interface: "utun9", address: "10.14.0.2", to: fixtureIni)
expect(applied.contains("Session\\Interface=utun9") && applied.contains("Session\\Port=8999"), "ini apply keeps rest")
expect(applied.components(separatedBy: "[BitTorrent]").count - 1 == 1, "ini one BitTorrent section")
let replaced = IniEditor.applyBinding(interface: "utun14", address: nil, to: "[BitTorrent]\nSession\\Interface=utun7\n")
expect(replaced.contains("utun14") && !replaced.contains("utun7"), "ini replace")
let crlf = IniEditor.binding(in: "[BitTorrent]\r\nSession\\Interface=utun2\r\n")
expect(crlf.iface == "utun2", "ini crlf")

print("== webui urls ==")
let base = URL(string: "http://127.0.0.1:8080")!
let login = QBWebUI.endpoint("/api/v2/auth/login", on: base).absoluteString
let ver = QBWebUI.endpoint("/api/v2/app/version", on: base).absoluteString
expect(login == "http://127.0.0.1:8080/api/v2/auth/login", "login URL", login)
expect(ver == "http://127.0.0.1:8080/api/v2/app/version", "version URL", ver)
expect(!login.contains("%2F"), "no percent-encoded slashes", login)
expect(WebUIReachability.offline.menuLabel == "offline / check", "offline label")
expect(WebUIReachability.online.menuLabel == "online", "online label")

print("== keychain (isolated test item) ==")
let svc = "app.surfsharkguard.selftest"
let acc = "selftest-\(UUID().uuidString)"
KeychainStore.deletePassword(service: svc, account: acc)
expect(KeychainStore.loadPassword(service: svc, account: acc) == nil, "empty load")
expect(KeychainStore.savePassword("secret-one", service: svc, account: acc), "save")
expect(KeychainStore.loadPassword(service: svc, account: acc) == "secret-one", "load after save")
expect(KeychainStore.savePassword("secret-two", service: svc, account: acc), "update")
expect(KeychainStore.loadPassword(service: svc, account: acc) == "secret-two", "load after update")
KeychainStore.deletePassword(service: svc, account: acc)
expect(KeychainStore.loadPassword(service: svc, account: acc) == nil, "load after delete")

let suiteName = "app.surfsharkguard.selftest.defaults"
let suite = UserDefaults(suiteName: suiteName)!
suite.removePersistentDomain(forName: suiteName)
suite.set("legacy-pass", forKey: KeychainStore.defaultsLegacyKey)
let migrated = KeychainStore.migrateFromUserDefaults(suite, service: svc, account: acc)
expect(migrated == "legacy-pass", "migrate returns password")
expect(suite.object(forKey: KeychainStore.defaultsLegacyKey) == nil, "defaults wiped after migrate")
expect(KeychainStore.loadPassword(service: svc, account: acc) == "legacy-pass", "keychain has migrated secret")
suite.set("should-be-ignored", forKey: KeychainStore.defaultsLegacyKey)
let second = KeychainStore.migrateFromUserDefaults(suite, service: svc, account: acc)
expect(second == "legacy-pass", "second migrate keeps keychain")
expect(suite.object(forKey: KeychainStore.defaultsLegacyKey) == nil, "stale defaults wiped")
KeychainStore.deletePassword(service: svc, account: acc)
suite.removePersistentDomain(forName: suiteName)

print("== live detector ==")
let routeOut = Shell.run("/sbin/route", ["-n", "get", "default"])
expect(!routeOut.isEmpty, "route -n get default runs")
let ifconfigOut = Shell.run("/sbin/ifconfig", ["-a"])
expect(ifconfigOut.contains("flags="), "ifconfig -a runs")
let parsedLive = IfconfigParser.parse(ifconfigOut)
expect(!parsedLive.isEmpty, "live ifconfig parsed")
if let def = RouteParser.defaultInterface(from: routeOut) {
    print("  info default iface: \(def)")
    expect(!def.isEmpty, "default iface name")
}
let tunnel = Detector.detect(provider: .auto)
if let tunnel {
    print("  info tunnel: \(tunnel.iface) ip=\(tunnel.ip ?? "-") wg=\(tunnel.wireGuard) vpn=\(tunnel.vpnName ?? "-")")
    expect(isVPNInterface(tunnel.iface), "detected iface is vpn")
} else {
    print("  info no tunnel right now (ok if VPN is down)")
}
print("  info qbittorrent running: \(Detector.qbittorrentRunning())")
let ssProcs = Detector.vpnProcesses(for: .auto)
print("  info vpn procs: \(ssProcs.count) \(ssProcs)")
expect(VPNProvider.surfshark.matches("123 /Applications/Surfshark.app"), "surfshark match")
expect(!VPNProvider.surfshark.matches("123 SurfsharkGuard"), "ignore our process")
expect(VPNProvider.mullvad.matches("88 /Applications/Mullvad VPN.app"), "mullvad match")

print("== live webui probe ==")
let box = ProbeBox()
let sem = DispatchSemaphore(value: 0)
Task.detached {
    box.status = await QBWebUI.probe(baseURL: base)
    box.closed = await QBWebUI.probe(baseURL: URL(string: "http://127.0.0.1:1")!)
    sem.signal()
}
if sem.wait(timeout: .now() + 8) == .timedOut {
    expect(false, "webui probe finished in time")
} else {
    print("  info probe 127.0.0.1:8080 => \(box.status.menuLabel)")
    expect(box.status == .online || box.status == .offline, "probe returns a status")
    expect(box.closed == .offline, "closed port is offline")
}

print("== qbittorrent config discovery ==")
let (existing, target) = QBittorrent.findConfig()
print("  info existing: \(existing ?? "nil")")
print("  info writeTarget: \(target)")
expect(target.contains("qBittorrent.ini"), "write target is an ini path")
expect(!target.contains("/Users/anonymous/.zcode"), "no leftover author path")

print("== interval policy ==")
func effectiveInterval(watch: Double, lowPower: Bool, thermalSerious: Bool) -> Double {
    let base = max(watch, 5)
    if lowPower { return max(base, 15) }
    if thermalSerious { return max(base, 30) }
    return base
}
expect(effectiveInterval(watch: 1, lowPower: false, thermalSerious: false) == 5, "floor 5s")
expect(effectiveInterval(watch: 5, lowPower: false, thermalSerious: false) == 5, "default 5s")
expect(effectiveInterval(watch: 5, lowPower: true, thermalSerious: false) == 15, "low power stretch")
expect(effectiveInterval(watch: 5, lowPower: false, thermalSerious: true) == 30, "thermal stretch")

if failed == 0 {
    print("\nALL SELFTESTS PASSED")
    exit(0)
} else {
    print("\n\(failed) FAILED")
    exit(1)
}
}
}
