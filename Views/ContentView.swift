import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: BottleStore
    @State private var selection: Bottle.ID?
    @State private var showingCreate = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section("Bottles") {
                    ForEach(store.bottles) { bottle in
                        Label(bottle.name, systemImage: "shippingbox")
                            .tag(bottle.id)
                            .contextMenu {
                                Button("Delete (keep files)") {
                                    store.remove(bottle, deleteFiles: false)
                                }
                                Button("Delete + erase prefix", role: .destructive) {
                                    store.remove(bottle, deleteFiles: true)
                                }
                            }
                    }
                }
            }
            .navigationTitle("GameBridge")
            .toolbar {
                ToolbarItem {
                    Button { showingCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .frame(minWidth: 220)
        } detail: {
            if let id = selection, let bottle = store.bottles.first(where: { $0.id == id }) {
                BottleDetailView(bottle: bottle)
                    .id(bottle.id)
            } else {
                ContentUnavailableView("No Bottle Selected",
                                       systemImage: "shippingbox",
                                       description: Text("Create a bottle, then drop a Windows .exe into it."))
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateBottleView()
        }
    }
}
