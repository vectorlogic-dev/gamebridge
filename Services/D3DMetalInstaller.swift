import Foundation

@MainActor
final class D3DMetalInstaller: ObservableObject {
    @Published private(set) var status: Status = .idle
    @Published private(set) var progress: String = ""

    enum Status: Equatable {
        case idle
        case installing
        case done
        case failed(String)
    }

    nonisolated private static let dllNames = [
        "d3d9.dll", "d3d10core.dll", "d3d11.dll",
        "d3d12.dll", "d3d12core.dll", "dxgi.dll",
    ]

    func install(into bottle: Bottle, winePath: String) {
        let fm = FileManager.default
        let sys32 = bottle.driveCURL.appendingPathComponent("windows/system32")

        guard fm.fileExists(atPath: sys32.path) else {
            status = .failed("Bottle not initialised — run wineboot first")
            return
        }

        guard let redistDir = Self.redistDirectory(for: winePath) else {
            status = .failed("D3DMetal DLLs not found — is GPTK installed?")
            return
        }

        status = .installing
        progress = "Copying D3DMetal DLLs…"

        var copied = 0
        for dll in Self.dllNames {
            let src = redistDir.appendingPathComponent(dll)
            let dst = sys32.appendingPathComponent(dll)
            guard fm.fileExists(atPath: src.path) else { continue }
            do {
                try? fm.removeItem(at: dst)
                try fm.copyItem(at: src, to: dst)
                copied += 1
            } catch {
                status = .failed("Failed to copy \(dll): \(error.localizedDescription)")
                return
            }
        }

        if copied == 0 {
            status = .failed("No D3DMetal DLLs found in \(redistDir.path)")
        } else {
            status = .done
            progress = "D3DMetal installed (\(copied) DLLs)"
        }
    }

    nonisolated static func candidateRedistDirectories(for winePath: String) -> [URL] {
        let resolvedWineBin = URL(fileURLWithPath: winePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let wineRoot = resolvedWineBin.deletingLastPathComponent().deletingLastPathComponent()

        return [
            wineRoot.appendingPathComponent("lib/wine/x86_64-windows"),
            wineRoot.appendingPathComponent("lib64/wine/x86_64-windows"),
            wineRoot.appendingPathComponent("share/wine/gecko/../../../lib/wine/x86_64-windows").standardizedFileURL,
        ]
    }

    nonisolated static func hasRequiredSupportFiles(
        in directory: URL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        dllNames.allSatisfy { fileExists(directory.appendingPathComponent($0).path) }
    }

    nonisolated static func redistDirectory(for winePath: String, fileManager: FileManager = .default) -> URL? {
        candidateRedistDirectories(for: winePath).first {
            hasRequiredSupportFiles(in: $0) { fileManager.fileExists(atPath: $0) }
        }
    }
}
