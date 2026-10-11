//  Updater.swift — check GitHub for a newer build and install it in place.
//
//  There are no prebuilt releases: the app is built from source on this Mac. So an
//  update is "download the latest main as a tarball, run its build.sh, then hand off to
//  its install.sh once we've quit". The build happens while the app is still running,
//  so a failed build leaves the installed app untouched.

import AppKit
import Foundation

/// What build.sh stamped into Contents/Resources/BuildInfo.plist.
struct BuildInfo {
    let commit: String?   // full SHA; nil when built from a folder that isn't a git checkout
    let build: Int?       // commit count on main
    let builtAt: Date?

    static let current: BuildInfo = {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any]
        else { return BuildInfo(commit: nil, build: nil, builtAt: nil) }
        let commit = (dict["Commit"] as? String).flatMap { $0.count == 40 ? $0 : nil }
        let build = (dict["Build"] as? String).flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        let builtAt = (dict["BuiltAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return BuildInfo(commit: commit, build: build, builtAt: builtAt)
    }()

    var summary: String {
        var parts: [String] = []
        parts.append(build.map { "Build \($0)" } ?? "Build ?")
        if let c = commit { parts.append(String(c.prefix(7))) }
        if let d = builtAt {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            parts.append(f.string(from: d))
        }
        return parts.joined(separator: " · ")
    }
}

final class Updater: ObservableObject {

    struct Release: Equatable {
        let sha: String
        let build: Int?
        let message: String
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    static let repo = "jonpikereally/Neewer-Light-Controller"
    static let branch = "main"
    private static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/NeewerLight-update.log")

    private let current = BuildInfo.current

    var isBusy: Bool {
        switch state {
        case .checking, .installing: return true
        default: return false
        }
    }

    // MARK: - Check

    func check() {
        guard !isBusy else { return }
        state = .checking
        fetchJSON("https://api.github.com/repos/\(Self.repo)/commits/\(Self.branch)") { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.fail("NL-UPD-01", "Couldn't check for updates: \(error.localizedDescription)")
            case .success(let json):
                guard let sha = json["sha"] as? String,
                      let commit = json["commit"] as? [String: Any]
                else { return self.fail("NL-UPD-01", "Couldn't check for updates: GitHub sent an unexpected reply.") }
                if sha == self.current.commit {
                    self.state = .upToDate
                    return
                }
                let message = (commit["message"] as? String)?
                    .split(separator: "\n").first.map(String.init) ?? ""
                self.fetchBuildNumber(sha: sha) { build in
                    self.state = .available(Release(sha: sha, build: build, message: message))
                }
            }
        }
    }

    /// Build number = commit count up to `sha`. GitHub doesn't return it directly, but
    /// with one commit per page the "last" page number in the Link header is the count.
    private func fetchBuildNumber(sha: String, done: @escaping (Int?) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/commits?sha=\(sha)&per_page=1")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { _, response, _ in
            var count: Int?
            if let http = response as? HTTPURLResponse {
                if let link = http.value(forHTTPHeaderField: "Link"),
                   let last = link.components(separatedBy: ",").first(where: { $0.contains("rel=\"last\"") }),
                   let range = last.range(of: #"[?&]page=(\d+)"#, options: .regularExpression) {
                    count = Int(last[range].drop { !$0.isNumber })
                } else if http.statusCode == 200 {
                    count = 1   // no Link header: a single page, so a single commit
                }
            }
            DispatchQueue.main.async { done(count) }
        }.resume()
    }

    // MARK: - Install

    func install(_ release: Release) {
        guard !isBusy else { return }

        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/swiftc"),
              run("/usr/bin/xcode-select", ["-p"]).status == 0
        else {
            return fail("NL-UPD-04", "Updating needs Apple's Command Line Tools. Run xcode-select --install, then try again.")
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeewerLight-update-\(release.sha.prefix(7))")
        try? FileManager.default.removeItem(at: work)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        } catch {
            return fail("NL-UPD-02", "Couldn't create a folder for the download: \(error.localizedDescription)")
        }

        state = .installing("Downloading…")
        let tarball = URL(string: "https://codeload.github.com/\(Self.repo)/tar.gz/\(release.sha)")!
        URLSession.shared.downloadTask(with: tarball) { [weak self] file, response, error in
            guard let self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let file, error == nil, code == 200 else {
                let why = error?.localizedDescription ?? "GitHub returned HTTP \(code)."
                return DispatchQueue.main.async { self.fail("NL-UPD-02", "Download failed: \(why)") }
            }
            let archive = work.appendingPathComponent("source.tar.gz")
            do {
                try FileManager.default.moveItem(at: file, to: archive)
            } catch {
                return DispatchQueue.main.async { self.fail("NL-UPD-02", "Download failed: \(error.localizedDescription)") }
            }
            self.buildAndHandOff(release, archive: archive, work: work)
        }.resume()
    }

