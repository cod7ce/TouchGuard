import AppKit

enum UpdateError: LocalizedError {
    case http(Int)
    case malformedFeed
    case noDownload(tag: String)
    case noAppInArchive
    case unsigned
    case adHocSigned
    case security(String, OSStatus)
    case wrongBundle(String)
    case notNewer(String)
    case commandFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .http(let code):
            return "GitHub 返回 HTTP \(code)。"
        case .malformedFeed:
            return "无法解析 GitHub 的发布信息。"
        case .noDownload(let tag):
            return "发布 \(tag) 里没有找到 .zip 附件。"
        case .noAppInArchive:
            return "下载的压缩包里没有 TouchGuard.app。"
        case .unsigned:
            return "下载的版本没有代码签名，已拒绝安装。"
        case .adHocSigned:
            return """
            当前这份 TouchGuard 是临时（ad-hoc）签名的，无法校验更新来源，已拒绝自动更新。
            请手动下载安装。
            """
        case .security(let step, let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "\(step)：\(message)"
        case .wrongBundle(let identifier):
            return "下载的版本标识为 \(identifier)，与当前应用不符，已拒绝安装。"
        case .notNewer(let version):
            return "下载的版本是 \(version)，并不比当前版本新，已拒绝安装。"
        case .commandFailed(let tool, let code):
            return "\(tool) 以状态码 \(code) 退出。"
        }
    }
}

/// The GitHub Releases feed this app updates from.
enum GitHub {
    static let repository = "cod7ce/TouchGuard"
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!
    private static let latestURL =
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    private struct Payload: Decodable {
        let tagName: String
        let body: String?
        let htmlURL: URL
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let downloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case downloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
            case assets
        }
    }

    static func latestRelease() async throws -> Updater.Release {
        var request = URLRequest(url: latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TouchGuard/\(Updater.currentVersion)", forHTTPHeaderField: "User-Agent")
        // The feed is polled at most daily; a cached answer would defeat it.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.http(http.statusCode)
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw UpdateError.malformedFeed
        }
        guard let asset = payload.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            throw UpdateError.noDownload(tag: payload.tagName)
        }

        return Updater.Release(
            version: payload.tagName.hasPrefix("v")
                ? String(payload.tagName.dropFirst())
                : payload.tagName,
            notes: (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pageURL: payload.htmlURL,
            downloadURL: asset.downloadURL
        )
    }
}

/// Downloads a release and swaps it in for the running bundle.
enum Installer {
    static func install(_ release: Updater.Release, replacing appURL: URL) async throws -> URL {
        try refuseIfAdHoc(appURL)
        let requirement = try designatedRequirement(of: appURL)

        // Staging next to the target keeps everything on one volume, which is
        // what makes the final swap atomic.
        let staging = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: appURL, create: true
        )
        defer { try? FileManager.default.removeItem(at: staging) }

        let archive = staging.appendingPathComponent("TouchGuard.zip")
        let (downloaded, response) = try await URLSession.shared.download(from: release.downloadURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.http(http.statusCode)
        }
        try FileManager.default.moveItem(at: downloaded, to: archive)

        let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
        // ditto, not any zip library: it is the one unarchiver that restores a
        // bundle's symlinks and metadata intact, so the signature survives.
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])

        let candidate = try locateApp(in: unpacked)
        try verify(candidate, satisfies: requirement)
        try verifyContents(of: candidate)

        _ = try FileManager.default.replaceItemAt(appURL, withItemAt: candidate)
        return appURL
    }

    /// Hands off to a detached shell so the swap-in copy starts only once this
    /// process is gone and its event tap is released.
    static func relaunch(_ appURL: URL) {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = [
            "-c",
            #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open "$2""#,
            "--",
            String(ProcessInfo.processInfo.processIdentifier),
            appURL.path,
        ]
        try? waiter.run()
        NSApp.terminate(nil)
    }

    // MARK: - Checks

    private static func locateApp(in directory: URL) throws -> URL {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.noAppInArchive
        }
        return app
    }

    private static func staticCode(at url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard status == errSecSuccess, let code else {
            throw UpdateError.security("读取代码签名", status)
        }
        return code
    }

    /// An ad-hoc signature's designated requirement pins the exact binary hash,
    /// so it can never match a later build. Rather than fail obscurely at
    /// install time, say so up front.
    private static func refuseIfAdHoc(_ url: URL) throws {
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(
            try staticCode(at: url), SecCSFlags(rawValue: kSecCSSigningInformation), &information
        )
        guard status == errSecSuccess,
              let dictionary = information as? [String: Any],
              let flags = dictionary[kSecCodeInfoFlags as String] as? UInt32 else {
            throw UpdateError.security("读取签名信息", status)
        }
        if SecCodeSignatureFlags(rawValue: flags).contains(.adhoc) { throw UpdateError.adHocSigned }
    }

    private static func designatedRequirement(of url: URL) throws -> SecRequirement {
        var requirement: SecRequirement?
        let status = SecCodeCopyDesignatedRequirement(try staticCode(at: url), [], &requirement)
        if status == errSecCSUnsigned { throw UpdateError.unsigned }
        guard status == errSecSuccess, let requirement else {
            throw UpdateError.security("读取签名要求", status)
        }
        return requirement
    }

    private static func verify(_ url: URL, satisfies requirement: SecRequirement) throws {
        let flags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate
        )
        let status = SecStaticCodeCheckValidity(try staticCode(at: url), flags, requirement)
        guard status == errSecSuccess else {
            throw UpdateError.security("校验下载版本的签名", status)
        }
    }

    /// Signature checks prove who built it, not what it claims to be; these two
    /// catch a correctly signed but wrong or stale artifact attached to a release.
    private static func verifyContents(of url: URL) throws {
        let information = Bundle(url: url)?.infoDictionary ?? [:]
        let identifier = information["CFBundleIdentifier"] as? String ?? ""
        guard identifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.wrongBundle(identifier)
        }
        let version = information["CFBundleShortVersionString"] as? String ?? "0"
        guard Updater.isNewer(version, than: Updater.currentVersion) else {
            throw UpdateError.notNewer(version)
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed(tool, process.terminationStatus)
        }
    }
}
