import Foundation
import Combine

/// Drives the actual Wine processes: initialises prefixes and launches games,
/// streaming their stdout/stderr back to the UI as a live log.
@MainActor
final class WineRunner: ObservableObject {
    @Published private(set) var logLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Idle"

    private var currentProcess: Process?
    private var helperProcess: Process?

    // MARK: - Public actions

    func logExternal(_ line: String) {
        appendLine(line)
    }

    /// Create + initialise a new prefix (wineboot). Safe to call on an existing one.
    func initialisePrefix(_ bottle: Bottle, winePath: String) {
        try? FileManager.default.createDirectory(at: bottle.prefixURL,
                                                 withIntermediateDirectories: true)
        statusMessage = "Initialising bottle…"
        run(winePath: winePath,
            arguments: ["wineboot", "--init"],
            workingDir: bottle.prefixURL,
            env: baseEnv(for: bottle, winePath: winePath),
            onFinish: { [weak self] code in
                self?.statusMessage = code == 0 ? "Bottle ready" : "wineboot exited \(code)"
            })
    }

    /// Launch a Windows .exe inside the bottle with the chosen backend.
    func launch(exe: URL,
                in bottle: Bottle,
                winePath: String,
                backend: GraphicsBackend,
                options: LaunchOptions,
                assistedLaunch: RFBananaAssistedLaunchPlan? = nil) {
        var env = baseEnv(for: bottle, winePath: winePath)
        for (k, v) in backend.environment(options: options) { env[k] = v }
        if options.advertiseAVX { env["ROSETTA_ADVERTISE_AVX"] = "1" }
        if options.showOverlay  { env["MTL_HUD_ENABLED"] = "1" }

        if let assistedLaunch {
            do {
                try FileManager.default.createDirectory(at: assistedLaunch.captureDirectory,
                                                        withIntermediateDirectories: true)
                appendLine("[rfbanana] capture dir: \(assistedLaunch.captureDirectory.path)")
                helperProcess = try startHelper(assistedLaunch)
            } catch {
                appendLine("[rfbanana] Failed to start assisted launch: \(error.localizedDescription)")
                statusMessage = "Assisted launch failed"
                ErrorLogger.shared.log(error, source: "wine", context: "rfbanana helper for \(exe.lastPathComponent)")
                return
            }
        }

        statusMessage = "Launching \(exe.lastPathComponent) [\(backend.label)]"
        do {
            currentProcess = try startProcess(
                executableURL: URL(fileURLWithPath: winePath),
                arguments: [exe.path],
                workingDir: exe.deletingLastPathComponent(),
                env: env,
                logPrefix: "[wine]",
                onFinish: { [weak self] code in
                    self?.isRunning = false
                    self?.currentProcess = nil
                    self?.stopHelperIfRunning()
                    self?.statusMessage = "Game exited (code \(code))"
                }
            )
            isRunning = true
        } catch {
            currentProcess = nil
            isRunning = false
            stopHelperIfRunning()
            statusMessage = "Launch failed"
            ErrorLogger.shared.log(error, source: "wine", context: "launch \(exe.lastPathComponent) via \(winePath)")
        }
    }

    /// Run winecfg so the user can tweak the prefix (Windows version, drives…).
    func openWinecfg(_ bottle: Bottle, winePath: String) {
        statusMessage = "Opening winecfg…"
        run(winePath: winePath,
            arguments: ["winecfg"],
            workingDir: bottle.prefixURL,
            env: baseEnv(for: bottle, winePath: winePath),
            onFinish: { [weak self] _ in self?.statusMessage = "Idle" })
    }

    func terminate() {
        stopHelperIfRunning()
        currentProcess?.terminate()
    }

    func clearLog() { logLines.removeAll() }

    // MARK: - Internals

    private func baseEnv(for bottle: Bottle, winePath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.prefixPath
        env["WINEMSYNC"] = "1"          // GPTK uses msync (not Linux esync)
        env["WINEDEBUG"] = "fixme-all"  // quiet but keep real errors
        // Make sure the wine bin dir is on PATH so it finds its siblings.
        let binDir = (winePath as NSString).deletingLastPathComponent
        env["PATH"] = binDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        return env
    }

