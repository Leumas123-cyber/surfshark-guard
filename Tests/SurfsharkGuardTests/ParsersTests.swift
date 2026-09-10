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

        let lowerHalfOnly = """
        Destination Gateway Flags Netif
        0/1 10.8.0.1 UGSc utun3
        """
        XCTAssertTrue(NetstatParser.tunnelCandidates(from: lowerHalfOnly).isEmpty)

        let splitAcrossInterfaces = """
        Destination Gateway Flags Netif
        0/1 10.8.0.1 UGSc utun3
        128.0/1 10.14.0.1 UGSc utun9
        """
        XCTAssertTrue(NetstatParser.tunnelCandidates(from: splitAcrossInterfaces).isEmpty)
    }

    func testIfconfigParser() {
        let ifaces = IfconfigParser.parse(fixtureIfconfig)
        XCTAssertEqual(ifaces["utun9"]?.ipv4, "10.14.0.2")
        XCTAssertEqual(ifaces["utun9"]?.mtu, "1380")
        XCTAssertEqual(ifaces["utun3"]?.ipv4, "10.8.0.2")
        XCTAssertEqual(ifaces["en0"]?.ipv4, "192.168.1.42")
        XCTAssertTrue(ifaces["utun9"]?.up ?? false)
        XCTAssertNil(ifaces["lo0"]?.ipv4)
        XCTAssertEqual(ifaces["en0"]?.globalIPv6, "2001:db8::5")
        XCTAssertNil(ifaces["lo0"]?.globalIPv6)
        XCTAssertTrue(Detector.ipv6Hint(ifconfigText: fixtureIfconfig, tunnel: "utun9")?.contains("en0") == true)
        XCTAssertNil(Detector.ipv6Hint(ifconfigText: fixtureIfconfig, tunnel: nil))
    }

    func testUpdateCheckVersions() {
        XCTAssertEqual(UpdateCheck.normalize("v1.3"), "1.3")
        XCTAssertTrue(UpdateCheck.isNewer("v1.3", than: "1.2"))
        XCTAssertTrue(UpdateCheck.isNewer("1.10", than: "1.2"))
        XCTAssertFalse(UpdateCheck.isNewer("1.3", than: "1.3"))
        XCTAssertFalse(UpdateCheck.isNewer("1.2", than: "1.3"))
        let data = Data(#"{"tag_name":"v1.2","html_url":"https://example.com/r"}"#.utf8)
        XCTAssertEqual(UpdateCheck.parseLatest(from: data)?.tag, "v1.2")
        XCTAssertEqual(UpdateCheck.parseLatest(from: data)?.htmlURL,
                       UpdateCheck.releasesPage)

        let trusted = Data(
            #"{"tag_name":"v1.4","html_url":"https://github.com/Leumas123-cyber/surfshark-guard/releases/tag/v1.4"}"#.utf8
        )
        XCTAssertEqual(UpdateCheck.parseLatest(from: trusted)?.htmlURL.absoluteString,
                       "https://github.com/Leumas123-cyber/surfshark-guard/releases/tag/v1.4")
        XCTAssertFalse(UpdateCheck.isTrustedReleaseURL(
            URL(string: "https://github.com.evil.example/Leumas123-cyber/surfshark-guard/releases/tag/v1.4")!
        ))
    }

    func testMenuBarTooltip() {
        XCTAssertEqual(MenuBarTooltip.text(tunnel: "utun14", qbInterface: "utun14"),
                       "utun14 · sealed")
        XCTAssertTrue(MenuBarTooltip.text(tunnel: "utun14", qbInterface: "en0")
            .contains("leak risk"))
        XCTAssertEqual(MenuBarTooltip.text(tunnel: nil, qbInterface: "en0"),
                       "No VPN tunnel")
    }

    func testVPNProviderMatching() {
        XCTAssertTrue(VPNProvider.surfshark.matches("123 /Applications/Surfshark.app"))
        XCTAssertFalse(VPNProvider.surfshark.matches("123 SurfsharkGuard"))
        XCTAssertTrue(VPNProvider.mullvad.matches("88 /Applications/Mullvad VPN.app"))
        XCTAssertTrue(VPNProvider.proton.matches("9 ProtonVPN"))
        XCTAssertTrue(VPNProvider.auto.matches("wireguard-go"))
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

    func testIniBindingReadsCRLF() {
        let (iface, _) = IniEditor.binding(in: "[BitTorrent]\r\nSession\\Interface=utun2\r\n")
        XCTAssertEqual(iface, "utun2")
    }

    func testIniApplyReplacesExistingBinding() {
        let text = "[BitTorrent]\nSession\\Interface=utun7\n"
        let result = IniEditor.applyBinding(interface: "utun14", address: nil,
                                            to: text)
        XCTAssertTrue(result.contains("Session\\Interface=utun14"))
        XCTAssertFalse(result.contains("utun7"))
    }

    func testWebUIURLValidation() {
        for raw in [
            "http://127.0.0.1:8080",
            "http://localhost:8080",
            "https://localhost",
            "http://[::1]:8080",
        ] {
            XCTAssertNotNil(WebUIURLValidator.validated(raw), raw)
        }
        for raw in [
            "http://127.0.0.1.evil.example:8080",
            "https://example.com",
            "file:///tmp/qb",
            "http://user:password@localhost:8080",
        ] {
            XCTAssertNil(WebUIURLValidator.validated(raw), raw)
        }
    }

    func testBindingStatusIncludesAddressWhenBothAreKnown() {
        let tunnel = TunnelInfo(
            iface: "utun9", ip: "10.14.0.2", mtu: nil,
            wireGuard: true, vpnRunning: true, vpnName: "VPN",
            why: [], otherCandidates: []
        )
        XCTAssertTrue(bindingMatchesTunnel(
            interface: "utun9", address: "10.14.0.2", tunnel: tunnel
        ))
        XCTAssertFalse(bindingMatchesTunnel(
            interface: "utun9", address: "10.8.0.2", tunnel: tunnel
        ))
        XCTAssertTrue(bindingMatchesTunnel(
            interface: "utun9", address: nil, tunnel: tunnel
        ))
    }

    func testDetectorRejectsSingleHalfRoute() {
        let halfRoute = "0/1 10.8.0.1 UGSc utun3\n"
        XCTAssertNil(Detector.detect(
            provider: .wireguard,
            ifconfigText: fixtureIfconfig,
            routeText: "",
            netstatText: halfRoute,
            processText: "42 wireguard-go"
        ))

        let tunnel = Detector.detect(
            provider: .wireguard,
            ifconfigText: fixtureIfconfig,
            routeText: "",
            netstatText: fixtureNetstat,
            processText: "42 wireguard-go"
        )
        XCTAssertEqual(tunnel?.iface, "utun3")
    }

    func testStateTransitionHelpers() {
        XCTAssertTrue(shouldPauseTorrents(previous: nil, current: .noTunnel))
        XCTAssertTrue(shouldPauseTorrents(previous: .ok, current: .noTunnel))
        XCTAssertFalse(shouldPauseTorrents(previous: .noTunnel, current: .noTunnel))

        XCTAssertTrue(shouldNotifyProblem(
            status: .wrongBinding, lastNotified: nil,
            notificationsEnabled: true, requested: true
        ))
        XCTAssertFalse(shouldNotifyProblem(
            status: .wrongBinding, lastNotified: .wrongBinding,
            notificationsEnabled: true, requested: true
        ))

        var queue = CheckRequestQueue()
        queue.enqueue(notify: false)
        queue.enqueue(notify: true)
        XCTAssertEqual(queue.take(), true)
        XCTAssertNil(queue.take())

        var gate = NotificationEpisodeGate()
        XCTAssertTrue(gate.shouldPost())
        XCTAssertFalse(gate.shouldPost())
        gate.reset()
        XCTAssertTrue(gate.shouldPost())
    }

    func testWebUIRequiresSuccessfulHTTPResponses() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let baseURL = URL(string: "http://127.0.0.1:8080")!

        URLProtocolStub.handler = { request in
            if request.url?.path == "/api/v2/auth/login" {
                return (200, Data("Ok.".utf8))
            }
            if request.url?.path == "/api/v2/app/setPreferences" {
                return (500, Data("failed".utf8))
            }
            return (404, Data())
        }
        let failingSet = QBWebUI(
            baseURL: baseURL, user: "admin", password: "secret", session: session
        )
        let loginSucceeded = await failingSet.login()
        let setSucceeded = await failingSet.setInterface("utun9", address: nil)
        XCTAssertTrue(loginSucceeded)
        XCTAssertFalse(setSucceeded)

        URLProtocolStub.handler = { _ in (403, Data("Ok.".utf8)) }
        let rejectedLogin = QBWebUI(
            baseURL: baseURL, user: "admin", password: "secret", session: session
        )
        let rejected = await rejectedLogin.login()
        XCTAssertFalse(rejected)
    }
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(
            self, didReceive: response, cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
