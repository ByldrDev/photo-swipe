import AppKit
import Foundation

/// "Check for Updates…" for the Mac app. Asks GitHub for the latest release of
/// ByldrDev/photo-swipe, compares its tag with this bundle's version, and offers
/// to download the .dmg into ~/Downloads and open it (which mounts the disk
/// image with its drag-to-Applications window). Also runs silently once a day at
/// launch and only speaks up when something newer exists.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/ByldrDev/photo-swipe/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    struct Release {
        let version: AppVersion
        let pageURL: URL
        let dmgURL: URL?
    }

    enum UpdateError: LocalizedError {
        case badResponse(Int)
        case unparsable

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "GitHub answered with status \(code)."
            case .unparsable: return "The release information couldn't be read."
            }
        }
    }

    private var isChecking = false

    var currentVersion: AppVersion {
        AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") ?? AppVersion(0, 0, 0)
    }

    /// Menu item: always reports a result (up to date, update available, or error).
    func checkInteractively() {
        Task { await check(interactive: true) }
    }

    /// Launch hook: at most once per day, and silent unless an update exists.
    func checkAutomaticallyIfDue() {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > Self.checkInterval else { return }
        Task { await check(interactive: false) }
    }

    private func check(interactive: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let release = try await fetchLatest()
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            if release.version > currentVersion {
                offer(release)
            } else if interactive {
                alert("You're up to date", "PhotoSwipe \(currentVersion) is the latest version.")
            }
        } catch {
            if interactive { alert("Couldn't check for updates", error.localizedDescription) }
        }
    }

    // MARK: - GitHub

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let assets: [Asset]
    }

    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PhotoSwipe-mac/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.badResponse(status) }
        let json = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let version = AppVersion(json.tag_name) else { throw UpdateError.unparsable }
        let dmg = json.assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url
        return Release(version: version, pageURL: json.html_url, dmgURL: dmg)
    }

    // MARK: - UI

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "PhotoSwipe \(release.version) is available"
        alert.informativeText = "You have \(currentVersion). The update downloads as a disk image; drag the new PhotoSwipe to Applications to replace this one, then relaunch."
        alert.addButton(withTitle: release.dmgURL == nil ? "Open Release Page" : "Download")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let dmg = release.dmgURL {
                Task { await download(dmg) }
            } else {
                NSWorkspace.shared.open(release.pageURL)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    /// Saves the .dmg to ~/Downloads (sandbox: files.downloads.read-write) and
    /// opens it, which mounts the image and shows its installer window.
    private func download(_ url: URL) async {
        do {
            let (temporary, response) = try await URLSession.shared.download(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw UpdateError.badResponse(status) }
            let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let destination = downloads.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            NSWorkspace.shared.open(destination)
        } catch {
            alert("Download failed", "\(error.localizedDescription)\n\nYou can download it from the releases page instead.")
        }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
