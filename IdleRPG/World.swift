import SwiftUI

// MARK: - Lieux

/// Le camp est au centre : tout trajet passe par lui.
enum Place: Codable, Equatable {
    case camp
    case shop
    case tavern
    case dungeon(Int)

    /// Temps de marche depuis le camp, en secondes.
    var distance: TimeInterval {
        switch self {
        case .camp: 0
        case .shop: 45
        case .tavern: 50
        case .dungeon(let index): Dungeon.all[index].travel
        }
    }

    var name: String {
        switch self {
        case .camp: "le camp"
        case .shop: "la boutique"
        case .tavern: "la taverne"
        case .dungeon(let index): Dungeon.all[index].name
        }
    }
}

/// Ambiance visuelle d'un donjon.
enum DungeonStyle {
    case cave, forest, crypt, ice, volcano
}

struct Dungeon: Identifiable {
    let id: Int
    let name: String
    let style: DungeonStyle
    /// Trajet depuis le camp et durée d'exploration, en secondes.
    let travel: TimeInterval
    let duration: TimeInterval
    let rooms: Int
    let monsterHP: Double
    let monsterDamage: Double
    /// Or et expérience par monstre ordinaire.
    let gold: Double
    let xp: Double
    /// Énergie dépensée pour une exploration complète. Il faut l'avoir en entier pour partir.
    let energyCost: Double
    let monsters: [(sprite: String, name: String)]
    let boss: (sprite: String, name: String)

    var tier: Int { id + 1 }
    var roomDuration: TimeInterval { duration / Double(rooms) }
    var roomEnergy: Double { energyCost / Double(rooms) }

    /// Chaque donjon se joue à plusieurs rangs. Terminer un rang débloque le suivant ;
    /// le Volcan, dernier donjon, n'a pas de limite.
    var maxRank: Int { id == Dungeon.all.count - 1 ? 999 : 5 }
    /// Rang à atteindre ici pour ouvrir le donjon suivant : il faut maîtriser chaque donjon.
    static let unlockRank = 5

    /// Les monstres, l'or et l'expérience gagnent 35 % par rang.
    static func rankScale(_ rank: Int) -> Double { pow(1.35, Double(max(rank, 1) - 1)) }

    /// Rythme réel : trajets et explorations durent 8,5 fois les valeurs de base (le Volcan, 17 h).
    /// Réglé avec `Outils/equilibrage.py` pour qu'un joueur régulier finisse le jeu en deux mois environ
    /// (8,5 plutôt que 8 depuis que les salles de coffre sont plus courtes).
    static let pace: TimeInterval = 8.5

    static let all: [Dungeon] = [
        Dungeon(id: 0, name: "Cave aux rats", style: .cave,
                travel: 20 * pace, duration: 2 * 60 * pace, rooms: 6,
                monsterHP: 24, monsterDamage: 3, gold: 5, xp: 6, energyCost: 6,
                monsters: [("m_rat", "Rat géant"), ("m_bat", "Chauve-souris"), ("m_spider", "Araignée"),
                           ("m_slime_green", "Gelée verte")],
                boss: ("b_golem", "Golem de pierre")),
        Dungeon(id: 1, name: "Bois hanté", style: .forest,
                travel: 60 * pace, duration: 10 * 60 * pace, rooms: 10,
                monsterHP: 70, monsterDamage: 7, gold: 15, xp: 16, energyCost: 15,
                monsters: [("m_werewolf", "Loup-garou"), ("m_ghost", "Spectre"), ("m_plant", "Plante carnivore"),
                           ("m_goblin", "Gobelin")],
                boss: ("b_lich", "Liche")),
        Dungeon(id: 2, name: "Crypte des os", style: .crypt,
                travel: 3 * 60 * pace, duration: 30 * 60 * pace, rooms: 16,
                monsterHP: 200, monsterDamage: 14, gold: 45, xp: 45, energyCost: 30,
                monsters: [("m_skeleton", "Squelette"), ("m_skeleton_archer", "Squelette archer"),
                           ("m_scorpion", "Scorpion"), ("m_spider_brown", "Araignée des sables")],
                boss: ("b_minotaur", "Minotaure")),
        Dungeon(id: 3, name: "Glacier du Kraken", style: .ice,
                travel: 6 * 60 * pace, duration: 60 * 60 * pace, rooms: 24,
                monsterHP: 600, monsterDamage: 28, gold: 140, xp: 120, energyCost: 55,
                monsters: [("m_gargoyle", "Gargouille"), ("m_golem_gray", "Golem de givre"),
                           ("m_slime_blue", "Gelée glacée"), ("m_ghost", "Spectre")],
                boss: ("b_kraken", "Kraken")),
        Dungeon(id: 4, name: "Volcan du dragon", style: .volcano,
                travel: 10 * 60 * pace, duration: 2 * 60 * 60 * pace, rooms: 36,
                monsterHP: 1800, monsterDamage: 55, gold: 420, xp: 320, energyCost: 90,
                monsters: [("m_imp", "Diablotin"), ("m_fire_imp", "Lutin de feu"), ("m_orc", "Orc"),
                           ("m_slime_red", "Gelée de lave")],
                boss: ("b_dragon", "Dragon")),
    ]
}

