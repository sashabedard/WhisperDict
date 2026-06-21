import Foundation

/// A GitHub release relevant to updating: its version and the .dmg asset URL.
struct Release {
    let version: String   // e.g. "0.2.2" (leading "v" stripped)
    let dmgURL: URL?       // the .dmg asset's download URL
}

/// Checks GitHub for a newer release. Pure parse/compare helpers are testable;
/// `fetchLatest` is the only network touch and returns nil on any failure.
enum UpdateChecker {
    private static let repo = "sashabedard/WhisperDict"

    static func currentVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    /// Strictly-newer comparison of dot-separated integer versions. Missing
    /// components count as 0; a leading "v" is ignored; non-numeric input is
    /// treated as 0 so garbage never reports "newer".
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let a = components(latest), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ v: String) -> [Int] {
        let trimmed = v.hasPrefix("v") ? String(v.dropFirst()) : v
        let parts = trimmed.split(separator: ".")
        // A version must start with a number; "abc"/"" → [] → all-zero → never newer.
        guard !parts.isEmpty, Int(parts[0]) != nil else { return [] }
        return parts.map { Int($0) ?? 0 }
    }

    /// Decodes the GitHub /releases/latest payload into a Release.
    static func parse(_ data: Data) -> Release? {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        struct Payload: Decodable { let tag_name: String; let assets: [Asset] }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let version = p.tag_name.hasPrefix("v") ? String(p.tag_name.dropFirst()) : p.tag_name
        let dmg = p.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        return Release(version: version, dmgURL: dmg.flatMap { URL(string: $0.browser_download_url) })
    }

    /// Fetches the latest release, or nil on any network/parse failure.
    static func fetchLatest() async -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return parse(data)
    }
}
