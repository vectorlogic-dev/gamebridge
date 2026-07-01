import SwiftUI
import AppKit

struct CreateBottleView: View {
    @EnvironmentObject var store: BottleStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = "New Bottle"
    @State private var backend: GraphicsBackend = .d3dmetal
    @State private var existingPrefix: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Bottle").font(.title2.bold())

            Form {
                TextField("Name", text: $name)
                Picker("Default graphics", selection: $backend) {
                    ForEach(GraphicsBackend.allCases) { Text($0.label).tag($0) }
                }
                prefixRow
            }
            .formStyle(.grouped)

            explanation
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    @ViewBuilder
    private var prefixRow: some View {
        LabeledContent("Existing prefix") {
            HStack(spacing: 8) {
                if let existingPrefix {
                    Text(existingPrefix.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Button {
                        self.existingPrefix = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Use the default location instead")
                } else {
                    Text("Use default location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose…") { pickExistingPrefix() }
            }
        }
    }

    private var explanation: Text {
        if let existingPrefix {
            return Text("Using existing prefix at ")
                + Text(existingPrefix.path).font(.caption.monospaced())
                + Text(". Nothing will be created; the bottle will point at what's already there.")
        } else {
            return Text("A new prefix will be created under Application Support. "
                       + "It won't be initialised until you open the bottle and press “Initialise”.")
        }
    }

    private func pickExistingPrefix() {
        let panel = NSOpenPanel()
        panel.title = "Choose an existing Wine prefix"
        panel.message = "Pick the WINEPREFIX directory (the parent of drive_c)."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            existingPrefix = url
        }
    }

    private func create() {
        let url = existingPrefix ?? store.defaultPrefixURL(for: name)
        let bottle = Bottle(name: name, prefixPath: url.path, defaultBackend: backend)
        store.add(bottle)
        dismiss()
    }
}
