import AppKit

/// Checks GitHub Releases for a newer build and installs it in place.
///
/// The downloaded bundle is only trusted if it satisfies the *running* app's
/// designated requirement, so an update has to carry the same signature as the
/// copy already on disk. That is also what keeps the Accessibility grant alive
/// across updates: macOS keys the grant to the signature, not to the file.
///
/// Everything here runs on the main thread; only the download, the unpack and
/// the signature checks hop off it, inside `Installer`.
final class Updater {
    static let shared = Updater()

    struct Release {
        let version: String
        let notes: String
        let pageURL: URL
        let downloadURL: URL
    }

    /// How long a silent check waits before looking again.
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    static let currentVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    /// Set while a check or install is in flight, so the UI can say so.
    private(set) var isBusy = false { didSet { onStateChange?() } }
    var onStateChange: (() -> Void)?

    private let settings = Settings.shared

    // MARK: - Entry points

    /// Called on launch and periodically after: stays quiet unless there is
    /// something to install.
    func checkInBackground() {
        guard settings.automaticUpdateChecks, !isBusy else { return }
        guard Date().timeIntervalSince(settings.lastUpdateCheck) >= Self.checkInterval else { return }
        run(userInitiated: false)
    }

    /// Called from the menu: always reports back, even when there is no news.
    func checkNow() {
        guard !isBusy else { return }
        run(userInitiated: true)
    }

    private func run(userInitiated: Bool) {
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                let release = try await GitHub.latestRelease()
                settings.lastUpdateCheck = Date()

                guard Self.isNewer(release.version, than: Self.currentVersion) else {
                    if userInitiated { presentUpToDate() }
                    return
                }
                // A version the user dismissed for good only stops the silent
                // check; asking explicitly always shows what is out there.
                if !userInitiated, settings.skippedVersion == release.version { return }

                presentAvailable(release)
            } catch {
                if userInitiated { present(error: error, title: "检查更新失败") }
            }
        }
    }

    /// Plain numeric comparison, which is all the x.y.z tags need.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    // MARK: - Dialogs

    private func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "已是最新版本"
        alert.informativeText = "TouchGuard \(Self.currentVersion) 就是当前发布的最新版本。"
        alert.addButton(withTitle: "好")
        show(alert)
    }

    private func presentAvailable(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "发现新版本 \(release.version)"
        alert.informativeText = """
        当前版本 \(Self.currentVersion)。

        \(release.notes.isEmpty ? "本次发布没有附带说明。" : release.notes)
        """
        alert.addButton(withTitle: "更新并重启")
        alert.addButton(withTitle: "稍后")
        alert.addButton(withTitle: "忽略此版本")

        switch show(alert) {
        case .alertFirstButtonReturn:
            install(release)
        case .alertThirdButtonReturn:
            settings.skippedVersion = release.version
        default:
            break
        }
    }

    private func install(_ release: Release) {
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                let installed = try await Installer.install(release, replacing: Bundle.main.bundleURL)
                settings.skippedVersion = nil
                Installer.relaunch(installed)
            } catch {
                present(error: error, title: "更新失败")
            }
        }
    }

    private func present(error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "打开下载页面")
        if show(alert) == .alertSecondButtonReturn {
            NSWorkspace.shared.open(GitHub.releasesPage)
        }
    }

    /// An accessory app has no windows to bring forward, so the alert would
    /// otherwise open behind whatever the user is working in.
    @discardableResult
    private func show(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
