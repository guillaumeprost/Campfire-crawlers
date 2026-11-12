import Foundation
import WatchConnectivity
import WidgetKit

/// Reçoit l'état du héros envoyé par le jeu sur l'iPhone, le range dans l'App Group
/// de la montre et prévient l'app et les complications.
///
/// Rien ne force le téléphone à être à portée : au lancement, et entre deux envois,
/// la montre relit la dernière chronologie reçue et montre le héros à l'heure qu'il est.
@MainActor
final class WatchLink: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchLink()

    @Published var data: HeroWidgetData?

    private override init() {
        super.init()
        data = HeroWidgetData.load()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func store(_ payload: Data) {
        guard let decoded = try? JSONDecoder().decode(HeroWidgetData.self, from: payload) else { return }
        decoded.save()
        WidgetCenter.shared.reloadAllTimelines()
        Task { @MainActor in self.data = decoded }
    }

    private func handle(_ dictionary: [String: Any]) {
        guard let payload = dictionary["heroWidgetData"] as? Data else { return }
        store(payload)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.handle(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.handle(userInfo) }
    }
}
