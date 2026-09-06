import Foundation

struct UpdateInfo: Equatable {
    var latest: String
    var current: String
    var htmlURL: URL
}

/// Compare GitHub release tags to this app’s short version. No Sparkle.
enum UpdateCheck {
    static let releasesAPI = URL(string:
        "https://api.github.com/repos/Leumas123-cyber/surfshark-guard/releases/latest")!
    static let releasesPage = URL(string:
        "https://github.com/Leumas123-cyber/surfshark-guard/releases/latest")!

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") {
            s.removeFirst()
        }
        return s
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        let a = normalize(latest)
        let b = normalize(current)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a.compare(b, options: .numeric) == .orderedDescending
    }

    static func parseLatest(from data: Data) -> (tag: String, htmlURL: URL)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else { return nil }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let raw = json["html_url"] as? String, let url = URL(string: raw) {
            return (trimmed, url)
        }
        return (trimmed, releasesPage)
    }

    static func currentVersion() -> String {
        if let fromBundle = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String, !fromBundle.isEmpty {
            return fromBundle
        }
        return "0"
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func fetchLatest() async -> (tag: String, htmlURL: URL)? {
        var request = URLRequest(url: releasesAPI)
        request.httpMethod = "GET"
        request.setValue("SurfsharkGuard", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(code) else { return nil }
            return parseLatest(from: data)
        } catch {
            return nil
        }
    }
}
