import XCTest
@testable import GameBridge

final class RuntimeDiscoveryTests: XCTestCase {
    func testDetectClassifiesGPTKRuntimeAsD3DMetalCapable() {
        let installs = WineLocator.detect(
            candidatePaths: [
                ("GPTK (gcenx)", "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64")
            ],
            isExecutable: { path in
                path.contains("Game Porting Toolkit.app")
            },
            canonicalPath: { $0 }
        )

        XCTAssertEqual(installs.count, 1)
        XCTAssertEqual(installs[0].family, .gptk)
        XCTAssertTrue(installs[0].capabilities.supportsD3DMetal)
        XCTAssertTrue(installs[0].capabilities.supportsGenericWineLaunch)
    }

    func testDetectDeduplicatesRepeatedExecutablePaths() {
        let installs = WineLocator.detect(
            candidatePaths: [
                ("Homebrew wine", "/opt/homebrew/bin/wine64"),
                ("Homebrew wine", "/opt/homebrew/bin/wine64")
            ],
            isExecutable: { _ in true },
            canonicalPath: { $0 }
        )

        XCTAssertEqual(installs.map(\.winePath), ["/opt/homebrew/bin/wine64"])
    }

    func testDetectDoesNotClassifyUsrLocalAliasAsGPTKWithoutGPTKPathEvidence() {
        let installs = WineLocator.detect(
            candidatePaths: [
                ("Game Porting Toolkit", "/usr/local/bin/wine64")
            ],
            isExecutable: { _ in true },
            canonicalPath: { _ in "/usr/local/Cellar/wine/stable/bin/wine64" }
        )

        XCTAssertEqual(installs.count, 1)
        XCTAssertEqual(installs[0].family, .homebrewWine)
        XCTAssertFalse(installs[0].capabilities.supportsD3DMetal)
    }

    func testDetectDeduplicatesAliasedPathsThatResolveToSameExecutable() {
        let installs = WineLocator.detect(
            candidatePaths: [
                ("Game Porting Toolkit", "/usr/local/bin/wine64"),
                ("GPTK (gcenx)", "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64")
            ],
            isExecutable: { _ in true },
            canonicalPath: { path in
                switch path {
                case "/usr/local/bin/wine64":
                    return "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"
                default:
                    return path
                }
            }
        )

        XCTAssertEqual(installs.count, 1)
        XCTAssertEqual(installs[0].family, .gptk)
        XCTAssertEqual(installs[0].winePath, "/usr/local/bin/wine64")
    }
}
