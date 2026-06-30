import SwiftUI

@main
struct GameBridgeApp: App {
    @StateObject private var store = BottleStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}
