import Foundation

// MARK: - Cimetière

/// La tombe d'un héros de la lignée : ce qu'il était, jusqu'où il est allé, comment il est mort.
struct Grave: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var heroClass: HeroClass
    var level: Int
    /// Rang dans la lignée : 1 pour le premier héros.
    var generation: Int
    /// « est tombé dans la Crypte des os », « est mort de soif »…
    var fate: String
    var date: Date
    /// Jours vécus, quand on connaît sa date de départ.
    var days: Int?
    var traits: [Trait]
    var relics: [Relic]
    /// Donjon le plus lointain terminé, et son meilleur rang.
    var dungeon: Int?
    var rank: Int?
    /// Combats gagnés de son vivant.
    var fights: Int
    var companion: CompanionKind?
    /// Ce qu'il a laissé à son successeur, une fois choisi.
    var legacy: String?

    /// « Niveau 12 · Crypte des os, rang 3 ».
    var summary: String {
        var parts = ["Niveau \(level)"]
        if let dungeon, Dungeon.all.indices.contains(dungeon) {
            parts.append("\(Dungeon.all[dungeon].name), rang \(rank ?? 1)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Ce qu'un héros mort peut laisser à son successeur : un seul legs, au choix du joueur.
enum Legacy: Hashable, Identifiable {
    /// Une part de plus de sa bourse.
    case purse(Double)
    case relic(Relic)
    case trait(Trait)

    var id: String {
        switch self {
        case .purse: "purse"
        case .relic(let relic): "relic.\(relic.rawValue)"
        case .trait(let trait): "trait.\(trait.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .purse: "Sa bourse"
        case .relic(let relic): relic.name
        case .trait(let trait): "Son caractère : \(trait.name)"
        }
    }

    var detail: String {
        switch self {
        case .purse(let gold): "+\(gold.short) or pour bien démarrer"
        case .relic(let relic): [relic.boon, relic.bane].compactMap { $0 }.joined(separator: " · ")
        case .trait(let trait): trait.effect
        }
    }

    var symbol: String {
        switch self {
        case .purse: "dollarsign.circle.fill"
        case .relic(let relic): relic.symbol
        case .trait(let trait): trait.symbol
        }
    }
}

/// Le legs en attente : ce que le dernier héros tombé peut transmettre.
struct PendingLegacy: Codable, Equatable {
    var grave: UUID
    var purse: Double
    var relics: [Relic]
    var traits: [Trait]

    var options: [Legacy] {
        relics.map(Legacy.relic) + traits.map(Legacy.trait) + (purse >= 1 ? [.purse(purse)] : [])
    }
}
