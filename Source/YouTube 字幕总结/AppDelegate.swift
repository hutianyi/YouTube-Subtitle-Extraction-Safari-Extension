import Cocoa
import SafariServices

private let safariExtensionBundleIdentifier = "com.example.YouTubeSubtitleExtraction.Extension"
private let callbackMessageName = "subtitleResult"
private let defaultPrompt = "这期节目讲了什么"
private let taskDirectoryURL = URL(
    fileURLWithPath: "/private/tmp/com.example.YouTubeSubtitleExtraction",
    isDirectory: true
)

@main
private enum YouTubeSubtitleSummaryMain {
    private static let delegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var handledLaunchURL = false
    private var startedJobIDs = Set<String>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        if let task = claimPendingTask() {
            handledLaunchURL = true
            startExtraction(jobID: task.jobID, videoURL: task.videoURL, cookies: task.cookies ?? [])
            return
        }

        // 用户手动打开应用时，只负责带到 Safari 的扩展设置页。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.handledLaunchURL else { return }
            SFSafariApplication.showPreferencesForExtension(
                withIdentifier: safariExtensionBundleIdentifier
            ) { _ in
                self.terminateIfIdle()
            }

            // Safari 某些版本不会调用上面的 completion；避免助手永久驻留。
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.terminateIfIdle()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleLaunchURL(url)
        }
    }

    private func handleLaunchURL(_ url: URL) {
        handledLaunchURL = true

        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == "ytsubsummary",
            components.host == "extract",
            let jobID = components.queryItems?.first(where: { $0.name == "job" })?.value,
            let videoURL = components.queryItems?.first(where: { $0.name == "url" })?.value,
            !jobID.isEmpty,
            !videoURL.isEmpty
        else {
            sendFailure(jobID: "unknown", message: "插件传来的任务参数无效。")
            return
        }

        startExtraction(jobID: jobID, videoURL: videoURL)
    }

    private func startExtraction(jobID: String, videoURL: String, cookies: [YouTubeCookie] = []) {
        guard startedJobIDs.insert(jobID).inserted else { return }
        NSLog("YouTube 字幕总结：收到任务 %@", jobID)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.extract(jobID: jobID, videoURL: videoURL, cookies: cookies)
        }
    }

    private func claimPendingTask() -> PendingTask? {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: taskDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { left, right in
                let leftDate = try? left.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                let rightDate = try? right.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                return (leftDate ?? .distantPast) < (rightDate ?? .distantPast)
            }

        for candidate in candidates {
            let claimedURL = taskDirectoryURL.appendingPathComponent(
                "processing-\(UUID().uuidString).json"
            )
            do {
                try fileManager.moveItem(at: candidate, to: claimedURL)
                defer { try? fileManager.removeItem(at: claimedURL) }
                let data = try Data(contentsOf: claimedURL)
                let task = try JSONDecoder().decode(PendingTask.self, from: data)
                guard !task.jobID.isEmpty, !task.videoURL.isEmpty else { continue }
                return task
            } catch {
                continue
            }
        }

        return nil
    }

    private func extract(jobID: String, videoURL: String, cookies: [YouTubeCookie]) {
        let fileManager = FileManager.default
        let taskDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("YouTubeSubtitleSummary-\(UUID().uuidString)", isDirectory: true)
        let resultURL = taskDirectory.appendingPathComponent("transcript.txt")

        do {
            try fileManager.createDirectory(
                at: taskDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            defer { try? fileManager.removeItem(at: taskDirectory) }

            guard let scriptURL = Bundle.main.url(
                forResource: "SubtitleExtractor",
                withExtension: "sh"
            ) else {
                throw HelperError("应用内没有找到字幕提取程序。")
            }

            let cookieURL = taskDirectory.appendingPathComponent("youtube-cookies.txt")
            let cookieLines = cookies.compactMap { $0.netscapeLine }
            if !cookieLines.isEmpty {
                let data = Data(("# Netscape HTTP Cookie File\n" + cookieLines.joined(separator: "\n") + "\n").utf8)
                guard fileManager.createFile(
                    atPath: cookieURL.path, contents: data,
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    throw HelperError("无法准备本次提取的 YouTube 登录数据。")
                }
            }

            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [scriptURL.path, videoURL, resultURL.path]
            if !cookieLines.isEmpty { process.arguments?.append(cookieURL.path) }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errorPipe
            process.environment = ProcessInfo.processInfo.environment.merging([
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "LANG": "en_US.UTF-8"
            ]) { _, new in new }

            try process.run()
            // 先读管道，避免子进程等待管道空间而与 waitUntilExit 相互阻塞。
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let errorText = String(data: errorData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw HelperError(lastUsefulLine(in: errorText) ?? "字幕提取失败。")
            }

            let transcript = try String(contentsOf: resultURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                throw HelperError("字幕提取完成，但结果为空。")
            }

            let completePrompt = "\(defaultPrompt)\n\n\(transcript)"
            copyToClipboard(completePrompt)
            NSLog("YouTube 字幕总结：字幕提取成功，共 \(transcript.count) 个字符")
            sendSuccess(jobID: jobID, transcript: transcript)
        } catch {
            let message = readableMessage(for: error)
            NSLog("YouTube 字幕总结：字幕提取失败：%@", message)
            if prepareManualFallback(videoURL: videoURL) {
                sendManualFallback(jobID: jobID, message: message)
            } else {
                sendFailure(jobID: jobID, message: message)
            }
        }
    }

    private func prepareManualFallback(videoURL: String) -> Bool {
        var didOpen = false
        DispatchQueue.main.sync {
            copyToClipboardOnMainThread(videoURL)
            guard let configuredPath = UserDefaults.standard.string(
                forKey: "ManualFallbackCommandPath"
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
                !configuredPath.isEmpty else { return }
            let commandPath = (configuredPath as NSString).expandingTildeInPath
            let commandURL = URL(fileURLWithPath: commandPath)
            guard FileManager.default.isExecutableFile(atPath: commandURL.path) else { return }
            // 通过一次性启动脚本传入网址，Terminal 仍可使用已有的系统访问权限。
            let launcherURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("YouTubeSubtitleFallback-\(UUID().uuidString).command")
            let launcher = """
            #!/bin/zsh
            trap '/bin/rm -f -- "$0"' EXIT
            /bin/zsh \(shellQuoted(commandURL.path)) \(shellQuoted(videoURL))
            """
            do {
                try launcher.write(to: launcherURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o700], ofItemAtPath: launcherURL.path
                )
                didOpen = NSWorkspace.shared.open(launcherURL)
                if !didOpen { try? FileManager.default.removeItem(at: launcherURL) }
            } catch {
                try? FileManager.default.removeItem(at: launcherURL)
                NSLog("YouTube 字幕总结：无法准备后备启动程序：%@", error.localizedDescription)
            }
        }
        return didOpen
    }

    private func copyToClipboard(_ text: String) {
        DispatchQueue.main.sync {
            copyToClipboardOnMainThread(text)
        }
    }

    private func copyToClipboardOnMainThread(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWrite = pasteboard.setString(text, forType: .string)
        let storedCharacters = pasteboard.string(forType: .string)?.count ?? 0
        NSLog(
            "YouTube 字幕总结：剪贴板写入 \(didWrite ? "成功" : "失败")，回读 \(storedCharacters) 个字符"
        )
    }

    private func sendSuccess(jobID: String, transcript: String) {
        let chunks = split(transcript, maximumCharacters: 45_000)
        let group = DispatchGroup()

        DispatchQueue.main.async {
            for (index, chunk) in chunks.enumerated() {
                group.enter()
                SFSafariApplication.dispatchMessage(
                    withName: callbackMessageName,
                    toExtensionWithIdentifier: safariExtensionBundleIdentifier,
                    userInfo: [
                        "jobId": jobID,
                        "ok": true,
                        "sequence": index,
                        "total": chunks.count,
                        "chunk": chunk,
                        "clipboardReady": true
                    ]
                ) { _ in
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.terminateSoon()
            }
        }
    }

    private func sendFailure(jobID: String, message: String) {
        DispatchQueue.main.async {
            SFSafariApplication.dispatchMessage(
                withName: callbackMessageName,
                toExtensionWithIdentifier: safariExtensionBundleIdentifier,
                userInfo: [
                    "jobId": jobID,
                    "ok": false,
                    "error": message,
                    "clipboardReady": false
                ]
            ) { _ in
                self.terminateSoon()
            }
        }
    }

    private func sendManualFallback(jobID: String, message: String) {
        DispatchQueue.main.async {
            SFSafariApplication.dispatchMessage(
                withName: callbackMessageName,
                toExtensionWithIdentifier: safariExtensionBundleIdentifier,
                userInfo: [
                    "jobId": jobID,
                    "ok": false,
                    "manualFallback": true,
                    "error": message,
                    "clipboardReady": true
                ]
            ) { _ in
                self.terminateSoon()
            }
        }
    }

    private func terminateSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func terminateIfIdle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard self.startedJobIDs.isEmpty else { return }
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct PendingTask: Decodable {
    let jobID: String
    let videoURL: String
    let cookies: [YouTubeCookie]?

    private enum CodingKeys: String, CodingKey {
        case jobID = "jobId"
        case videoURL = "url"
        case cookies
    }
}

private struct HelperError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private func readableMessage(for error: Error) -> String {
    if let localized = error as? LocalizedError,
       let description = localized.errorDescription,
       !description.isEmpty {
        return description
    }
    return error.localizedDescription
}

private func lastUsefulLine(in text: String) -> String? {
    text
        .split(whereSeparator: { $0.isNewline })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .last(where: { !$0.isEmpty })
}

private func split(_ text: String, maximumCharacters: Int) -> [String] {
    guard text.count > maximumCharacters else { return [text] }

    var chunks: [String] = []
    var start = text.startIndex
    while start < text.endIndex {
        let end = text.index(
            start,
            offsetBy: maximumCharacters,
            limitedBy: text.endIndex
        ) ?? text.endIndex
        chunks.append(String(text[start..<end]))
        start = end
    }
    return chunks
}

private func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private struct YouTubeCookie: Decodable {
    let domain: String
    let path: String
    let name: String
    let value: String
    let secure: Bool
    let httpOnly: Bool
    let expirationDate: Int

    var netscapeLine: String? {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard host == "youtube.com" || host.hasSuffix(".youtube.com"),
              [domain, path, name, value].allSatisfy({ $0.rangeOfCharacter(from: CharacterSet(charactersIn: "\t\r\n")) == nil })
        else { return nil }
        let cookieDomain = (httpOnly ? "#HttpOnly_" : "") + domain
        return [cookieDomain, domain.hasPrefix(".") ? "TRUE" : "FALSE",
                path, secure ? "TRUE" : "FALSE", String(max(0, expirationDate)), name, value]
            .joined(separator: "\t")
    }
}