    private func run(winePath: String,
                     arguments: [String],
                     workingDir: URL,
                     env: [String: String],
                     onFinish: @MainActor @escaping @Sendable (Int32) -> Void) {
        do {
            currentProcess = try startProcess(
                executableURL: URL(fileURLWithPath: winePath),
                arguments: arguments,
                workingDir: workingDir,
                env: env,
                logPrefix: "[wine]",
                onFinish: { [weak self] code in
                    self?.isRunning = false
                    self?.currentProcess = nil
                    onFinish(code)
                }
            )
            isRunning = true
        } catch {
            currentProcess = nil
            isRunning = false
            ErrorLogger.shared.log(error, source: "wine", context: "run \(arguments.first ?? "?") via \(winePath)")
        }
    }

    private func startProcess(executableURL: URL,
                              arguments: [String],
                              workingDir: URL,
                              env: [String: String],
                              logPrefix: String,
                              onFinish: @MainActor @escaping @Sendable (Int32) -> Void) throws -> Process {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            let message = "Executable not found or not executable: \(executableURL.path)"
            appendLine("\(logPrefix) Failed to start: \(message)")
            let error = NSError(domain: NSCocoaErrorDomain,
                                code: CocoaError.fileReadNoSuchFile.rawValue,
                                userInfo: [
                                    NSLocalizedDescriptionKey: message,
                                    NSFilePathErrorKey: executableURL.path
                                ])
            throw error
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = env
        process.currentDirectoryURL = workingDir

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendChunk(text, prefix: logPrefix)
            }
        }

        process.terminationHandler = { proc in
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                onFinish(proc.terminationStatus)
            }
        }

        do {
            appendLine("\(logPrefix) ▶ \(executableURL.path) \(arguments.joined(separator: " "))")
            try process.run()
            return process
        } catch {
            appendLine("\(logPrefix) Failed to start: \(error.localizedDescription)")
            throw error
        }
    }

    private func startHelper(_ plan: RFBananaAssistedLaunchPlan) throws -> Process {
        let process = try startProcess(
            executableURL: plan.helperExecutableURL,
            arguments: plan.helperArguments,
            workingDir: plan.helperWorkingDirectory,
            env: ProcessInfo.processInfo.environment,
            logPrefix: plan.helperLogPrefix,
            onFinish: { [weak self] code in
                self?.helperProcess = nil
                self?.appendLine("[rfbanana-helper] exited with code \(code)")
            }
        )
        appendLine("[rfbanana] assisted launch started")
        return process
    }

    private func stopHelperIfRunning() {
        helperProcess?.terminate()
        helperProcess = nil
    }

    /// Kill any leftover helper subprocesses from a prior GameBridge run that
    /// didn't clean up (crash, force-quit, debugger stop). The normal path
    /// (`stopHelperIfRunning`) doesn't fire in those cases and the Python
    /// child is left running — we saw five orphans accumulate over one
    /// evening. Safe to call at app startup because the single-instance
    /// guard has already established we're the only GameBridge process, so
    /// any matching Python is genuinely stale.
    ///
    /// Matches on the *bundled* helper script path so we only kill processes
    /// that were spawned from this specific `.app` bundle — a different
    /// GameBridge build living somewhere else on disk is left alone.
    nonisolated static func reapOrphanHelpers() {
        guard let helperPath = Bundle.main.url(
            forResource: "rfbanana_handoff_patcher",
            withExtension: "py"
        )?.path else { return }

        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", helperPath]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = Pipe()

        do {
            try pgrep.run()
            pgrep.waitUntilExit()
        } catch {
            return
        }

        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else { return }

        let pids = output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0) }
            .filter { $0 > 0 }

        for pid in pids {
            _ = kill(pid, SIGTERM)
        }

        if !pids.isEmpty {
            ErrorLogger.shared.log(
                "Reaped \(pids.count) orphan helper process\(pids.count == 1 ? "" : "es"): \(pids.map(String.init).joined(separator: ", "))",
                source: "wine"
            )
        }
    }

    private func appendChunk(_ text: String, prefix: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines where !line.isEmpty {
            appendLine("\(prefix) \(line)")
        }
    }

    private func appendLine(_ line: String) {
        logLines.append(line)
        if logLines.count > 5000 { logLines.removeFirst(logLines.count - 5000) }
    }
}
