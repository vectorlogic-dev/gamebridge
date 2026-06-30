import Foundation

enum ReadinessSeverity: String, Equatable {
    case info
    case warning
    case blocked
}

enum ReadinessCode: String, Equatable {
    case missingRuntimeSelection
    case selectedRuntimeMissing
    case uninitialisedBottle
    case unsupportedGraphicsBackend
    case missingD3DMetalSupportFiles
    case missingDXVKSupportFiles
    case executableMissing
}

struct ReadinessFinding: Equatable, Identifiable {
    var id: String { "\(code.rawValue):\(message)" }

    let severity: ReadinessSeverity
    let code: ReadinessCode
    let message: String
}

struct LaunchReadinessReport: Equatable {
    let status: ReadinessSeverity
    let selectedRuntime: GameRuntimeInstall?
    let findings: [ReadinessFinding]
}
