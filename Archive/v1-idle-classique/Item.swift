import SwiftUI
import UIKit

// MARK: - Emplacements

/// Chaque emplacement renforce une seule statistique du héros.
enum ItemSlot: String, Codable, CaseIterable, Identifiable {
    case weapon, ring, amulet, boots

    var id: String { rawValue }

    var name: String {
        switch self {
        case .weapon: "Arme"
        case .ring: "Anneau"
        case .amulet: "Amulette"
        case .boots: "Bottes"
        }
    }

    var statLabel: String {
        switch self {
        case .weapon: "dégâts"
        case .ring: "critique"
        case .amulet: "or"
        case .boots: "vitesse"
        }
    }

    var placeholderIcon: String {
        switch self {
        case .weapon: "wand.and.stars"
        case .ring: "circle.circle"
        case .amulet: "seal"
        case .boots: "shoe.fill"
        }
    }

    /// Apparences possibles : (nom de l'image, nom de base).
    var bases: [(String, String)] {
        switch self {
        case .weapon: [("item_wand", "Baguette"), ("item_orb", "Orbe"), ("item_grimoire", "Grimoire")]
        case .ring: [("item_ring", "Anneau"), ("item_gem", "Gemme")]
        case .amulet: [("item_amulet", "Amulette"), ("item_talisman", "Talisman")]
        case .boots: [("item_boots", "Bottes"), ("item_ankleboots", "Bottines")]
        }
    }

    /// Bonus de base en pourcentage pour un objet commun trouvé dans une zone donnée.
    func baseBonus(stage: Int) -> Double {
        let s = Double(stage)
        switch self {
        case .weapon: return 15 + 5 * s
        case .amulet: return 10 + 4 * s
        case .boots: return 4 + 0.4 * s
        case .ring: return 2 + 0.25 * s
        }
    }

    /// Plafond du bonus, pour les statistiques qui ne doivent pas s'emballer.
    var bonusCap: Double? {
        switch self {
        case .boots: 100
        case .ring: 35
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
        case .common: "d'apprenti"
        case .rare: "de mage"
        case .epic: "d'archimage"
        case .legendary: "des anciens dieux"
        }
    }

    var multiplier: Double {
        switch self {
        case .common: 1
        case .rare: 1.8
        case .epic: 3
        case .legendary: 5
        }
    }

    var sellFactor: Double {
        switch self {
        case .common: 3
        case .rare: 8
        case .epic: 20
        case .legendary: 60
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

    /// Tirage pondéré. Les boss donnent au minimum du rare.
    static func roll(boss: Bool) -> Rarity {
        let weights: [(Rarity, Double)] = boss
            ? [(.rare, 55), (.epic, 35), (.legendary, 10)]
            : [(.common, 60), (.rare, 28), (.epic, 10), (.legendary, 2)]
        var pick = Double.random(in: 0..<weights.reduce(0) { $0 + $1.1 })
        for (rarity, weight) in weights {
            if pick < weight { return rarity }
            pick -= weight
        }
        return weights[0].0
    }
}

// MARK: - Objet

struct Item: Identifiable, Equatable {
    let id: UUID
    let slot: ItemSlot
    let rarity: Rarity
    /// Nom de l'image dans le catalogue d'assets.
    let sprite: String
    let name: String
    /// Bonus en pourcentage (points de pourcentage pour le critique).
    let bonus: Double
    /// Zone où l'objet a été trouvé.
    let stage: Int
    let sellValue: Double

    var shortBonus: String { "+\(Int(bonus)) %" }
    var bonusText: String { "+\(Int(bonus)) % \(slot.statLabel)" }

    static func random(stage: Int, boss: Bool) -> Item {
        let slot = ItemSlot.allCases.randomElement() ?? .weapon
        let rarity = Rarity.roll(boss: boss)
        let (sprite, baseName) = slot.bases.randomElement() ?? slot.bases[0]
        var bonus = slot.baseBonus(stage: stage) * rarity.multiplier * Double.random(in: 0.85...1.15)
        if let cap = slot.bonusCap { bonus = min(bonus, cap) }
        let value = GameState.monsterHP(stage: stage, boss: false) * 0.35 * rarity.sellFactor
        return Item(
            id: UUID(),
            slot: slot,
            rarity: rarity,
            sprite: sprite,
            name: "\(baseName) \(rarity.suffix)",
            bonus: max(bonus.rounded(), 1),
            stage: stage,
            sellValue: value.rounded(.up)
        )
    }
}

extension Item: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, slot, rarity, sprite, emoji, name, bonus, stage, sellValue
    }

    /// Les sauvegardes d'avant les images stockaient un emoji.
    private static let legacySprites: [String: String] = [
        "🪄": "item_wand", "🔮": "item_orb", "📖": "item_grimoire",
        "💍": "item_ring", "💎": "item_gem",
        "📿": "item_amulet", "🧿": "item_talisman",
        "👢": "item_boots", "🥾": "item_ankleboots",
    ]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        slot = try c.decode(ItemSlot.self, forKey: .slot)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        if let stored = try c.decodeIfPresent(String.self, forKey: .sprite) {
            sprite = stored
        } else {
            let emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
            sprite = Self.legacySprites[emoji] ?? slot.bases[0].0
        }
        name = try c.decode(String.self, forKey: .name)
        bonus = try c.decode(Double.self, forKey: .bonus)
        stage = try c.decode(Int.self, forKey: .stage)
        sellValue = try c.decode(Double.self, forKey: .sellValue)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(slot, forKey: .slot)
        try c.encode(rarity, forKey: .rarity)
        try c.encode(sprite, forKey: .sprite)
        try c.encode(name, forKey: .name)
        try c.encode(bonus, forKey: .bonus)
        try c.encode(stage, forKey: .stage)
        try c.encode(sellValue, forKey: .sellValue)
    }
}

enum LootOutcome {
    /// L'emplacement était vide : l'objet est équipé d'office.
    case equipped
    /// L'objet est rangé dans le sac.
    case stored
    /// Le sac était plein : l'objet est vendu d'office.
    case sold
}
