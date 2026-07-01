import SwiftUI
import AppKit

struct BottleDetailView: View {
    @EnvironmentObject var store: BottleStore
    @StateObject private var runner = WineRunner()
    @StateObject private var dxvk = DXVKInstaller()
    @StateObject private var d3dmetal = D3DMetalInstaller()
    @StateObject private var holdRunner = HoldRunner()

    let bottle: Bottle

    @State private var backend: GraphicsBackend
    @State private var options = LaunchOptions()
    @State private var wineInstalls: [WineInstall] = WineLocator.detect()
    @State private var shortcutName = ""
    @State private var pendingExeURL: URL?
    @State private var showingSaveSheet = false
    @State private var readinessReport = LaunchReadinessReport(status: .info, selectedRuntime: nil, findings: [])

    private let scanner = EnvironmentScanner()

    private var launchState: BottleLaunchState {
        BottleLaunchState(report: readinessReport)
    }

    init(bottle: Bottle) {
        self.bottle = bottle
        _backend = State(initialValue: bottle.defaultBackend)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ReadinessSummaryView(state: launchState)
                .padding(.horizontal)
                .padding(.top, 10)
            controls
            Divider()
            if !bottle.shortcuts.isEmpty {
                shortcutsList
                Divider()
            }
            HoldMacroPanel(runner: holdRunner)
            Divider()
            logView
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(bottle.name)
        .sheet(isPresented: $showingSaveSheet) {
            saveShortcutSheet
        }
        .onAppear {
            refreshReadiness()
            if let saved = bottle.holdTargetKey {
                holdRunner.targetKey = saved
            }
        }
        .onChange(of: store.selectedWinePath) { _, _ in refreshReadiness() }
        .onChange(of: backend) { _, _ in refreshReadiness() }
        .onChange(of: bottle.isInitialised) { _, _ in refreshReadiness() }
        .onChange(of: holdRunner.targetKey) { _, newKey in persistHoldTargetKey(newKey) }
    }

    private func persistHoldTargetKey(_ newKey: NumberKey) {
        guard bottle.holdTargetKey != newKey else { return }
        var updated = bottle
        updated.holdTargetKey = newKey
        store.update(updated)
    }

