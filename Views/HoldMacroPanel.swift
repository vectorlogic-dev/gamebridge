import SwiftUI

struct HoldMacroPanel: View {
    @ObservedObject var runner: HoldRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Hold key (autobuff)", systemImage: "hand.point.up.left.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                statusBadge
            }

            HStack {
                Text("Key").font(.callout)
                Picker("Key", selection: $runner.targetKey) {
                    ForEach(NumberKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                .disabled(runner.state != .idle)
            }

            instructions
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let error = runner.registrationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .onAppear { runner.registerHotkeys() }
        .onDisappear {
            runner.disarm()
            runner.unregisterHotkeys()
        }
    }

    // Don't apply `.fixedSize(horizontal: false, vertical: true)` here:
    // on macOS 26 it causes the entire NavigationSplitView body to render
    // empty. SwiftUI's default text wrapping inside the bounded panel is fine.
    private var instructions: Text {
        let start = runner.label(for: runner.startKeyCode, modifiers: runner.startModifiers)
        let stop = runner.label(for: runner.stopKeyCode, modifiers: runner.stopModifiers)
        let key = runner.targetKey.label
        return Text("Click into the game, press ")
            + Text(start).bold()
            + Text(" to start holding ")
            + Text(key).bold()
            + Text(" in that app. Press ")
            + Text(stop).bold()
            + Text(" to stop. Keys go only to the captured app, so you can use other apps while it runs.")
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch runner.state {
        case .idle:
            Label("Idle", systemImage: "pause.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .holding(let app, let since):
            Label("Holding \(runner.targetKey.label) → \(app) (\(elapsed(since: since)))",
                  systemImage: "play.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private func elapsed(since: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(since))
        let m = seconds / 60, s = seconds % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}
