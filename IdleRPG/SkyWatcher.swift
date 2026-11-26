import CoreLocation
import Observation
import UIKit
import WeatherKit

/// Relève le vrai ciel du joueur : sa position approximative, pour le lever et le coucher du soleil,
/// et la météo d'Apple heure par heure. Le jeu ne lit jamais ce service directement : il reçoit un
/// `Sky` qu'il sauvegarde, et c'est ce relevé que rejoue la prévision.
@MainActor
@Observable
final class SkyWatcher: NSObject, CLLocationManagerDelegate {
    static let shared = SkyWatcher()

    enum Access { case unknown, granted, refused }

    private(set) var access = Access.unknown
    /// Logo et mentions légales d'Apple Weather, à afficher dès que sa météo est à l'écran.
    private(set) var attribution: WeatherAttribution?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private weak var game: GameState?
    @ObservationIgnored private var fetching = false
    @ObservationIgnored private var timer: Timer?

    /// Un relevé par demi-heure suffit : la météo ne tourne pas plus vite.
    private static let freshness: TimeInterval = 1_800
    /// On relève cinq jours : la prévision du jeu regarde quatre jours devant.
    private static let horizon: TimeInterval = 5 * 86_400

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        access = Self.access(for: manager.authorizationStatus)
    }

    private static func access(for status: CLAuthorizationStatus) -> Access {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: .granted
        case .denied, .restricted: .refused
        default: .unknown
        }
    }

    /// Pendant les tests, on ne demande rien au joueur et on n'appelle aucun service.
    private static var isQuiet: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || UserDefaults.standard.string(forKey: "debugSky") != nil
    }

    /// L'app revient à l'écran : on relève le ciel s'il a vieilli. La première fois, une fois le
    /// héros choisi, on demande la position.
    func watch(_ game: GameState) {
        guard !Self.isQuiet else { return }
        self.game = game
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: Self.freshness, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        refresh()
    }

    func rest() {
        timer?.invalidate()
        timer = nil
    }

    /// Le joueur demande à suivre le vrai ciel depuis la fiche de la météo.
    func ask() {
        switch access {
        case .unknown: manager.requestWhenInUseAuthorization()
        case .granted: refresh(force: true)
        case .refused:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }
    }

    private func refresh(force: Bool = false) {
        guard let game, game.heroClass != nil else { return }
        switch access {
        case .unknown: manager.requestWhenInUseAuthorization()
        case .refused: game.forgetSky()
        case .granted:
            let age = game.sky.fetched.map { Date().timeIntervalSince($0) } ?? .infinity
            if force || age < 0 || age >= Self.freshness { manager.requestLocation() }
        }
    }

    private func read(at location: CLLocation) async {
        guard let game, !fetching else { return }
        fetching = true
        defer { fetching = false }
        let now = Date()
        var fresh = Sky(latitude: (location.coordinate.latitude * 100).rounded() / 100,
                        longitude: (location.coordinate.longitude * 100).rounded() / 100)
        do {
            let (current, hourly) = try await WeatherService.shared.weather(
                for: location, including: .current, .hourly(startDate: now, endDate: now.addingTimeInterval(Self.horizon)))
            for hour in hourly.forecast { fresh.hours[Sky.hourKey(hour.date)] = Weather(hour.condition) }
            // L'heure en cours suit ce qu'il fait vraiment dehors, pas ce qui était annoncé.
            fresh.hours[Sky.hourKey(now)] = Weather(current.condition)
            fresh.fetched = now
            if attribution == nil { attribution = try? await WeatherService.shared.attribution }
        } catch {
            // Sans réseau ou sans service, le soleil suit quand même la position ; la météo garde
            // le dernier relevé, puis redevient imaginaire.
        }
        game.updateSky(fresh)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            access = Self.access(for: status)
            refresh(force: true)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await read(at: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension Weather {
    /// Le temps du jeu le plus proche d'une condition d'Apple Weather.
    init(_ condition: WeatherCondition) {
        switch condition {
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms,
             .hurricane, .tropicalStorm, .hail:
            self = .storm
        case .drizzle, .rain, .heavyRain, .freezingDrizzle, .freezingRain, .sunShowers:
            self = .rain
        case .snow, .heavySnow, .flurries, .sunFlurries, .sleet, .wintryMix, .blizzard, .blowingSnow:
            self = .snow
        case .foggy, .haze, .smoky, .blowingDust:
            self = .fog
        case .cloudy, .mostlyCloudy:
            self = .cloudy
        default:
            self = .clear
        }
    }
}
