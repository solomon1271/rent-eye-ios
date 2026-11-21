import SwiftUI

@main
struct RentEyeManagerApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                // The Rent Eye colours are designed for a light background; in dark mode iOS turned
                // typed text white on light fields. Keep the app light whatever the phone's setting.
                .preferredColorScheme(.light)
        }
    }
}
