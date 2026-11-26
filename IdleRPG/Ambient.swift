import Foundation

// MARK: - Météo

/// Le temps qu'il fait dehors. Il suit la vraie météo quand le joueur partage sa position (`Sky`),
/// sinon il est tiré de la date seule. Dans les deux cas il ne dépend que de la date et du ciel
/// enregistré : la prévision du retour du héros reste exacte, sans toucher au générateur de la partie.
enum Weather: String, CaseIterable, Codable {
    case clear, cloudy, rain, snow, fog, storm

    var name: String {
        switch self {
        case .clear: "Ciel dégagé"
        case .cloudy: "Ciel couvert"
        case .snow: "Neige"
        case .rain: "Pluie"
        case .fog: "Brume"
        case .storm: "Orage"
        }
    }

    func symbol(night: Bool) -> String {
        switch self {
        case .clear: night ? "moon.stars.fill" : "sun.max.fill"
        case .cloudy: night ? "cloud.moon.fill" : "cloud.fill"
        case .snow: "cloud.snow.fill"
        case .rain: "cloud.rain.fill"
        case .fog: "cloud.fog.fill"
        case .storm: "cloud.bolt.rain.fill"
        }
    }

    /// Ce que le temps change, en clair.
    var effects: [String] {
        switch self {
        case .clear, .cloudy: []
        case .snow: ["Le feu faiblit : repos 25\u{00A0}% plus lent", "Trajets 15\u{00A0}% plus longs"]
        case .rain: ["Le feu faiblit : repos 25\u{00A0}% plus lent", "La soif vient 30\u{00A0}% moins vite"]
        case .fog: ["On se perd de vue : fuite +10\u{00A0}%", "Trajets 15\u{00A0}% plus longs"]
        case .storm: ["Le feu faiblit : repos 25\u{00A0}% plus lent", "Trajets 25\u{00A0}% plus longs"]
        }
    }

    /// Repos au feu de camp : la pluie, la neige et l'orage étouffent les flammes.
    var restFactor: Double { self == .rain || self == .snow || self == .storm ? 0.75 : 1 }
    var thirstFactor: Double { self == .rain ? 0.7 : 1 }
    var escapeBonus: Double { self == .fog ? 0.10 : 0 }
    var travelFactor: Double {
        switch self {
        case .fog, .snow: 1.15
        case .storm: 1.25
        default: 1
        }
    }
}

// MARK: - Le vrai ciel

/// Ce que le jeu sait du ciel du joueur : où il se trouve, pour le lever et le coucher du soleil,
/// et la météo relevée heure par heure. Il est sauvegardé avec la partie, pour que le temps déjà
/// annoncé au joueur soit bien celui qui se joue, même sans réseau au retour.
struct Sky: Codable, Equatable {
    /// Position arrondie au centième de degré (environ un kilomètre).
    var latitude: Double?
    var longitude: Double?
    /// Météo relevée ou annoncée, par heure universelle (`hourKey`).
    var hours: [Int: Weather] = [:]
    var fetched: Date?

    var followsSun: Bool { latitude != nil && longitude != nil }

    /// Numéro de l'heure universelle qui contient cette date.
    static func hourKey(_ date: Date) -> Int {
        Int(((date.timeIntervalSinceReferenceDate + 0.001) / 3_600).rounded(.down))
    }

    /// Adopte un relevé plus récent. Les heures déjà jouées gardent le temps qu'elles ont eu.
    mutating func adopt(_ fresh: Sky, from date: Date) {
        let now = Self.hourKey(date)
        hours = hours.filter { $0.key >= now - 48 }.merging(fresh.hours.filter { $0.key >= now }) { $1 }
        latitude = fresh.latitude ?? latitude
        longitude = fresh.longitude ?? longitude
        fetched = fresh.fetched ?? fetched
    }

