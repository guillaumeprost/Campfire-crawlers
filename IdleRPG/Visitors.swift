import Foundation

// MARK: - Visiteurs du camp

/// Ceux qui passent au feu de camp. Deux visites par jour, tirées d'après la date seule
/// (jamais avec le générateur de la partie) : la prévision du retour du héros reste exacte.
/// Un visiteur ne fait rien tout seul : c'est le joueur qui décide quoi en faire.
enum VisitorKind: String, CaseIterable {
    case merchant, wounded, gambler, pilgrim, stray

    var name: String {
        switch self {
        case .merchant: "Marchand ambulant"
        case .wounded: "Voyageur blessé"
        case .gambler: "Joueur de dés"
        case .pilgrim: "Pèlerin"
        case .stray: "Animal égaré"
        }
    }

    var intro: String {
        switch self {
        case .merchant: "Sa mule croule sous les babioles. Il déballe une curiosité près du feu."
        case .wounded: "Il boite jusqu'au feu, une main sur le flanc, et demande de l'aide."
        case .gambler: "Il fait rouler deux dés d'os dans sa paume et propose une partie."
        case .pilgrim: "Il s'assoit sans un mot, bénit les flammes, puis sourit."
        case .stray: "Une bête maigre rôde à la lisière de la lumière, attirée par l'odeur du repas."
        }
    }

    var symbol: String {
        switch self {
        case .merchant: "bag.fill"
        case .wounded: "bandage.fill"
        case .gambler: "dice.fill"
        case .pilgrim: "hands.and.sparkles.fill"
        case .stray: "pawprint.fill"
        }
    }

    /// Titre de la notification qui annonce sa venue : court, pour tenir sur l'écran verrouillé.
    var notice: String {
        switch self {
        case .merchant: "Un marchand passe au camp"
        case .wounded: "Un blessé arrive au camp"
        case .gambler: "Un joueur de dés au camp"
        case .pilgrim: "Un pèlerin s'invite au feu"
        case .stray: "Une bête rôde près du feu"
        }
    }
}

/// Une visite : qui, et pendant quelles heures.
struct CampVisit: Equatable, Identifiable {
    /// « jour.rang » : sert à se souvenir des visites déjà traitées.
    let id: String
    let kind: VisitorKind
    let start: Date
    let end: Date
    /// Graine propre à la visite, pour ce qu'elle propose (la relique du marchand, l'animal égaré).
    let seed: UInt64

    /// Durée d'une visite, en heures.
    static let stay = 2.0

    /// Les deux visites d'un jour : une le matin, une en fin de journée.
    static func visits(onDay day: Int) -> [CampVisit] {
        var generator = SeededGenerator(state: UInt64(bitPattern: Int64(day)) &* 0xD6E8_FEB8_6659_FD93 ^ 0x5649_5349_54)
        let windows: [ClosedRange<Double>] = [8...11.5, 15...19.5]
        return windows.enumerated().map { index, window in
            // Départs calés sur la demi-heure.
            let hour = (Double.random(in: window, using: &generator) * 2).rounded() / 2
            let kind = VisitorKind.allCases.randomElement(using: &generator) ?? .merchant
            let seed = generator.next()
            return CampVisit(id: "\(day).\(index)", kind: kind,
                             start: Ambient.date(day: day, hour: hour),
                             end: Ambient.date(day: day, hour: hour + stay), seed: seed)
        }
    }

    /// Le visiteur présent à cet instant, s'il y en a un.
    static func current(at date: Date) -> CampVisit? {
        visits(onDay: Ambient.day(date)).first { $0.start <= date && date < $0.end }
    }

    /// La prochaine visite à venir, aujourd'hui ou demain.
    static func next(after date: Date) -> CampVisit? {
        let day = Ambient.day(date)
        return (visits(onDay: day) + visits(onDay: day + 1)).first { $0.start > date }
    }
}

/// Une réponse possible à un visiteur.
struct VisitOption: Identifiable {
    let id: Int
    var title: String
    var detail: String
    /// Prix en or, s'il y en a un.
    var price: Double?
    /// Raison qui empêche ce choix, ou nil.
    var blocker: String?
}

/// Ce qu'a donné la rencontre, affiché au camp jusqu'à ce que le joueur le referme.
struct VisitOutcome: Identifiable, Equatable {
    let id = UUID()
    var symbol: String
    var text: String
    var good: Bool
}
