import SwiftUI

struct CreateBottleView: View {
    @EnvironmentObject var store: BottleStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = "New Bottle"
    @State private var backend: GraphicsBackend = .d3dmetal

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Bottle").font(.title2.bold())

            Form {
                TextField("Name", text: $name)
                Picker("Default graphics", selection: $backend) {
                    ForEach(GraphicsBackend.allCases) { Text($0.label).tag($0) }
                }
            }
            .formStyle(.grouped)

            Text("A new prefix will be created under Application Support. "
                 + "It won't be initialised until you open the bottle and press “Initialise”.")
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
        .frame(width: 420)
    }

    private func create() {
        let url = store.defaultPrefixURL(for: name)
        let bottle = Bottle(name: name, prefixPath: url.path, defaultBackend: backend)
        store.add(bottle)
        dismiss()
    }
}
