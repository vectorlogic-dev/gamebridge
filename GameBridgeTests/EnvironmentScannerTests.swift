import XCTest
@testable import GameBridge

final class EnvironmentScannerTests: XCTestCase {
    private let dxvkDLLs = ["d3d9.dll", "d3d10core.dll", "d3d11.dll", "dxgi.dll"]
    private let d3dMetalDLLs = ["d3d9.dll", "d3d10core.dll", "d3d11.dll", "d3d12.dll", "d3d12core.dll", "dxgi.dll"]

    func testScanBlocksWhenNoRuntimeIsSelectedAndBottleIsNotInitialised() {
        let bottle = Bottle(name: "Test Bottle", prefixPath: "/tmp/DoesNotExist")
        let scanner = EnvironmentScanner(
            runtimeDetector: { [] },
            fileExists: { _ in false },
            d3dMetalRedistLocator: { _ in nil },
            dxvkCacheLocator: { URL(fileURLWithPath: "/tmp/missing-dxvk") }
        )

        let report = scanner.scan(
            bottle: bottle,
            selectedRuntimePath: "",
            backend: .d3dmetal,
            executableURL: nil
        )

        XCTAssertEqual(report.status, .blocked)
        XCTAssertNil(report.selectedRuntime)
        XCTAssertTrue(report.findings.contains { $0.code == .missingRuntimeSelection })
        XCTAssertTrue(report.findings.contains { $0.code == .uninitialisedBottle })
    }

    func testScanBlocksWhenBottleIsMissingSystem32EvenIfDriveCExists() {
        let bottle = Bottle(name: "Almost Ready Bottle", prefixPath: "/tmp/AlmostReadyPrefix")
        let runtime = GameRuntimeInstall(
            name: "Homebrew wine",
            winePath: "/opt/homebrew/bin/wine64",
            family: .homebrewWine,
            capabilities: RuntimeCapabilities(
                supportsGenericWineLaunch: true,
                supportsD3DMetal: false,
                supportsDXVK: true
            )
        )

        let scanner = EnvironmentScanner(
            runtimeDetector: { [runtime] },
            fileExists: { path in
                path == runtime.winePath || path == bottle.driveCURL.path
            },
            d3dMetalRedistLocator: { _ in nil },
            dxvkCacheLocator: { URL(fileURLWithPath: "/tmp/missing-dxvk") }
        )

        let report = scanner.scan(
            bottle: bottle,
            selectedRuntimePath: runtime.winePath,
            backend: .wined3d,
            executableURL: nil
        )

        XCTAssertEqual(report.status, .blocked)
        XCTAssertTrue(report.findings.contains { $0.code == .uninitialisedBottle })
    }

    func testScanWarnsWhenDXVKBackendIsChosenWithoutCachedDXVK() {
        let bottle = Bottle(name: "Ready Bottle", prefixPath: "/tmp/ReadyPrefix")
        let runtime = GameRuntimeInstall(
            name: "Homebrew wine",
            winePath: "/opt/homebrew/bin/wine64",
            family: .homebrewWine,
            capabilities: RuntimeCapabilities(
                supportsGenericWineLaunch: true,
                supportsD3DMetal: false,
                supportsDXVK: true
            )
        )

        let scanner = EnvironmentScanner(
            runtimeDetector: { [runtime] },
            fileExists: { path in
                path == runtime.winePath || path.contains("/tmp/ReadyPrefix/drive_c")
            },
            d3dMetalRedistLocator: { _ in nil },
            dxvkCacheLocator: { URL(fileURLWithPath: "/tmp/missing-dxvk") }
        )

        let report = scanner.scan(
            bottle: bottle,
            selectedRuntimePath: runtime.winePath,
            backend: .dxvk,
            executableURL: nil
        )

        XCTAssertEqual(report.status, .warning)
        XCTAssertEqual(report.selectedRuntime, runtime)
        XCTAssertTrue(report.findings.contains { $0.code == .missingDXVKSupportFiles })
    }

    func testScanWarnsWhenDXVKBackendIsUnsupportedBySelectedRuntime() {
        let bottle = Bottle(name: "Ready Bottle", prefixPath: "/tmp/ReadyPrefix")
        let runtime = GameRuntimeInstall(
            name: "Unsupported wine",
            winePath: "/opt/homebrew/bin/wine64",
            family: .unknown,
            capabilities: RuntimeCapabilities(
                supportsGenericWineLaunch: true,
                supportsD3DMetal: false,
                supportsDXVK: false
            )
        )

        let scanner = EnvironmentScanner(
            runtimeDetector: { [runtime] },
            fileExists: { path in
                path == runtime.winePath || path == bottle.driveCURL.appendingPathComponent("windows/system32").path
            },
            d3dMetalRedistLocator: { _ in nil },
            dxvkCacheLocator: { URL(fileURLWithPath: "/tmp/cached-dxvk") }
        )

        let report = scanner.scan(
            bottle: bottle,
            selectedRuntimePath: runtime.winePath,
            backend: .dxvk,
            executableURL: nil
        )

        XCTAssertEqual(report.status, .warning)
        XCTAssertTrue(report.findings.contains(where: { $0.code == .unsupportedGraphicsBackend }))
        XCTAssertFalse(report.findings.contains(where: { $0.code == .missingDXVKSupportFiles }))
    }

