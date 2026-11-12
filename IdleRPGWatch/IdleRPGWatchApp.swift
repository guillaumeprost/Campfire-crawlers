import SwiftUI

@main
struct IdleRPGWatchApp: App {
    @StateObject private var link = WatchLink.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(link)
        }
    }
}
