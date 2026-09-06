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

/// Minimal qBittorrent Web API client — live interface rebinding only.
struct QBWebUI {
    let baseURL: URL
    let user: String
    let password: String

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
        let (data, response) = try await URLSession.shared.data(for: request)
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
        guard !user.isEmpty else { return false }
        let result = try? await post("/api/v2/auth/login",
                                     form: ["username": user, "password": password])
        return result?.body.contains("Ok") == true
    }

    /// Live NIC from a running qBittorrent (ini can be stale).
    func currentBinding() async -> (iface: String?, addr: String?)? {
        var request = URLRequest(url: Self.endpoint("/api/v2/app/preferences", on: baseURL))
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
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
        var prefs: [String: Any] = [
            "current_interface_name": name,
            "current_network_interface": name,
        ]
        if let address { prefs["current_interface_address"] = address }
        guard let json = try? JSONSerialization.data(withJSONObject: prefs),
              let jsonText = String(data: json, encoding: .utf8)
        else { return false }
        do {
            _ = try await post("/api/v2/app/setPreferences",
                              form: ["json": jsonText])
            return true
        } catch { return false }
    }
}
