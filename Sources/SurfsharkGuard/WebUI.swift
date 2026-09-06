import Foundation

/// Minimal qBittorrent Web API client — live interface rebinding only.
struct QBWebUI {
    let baseURL: URL
    let user: String
    let password: String

    private func post(_ path: String, form: [String: String]) async throws -> String {
        var components = URLComponents()
        components.queryItems = form.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        let body = components.percentEncodedQuery?.data(using: .utf8) ?? Data()
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func login() async -> Bool {
        guard !user.isEmpty else { return false }
        let body = try? await post("/api/v2/auth/login",
                                   form: ["username": user, "password": password])
        return body?.contains("Ok") == true
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