    func testScanWarnsWhenDXVKCacheIsOnlyPartiallyPresent() {
        let bottle = Bottle(name: "Ready Bottle", prefixPath: "/tmp/ReadyPrefix")
        let runtime = GameRuntimeInstall(
            name: "Homebrew wine",
            winePath: "/opt/homebrew/bin/wine64",
            family: .homebrewWine,
            capabilities: RuntimeCapabilities(
                supportsGenericWineLaunch: true,
                supportsD3DMetal: false,
                supportsDXVK: true
            )
        )
        let cacheRoot = URL(fileURLWithPath: "/tmp/partial-dxvk")

        let scanner = EnvironmentScanner(
            runtimeDetector: { [runtime] },
            fileExists: { path in
                if path == runtime.winePath || path == bottle.driveCURL.appendingPathComponent("windows/system32").path {
                    return true
                }
                return path == cacheRoot.appendingPathComponent("x64/d3d11.dll").path
            },
            d3dMetalRedistLocator: { _ in nil },
            dxvkCacheLocator: { cacheRoot }
        )

        let report = scanner.scan(
            bottle: bottle,
            selectedRuntimePath: runtime.winePath,
            backend: .dxvk,
            executableURL: nil
        )

        XCTAssertEqual(report.status, .warning)
        XCTAssertTrue(report.findings.contains { $0.code == .missingDXVKSupportFiles })
    }

    func testScanWarnsWhenD3DMetalSupportFilesAreOnlyPartiallyPresent() {
        let bottle = Bottle(name: "Ready Bottle", prefixPath: "/tmp/ReadyPrefix")
        let runtime = GameRuntimeInstall(
            name: "GPTK (gcenx)",
            winePath: "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64",
            family: .gptk,
            capabilities: RuntimeCapabilities(
                supportsGenericWineLaunch: true,
                supportsD3DMetal: true,
                supportsDXVK: true
            )
        )
        let d3dMetalDirectory = URL(fileURLWithPath: "/tmp/partial-gptk-redist")

        let scanner = EnvironmentScanner(
            runtimeDetector: { [runtime] },
            fileExists: { path in
                if path == runtime.winePath || path == bottle.driveCURL.appendingPathComponent("windows/system32").path {
                    return true
                }
                return path == d3dMetalDirectory.appendingPathComponent("d3d11.dll").path
            },
            d3dMetalRedistLocator: { _ in d3dMetalDirectory },
            dxvkCacheLocator: { URL(fileURLWithPath: "/tmp/cached-dxvk") }
        )

        let report = scanner.scan(
            bottle: bottle,
            selectedRuntimePath: runtime.winePath,
            backend: .d3dmetal,
            executableURL: nil
        )

        XCTAssertEqual(report.status, .warning)
        XCTAssertTrue(report.findings.contains { $0.code == .missingD3DMetalSupportFiles })
    }

    func testScanWarnsWhenD3DMetalBackendIsUnsupportedBySelectedRuntime() {
        let bottle = Bottle(name: "Ready Bottle", prefixPath: "/tmp/ReadyPrefix")
        let runtime = GameRuntimeInstall(
            name: "Homebrew wine",
            winePath: "/opt/homebrew/bin/wine64",
            family: .homebrewWine,
            capabilities: RuntimeCapabilities(
                supportsGenericWineLaunch: true,
                supportsD3DMetal: false,
                supportsDXVK: true
            )
        )

        let scanner = EnvironmentScanner(
            runtimeDetector: { [runtime] },
            fileExists: { path in
                path == runtime.winePath || path == bottle.driveCURL.appendingPathComponent("windows/system32").path
            },
            d3dMetalRedistLocator: { _ in URL(fileURLWithPath: "/tmp/unneeded") },
            dxvkCacheLocator: { URL(fileURLWithPath: "/tmp/cached-dxvk") }
        )

        let report = scanner.scan(
            bottle: bottle,
            selectedRuntimePath: runtime.winePath,
            backend: .d3dmetal,
            executableURL: nil
        )

        XCTAssertEqual(report.status, .warning)
        XCTAssertTrue(report.findings.contains(where: { $0.code == .unsupportedGraphicsBackend }))
        XCTAssertFalse(report.findings.contains(where: { $0.code == .missingD3DMetalSupportFiles }))
    }

