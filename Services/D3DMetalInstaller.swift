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

    private static let dllNames = [
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

        guard let redistDir = findRedistDir(winePath: winePath) else {
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

    private func findRedistDir(winePath: String) -> URL? {
        let fm = FileManager.default
        let wineBin = URL(fileURLWithPath: winePath)
        let wineRoot = wineBin.deletingLastPathComponent().deletingLastPathComponent()

        let candidates = [
            wineRoot.appendingPathComponent("lib/wine/x86_64-windows"),
            wineRoot.appendingPathComponent("lib64/wine/x86_64-windows"),
            wineRoot.appendingPathComponent("share/wine/gecko/../../../lib/wine/x86_64-windows"),
        ]

        for dir in candidates {
            let probe = dir.appendingPathComponent("d3d11.dll")
            if fm.fileExists(atPath: probe.path) {
                return dir
            }
        }

        let hardcoded = [
            "/usr/local/opt/game-porting-toolkit/lib/wine/x86_64-windows",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows",
        ]
        for path in hardcoded {
            let dir = URL(fileURLWithPath: path)
            if fm.fileExists(atPath: dir.appendingPathComponent("d3d11.dll").path) {
                return dir
            }
        }

        return nil
    }
}
