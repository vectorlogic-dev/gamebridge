import Foundation

struct RFBananaAssistedLaunchPlan: Equatable {
    let helperExecutableURL: URL
    let helperArguments: [String]
    let helperWorkingDirectory: URL
    let captureDirectory: URL
    let helperLogPrefix: String
}

enum RFBananaAssistedLaunchDecision: Equatable {
    case notApplicable
    case blocked(String)
    case ready(RFBananaAssistedLaunchPlan)
}

enum RFBananaAssistedLaunch {
    static func decide(
        for exeURL: URL,
        in bottle: Bottle,
        scriptURL: URL? = Bundle.main.url(forResource: "rfbanana_handoff_patcher", withExtension: "py"),
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> RFBananaAssistedLaunchDecision {
        guard exeURL.lastPathComponent.caseInsensitiveCompare("bananarfo.exe") == .orderedSame else {
            return .notApplicable
        }

        let installRoot = exeURL.deletingLastPathComponent()
        let gameBinary = installRoot.appendingPathComponent("RF_Online.bin")
        let defaultSet = installRoot.appendingPathComponent("System/DefaultSet.tmp")

        guard fileManager.fileExists(atPath: gameBinary.path),
              fileManager.fileExists(atPath: defaultSet.path) else {
            return .notApplicable
        }

        guard let scriptURL else {
            return .blocked("[rfbanana] Bundled assisted-launch helper is missing.")
        }

        let captureDirectory = diagnosticsRoot(for: bottle)
            .appendingPathComponent(timestampString(from: now), isDirectory: true)

        return .ready(
            RFBananaAssistedLaunchPlan(
                helperExecutableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                helperArguments: [
                    scriptURL.path,
                    "--game-dir", installRoot.path,
                    "--no-patch",
                    "--out-dir", captureDirectory.path
                ],
                helperWorkingDirectory: installRoot,
                captureDirectory: captureDirectory,
                helperLogPrefix: "[rfbanana-helper]"
            )
        )
    }

    private static func diagnosticsRoot(for bottle: Bottle) -> URL {
        bottle.prefixURL
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("RFBanana", isDirectory: true)
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.string(from: date)
    }
}
