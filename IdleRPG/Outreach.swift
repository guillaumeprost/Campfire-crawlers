import ActivityKit
import Foundation
import UIKit
import UserNotifications

/// Une notification locale à programmer.
struct PlannedNotification {
    let id: String
    let date: Date
    let title: String
    let body: String
}

/// Tout ce que le jeu veut montrer hors de l'application :
/// les notifications à venir et l'activité en direct.
struct OutreachPlan {
    var notifications: [PlannedNotification] = []
    var live: HeroActivityAttributes.ContentState?
    /// Moment où l'activité en direct bascule sur son second panneau.
    var staleDate: Date?
}

/// Programme les notifications et tient à jour l'activité en direct.
enum Outreach {
    private static let ids = ["hero.landing", "hero.rested", "hero.hungry", "hero.thirsty", "hero.starving", "hero.dying", "hero.fork", "hero.bored"]

    /// Portrait du héros, joint aux notifications.
    static var portrait = "hero_mage_portrait"
    private static var lastPlan = OutreachPlan()
    private static var chain: Task<Void, Never>?

    /// Demande l'accord pour les notifications. Sans effet si la question a déjà été posée.
    static func askPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { schedule(lastPlan.notifications) }
        }
    }

    /// Retire les notifications déjà affichées : le joueur est revenu dans le jeu.
    static func clearDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    static func apply(_ plan: OutreachPlan) {
        lastPlan = plan
        schedule(plan.notifications)

        let previous = chain
        chain = Task {
            await previous?.value
            await syncActivity(state: plan.live, staleDate: plan.staleDate)
        }
    }

    private static func schedule(_ notifications: [PlannedNotification]) {
        let center = UNUserNotificationCenter.current()
        // Ajouter une demande remplace celle du même identifiant : on ne retire que les autres.
        let kept = Set(notifications.map(\.id))
        center.removePendingNotificationRequests(withIdentifiers: ids.filter { !kept.contains($0) })

        for note in notifications {
            let delay = note.date.timeIntervalSinceNow
            guard delay > 1 else {
                center.removePendingNotificationRequests(withIdentifiers: [note.id])
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = note.title
            content.body = note.body
            content.sound = .default
            content.threadIdentifier = "hero"
            if let attachment = portraitAttachment(for: note.id) { content.attachments = [attachment] }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            center.add(UNNotificationRequest(identifier: note.id, content: content, trigger: trigger))
        }
    }

    /// Le système déplace la pièce jointe : on en écrit une copie par notification.
    private static func portraitAttachment(for id: String) -> UNNotificationAttachment? {
        guard let image = UIImage(named: portrait) else { return nil }
        // Agrandi sans lissage pour garder les pixels nets.
        let side: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            context.cgContext.interpolationQuality = .none
            let ratio = min(side / image.size.width, side / image.size.height) * 0.9
            let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        guard let data = big.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(id)-\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: id, url: url)
    }

    private static func syncActivity(state: HeroActivityAttributes.ContentState?, staleDate: Date?) async {
        let running = ActivityKit.Activity<HeroActivityAttributes>.activities
        guard let state else {
            for activity in running { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let content = ActivityContent(state: state, staleDate: staleDate)
        if let activity = running.first {
            await activity.update(content)
            for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? ActivityKit.Activity<HeroActivityAttributes>.request(
                attributes: HeroActivityAttributes(), content: content, pushType: nil)
        }
    }
}