// MARK: - Classes de héros

enum HeroClass: String, Codable, CaseIterable, Identifiable {
    case warrior, archer, mage

    var id: String { rawValue }

    /// Avec l'article, élidé devant une voyelle : « le Guerrier », « l'Archer ».
    var theName: String { self == .archer ? "l'\(name)" : "le \(name)" }

    var name: String {
        switch self {
        case .warrior: "Guerrier"
        case .archer: "Archer"
        case .mage: "Mage"
        }
    }

    var motto: String {
        switch self {
        case .warrior: "Encaisse les coups"
        case .archer: "Rapide et chanceux"
        case .mage: "Frappe très fort"
        }
    }

    var perks: [String] {
        switch self {
        case .warrior: ["+30\u{00A0}% de PV"]
        case .archer: ["+25\u{00A0}% de vitesse", "+25\u{00A0}% de chance au butin"]
        case .mage: ["+25\u{00A0}% d'attaque", "-10\u{00A0}% de PV"]
        }
    }

    var hpFactor: Double {
        switch self {
        case .warrior: 1.3
        case .archer: 1
        case .mage: 0.9
        }
    }

    var attackFactor: Double { self == .mage ? 1.25 : 1 }
    /// Fractions ajoutées aux bonus d'équipement.
    var speedBonus: Double { self == .archer ? 0.25 : 0 }
    var luckBonus: Double { self == .archer ? 0.25 : 0 }

    var weaponName: String {
        switch self {
        case .warrior: "Épée"
        case .archer: "Arc"
        case .mage: "Bâton"
        }
    }

    /// Noms des images d'une animation : idle, walk, attack, special, hurt, flee, rest, sleep ou tavern.
    /// Sprites pixel art animés avec PixelLab, installés par `Art/import_pixellab.py`.
    /// `rest` : 4 images calmes puis 4 où il s'occupe (aiguise sa lame, taille des flèches, lit).
    func frames(_ animation: String) -> [String] {
        let count: Int
        switch animation {
        case "hurt": count = 1
        case "attack": count = 6
        case "special": count = 10
        case "walk", "flee", "rest", "tavern": count = 8
        default: count = 4
        }
        return (1...count).map { "hero_\(rawValue)_\(animation)_\($0)" }
    }

    /// Nom proposé tant que le joueur n'a pas baptisé son héros.
    var defaultName: String {
        switch self {
        case .warrior: "Bjorn"
        case .archer: "Elwyn"
        case .mage: "Merlin"
        }
    }

    /// Image qui représente la classe dans les menus et l'activité en direct.
    var portrait: String { "hero_\(rawValue)_portrait" }
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
    /// Rang choisi pour le donjon visé. Absent des anciennes sauvegardes.
    var rank: Int?
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
    /// Provision trouvée dans la salle : fruits, tisane, herbes...
    var provision: Provision?
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
    /// Rang du donjon. Absent des anciennes sauvegardes.
    var rank: Int?
    /// Objets trouvés pendant la sortie. Ils ne sont à l'abri qu'une fois sortis du donjon :
    /// en cas de fuite, ils sont perdus.
    var loot: [Item]?
    /// Bénédictions choisies aux carrefours, valables jusqu'à la fin de la sortie.
    var blessings: [Blessing]?
    /// Carrefour en cours : trois bénédictions au choix pendant la salle, et le choix du joueur.
    var fork: [Blessing]?
    var forkChoice: Int?
    /// Nature imposée à la prochaine salle par une bénédiction.
    var forcedKind: RoomKind?

