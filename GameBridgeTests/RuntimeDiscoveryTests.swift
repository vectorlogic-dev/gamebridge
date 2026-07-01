import XCTest
@testable import GameBridge

final class RuntimeDiscoveryTests: XCTestCase {
    func testDetectClassifiesGPTKRuntimeAsD3DMetalCapableWhenRedistPresent() {
        let installs = WineLocator.detect(
            candidatePaths: [
                ("GPTK (gcenx)", "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64")
            ],
            isExecutable: { path in
                path.contains("Game Porting Toolkit.app")
            },
            canonicalPath: { $0 },
            d3dMetalProbe: { _ in true }
        )

        XCTAssertEqual(installs.count, 1)
        XCTAssertEqual(installs[0].family, .gptk)
        XCTAssertTrue(installs[0].capabilities.supportsD3DMetal)
        XCTAssertTrue(installs[0].capabilities.supportsGenericWineLaunch)
    }

    func testDetectReportsGPTKAsD3DMetalIncapableWhenRedistMissing() {
        // Broken / incomplete GPTK install: family is still .gptk, but the
        // capability is driven by the probe, not the family, so we correctly
        // say D3DMetal is unavailable.
        let installs = WineLocator.detect(
            candidatePaths: [
                ("GPTK (gcenx)", "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64")
            ],
            isExecutable: { _ in true },
            canonicalPath: { $0 },
            d3dMetalProbe: { _ in false }
        )

        XCTAssertEqual(installs.count, 1)
        XCTAssertEqual(installs[0].family, .gptk)
        XCTAssertFalse(installs[0].capabilities.supportsD3DMetal)
    }

    func testDetectReportsHomebrewAsD3DMetalCapableWhenRedistPresent() {
        // Community D3DMetal DLLs dropped into a Homebrew wine tree: the
        // family stays .homebrewWine, but the probe confirms the DLLs are
        // there, so the capability is now true — no more false warning.
        let installs = WineLocator.detect(
            candidatePaths: [
                ("Homebrew wine", "/opt/homebrew/bin/wine")
            ],
            isExecutable: { _ in true },
            canonicalPath: { $0 },
            d3dMetalProbe: { path in path.hasPrefix("/opt/homebrew/") }
        )

        XCTAssertEqual(installs.count, 1)
        XCTAssertEqual(installs[0].family, .homebrewWine)
        XCTAssertTrue(installs[0].capabilities.supportsD3DMetal)
    }

    func testDetectDeduplicatesRepeatedExecutablePaths() {
        let installs = WineLocator.detect(
            candidatePaths: [
                ("Homebrew wine", "/opt/homebrew/bin/wine64"),
                ("Homebrew wine", "/opt/homebrew/bin/wine64")
            ],
            isExecutable: { _ in true },
            canonicalPath: { $0 },
            d3dMetalProbe: { _ in false }
        )

        XCTAssertEqual(installs.map(\.winePath), ["/opt/homebrew/bin/wine64"])
    }

    func testDetectDoesNotClassifyUsrLocalAliasAsGPTKWithoutGPTKPathEvidence() {
        let installs = WineLocator.detect(
            candidatePaths: [
                ("Game Porting Toolkit", "/usr/local/bin/wine64")
            ],
            isExecutable: { _ in true },
            canonicalPath: { _ in "/usr/local/Cellar/wine/stable/bin/wine64" },
            d3dMetalProbe: { _ in false }
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
            },
            d3dMetalProbe: { _ in true }
        )

        XCTAssertEqual(installs.count, 1)
        XCTAssertEqual(installs[0].family, .gptk)
        XCTAssertEqual(installs[0].winePath, "/usr/local/bin/wine64")
    }
}
