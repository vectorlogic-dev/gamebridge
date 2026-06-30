import Foundation

@MainActor
final class DXVKInstaller: ObservableObject {
    @Published private(set) var status: Status = .idle
    @Published private(set) var progress: String = ""

    enum Status: Equatable {
        case idle
        case downloading
        case installing
        case done
        case failed(String)
    }

    private static let dxvkVersion = "2.5.3"
    private static let downloadURL = URL(string: "https://github.com/doitsujin/dxvk/releases/download/v\(dxvkVersion)/dxvk-\(dxvkVersion).tar.gz")!

    private static let dllNames = ["d3d9.dll", "d3d10core.dll", "d3d11.dll", "dxgi.dll"]

    private var cacheDir: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameBridge/Cache/dxvk-\(Self.dxvkVersion)", isDirectory: true)
        return appSupport
    }

    func install(into bottle: Bottle) async {
        let fm = FileManager.default
        let sys32 = bottle.driveCURL.appendingPathComponent("windows/system32")
        let syswow = bottle.driveCURL.appendingPathComponent("windows/syswow64")

        guard fm.fileExists(atPath: sys32.path) else {
            status = .failed("Bottle not initialised — run wineboot first")
            return
        }

        do {
            let extractedDir = try await ensureCached()

            status = .installing
            progress = "Copying DLLs…"

            let x64 = extractedDir.appendingPathComponent("x64")
            let x32 = extractedDir.appendingPathComponent("x32")

            for dll in Self.dllNames {
                let src64 = x64.appendingPathComponent(dll)
                let dst64 = sys32.appendingPathComponent(dll)
                if fm.fileExists(atPath: src64.path) {
                    try? fm.removeItem(at: dst64)
                    try fm.copyItem(at: src64, to: dst64)
                }

                let src32 = x32.appendingPathComponent(dll)
                let dst32 = syswow.appendingPathComponent(dll)
                if fm.fileExists(atPath: src32.path), fm.fileExists(atPath: syswow.path) {
                    try? fm.removeItem(at: dst32)
                    try fm.copyItem(at: src32, to: dst32)
                }
            }

            status = .done
            progress = "DXVK \(Self.dxvkVersion) installed"
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func ensureCached() async throws -> URL {
        let fm = FileManager.default
        let extractedDir = cacheDir.appendingPathComponent("dxvk-\(Self.dxvkVersion)")

        if fm.fileExists(atPath: extractedDir.appendingPathComponent("x64/d3d11.dll").path) {
            progress = "Using cached DXVK \(Self.dxvkVersion)"
            return extractedDir
        }

        status = .downloading
        progress = "Downloading DXVK \(Self.dxvkVersion)…"

        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let tarball = cacheDir.appendingPathComponent("dxvk.tar.gz")

        let (data, response) = try await URLSession.shared.data(from: Self.downloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstallerError.downloadFailed
        }
        try data.write(to: tarball, options: .atomic)

        progress = "Extracting…"
        try await extract(tarball: tarball, to: cacheDir)
        try? fm.removeItem(at: tarball)

        guard fm.fileExists(atPath: extractedDir.appendingPathComponent("x64/d3d11.dll").path) else {
            throw InstallerError.extractionFailed
        }

        return extractedDir
    }

    private func extract(tarball: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["xzf", tarball.path, "-C", destination.path]
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: InstallerError.extractionFailed)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    enum InstallerError: LocalizedError {
        case downloadFailed
        case extractionFailed

        var errorDescription: String? {
            switch self {
            case .downloadFailed: "Failed to download DXVK from GitHub"
            case .extractionFailed: "Failed to extract DXVK archive"
            }
        }
    }
}