    var level: Int { rank ?? 1 }
    func has(_ blessing: Blessing) -> Bool { blessings?.contains(blessing) ?? false }
}

// MARK: - Carrefours

/// Une bénédiction, choisie à un carrefour du donjon pour le reste de la sortie.
enum Blessing: String, Codable, CaseIterable, Identifiable {
    case sharp, stone, fortune, secondWind, treasure, sanctuary

    static let sharpBonus = 1.12
    static let stoneFactor = 0.88
    static let fortuneBonus = 1.3
    static let secondWindHeal = 0.25

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sharp: "Lame affûtée"
        case .stone: "Peau de pierre"
        case .fortune: "Fortune"
        case .secondWind: "Second souffle"
        case .treasure: "Piste du trésor"
        case .sanctuary: "Halte sacrée"
        }
    }

    var detail: String {
        switch self {
        case .sharp: "+12\u{00A0}% d'attaque jusqu'à la sortie"
        case .stone: "-12\u{00A0}% de dégâts reçus jusqu'à la sortie"
        case .fortune: "+30\u{00A0}% d'or jusqu'à la sortie"
        case .secondWind: "Rend 25\u{00A0}% des PV tout de suite"
        case .treasure: "La prochaine salle est un coffre"
        case .sanctuary: "La prochaine salle est un sanctuaire"
        }
    }

    var symbol: String {
        switch self {
        case .sharp: "bolt.fill"
        case .stone: "shield.fill"
        case .fortune: "dollarsign.circle.fill"
        case .secondWind: "heart.fill"
        case .treasure: "shippingbox.fill"
        case .sanctuary: "sparkles"
        }
    }
}

// MARK: - Caractère du héros

/// Traits gagnés au fil des aventures. Ils donnent un petit bonus et guident les choix
/// du héros quand le joueur n'est pas là pour décider.
enum Trait: String, CaseIterable, Identifiable {
    case brave, careful, glutton, lovable

    var id: String { rawValue }

    var name: String {
        switch self {
        case .brave: "Téméraire"
        case .careful: "Prudent"
        case .glutton: "Gourmand"
        case .lovable: "Attachant"
        }
    }

    var detail: String {
        switch self {
        case .brave: "5 boss vaincus : +3\u{00A0}% d'attaque"
        case .careful: "3 fuites : se replie plus tôt, à 35\u{00A0}% des PV"
        case .glutton: "10 repas : les rations nourrissent 50\u{00A0}% de plus"
        case .lovable: "15 encouragements : le moral baisse deux fois moins vite"
        }
    }

    var symbol: String {
        switch self {
        case .brave: "flame.fill"
        case .careful: "eye.fill"
        case .glutton: "fork.knife"
        case .lovable: "heart.circle.fill"
        }
    }
}

enum Activity: Codable {
    case resting
    case shopping
    case traveling(Trip)
    case exploring(Run)
    case roaming(Roam)
    case tavern(TavernVisit)
}

// MARK: - Taverne

/// Une soirée à la taverne : ce que le héros a déjà commandé.
struct TavernVisit: Codable {
    var start: TimeInterval
    var drinks = 0
    var sang = false
}

/// Ce qu'on peut offrir au héros à la taverne.
enum TavernOrder: String, CaseIterable, Identifiable {
    case ale, stew, bard

    var id: String { rawValue }

    /// Plus de trois chopes et le tavernier refuse de le resservir.
    static let maxDrinks = 3
    /// Le moral monte tout seul au coin de l'âtre, par heure.
    static let moodPerHour = 12.0

    var name: String {
        switch self {
        case .ale: "Chope de cervoise"
        case .stew: "Ragoût du jour"
        case .bard: "Chanson du barde"
        }
    }

