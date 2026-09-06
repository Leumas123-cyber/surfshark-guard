import XCTest
@testable import SurfsharkGuard

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
lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
	inet 127.0.0.1 netmask 0xff000000
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

final class ParsersTests: XCTestCase {

    func testInterfaceTypeCheck() {
        XCTAssertTrue(isVPNInterface("utun14"))
        XCTAssertTrue(isVPNInterface("ipsec0"))
        XCTAssertTrue(isVPNInterface("ppp1"))
        XCTAssertFalse(isVPNInterface("en0"))
        XCTAssertFalse(isVPNInterface("utunx"))
        XCTAssertFalse(isVPNInterface("utun"))
    }

    func testRouteParserFindsInterface() {
        XCTAssertEqual(RouteParser.defaultInterface(from: fixtureRoute), "utun9")
        XCTAssertNil(RouteParser.defaultInterface(from: "no interface here"))
    }

    func testNetstatParserTunnelCandidates() {
        XCTAssertEqual(NetstatParser.tunnelCandidates(from: fixtureNetstat),
                       ["utun3"])
    }

    func testIfconfigParser() {
        let ifaces = IfconfigParser.parse(fixtureIfconfig)
        XCTAssertEqual(ifaces["utun9"]?.ipv4, "10.14.0.2")
        XCTAssertEqual(ifaces["utun9"]?.mtu, "1380")
        XCTAssertEqual(ifaces["utun3"]?.ipv4, "10.8.0.2")
        XCTAssertEqual(ifaces["en0"]?.ipv4, "192.168.1.42")
        XCTAssertTrue(ifaces["utun9"]?.up ?? false)
        XCTAssertNil(ifaces["lo0"]?.ipv4)
    }

    func testIniBindingRead() {
        let text = "[BitTorrent]\nSession\\Interface=utun7\n"
            + "Session\\InterfaceName=utun7\nSession\\Port=123\n"
        let (iface, addr) = IniEditor.binding(in: text)
        XCTAssertEqual(iface, "utun7")
        XCTAssertNil(addr)

        let withAddr = text + "Session\\InterfaceAddress=10.8.0.9\n"
        XCTAssertEqual(IniEditor.binding(in: withAddr).addr, "10.8.0.9")

        let outside = "[Network]\nSession\\Interface=en0\n"
        XCTAssertNil(IniEditor.binding(in: outside).iface)
    }

    func testIniApplySetsInterfaceAndMovesAddress() {
        let result = IniEditor.applyBinding(interface: "utun9",
                                            address: "10.14.0.2",
                                            to: fixtureIni)
        XCTAssertTrue(result.contains("Session\\Interface=utun9"))
        XCTAssertTrue(result.contains("Session\\InterfaceName=utun9"))
        XCTAssertTrue(result.contains("Session\\InterfaceAddress=10.14.0.2"))
        XCTAssertTrue(result.contains("Session\\Port=8999"))
        XCTAssertTrue(result.contains("[Network]"))
        XCTAssertTrue(result.contains("Cookies=true"))
        XCTAssertEqual(result.components(separatedBy: "[BitTorrent]").count - 1, 1)
    }

    func testIniApplyCreatesMissingSection() {
        let result = IniEditor.applyBinding(interface: "utun2", address: nil,
                                            to: "[Network]\nCookies=true\n")
        XCTAssertTrue(result.contains("[BitTorrent]"))
        XCTAssertTrue(result.contains("Session\\Interface=utun2"))
        XCTAssertFalse(result.contains("Session\\InterfaceAddress"))
        XCTAssertTrue(result.contains("[Network]"))
    }

    func testIniApplyReplacesExistingBinding() {
        let text = "[BitTorrent]\nSession\\Interface=utun7\n"
        let result = IniEditor.applyBinding(interface: "utun14", address: nil,
                                            to: text)
        XCTAssertTrue(result.contains("Session\\Interface=utun14"))
        XCTAssertFalse(result.contains("utun7"))
    }
}