    /// Runs off the main thread: extract, build, then launch the installer and quit.
    private func buildAndHandOff(_ release: Release, archive: URL, work: URL) {
        let source = work.appendingPathComponent("src")
        try? FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let untar = run("/usr/bin/tar", ["-xzf", archive.path, "-C", source.path, "--strip-components", "1"])
        guard untar.status == 0 else {
            return DispatchQueue.main.async { self.fail("NL-UPD-03", "Couldn't unpack the download: \(untar.output.lastLine)") }
        }

        DispatchQueue.main.async { self.state = .installing("Building — this takes a minute…") }
        var env = ProcessInfo.processInfo.environment
        env["NEEWER_COMMIT"] = release.sha
        if let build = release.build { env["NEEWER_BUILD"] = String(build) }
        let build = run("/bin/zsh", [source.appendingPathComponent("build.sh").path], env: env)
        appendLog("=== build \(release.sha) ===\n\(build.output)")
        guard build.status == 0 else {
            return DispatchQueue.main.async {
                self.fail("NL-UPD-05", "The new version didn't build: \(build.output.lastLine) (full output in ~/Library/Logs/NeewerLight-update.log)")
            }
        }

        // install.sh replaces the app bundle, so it has to run after we've quit. This
        // script waits for our PID to go away, installs the already-built app, and
        // relaunches it. Output goes to the update log.
        let dest = Bundle.main.bundleURL.path
        let script = """
        #!/bin/zsh
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        echo "=== install \(release.sha) — $(date) ==="
        if SKIP_BUILD=1 DEST=\(dest.shellQuoted) /bin/zsh \(source.appendingPathComponent("install.sh").path.shellQuoted); then
          open \(dest.shellQuoted)
        else
          echo "NL-UPD-07: install.sh failed"
          osascript -e 'display alert "Neewer Light update failed (NL-UPD-07)" message "See ~/Library/Logs/NeewerLight-update.log. The error list is in the README."'
          open \(dest.shellQuoted)
        fi
        """
        let scriptURL = work.appendingPathComponent("handoff.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            p.arguments = ["/bin/zsh", scriptURL.path]
            p.standardInput = FileHandle.nullDevice
            let log = try logHandle()
            p.standardOutput = log
            p.standardError = log
            try p.run()
        } catch {
            return DispatchQueue.main.async { self.fail("NL-UPD-06", "Couldn't start the installer: \(error.localizedDescription)") }
        }

        DispatchQueue.main.async {
            self.state = .installing("Restarting…")
            NSApp.terminate(nil)
        }
    }

    // MARK: - Helpers

    private func fail(_ code: String, _ message: String) {
        state = .failed("\(code) · \(message)")
    }

    private func fetchJSON(_ url: String, done: @escaping (Result<[String: Any], Error>) -> Void) {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, response, error in
            let result: Result<[String: Any], Error>
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error {
                result = .failure(error)
            } else if code != 200 {
                let reason = code == 403 || code == 429
                    ? "GitHub rate limit hit, try again in an hour."
                    : "GitHub returned HTTP \(code)."
                result = .failure(NSError(domain: "Updater", code: code,
                                          userInfo: [NSLocalizedDescriptionKey: reason]))
            } else if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result = .success(json)
            } else {
                result = .failure(NSError(domain: "Updater", code: 0,
                                          userInfo: [NSLocalizedDescriptionKey: "Unreadable reply from GitHub."]))
            }
            DispatchQueue.main.async { done(result) }
        }.resume()
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String], env: [String: String]? = nil) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        if let env { p.environment = env }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func logHandle() throws -> FileHandle {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: Self.logURL.path) { fm.createFile(atPath: Self.logURL.path, contents: nil) }
        let h = try FileHandle(forWritingTo: Self.logURL)
        h.seekToEndOfFile()
        return h
    }

    private func appendLog(_ text: String) {
        guard let h = try? logHandle() else { return }
        h.write(Data((text + "\n").utf8))
        try? h.close()
    }
}

private extension String {
    var shellQuoted: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }
    var lastLine: String {
        split(separator: "\n").last.map(String.init) ?? "no output"
    }
}