    var detail: String {
        switch self {
        case .ale: "+20 moral, +30 d'hydratation"
        case .stew: "+45 satiété, +10 d'hydratation"
        case .bard: "+10 moral, une fois par soirée"
        }
    }

    var symbol: String {
        switch self {
        case .ale: "mug.fill"
        case .stew: "fork.knife"
        case .bard: "music.note"
        }
    }

    /// Prix de base, multiplié par le niveau des boutiques. Réglés avec `Outils/equilibrage.py` :
    /// la taverne doit coûter assez pour rester un choix, sans valoir mieux que les soins gratuits.
    var basePrice: Double {
        switch self {
        case .ale: 30
        case .stew: 40
        case .bard: 5
        }
    }
}

// MARK: - Provisions

/// Ce que le héros mange, boit ou utilise au camp pour aller mieux.
/// On en trouve en donjon et en itinérance ; la ration s'achète aussi chez le marchand.
enum Provision: String, Codable, CaseIterable, Identifiable {
    case fruit, ration, tea, herbs, water

    var id: String { rawValue }

    var name: String {
        switch self {
        case .water: "Gourde d'eau"
        case .fruit: "Fruits des bois"
        case .ration: "Ration"
        case .tea: "Tisane"
        case .herbs: "Herbes médicinales"
        }
    }

    /// Nom en minuscules, accordé au nombre : "2 tisanes", "1 ration".
    func label(_ count: Int) -> String {
        switch self {
        case .fruit: "fruits des bois"
        case .ration: count > 1 ? "rations" : "ration"
        case .tea: count > 1 ? "tisanes" : "tisane"
        case .herbs: "herbes médicinales"
        case .water: count > 1 ? "gourdes d'eau" : "gourde d'eau"
        }
    }

    var verb: String {
        switch self {
        case .fruit, .ration: "Manger"
        case .tea, .water: "Boire"
        case .herbs: "Soigner"
        }
    }

    var detail: String {
        switch self {
        case .fruit: "+15 de satiété, +10 d'hydratation"
        case .ration: "+40 de satiété, +10 d'énergie"
        case .tea: "+15 de moral, +20 d'énergie, +25 d'hydratation"
        case .water: "+50 d'hydratation"
        case .herbs: "Guérit les blessures, +25\u{00A0}% de PV"
        }
    }

    var symbol: String {
        switch self {
        case .fruit: "leaf.fill"
        case .ration: "fork.knife"
        case .tea: "cup.and.saucer.fill"
        case .herbs: "cross.case.fill"
        case .water: "drop.fill"
        }
    }
}

/// Itinérance : le héros se promène dans les champs et les villages, sans danger,
/// et ramasse des provisions et quelques pièces. Une trouvaille toutes les 5 minutes.
struct Roam: Codable {
    var start: TimeInterval
    var end: TimeInterval
    var nextFind: TimeInterval
    /// Trouvailles de la balade, par nom de provision (et "or").
    var found: [String: Double]

    static let findEvery: TimeInterval = 300
    static let durations: [TimeInterval] = [1_800, 3_600, 7_200]
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
    case potion, ration, water, scroll, bedroll

    var id: String { rawValue }

    var name: String {
        switch self {
        case .potion: "Potion de soin"
        case .ration: "Ration"
        case .water: "Gourde d'eau"
        case .scroll: "Parchemin de force"
        case .bedroll: "Sac de couchage"
        }
    }

    var detail: String {
        switch self {
        case .potion: "Bue seule en donjon quand le héros flanche : rend 40\u{00A0}% des PV"
        case .ration: "À donner au camp : +40 de satiété et +10 d'énergie"
        case .water: "À donner au camp : +50 d'hydratation. Sans eau, le héros dépérit"
        case .scroll: "+25\u{00A0}% d'attaque au prochain donjon"
        case .bedroll: "Repos 50\u{00A0}% plus rapide, pour toujours"
        }
    }

    /// La gourde n'a pas encore d'image : un symbole en attendant.
    var sprite: String { self == .water ? "drop.fill" : "s_\(rawValue)" }

    var basePrice: Double {
        switch self {
        case .potion: 30
        case .ration: 20
        case .water: 10
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
        case .deadly: "Très dangereux"
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
