import Foundation

struct EnvironmentScanner {
    var runtimeDetector: () -> [GameRuntimeInstall] = { WineLocator.detect() }
    var fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    var d3dMetalRedistLocator: (String) -> URL? = { D3DMetalInstaller.redistDirectory(for: $0) }
    var dxvkCacheLocator: () -> URL = { DXVKInstaller.cachedInstallDirectory() }
    var canonicalizePath: (String) -> String = {
        URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardized.path
    }

    func scan(
        bottle: Bottle,
        selectedRuntimePath: String,
        backend: GraphicsBackend,
        executableURL: URL?
    ) -> LaunchReadinessReport {
        let runtimes = runtimeDetector()
        let canonicalSelectedRuntimePath = selectedRuntimePath.isEmpty ? "" : canonicalizePath(selectedRuntimePath)
        let selectedRuntime = runtimes.first(where: {
            canonicalizePath($0.winePath) == canonicalSelectedRuntimePath
        })
        var findings: [ReadinessFinding] = []

        if selectedRuntimePath.isEmpty {
            findings.append(
                ReadinessFinding(
                    severity: .blocked,
                    code: .missingRuntimeSelection,
                    message: "Choose a Wine runtime before launching."
                )
            )
        } else if selectedRuntime == nil || !selectedRuntimeExists(
            selectedRuntimePath: selectedRuntimePath,
            canonicalSelectedRuntimePath: canonicalSelectedRuntimePath,
            selectedRuntime: selectedRuntime
        ) {
            findings.append(
                ReadinessFinding(
                    severity: .blocked,
                    code: .selectedRuntimeMissing,
                    message: "The selected Wine runtime is no longer available."
                )
            )
        }

        let system32Path = bottle.driveCURL
            .appendingPathComponent("windows/system32")
            .path
        if !fileExists(system32Path) {
            findings.append(
                ReadinessFinding(
                    severity: .blocked,
                    code: .uninitialisedBottle,
                    message: "Initialise this bottle before launching games."
                )
            )
        }

        if let executableURL, !fileExists(executableURL.path) {
            findings.append(
                ReadinessFinding(
                    severity: .blocked,
                    code: .executableMissing,
                    message: "The selected Windows executable could not be found."
                )
            )
        }

        if let selectedRuntime {
            if backend == .d3dmetal, selectedRuntime.capabilities.supportsD3DMetal == false {
                findings.append(
                    ReadinessFinding(
                        severity: .blocked,
                        code: .unsupportedGraphicsBackend,
                        message: "The selected Wine runtime does not support D3DMetal."
                    )
                )
            } else if backend == .d3dmetal {
                let hasD3DMetalSupportFiles = d3dMetalRedistLocator(selectedRuntime.winePath).map { directory in
                    D3DMetalInstaller.hasRequiredSupportFiles(in: directory, fileExists: fileExists)
                } == true
                if !hasD3DMetalSupportFiles {
                findings.append(
                    ReadinessFinding(
                        severity: .warning,
                        code: .missingD3DMetalSupportFiles,
                        message: "D3DMetal support files were not found for the selected runtime."
                    )
                )
                }
            }

            if backend == .dxvk, selectedRuntime.capabilities.supportsDXVK == false {
                findings.append(
                    ReadinessFinding(
                        severity: .blocked,
                        code: .unsupportedGraphicsBackend,
                        message: "The selected Wine runtime does not support DXVK."
                    )
                )
            } else if backend == .dxvk,
                      !DXVKInstaller.isUsableCachedExtractedDirectory(in: dxvkCacheLocator(), fileExists: fileExists) {
                findings.append(
                    ReadinessFinding(
                        severity: .warning,
                        code: .missingDXVKSupportFiles,
                        message: "DXVK is not cached yet and may need installation."
                    )
                )
            }
        }

        let status: ReadinessSeverity
        if findings.contains(where: { $0.severity == .blocked }) {
            status = .blocked
        } else if findings.contains(where: { $0.severity == .warning }) {
            status = .warning
        } else {
            status = .info
        }

        return LaunchReadinessReport(
            status: status,
            selectedRuntime: selectedRuntime,
            findings: findings
        )
    }

    private func selectedRuntimeExists(
        selectedRuntimePath: String,
        canonicalSelectedRuntimePath: String,
        selectedRuntime: GameRuntimeInstall?
    ) -> Bool {
        if fileExists(selectedRuntimePath) || fileExists(canonicalSelectedRuntimePath) {
            return true
        }
        guard let selectedRuntime else { return false }
        return fileExists(selectedRuntime.winePath) || fileExists(canonicalizePath(selectedRuntime.winePath))
    }
}
