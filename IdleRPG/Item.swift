import SwiftUI
import UIKit

// MARK: - Emplacements

/// Chaque emplacement renforce une seule caractéristique du héros.
enum ItemSlot: String, Codable, CaseIterable, Identifiable {
    case weapon, helmet, armor, amulet, ring, boots

    var id: String { rawValue }

    var name: String {
        switch self {
        case .weapon: "Arme"
        case .helmet: "Casque"
        case .armor: "Armure"
        case .amulet: "Amulette"
        case .ring: "Anneau"
        case .boots: "Bottes"
        }
    }

    var statLabel: String {
        switch self {
        case .weapon: "attaque"
        case .helmet: "fuite"
        case .armor: "défense"
        case .amulet: "PV max"
        case .ring: "chance"
        case .boots: "vitesse"
        }
    }

    /// L'arme et l'amulette donnent des points, les autres un pourcentage.
    var isPercent: Bool { self != .weapon && self != .amulet }

    /// Casque, armure et arme sont propres à une classe : un mage ne porte ni grosse
    /// plaque ni arc. Bottes, amulette et anneau conviennent à tout le monde.
    var isClassBound: Bool {
        switch self {
        case .weapon, .armor, .helmet: true
        case .amulet, .ring, .boots: false
        }
    }

    var placeholderIcon: String {
        switch self {
        case .weapon: "wand.and.stars"
        case .helmet: "crown"
        case .armor: "tshirt"
        case .amulet: "seal"
        case .ring: "circle.circle"
        case .boots: "shoe.fill"
        }
    }

    /// Apparences possibles : (nom de l'image, nom de base).
    var bases: [(String, String)] {
        switch self {
        case .weapon: [("item_wand", "Baguette"), ("item_orb", "Orbe"), ("item_grimoire", "Grimoire")]
        case .helmet: [("eq_helmet_0_1", "Casque")]
        case .armor: [("eq_armor_0_1", "Armure")]
        case .amulet: [("item_amulet", "Amulette"), ("item_talisman", "Talisman")]
        case .ring: [("item_ring", "Anneau"), ("item_gem", "Gemme")]
        case .boots: [("item_boots", "Bottes"), ("item_ankleboots", "Bottines")]
        }
    }

    /// Bonus d'un objet commun, par palier de donjon (1 à 5).
    func baseBonus(tier: Int) -> Double {
        let table: [Double]
        switch self {
        case .weapon: table = [4, 10, 28, 80, 230]
        // Armure : part des dégâts évitée. Casque : points de chance de fuite.
        // Réglés avec Outils/equilibrage.py : plus forts, ils raccourcissaient le jeu de trois semaines.
        case .armor: table = [2, 3, 4, 5, 6]
        case .helmet: table = [2, 2, 3, 3, 4]
        case .amulet: table = [25, 60, 140, 320, 750]
        case .ring: table = [8, 12, 16, 20, 25]
        case .boots: table = [5, 8, 11, 14, 17]
        }
        return table[min(max(tier, 1), table.count) - 1]
    }

    var bonusCap: Double? {
        switch self {
        case .boots: 60
        case .ring: 150
        case .armor: 30
        case .helmet: 15
        default: nil
        }
    }
}

// MARK: - Rareté

enum Rarity: Int, Codable, CaseIterable {
    case common, rare, epic, legendary

    var name: String {
        switch self {
        case .common: "Commun"
        case .rare: "Rare"
        case .epic: "Épique"
        case .legendary: "Légendaire"
        }
    }

    var suffix: String {
        switch self {
        case .common: "de novice"
        case .rare: "de vétéran"
        case .epic: "de champion"
        case .legendary: "de légende"
        }
    }

    var multiplier: Double {
        switch self {
        case .common: 1
        case .rare: 1.5
        case .epic: 2.2
        case .legendary: 3.5
        }
    }

    var sellFactor: Double {
        switch self {
        case .common: 4
        case .rare: 10
        case .epic: 25
        case .legendary: 70
        }
    }

    var uiColor: UIColor {
        switch self {
        case .common: UIColor(white: 0.72, alpha: 1)
        case .rare: UIColor(red: 0.30, green: 0.62, blue: 1.0, alpha: 1)
        case .epic: UIColor(red: 0.74, green: 0.42, blue: 1.0, alpha: 1)
        case .legendary: UIColor(red: 1.0, green: 0.62, blue: 0.12, alpha: 1)
        }
    }

    var color: Color { Color(uiColor) }

    /// Tirage pondéré. La chance du héros gonfle les raretés au-dessus de commun.
    static func roll<G: RandomNumberGenerator>(floor: Rarity, luck: Double, using rng: inout G) -> Rarity {
        let boost = 1 + luck
        let weights: [(Rarity, Double)] = [
            (.common, 60), (.rare, 28 * boost), (.epic, 10 * boost), (.legendary, 2 * boost),
        ].filter { $0.0.rawValue >= floor.rawValue }
        var pick = Double.random(in: 0..<weights.reduce(0) { $0 + $1.1 }, using: &rng)
        for (rarity, weight) in weights {
            if pick < weight { return rarity }
            pick -= weight
        }
        return floor
    }
}

// MARK: - Objet

