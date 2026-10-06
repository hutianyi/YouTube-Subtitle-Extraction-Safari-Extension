import AppKit
import SafariServices

private let taskDirectoryURL = URL(
    fileURLWithPath: "/private/tmp/com.example.YouTubeSubtitleExtraction",
    isDirectory: true
)

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let rawMessage: Any?

        if #available(macOS 11.0, *) {
            rawMessage = request?.userInfo?[SFExtensionMessageKey]
        } else {
            rawMessage = request?.userInfo?["message"]
        }

        guard
            let message = rawMessage as? [String: Any],
            message["action"] as? String == "extractAndSummarize",
            let videoURL = message["url"] as? String,
            let jobID = message["jobId"] as? String,
            !videoURL.isEmpty,
            !jobID.isEmpty
        else {
            complete(context, payload: [
                "ok": false,
                "error": "插件请求参数无效。"
            ])
            return
        }

        let taskFileURL = taskDirectoryURL
            .appendingPathComponent("\(UUID().uuidString).json")

        do {
            try FileManager.default.createDirectory(
                at: taskDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let taskData = try JSONSerialization.data(withJSONObject: [
                "jobId": jobID,
                "url": videoURL
            ])
            try taskData.write(to: taskFileURL, options: .atomic)
        } catch {
            complete(context, payload: [
                "ok": false,
                "error": "无法把任务交给后台字幕助手：\(error.localizedDescription)"
            ])
            return
        }

        let containingAppURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        guard containingAppURL.pathExtension.lowercased() == "app" else {
            try? FileManager.default.removeItem(at: taskFileURL)
            complete(context, payload: [
                "ok": false,
                "error": "无法定位后台字幕助手。"
            ])
            return
        }

        if #available(macOS 10.15, *) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(
                at: containingAppURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    try? FileManager.default.removeItem(at: taskFileURL)
                    self.complete(context, payload: [
                        "ok": false,
                        "error": "无法启动后台字幕助手：\(error.localizedDescription)"
                    ])
                } else {
                    self.complete(context, payload: ["ok": true, "accepted": true])
                }
            }
        } else if NSWorkspace.shared.open(containingAppURL) {
            complete(context, payload: ["ok": true, "accepted": true])
        } else {
            try? FileManager.default.removeItem(at: taskFileURL)
            complete(context, payload: [
                "ok": false,
                "error": "无法启动后台字幕助手。"
            ])
        }
    }

    private func complete(_ context: NSExtensionContext, payload: [String: Any]) {
        let response = NSExtensionItem()
        if #available(macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: payload]
        } else {
            response.userInfo = ["message": payload]
        }
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
