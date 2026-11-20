import Foundation

// MARK: - Météo

/// Le temps qu'il fait dehors. Il change toutes les trois heures et ne dépend que de la date :
/// la prévision du retour du héros reste donc exacte, sans toucher au générateur de la partie.
enum Weather: String, CaseIterable {
    case clear, rain, fog, storm

    var name: String {
        switch self {
        case .clear: "Ciel dégagé"
        case .rain: "Pluie"
        case .fog: "Brume"
        case .storm: "Orage"
        }
    }

    func symbol(night: Bool) -> String {
        switch self {
        case .clear: night ? "moon.stars.fill" : "sun.max.fill"
        case .rain: "cloud.rain.fill"
        case .fog: "cloud.fog.fill"
        case .storm: "cloud.bolt.rain.fill"
        }
    }

    /// Ce que le temps change, en clair.
    var effects: [String] {
        switch self {
        case .clear: []
        case .rain: ["Le feu faiblit : repos 25\u{00A0}% plus lent", "La soif vient 30\u{00A0}% moins vite"]
        case .fog: ["On se perd de vue : fuite +10\u{00A0}%", "Trajets 15\u{00A0}% plus longs"]
        case .storm: ["Le feu faiblit : repos 25\u{00A0}% plus lent", "Trajets 25\u{00A0}% plus longs"]
        }
    }

    /// Repos au feu de camp : la pluie et l'orage étouffent les flammes.
    var restFactor: Double { self == .rain || self == .storm ? 0.75 : 1 }
    var thirstFactor: Double { self == .rain ? 0.7 : 1 }
    var escapeBonus: Double { self == .fog ? 0.10 : 0 }
    var travelFactor: Double {
        switch self {
        case .fog: 1.15
        case .storm: 1.25
        default: 1
        }
    }
}

// MARK: - Heure et temps du moment

/// L'ambiance à un instant donné : jour ou nuit, et la météo.
struct Ambient: Equatable {
    var night: Bool
    var weather: Weather

    /// Il fait jour de 7 h à 19 h, à l'heure du téléphone.
    static let dayHours = 7..<19
    /// La nuit, les monstres frappent plus fort, mais leur butin est plus riche.
    static let nightDamage = 1.15
    static let nightGold = 1.25
    /// La nuit, le héros dort au camp : il récupère plus vite.
    static let nightRest = 1.25
    /// Durée d'un même temps, en heures.
    static let weatherSpan = 3

    static let nightEffects = ["Monstres : +15\u{00A0}% de dégâts", "Butin : +25\u{00A0}% d'or",
                               "Au camp, il dort : repos 25\u{00A0}% plus rapide"]

    var symbol: String { weather.symbol(night: night) }
    var title: String { "\(night ? "Nuit" : "Jour") · \(weather.name)" }
    var effects: [String] { (night ? Self.nightEffects : []) + weather.effects }

    private static func localSeconds(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate + Double(TimeZone.current.secondsFromGMT(for: date))
    }

    /// Heures locales entières écoulées depuis la date de référence. La petite marge évite
    /// de rester coincé juste sous une heure pile à cause des arrondis.
    static func hourIndex(_ date: Date) -> Int {
        Int(((localSeconds(date) + 0.001) / 3_600).rounded(.down))
    }

    /// Heure locale, de 0 à 23.
    static func hour(_ date: Date) -> Int { ((hourIndex(date) % 24) + 24) % 24 }

    /// Numéro du jour local.
    static func day(_ date: Date) -> Int { Int((Double(hourIndex(date)) / 24).rounded(.down)) }

    /// La date d'une heure locale d'un jour donné.
    static func date(day: Int, hour: Double) -> Date {
        let local = Double(day) * 86_400 + hour * 3_600
        let guess = Date(timeIntervalSinceReferenceDate: local)
        return Date(timeIntervalSinceReferenceDate: local - Double(TimeZone.current.secondsFromGMT(for: guess)))
    }

    /// Secondes jusqu'à la prochaine heure pile : c'est là que le jour, la nuit ou la météo peuvent changer.
    static func untilNextHour(_ date: Date) -> TimeInterval {
        Double(hourIndex(date) + 1) * 3_600 - localSeconds(date)
    }

    static func isNight(_ date: Date) -> Bool { !dayHours.contains(hour(date)) }

    static func weather(at date: Date) -> Weather {
        let block = Int((Double(hourIndex(date)) / Double(weatherSpan)).rounded(.down))
        var generator = SeededGenerator(state: UInt64(bitPattern: Int64(block)) &* 0x9E37_79B9_7F4A_7C15 ^ 0x4D45_5445_4F)
        switch Double.random(in: 0..<1, using: &generator) {
        case ..<0.56: return .clear
        case ..<0.78: return .rain
        case ..<0.90: return .fog
        default: return .storm
        }
    }

    static func at(_ date: Date) -> Ambient {
        Ambient(night: isNight(date), weather: weather(at: date))
    }
}
