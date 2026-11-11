import SwiftUI

@main
struct IdleRPGApp: App {
    @State private var game = GameState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(game: game)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                game.resume()
            case .background, .inactive:
                game.suspend()
            @unknown default:
                break
            }
        }
    }
}
