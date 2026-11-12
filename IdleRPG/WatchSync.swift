import Foundation
import WatchConnectivity

/// Envoie l'état du héros à l'Apple Watch.
///
/// L'App Group ne traverse pas d'un appareil à l'autre : le jeu pousse donc
/// la même `HeroWidgetData` (sa chronologie de frames + les moments à venir)
/// vers la montre, qui la range dans son propre App Group et redessine ses
/// complications. Comme pour les widgets, la montre « rejoue » ensuite seule
/// la chronologie reçue, même hors de portée du téléphone.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    /// Dernier état en attente si la session n'est pas encore prête.
    private var pending: HeroWidgetData?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// À appeler à chaque fois que le jeu réécrit l'état des widgets.
    func send(_ data: HeroWidgetData) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = data
            return
        }
        push(data, on: session)
    }

    private func push(_ data: HeroWidgetData, on session: WCSession) {
        guard let payload = try? JSONEncoder().encode(data) else { return }
        let context = ["heroWidgetData": payload]
        // Contexte : toujours le plus récent, remplacé à chaque envoi, livré dès que possible.
        try? session.updateApplicationContext(context)
        // En plus, un transfert dédié aux complications quand le budget le permet.
        #if os(iOS)
        if session.isComplicationEnabled {
            session.transferCurrentComplicationUserInfo(context)
        }
        #endif
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if state == .activated, let data = pending {
            pending = nil
            push(data, on: session)
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Réactiver pour la montre suivante (changement d'appareil).
        WCSession.default.activate()
    }
    #endif
}