    func testScanReturnsInfoWhenRuntimeBottleAndBackendSupportAreReady() {
        let bottle = Bottle(name: "Ready Bottle", prefixPath: "/tmp/ReadyPrefix")
        let runtime = GameRuntimeInstall(
            name: "GPTK (gcenx)",
            winePath: "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64",
            family: .gptk,
            capabilities: RuntimeCapabilities(
                supportsGenericWineLaunch: true,
                supportsD3DMetal: true,
                supportsDXVK: true
            )
        )
        let d3dMetalDirectory = URL(fileURLWithPath: "/tmp/gptk-redist")

        let scanner = EnvironmentScanner(
            runtimeDetector: { [runtime] },
            fileExists: { path in
                if path == runtime.winePath ||
                    path == bottle.driveCURL.appendingPathComponent("windows/system32").path ||
                    path == "/tmp/ReadyPrefix/drive_c/Game/game.exe" {
                    return true
                }

                return self.d3dMetalDLLs.contains {
                    path == d3dMetalDirectory.appendingPathComponent($0).path
                }
            },
            d3dMetalRedistLocator: { _ in d3dMetalDirectory },
            dxvkCacheLocator: { URL(fileURLWithPath: "/tmp/cached-dxvk") }
        )

        let report = scanner.scan(
            bottle: bottle,
            selectedRuntimePath: runtime.winePath,
            backend: .d3dmetal,
            executableURL: URL(fileURLWithPath: "/tmp/ReadyPrefix/drive_c/Game/game.exe")
        )

        XCTAssertEqual(report.status, .info)
        XCTAssertEqual(report.selectedRuntime, runtime)
        XCTAssertTrue(report.findings.isEmpty)
    }

    func testScanMatchesSelectedRuntimeUsingCanonicalPaths() {
        let bottle = Bottle(name: "Ready Bottle", prefixPath: "/tmp/ReadyPrefix")
        let runtime = GameRuntimeInstall(
            name: "GPTK (gcenx)",
            winePath: "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64",
            family: .gptk,
            capabilities: RuntimeCapabilities(
                supportsGenericWineLaunch: true,
                supportsD3DMetal: true,
                supportsDXVK: true
            )
        )
        let selectedAliasPath = "/usr/local/bin/wine64"

        let scanner = EnvironmentScanner(
            runtimeDetector: { [runtime] },
            fileExists: { path in
                path == runtime.winePath || path == bottle.driveCURL.appendingPathComponent("windows/system32").path
            },
            d3dMetalRedistLocator: { _ in URL(fileURLWithPath: "/tmp/missing-redist") },
            dxvkCacheLocator: { URL(fileURLWithPath: "/tmp/cached-dxvk") },
            canonicalizePath: { path in
                path == selectedAliasPath ? runtime.winePath : path
            }
        )

        let report = scanner.scan(
            bottle: bottle,
            selectedRuntimePath: selectedAliasPath,
            backend: .d3dmetal,
            executableURL: nil
        )

        XCTAssertEqual(report.selectedRuntime, runtime)
        XCTAssertEqual(report.status, .warning)
        XCTAssertTrue(report.findings.contains(where: { $0.code == .missingD3DMetalSupportFiles }))
        XCTAssertFalse(report.findings.contains(where: { $0.code == .selectedRuntimeMissing }))
    }

    func testD3DMetalCandidateDirectoriesStayScopedToSelectedRuntime() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let winePath = tempRoot
            .appendingPathComponent("runtime/bin/wine64")
            .path

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("runtime/bin"),
            withIntermediateDirectories: true
        )

        let candidates = D3DMetalInstaller.candidateRedistDirectories(for: winePath)

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy { $0.path.hasPrefix(tempRoot.appendingPathComponent("runtime").path) })
        XCTAssertFalse(candidates.contains { $0.path.contains("/Applications/CrossOver.app/") })
        XCTAssertFalse(candidates.contains { $0.path.contains("/usr/local/opt/game-porting-toolkit/") })
    }

    func testDXVKCachedExtractedDirectoryValidityRequiresFullDLLSet() {
        let cacheRoot = URL(fileURLWithPath: "/tmp/dxvk-cache")

        let partialCacheIsValid = DXVKInstaller.isUsableCachedExtractedDirectory(in: cacheRoot) { path in
            path == cacheRoot.appendingPathComponent("x64/d3d11.dll").path
        }

        XCTAssertFalse(partialCacheIsValid)

        let fullCacheIsValid = DXVKInstaller.isUsableCachedExtractedDirectory(in: cacheRoot) { path in
            self.dxvkDLLs.contains { dllName in
                path == cacheRoot.appendingPathComponent("x64/\(dllName)").path ||
                    path == cacheRoot.appendingPathComponent("x32/\(dllName)").path
            }
        }

        XCTAssertTrue(fullCacheIsValid)
    }
}
