import Foundation

/// Which DirectX -> GPU translation path Wine should use inside a bottle.
enum GraphicsBackend: String, CaseIterable, Codable, Identifiable {
    /// Apple's Direct3D -> Metal layer (Game Porting Toolkit). Fastest path for
    /// most modern D3D11/12 titles. Requires the GPTK D3DMetal redist libraries
    /// to be present in the bottle (see README).
    case d3dmetal
    /// Direct3D -> Vulkan via DXVK + MoltenVK. Broad-compatibility fallback for
    /// titles D3DMetal mishandles. Requires DXVK dlls installed in the bottle.
    case dxvk
    /// Wine's built-in OpenGL-based D3D. Slowest, but needs no extra redist.
    case wined3d

    var id: String { rawValue }

    var label: String {
        switch self {
        case .d3dmetal: return "D3DMetal (GPTK)"
        case .dxvk:     return "DXVK (Vulkan)"
        case .wined3d:  return "wined3d (OpenGL)"
        }
    }

    /// DLL overrides + env that steer Wine toward this backend.
    /// "n" = native (the backend's dll), "b" = builtin fallback.
    func environment(options: LaunchOptions) -> [String: String] {
        var env: [String: String] = [:]
        switch self {
        case .d3dmetal:
            env["WINEDLLOVERRIDES"] = "d3d9,d3d10core,d3d11,d3d12,d3d12core,dxgi=n,b"
            env["D3DM_ENABLE_METALFX"] = options.metalFX ? "1" : "0"
        case .dxvk:
            env["WINEDLLOVERRIDES"] = "d3d9,d3d10core,d3d11,dxgi=n"
            if options.showOverlay { env["DXVK_HUD"] = "fps,devinfo" }
        case .wined3d:
            env["WINEDLLOVERRIDES"] = ""
        }
        return env
    }
}

/// Per-launch tweaks surfaced in the UI.
struct LaunchOptions {
    var metalFX: Bool = true        // D3DMetal upscaling
    var showOverlay: Bool = false   // Metal HUD / DXVK HUD FPS overlay
    var advertiseAVX: Bool = true   // needed by some titles (Rosetta on Sequoia+)
}
