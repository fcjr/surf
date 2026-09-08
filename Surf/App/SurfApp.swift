import SwiftUI

@main
struct SurfApp: App {
    @State private var store = RemoteStore()

    init() {
        _ = Updater.controller  // start Sparkle's scheduled update checks
    }

    var body: some Scene {
        MenuBarExtra("Surf", systemImage: "appletvremote.gen4") {
            MenuView()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Window("Surf Buttons", id: "buttons") {
            ButtonsView()
                .environment(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
