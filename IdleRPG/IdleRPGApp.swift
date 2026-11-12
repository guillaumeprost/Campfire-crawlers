import SwiftUI

@main
struct IdleRPGApp: App {
    @State private var game = GameState()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                withAnimation(.easeOut(duration: 0.6)) { showSplash = false }
                            }
                        }
                } else {
                    ContentView(game: game)
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                game.resume()
                Outreach.clearDelivered()
            case .background, .inactive:
                game.suspend()
            @unknown default:
                break
            }
        }
    }
}

/// Écran de lancement : la key art avec le logo, qui s'efface en fondu.
private struct SplashView: View {
    @State private var frame = 1
    @State private var appeared = false
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(red: 0.067, green: 0.078, blue: 0.169)
            HStack(alignment: .bottom, spacing: -48) {
                runner("hero_warrior")
                runner("hero_archer")
                runner("hero_mage")
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
        }
        .ignoresSafeArea()
        .onReceive(timer) { _ in frame = frame % 8 + 1 }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { appeared = true }
        }
    }

    /// Un héros qui court sur place, en bouclant ses 8 frames de marche.
    private func runner(_ hero: String) -> some View {
        Image("\(hero)_walk_\(frame)")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(height: 92)
    }
}
