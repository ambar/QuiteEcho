import Foundation

/// Checks GitHub releases for newer versions.
final class UpdateChecker {
    struct Release {
        let version: String   // e.g. "0.2.0"
        let tagName: String   // e.g. "v0.2.0"
        let htmlURL: String   // release page URL
        let dmgURL: String?   // direct .dmg download URL
    }

    private(set) var latestRelease: Release?
    var onUpdateAvailable: ((Release) -> Void)?
    /// Called after a manual check completes. Bool = update found.
    var onCheckComplete: ((Bool) -> Void)?

    private let owner = "ambar"
    private let repo = "QuiteEcho"
    private let checkInterval: TimeInterval = 24 * 60 * 60  // 24 hours
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var isUpdateAvailable: Bool {
        guard let release = latestRelease else { return false }
        return Self.compareVersions(release.version, isNewerThan: currentVersion)
    }

    // MARK: - Public

    func startPeriodicChecks() {
        check()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func check(manual: Bool = false) {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self, let data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String
            else {
                if let error {
                    NSLog("[UpdateChecker] %@", error.localizedDescription)
                }
                DispatchQueue.main.async { self?.onCheckComplete?(false) }
                return
            }

            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            // Find .dmg asset
            var dmgURL: String?
            if let assets = json["assets"] as? [[String: Any]] {
                dmgURL = assets.first(where: {
                    ($0["name"] as? String)?.hasSuffix(".dmg") == true
                })?["browser_download_url"] as? String
            }

            let release = Release(version: version, tagName: tagName, htmlURL: htmlURL, dmgURL: dmgURL)
            let hasUpdate = Self.compareVersions(version, isNewerThan: self.currentVersion)

            DispatchQueue.main.async {
                self.latestRelease = release
                if hasUpdate {
                    NSLog("[UpdateChecker] Update available: %@ → %@", self.currentVersion, version)
                    self.onUpdateAvailable?(release)
                }
                if manual {
                    self.onCheckComplete?(hasUpdate)
                }
            }
        }.resume()
    }

    // MARK: - Semver comparison

    static func compareVersions(_ a: String, isNewerThan b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(partsA.count, partsB.count) {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va != vb { return va > vb }
        }
        return false
    }

    deinit { stop() }
}
