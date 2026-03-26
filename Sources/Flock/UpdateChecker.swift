import AppKit

final class UpdateChecker {
    static let shared = UpdateChecker()
    static let updateAvailable = Notification.Name("FlockUpdateAvailable")

    private let versionURL = URL(string: "https://divagation.github.io/flock/version.json")!
    private var hasCheckedThisLaunch = false

    struct Release: Decodable {
        let version: String
        let url: String
        let notes: String?
    }

    // MARK: - Public

    /// Check on launch (once per session, respects setting)
    func checkOnLaunchIfNeeded() {
        guard Settings.shared.autoCheckUpdates, !hasCheckedThisLaunch else { return }
        hasCheckedThisLaunch = true
        check(silent: true)
    }

    /// Manual check from menu (always shows result)
    func checkNow() {
        check(silent: false)
    }

    // MARK: - Core

    private func check(silent: Bool) {
        let request = URLRequest(url: versionURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else {  return }
            guard let data, error == nil else {
                if !silent { self.showNoUpdate() }
                return
            }
            guard let release = try? JSONDecoder().decode(Release.self, from: data) else {
                if !silent { self.showNoUpdate() }
                return
            }
            if self.isNewer(release.version, than: self.currentVersion) {
                DispatchQueue.main.async { self.showUpdateAlert(release) }
            } else if !silent {
                DispatchQueue.main.async { self.showNoUpdate() }
            }
        }.resume()
    }

    // MARK: - Version comparison

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? FlockVersion.current
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    // MARK: - UI

    private func showUpdateAlert(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "Flock v\(release.version) Available"
        alert.informativeText = release.notes ?? "A new version of Flock is available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: release.url) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showNoUpdate() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "You're Up to Date"
            alert.informativeText = "Flock v\(self.currentVersion) is the latest version."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// Fallback version constant (used when not running as .app bundle)
enum FlockVersion {
    static let current = "0.8.0"
}