    /// Hauteur du soleil au-dessus de l'horizon, en degrés (formules de l'almanach astronomique,
    /// justes à un centième de degré près).
    static func sunAltitude(at date: Date, latitude: Double, longitude: Double) -> Double {
        let rad = Double.pi / 180
        // Jours depuis le 1er janvier 2000 à midi.
        let n = date.timeIntervalSinceReferenceDate / 86_400 + 365.5
        let mean = (280.460 + 0.985_647_4 * n) * rad
        let anomaly = (357.528 + 0.985_600_3 * n) * rad
        let ecliptic = mean + (1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * rad
        let tilt = (23.439 - 0.000_000_4 * n) * rad
        let declination = asin(sin(tilt) * sin(ecliptic))
        let ascension = atan2(cos(tilt) * sin(ecliptic), cos(ecliptic))
        let sidereal = (18.697_374_558 + 24.065_709_824_419_08 * n) * 15 * rad
        let hourAngle = sidereal + longitude * rad - ascension
        let phi = latitude * rad
        return asin(sin(phi) * sin(declination) + cos(phi) * cos(declination) * cos(hourAngle)) / rad
    }

    /// Le soleil se lève et se couche quand son bord supérieur touche l'horizon, réfraction comprise.
    static let horizon = -0.833
}

// MARK: - Heure et temps du moment

/// L'ambiance à un instant donné : jour ou nuit, et la météo.
struct Ambient: Equatable {
    var night: Bool
    var weather: Weather

    /// Sans position connue, il fait jour de 7 h à 19 h, à l'heure du téléphone.
    static let dayHours = 7..<19
    /// La nuit, les monstres frappent plus fort, mais leur butin est plus riche.
    static let nightDamage = 1.15
    static let nightGold = 1.25
    /// La nuit, le héros dort au camp : il récupère plus vite.
    static let nightRest = 1.25
    /// Durée d'un même temps quand il est imaginaire, en heures.
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

    /// Secondes jusqu'à la prochaine heure pile, à l'heure du téléphone.
    static func untilNextHour(_ date: Date) -> TimeInterval {
        Double(hourIndex(date) + 1) * 3_600 - localSeconds(date)
    }

    /// Le prochain instant où le jour, la nuit ou la météo peuvent changer : une heure pile
    /// (locale ou universelle, elles diffèrent dans les fuseaux à la demi-heure), ou bien le lever
    /// ou le coucher du soleil s'il tombe avant.
    static func untilNextChange(_ date: Date, sky: Sky = Sky()) -> TimeInterval {
        let seconds = date.timeIntervalSinceReferenceDate
        let universal = Double(Sky.hourKey(date) + 1) * 3_600 - seconds
        let span = min(untilNextHour(date), universal)
        guard sky.followsSun else { return span }
        let night = isNight(date, sky: sky)
        guard isNight(date.addingTimeInterval(span), sky: sky) != night else { return span }
        // Le soleil passe l'horizon dans l'intervalle : on resserre jusqu'à la demi-seconde,
        // et on rend l'instant où il est déjà de l'autre côté.
        var before = 0.0, after = span
        while after - before > 0.5 {
            let middle = (before + after) / 2
            if isNight(date.addingTimeInterval(middle), sky: sky) == night { before = middle } else { after = middle }
        }
        return after
    }

    static func isNight(_ date: Date, sky: Sky = Sky()) -> Bool {
        if let latitude = sky.latitude, let longitude = sky.longitude {
            return Sky.sunAltitude(at: date, latitude: latitude, longitude: longitude) < Sky.horizon
        }
        return !dayHours.contains(hour(date))
    }

    static func weather(at date: Date, sky: Sky = Sky()) -> Weather {
        if let real = sky.hours[Sky.hourKey(date)] { return real }
        let block = Int((Double(hourIndex(date)) / Double(weatherSpan)).rounded(.down))
        var generator = SeededGenerator(state: UInt64(bitPattern: Int64(block)) &* 0x9E37_79B9_7F4A_7C15 ^ 0x4D45_5445_4F)
        switch Double.random(in: 0..<1, using: &generator) {
        case ..<0.56: return .clear
        case ..<0.78: return .rain
        case ..<0.90: return .fog
        default: return .storm
        }
    }

    static func at(_ date: Date, sky: Sky = Sky()) -> Ambient {
        Ambient(night: isNight(date, sky: sky), weather: weather(at: date, sky: sky))
    }
}
