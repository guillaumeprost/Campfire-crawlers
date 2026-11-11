import Foundation

/// Ce que les widgets montrent du héros, écrit par le jeu dans le groupe d'apps partagé.
///
/// Comme pour l'activité en direct, le jeu ne peut pas réveiller les widgets une fois fermé :
/// il rejoue donc la suite sur une copie de lui-même et écrit d'avance une image du héros
/// toutes les dix minutes. Chaque widget affiche celle de l'heure qu'il est.
struct HeroWidgetData: Codable, Hashable {
    /// Le héros à un instant donné.
    struct Frame: Codable, Hashable {
        var date: Date
        var name: String
        var portrait: String
        var level: Int
        var gold: Double
        /// Lieu en un mot : « Camp », « Grotte », « En route ».
        var place: String
        var title: String
        var detail: String
        /// Petite image du lieu : feu de camp, boss du donjon, enseigne.
        var sprite: String
        /// Vignette du lieu, en fond.
        var scene: String
        /// Barre qui se remplit seule entre deux dates, et compte à rebours jusqu'à la fin.
        var start: Date?
        var end: Date?
        /// Parts de 0 à 1.
        var hp: Double
        var energy: Double
        var hunger: Double
        var thirst: Double
        var mood: Double
        /// Ce qui demande le joueur : « Assoiffé », « Dépérit », « Carrefour ».
        var alert: String?
        var dead: Bool
        /// Animation du héros : idle, walk, attack, rest ou flee. Absente des anciennes données.
        var pose: String?

        /// Classe du héros, tirée du nom de son portrait : warrior, archer ou mage.
        var heroClass: String {
            let parts = portrait.split(separator: "_")
            return parts.count > 1 ? String(parts[1]) : "mage"
        }

        /// Police qui dessine l'animation du héros, image par image (voir `Outils/polices_widget.py`).
        var animationFont: String? {
            guard !dead, let pose else { return nil }
            return "CC\(heroClass.capitalized)\(pose.capitalized)"
        }
    }

    /// Un moment à venir, repris des notifications prévues.
    struct Upcoming: Codable, Hashable {
        var date: Date
        var title: String
        var symbol: String
    }

    var frames: [Frame]
    var upcoming: [Upcoming]

    static let group = "group.com.guillaumeprost.campfirecrawlers"
    private static let key = "heroWidgetData"

    static func load() -> HeroWidgetData? {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HeroWidgetData.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(data, forKey: Self.key)
    }

    /// L'image du héros à l'heure dite : la dernière déjà commencée.
    func frame(at date: Date) -> Frame? {
        frames.last { $0.date <= date } ?? frames.first
    }

    /// Exemple pour la galerie de widgets.
    static let sample: HeroWidgetData = {
        let now = Date()
        let frame = Frame(date: now, name: "Elwyn", portrait: "hero_archer_portrait", level: 4, gold: 1_840,
                          place: "Cave aux rats", title: "Cave aux rats · salle 3/8", detail: "Rang 2 · Combat : Chauve-souris",
                          sprite: "monster_bat", scene: "lw_cave",
                          start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(5_400),
                          hp: 0.72, energy: 0.6, hunger: 0.55, thirst: 0.4, mood: 0.8, alert: nil, dead: false, pose: "attack")
        return HeroWidgetData(frames: [frame], upcoming: [
            Upcoming(date: now.addingTimeInterval(5_400), title: "Retour au camp", symbol: "flame.fill"),
            Upcoming(date: now.addingTimeInterval(9_000), title: "A soif", symbol: "drop.fill"),
        ])
    }()
}