    private func refreshReadiness(for executableURL: URL? = nil) {
        readinessReport = scanner.scan(
            bottle: bottle,
            selectedRuntimePath: store.selectedWinePath,
            backend: backend,
            executableURL: executableURL
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill").font(.largeTitle).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.name).font(.title2.bold())
                Text(bottle.prefixPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Label(bottle.isInitialised ? "Initialised" : "Not initialised",
                  systemImage: bottle.isInitialised ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(bottle.isInitialised ? .green : .orange)
                .font(.callout)
        }
        .padding()
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Wine", selection: $store.selectedWinePath) {
                    if wineInstalls.isEmpty {
                        Text("None found").tag("")
                    }
                    ForEach(wineInstalls) { Text("\($0.name) — \($0.winePath)").tag($0.winePath) }
                }
                .frame(maxWidth: 360)
                Button { wineInstalls = WineLocator.detect() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-scan for Wine / GPTK / CrossOver")
            }

            Picker("Graphics", selection: $backend) {
                ForEach(GraphicsBackend.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 460)

            HStack(spacing: 20) {
                Toggle("MetalFX upscaling", isOn: $options.metalFX)
                Toggle("FPS overlay", isOn: $options.showOverlay)
                Toggle("Advertise AVX", isOn: $options.advertiseAVX)
            }
            .toggleStyle(.checkbox)
            .font(.callout)

            HStack(spacing: 12) {
                Button {
                    runner.initialisePrefix(bottle, winePath: store.selectedWinePath)
                } label: { Label("Initialise", systemImage: "gearshape") }

                Button {
                    runner.openWinecfg(bottle, winePath: store.selectedWinePath)
                } label: { Label("winecfg", systemImage: "slider.horizontal.3") }
                .disabled(!bottle.isInitialised)

                Button {
                    d3dmetal.install(into: bottle, winePath: store.selectedWinePath)
                } label: { Label("Install D3DMetal", systemImage: "cpu") }
                .disabled(!bottle.isInitialised || store.selectedWinePath.isEmpty || d3dmetal.status == .installing)

                Button {
                    Task { await dxvk.install(into: bottle) }
                } label: { Label("Install DXVK", systemImage: "arrow.down.circle") }
                .disabled(!bottle.isInitialised || dxvk.status == .downloading || dxvk.status == .installing)

                Button {
                    pickAndLaunch()
                } label: { Label("Run .exe…", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedWinePath.isEmpty || !launchState.canLaunch)
                .help(launchState.canLaunch ? "" : launchState.primaryMessage)

                if runner.isRunning {
                    Button(role: .destructive) { runner.terminate() } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
                Spacer()
                if d3dmetal.status != .idle {
                    installerStatusLabel(busy: d3dmetal.status == .installing,
                                         done: d3dmetal.status == .done,
                                         text: d3dmetal.progress)
                }
                if dxvk.status != .idle {
                    dxvkStatusView
                }
                if runner.isRunning { ProgressView().controlSize(.small) }
            }
        }
        .padding()
    }

    // MARK: Installer status

    private var dxvkStatusView: some View {
        installerStatusLabel(busy: dxvk.status == .downloading || dxvk.status == .installing,
                             done: dxvk.status == .done,
                             text: dxvk.progress)
    }

    private func installerStatusLabel(busy: Bool, done: Bool, text: String) -> some View {
        HStack(spacing: 4) {
            if busy {
                ProgressView().controlSize(.small)
            } else if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Shortcuts

    private var shortcutsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Saved Games").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(bottle.shortcuts) { shortcut in
                HStack(spacing: 8) {
                    Button {
                        launchShortcut(shortcut)
                    } label: {
                        Label(shortcut.name, systemImage: "gamecontroller.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.selectedWinePath.isEmpty || runner.isRunning)

                    Text(shortcut.exeURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button(role: .destructive) {
                        removeShortcut(shortcut)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove shortcut")
                }
            }
        }
        .padding()
    }

    // MARK: Log

    private var logView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(runner.statusMessage).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { runner.clearLog() }.controlSize(.small)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(runner.logLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: runner.logLines.count) { _, count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
        .padding([.horizontal, .bottom])
    }

    // MARK: Save shortcut sheet

    private var saveShortcutSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Game Shortcut").font(.title3.bold())

            if let url = pendingExeURL {
                Text(url.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextField("Name", text: $shortcutName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Skip") {
                    showingSaveSheet = false
                    launchExe(pendingExeURL!)
                }
                Button("Save & Launch") {
                    saveAndLaunch()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(shortcutName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    // MARK: Actions

    private func pickAndLaunch() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Windows executable"
        panel.canChooseFiles = true
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.directoryURL = bottle.driveCURL
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alreadySaved = bottle.shortcuts.contains { $0.exePath == url.path }
        if alreadySaved {
            launchExe(url)
        } else {
            pendingExeURL = url
            shortcutName = url.deletingPathExtension().lastPathComponent
            showingSaveSheet = true
        }
    }

    private func saveAndLaunch() {
        guard let url = pendingExeURL else { return }
        let shortcut = GameShortcut(name: shortcutName.trimmingCharacters(in: .whitespaces),
                                    exePath: url.path)
        var updated = bottle
        updated.shortcuts.append(shortcut)
        store.update(updated)
        showingSaveSheet = false
        launchExe(url)
    }

    private func launchShortcut(_ shortcut: GameShortcut) {
        launchExe(shortcut.exeURL)
    }

    private func launchExe(_ url: URL) {
        switch RFBananaAssistedLaunch.decide(for: url, in: bottle) {
        case .notApplicable:
            runner.launch(
                exe: url,
                in: bottle,
                winePath: store.selectedWinePath,
                backend: backend,
                options: options
            )

        case .blocked(let message):
            runner.logExternal(message)
            runner.logExternal("[rfbanana] Assisted launch aborted before Wine startup.")

        case .ready(let assistedLaunch):
            runner.launch(
                exe: url,
                in: bottle,
                winePath: store.selectedWinePath,
                backend: backend,
                options: options,
                assistedLaunch: assistedLaunch
            )
        }
    }

    private func removeShortcut(_ shortcut: GameShortcut) {
        var updated = bottle
        updated.shortcuts.removeAll { $0.id == shortcut.id }
        store.update(updated)
    }
}
