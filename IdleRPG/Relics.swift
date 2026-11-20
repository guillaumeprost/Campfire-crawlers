import Foundation

// MARK: - Reliques

/// Une relique : un objet rare que le héros garde toute sa vie. Chacune donne un atout
/// et une contrepartie, pour que deux héros de la même classe ne se jouent pas pareil.
/// On en gagne une en battant pour la première fois le boss d'un donjon, parfois sur les
/// boss suivants, et chez le marchand ambulant qui passe au camp.
enum Relic: String, Codable, CaseIterable, Identifiable {
    case chalice, stormHeart, glassBlade, miserPurse, shell, rabbitFoot, hermitFlask, moonCharm, ember

    var id: String { rawValue }

    var name: String {
        switch self {
        case .chalice: "Calice de sang"
        case .stormHeart: "Cœur d'orage"
        case .glassBlade: "Éclat de verre"
        case .miserPurse: "Bourse de l'avare"
        case .shell: "Carapace ancienne"
        case .rabbitFoot: "Patte de lapin"
        case .hermitFlask: "Gourde de l'ermite"
        case .moonCharm: "Amulette de lune"
        case .ember: "Braise éternelle"
        }
    }

    /// L'atout.
    var boon: String {
        switch self {
        case .chalice: "Les sanctuaires soignent le double"
        case .stormHeart: "Coup spécial chargé en 2 victoires"
        case .glassBlade: "+20\u{00A0}% d'attaque"
        case .miserPurse: "+40\u{00A0}% d'or en donjon"
        case .shell: "-15\u{00A0}% de dégâts reçus"
        case .rabbitFoot: "+15\u{00A0}% de chances de fuite"
        case .hermitFlask: "Faim et soif 25\u{00A0}% plus lentes"
        case .moonCharm: "La nuit, +15\u{00A0}% d'attaque"
        case .ember: "Repos 30\u{00A0}% plus rapide, même sous la pluie"
        }
    }

    /// La contrepartie. La braise n'en a pas : c'est la relique de confort.
    var bane: String? {
        switch self {
        case .chalice: "Les pièges blessent 50\u{00A0}% de plus"
        case .stormHeart: "Chaque coup spécial coûte 8 de satiété"
        case .glassBlade: "-10\u{00A0}% de PV max"
        case .miserPurse: "Les potions ne rendent que 30\u{00A0}% des PV"
        case .shell: "-10\u{00A0}% de vitesse"
        case .rabbitFoot: "-5\u{00A0}% d'attaque"
        case .hermitFlask: "Le moral s'use 25\u{00A0}% plus vite"
        case .moonCharm: "Le jour, -5\u{00A0}% d'attaque"
        case .ember: nil
        }
    }

    var symbol: String {
        switch self {
        case .chalice: "wineglass.fill"
        case .stormHeart: "bolt.heart.fill"
        case .glassBlade: "diamond.fill"
        case .miserPurse: "bag.fill"
        case .shell: "tortoise.fill"
        case .rabbitFoot: "hare.fill"
        case .hermitFlask: "waterbottle.fill"
        case .moonCharm: "moon.fill"
        case .ember: "flame.fill"
        }
    }

    // Les chiffres, réunis ici pour que les règles et les textes ne divergent pas.
    static let chaliceHeal = 2.0
    static let chaliceTrap = 1.5
    static let stormHunger = 8.0
    static let glassAttack = 1.20
    static let glassHP = 0.90
    static let miserGold = 1.4
    static let miserPotion = 0.3
    static let shellArmor = 0.85
    static let shellSpeed = -0.10
    static let rabbitEscape = 0.15
    static let rabbitAttack = 0.95
    static let hermitNeeds = 0.75
    static let hermitMood = 1.25
    static let moonNight = 1.15
    static let moonDay = 0.95
    static let emberRest = 1.3

    /// Chance qu'un boss déjà vaincu par ce héros lâche encore une relique.
    static let bossChance = 0.10
}
