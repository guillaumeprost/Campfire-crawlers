import SwiftUI

// MARK: - Lieux

/// Le camp est au centre : tout trajet passe par lui.
enum Place: Codable, Equatable {
    case camp
    case shop
    case dungeon(Int)

    /// Temps de marche depuis le camp, en secondes.
    var distance: TimeInterval {
        switch self {
        case .camp: 0
        case .shop: 45
        case .dungeon(let index): Dungeon.all[index].travel
        }
    }

    var name: String {
        switch self {
        case .camp: "le camp"
        case .shop: "la boutique"
        case .dungeon(let index): Dungeon.all[index].name
        }
    }
}

struct Dungeon: Identifiable {
    let id: Int
    let name: String
    let background: String
    /// Trajet depuis le camp et durée d'exploration, en secondes.
    let travel: TimeInterval
    let duration: TimeInterval
    let rooms: Int
    let monsterHP: Double
    let monsterDamage: Double
    /// Or et expérience par monstre ordinaire.
    let gold: Double
    let xp: Double
    /// Énergie dépensée pour une exploration complète.
    let energyCost: Double
    let monsters: [(sprite: String, name: String)]
    let boss: (sprite: String, name: String)

    var tier: Int { id + 1 }
    var roomDuration: TimeInterval { duration / Double(rooms) }
    var roomEnergy: Double { energyCost / Double(rooms) }

    static let all: [Dungeon] = [
        Dungeon(id: 0, name: "Cave aux rats", background: "bg_cave",
                travel: 20, duration: 2 * 60, rooms: 6,
                monsterHP: 24, monsterDamage: 3, gold: 5, xp: 6, energyCost: 30,
                monsters: [("monster_rat", "Rat géant"), ("monster_bat", "Chauve-souris"), ("monster_spider", "Araignée")],
                boss: ("boss_scorpion", "Scorpion royal")),
        Dungeon(id: 1, name: "Bois hanté", background: "bg_forest",
                travel: 60, duration: 10 * 60, rooms: 10,
                monsterHP: 70, monsterDamage: 7, gold: 15, xp: 16, energyCost: 45,
                monsters: [("monster_wolf", "Loup"), ("monster_snake", "Vipère"), ("monster_ghost", "Spectre")],
                boss: ("boss_vampire", "Vampire")),
        Dungeon(id: 2, name: "Désert des os", background: "bg_desert",
                travel: 3 * 60, duration: 30 * 60, rooms: 16,
                monsterHP: 200, monsterDamage: 14, gold: 45, xp: 45, energyCost: 60,
                monsters: [("monster_snake", "Vipère"), ("monster_skeleton", "Squelette"), ("monster_zombie", "Zombie")],
                boss: ("boss_demon", "Démon")),
        Dungeon(id: 3, name: "Glacier du Kraken", background: "bg_ice",
                travel: 6 * 60, duration: 60 * 60, rooms: 24,
                monsterHP: 600, monsterDamage: 28, gold: 140, xp: 120, energyCost: 75,
                monsters: [("monster_wolf", "Loup"), ("monster_ghost", "Spectre"), ("monster_troll", "Troll")],
                boss: ("boss_kraken", "Kraken")),
        Dungeon(id: 4, name: "Volcan du dragon", background: "bg_volcano",
                travel: 10 * 60, duration: 2 * 60 * 60, rooms: 36,
                monsterHP: 1800, monsterDamage: 55, gold: 420, xp: 320, energyCost: 90,
                monsters: [("monster_ogre", "Ogre"), ("monster_troll", "Troll"), ("monster_skeleton", "Squelette")],
                boss: ("boss_dragon", "Dragon")),
    ]
}

// MARK: - Activité du héros

enum TripReason: String, Codable {
    case normal, victory, fled, exhausted, recalled
}

/// Un trajet. Les heures sont celles de l'horloge du jeu.
struct Trip: Codable {
    var from: Place
    var to: Place
    var start: TimeInterval
    var end: TimeInterval
    var reason: TripReason
}

enum RoomKind: String, Codable {
    case monster, boss, chest, trap, fountain
}

/// Une salle de donjon. Son issue est tirée à l'entrée, puis appliquée à la sortie.
struct Room: Codable {
    var kind: RoomKind
    var sprite: String
    var name: String
    /// Variation de PV : négative pour des dégâts, positive pour un soin.
    var hpDelta: Double
    var gold: Double
    var xp: Double
    var item: Item?
    /// Le héros n'y survivrait pas : il fuit, gravement blessé.
    var knockedOut: Bool
    /// Une potion est bue en plein combat pour tenir jusqu'au bout.
    var usesPotion: Bool?
}

struct Run: Codable {
    var dungeon: Int
    var roomIndex: Int
    var roomStart: TimeInterval
    var roomEnd: TimeInterval
    var room: Room
    var gold: Double
    var items: Int
    /// Parchemin de force actif pour cette exploration.
    var boosted: Bool
}

enum Activity: Codable {
    case resting
    case shopping
    case traveling(Trip)
    case exploring(Run)
}

// MARK: - Journal

struct JournalEntry: Codable, Identifiable {
    enum Tone: String, Codable { case good, bad, neutral }
    var id = UUID()
    var icon: String
    var text: String
    var tone: Tone
}

struct AwayReport: Identifiable {
    let id = UUID()
    let seconds: TimeInterval
    let gold: Double
    let items: Int
    let levels: Int
    let lines: [JournalEntry]
}

// MARK: - Boutique

enum Supply: String, CaseIterable, Identifiable {
    case potion, ration, scroll, bedroll

    var id: String { rawValue }

    var name: String {
        switch self {
        case .potion: "Potion de soin"
        case .ration: "Ration"
        case .scroll: "Parchemin de force"
        case .bedroll: "Sac de couchage"
        }
    }

    var detail: String {
        switch self {
        case .potion: "Bue seule en donjon quand le héros flanche : rend 40\u{00A0}% des PV"
        case .ration: "Rend 50 d'énergie tout de suite"
        case .scroll: "+25\u{00A0}% d'attaque au prochain donjon"
        case .bedroll: "Repos 50\u{00A0}% plus rapide, pour toujours"
        }
    }

    var sprite: String { "icon_\(rawValue)" }

    var basePrice: Double {
        switch self {
        case .potion: 30
        case .ration: 20
        case .scroll: 60
        case .bedroll: 400
        }
    }
}

// MARK: - Risque d'un donjon

enum Risk {
    case easy, fair, risky, deadly

    var label: String {
        switch self {
        case .easy: "Facile"
        case .fair: "Équilibré"
        case .risky: "Risqué"
        case .deadly: "Trop dangereux"
        }
    }

    var color: Color {
        switch self {
        case .easy: .green
        case .fair: .yellow
        case .risky: .orange
        case .deadly: .red
        }
    }
}

/// Ce que le héros est en train de faire, prêt à afficher.
struct ActivityInfo {
    var title: String
    var detail: String
    var progress: Double?
    /// Secondes réelles restantes.
    var eta: TimeInterval?
}
