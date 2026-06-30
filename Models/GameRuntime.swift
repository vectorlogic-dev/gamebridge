import Foundation

enum RuntimeFamily: String, Codable, Hashable {
    case gptk
    case crossover
    case whisky
    case homebrewWine
    case unknown
}

struct RuntimeCapabilities: Codable, Hashable {
    let supportsGenericWineLaunch: Bool
    let supportsD3DMetal: Bool
    let supportsDXVK: Bool
}

struct GameRuntimeInstall: Identifiable, Codable, Hashable {
    var id: String { winePath }

    let name: String
    let winePath: String
    let family: RuntimeFamily
    let capabilities: RuntimeCapabilities
}

typealias WineInstall = GameRuntimeInstall
