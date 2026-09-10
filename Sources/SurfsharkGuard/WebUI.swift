import Foundation

enum WebUIReachability: Equatable {
    case unused
    case online
    case offline

    var menuLabel: String {
        switch self {
        case .unused: return "off"
        case .online: return "online"
        case .offline: return "offline / check"
        }
    }
}

enum WebUIURLValidator {
    static func isAllowed(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil,
              components.password == nil,
              let rawHost = components.host?.lowercased()
        else { return false }

        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    static func validated(_ rawValue: String) -> URL? {
        guard let url = URL(string: rawValue), isAllowed(url) else { return nil }
        return url
    }
}

/// Minimal qBittorrent Web API client — live interface rebinding only.
struct QBWebUI {
    let baseURL: URL
    let user: String
    let password: String
    private let session: URLSession

    init(baseURL: URL, user: String, password: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.user = user
        self.password = password
        self.session = session ?? Self.makeSession()
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 4
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    static func endpoint(_ path: String, on baseURL: URL) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var root = baseURL.absoluteString
        if !root.hasSuffix("/") { root += "/" }
        if let base = URL(string: root), let url = URL(string: trimmed, relativeTo: base) {
            return url.absoluteURL
        }
        return baseURL.appending(path: trimmed)
    }

    private func post(_ path: String, form: [String: String]) async throws -> (body: String, code: Int) {
        guard WebUIURLValidator.isAllowed(baseURL) else {
            throw URLError(.unsupportedURL)
        }
        var components = URLComponents()
        components.queryItems = form.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        let body = components.percentEncodedQuery?.data(using: .utf8) ?? Data()
        var request = URLRequest(url: Self.endpoint(path, on: baseURL))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (String(data: data, encoding: .utf8) ?? "", code)
    }

    private static let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Cheap reachability: any HTTP answer means the Web UI is up (403 is fine).
    static func probe(baseURL: URL) async -> WebUIReachability {
        guard WebUIURLValidator.isAllowed(baseURL) else { return .offline }
        var request = URLRequest(url: endpoint("/api/v2/app/version", on: baseURL))
        request.httpMethod = "GET"
        request.timeoutInterval = 1.5
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        do {
            let (_, response) = try await probeSession.data(for: request)
            return response is HTTPURLResponse ? .online : .offline
        } catch {
            return .offline
        }
    }

    func login() async -> Bool {
        guard WebUIURLValidator.isAllowed(baseURL), !user.isEmpty else { return false }
        let result = try? await post("/api/v2/auth/login",
                                     form: ["username": user, "password": password])
        guard let result, (200...299).contains(result.code) else { return false }
        let body = result.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return body == "Ok." || body == "Ok"
    }

    /// Live NIC from a running qBittorrent (ini can be stale).
    func currentBinding() async -> (iface: String?, addr: String?)? {
        guard WebUIURLValidator.isAllowed(baseURL) else { return nil }
        var request = URLRequest(url: Self.endpoint("/api/v2/app/preferences", on: baseURL))
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(code),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            func nonEmpty(_ key: String) -> String? {
                guard let raw = json[key] as? String else { return nil }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            let iface = nonEmpty("current_interface_name")
                ?? nonEmpty("current_network_interface")
            return (iface, nonEmpty("current_interface_address"))
        } catch {
            return nil
        }
    }

    /// qB 4.x uses pause; qB 5.x uses stop.
    func pauseAllTorrents() async -> Bool {
        guard WebUIURLValidator.isAllowed(baseURL) else { return false }
        for path in ["/api/v2/torrents/stop", "/api/v2/torrents/pause"] {
            if let result = try? await post(path, form: ["hashes": "all"]),
               (200...299).contains(result.code) {
                return true
            }
        }
        return false
    }

    /// `current_network_interface` is the older qBittorrent key; unknown
    /// keys are ignored, so sending both is safe.
    func setInterface(_ name: String, address: String?) async -> Bool {
        guard WebUIURLValidator.isAllowed(baseURL) else { return false }
        var prefs: [String: Any] = [
            "current_interface_name": name,
            "current_network_interface": name,
        ]
        if let address { prefs["current_interface_address"] = address }
        guard let json = try? JSONSerialization.data(withJSONObject: prefs),
              let jsonText = String(data: json, encoding: .utf8)
        else { return false }
        do {
            let result = try await post("/api/v2/app/setPreferences",
                                        form: ["json": jsonText])
            return (200...299).contains(result.code)
        } catch { return false }
    }
}
