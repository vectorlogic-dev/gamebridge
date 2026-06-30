import Foundation

/// Append-only error log at
/// `~/Library/Application Support/GameBridge/errors.log`.
///
/// The UI surfaces problems via `WineRunner.logLines` and
/// `HoldRunner.registrationError`, but both are in-memory and reset on
/// relaunch. `ErrorLogger` persists the same problems (plus the silent
/// failures we used to swallow with `try?`) so the user can inspect them
/// after the fact.
///
/// Writes are serialised on a dedicated queue, then duplicated to stderr
/// so Xcode's console picks them up during development.
final class ErrorLogger: @unchecked Sendable {
    static let shared = ErrorLogger()

    private let url: URL
    private let queue = DispatchQueue(label: "com.argie.gamebridge.errorLogger")
    private let formatter: ISO8601DateFormatter

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.url = appSupport.appendingPathComponent("errors.log")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
    }

    /// File the log lives in. Exposed so a future "Reveal in Finder" button can
    /// point at it.
    var logFileURL: URL { url }

    /// Append a single error entry. `source` is a short tag — e.g. "wine",
    /// "hotkey", "bottle" — used to filter when reading the log.
    func log(_ message: String, source: String = "general") {
        let line = "[\(formatter.string(from: Date()))] [\(source)] \(message)\n"
        let data = Data(line.utf8)
        let url = self.url
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                // First write — file doesn't exist yet.
                try? data.write(to: url, options: .atomic)
            }
        }
        FileHandle.standardError.write(data)
    }

    /// Convenience for a thrown `Error` — flattens to localizedDescription.
    func log(_ error: Error, source: String = "general", context: String? = nil) {
        let payload = context.map { "\($0): \(error.localizedDescription)" } ?? error.localizedDescription
        log(payload, source: source)
    }

    /// Read the last N bytes of the log. Useful for a future in-app viewer.
    func recent(maxBytes: Int = 64 * 1024) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        if text.count <= maxBytes { return text }
        return String(text.suffix(maxBytes))
    }
}