struct Item: Codable, Identifiable, Equatable {
    let id: UUID
    let slot: ItemSlot
    let rarity: Rarity
    /// Nom de l'image dans le catalogue d'assets.
    let sprite: String
    let name: String
    /// Bonus de base : points (arme, amulette) ou pourcentage (anneau, bottes).
    let bonus: Double
    /// Palier du donjon d'origine, de 1 à 5.
    let tier: Int
    let sellValue: Double
    /// Rang du donjon d'origine et améliorations faites à la forge.
    /// Absents des anciennes sauvegardes.
    var rank: Int?
    var forge: Int?
    /// Classe à laquelle l'objet est réservé (arme, armure, casque) : un mage ne
    /// peut pas porter une plaque de guerrier ni un arc. nil = utilisable par tous
    /// (bottes, amulette, anneau) ou ancienne sauvegarde sans classe enregistrée.
    var heroClass: HeroClass?

    static let maxForge = 10
    var forgeLevel: Int { forge ?? 0 }

    /// Bonus réel : chaque passage à la forge ajoute 10 % du bonus de base.
    var power: Double {
        let value = (bonus * (1 + 0.1 * Double(forgeLevel))).rounded()
        if let cap = slot.bonusCap { return min(value, cap) }
        return value
    }

    /// Prix du prochain passage à la forge.
    var forgePrice: Double { (sellValue * 3 * pow(1.5, Double(forgeLevel))).rounded() }

    /// Nombre de dessins par rareté (commun, rare, épique, légendaire), d'après
    /// Art/import_equipements.py. Chaque rareté a son élément : acier, glace, ombre, feu.
    ///
    /// L'arme est déjà déclinée par classe (`weapon_<classe>`). Pour faire de même avec
    /// l'armure et le casque (plaque pour le guerrier, cuir pour l'archer, robe/chapeau
    /// pour le mage), il suffit d'ajouter l'art `eq_armor_<classe>_<rareté>_<variante>` /
    /// `eq_helmet_<classe>_…` puis les lignes `"armor_warrior": […]`, `"armor_archer"`,
    /// `"armor_mage"` (idem casque) ici : `image(for:)` bascule tout seul dessus. Tant
    /// que ces clés manquent, armure et casque gardent le dessin générique ci-dessous.
    private static let looks: [String: [Int]] = [
        "weapon_warrior": [3, 6, 6, 6],
        "weapon_archer": [4, 2, 4, 5],
        "weapon_mage": [3, 4, 5, 6],
        "armor": [2, 5, 2, 2],
        "helmet": [2, 2, 4, 2],
        "amulet": [2, 2, 2, 2],
        "ring": [1, 1, 1, 2],
        "boots": [1, 1, 1, 1],
    ]

    /// Image de l'objet. Les emplacements liés à une classe (arme, armure, casque)
    /// prennent l'apparence de celle du héros : épée/arc/bâton, plaque/cuir/robe…
    /// Tant que l'art par classe n'existe pas (clé absente de `looks`), on retombe
    /// sur le dessin générique de l'emplacement. Le dessin est tiré de l'identifiant
    /// de l'objet : il ne change jamais.
    func image(for hero: HeroClass) -> String {
        let cls = heroClass ?? hero
        let perClass = "\(slot.rawValue)_\(cls.rawValue)"
        let family = slot.isClassBound && Self.looks[perClass] != nil ? perClass : slot.rawValue
        let count = Self.looks[family]?[rarity.rawValue] ?? 1
        let variant = Int(id.uuid.1) % count + 1
        return "eq_\(family)_\(rarity.rawValue)_\(variant)"
    }

    /// Nom affiché, lui aussi fonction de la classe pour l'arme.
    func title(for hero: HeroClass) -> String {
        let base = slot == .weapon ? (heroClass ?? hero).weaponName : slot.name
        return "\(base) \(rarity.suffix)\(forgeLevel > 0 ? " +\(forgeLevel)" : "")"
    }

    var shortBonus: String { slot.isPercent ? "+\(Int(power))\u{00A0}%" : "+\(power.short)" }
    var bonusText: String { "\(shortBonus) \(slot.statLabel)" }

    /// Les objets gagnent 15 % par rang de donjon, moins que les monstres (30 %) :
    /// pour monter en rang, il faut aussi des niveaux et la forge.
    static func rankScale(_ rank: Int) -> Double { pow(1.15, Double(max(rank, 1) - 1)) }

    static func random<G: RandomNumberGenerator>(tier: Int, rank: Int = 1, floor: Rarity = .common, luck: Double = 0,
                                                 hero: HeroClass, using rng: inout G) -> Item {
        let slot = ItemSlot.allCases.randomElement(using: &rng) ?? .weapon
        let rarity = Rarity.roll(floor: floor, luck: luck, using: &rng)
        let (sprite, baseName) = slot.bases.randomElement(using: &rng) ?? slot.bases[0]
        var bonus = slot.baseBonus(tier: tier) * rarity.multiplier * Double.random(in: 0.85...1.15, using: &rng)
            * rankScale(rank)
        if let cap = slot.bonusCap { bonus = min(bonus, cap) }
        let value = Dungeon.all[min(max(tier, 1), Dungeon.all.count) - 1].gold * rarity.sellFactor * rankScale(rank)
        return Item(
            id: UUID(),
            slot: slot,
            rarity: rarity,
            sprite: sprite,
            name: "\(baseName) \(rarity.suffix)",
            bonus: max(bonus.rounded(), 1),
            tier: tier,
            sellValue: value.rounded(.up),
            rank: rank,
            forge: 0,
            heroClass: slot.isClassBound ? hero : nil
        )
    }
}

enum LootOutcome {
    /// L'emplacement était vide : l'objet est équipé d'office.
    case equipped
    /// L'objet est rangé dans le sac.
    case stored
    /// Trouvé en donjon : il reste dans la sacoche jusqu'à la sortie.
    case carried
    /// Le sac était plein : l'objet est vendu d'office.
    case sold
}
