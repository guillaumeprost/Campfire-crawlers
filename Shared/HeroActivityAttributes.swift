import ActivityKit
import Foundation

/// Données de l'activité en direct, partagées entre le jeu et l'extension.
///
/// L'extension ne peut pas être réveillée par le jeu quand il est fermé.
/// Tout repose donc sur des dates : barres et comptes à rebours avancent seuls.
/// Un second panneau prend le relais quand l'activité devient périmée,
/// ce qui arrive à une date choisie par le jeu.
struct HeroActivityAttributes: ActivityAttributes {
    /// Une étape, dessinée comme une barre qui se remplit entre deux dates.
    struct Step: Codable, Hashable {
        var label: String
        var start: Date
        var end: Date
    }

    struct Panel: Codable, Hashable {
        var headline: String
        var detail: String
        /// Nom de l'image dans le catalogue de l'extension.
        var sprite: String
        var steps: [Step]
        /// Cible du compte à rebours. Nil : rien à attendre.
        var end: Date?
        /// Texte placé devant l'heure : "Retour à", "Reposé à".
        var endLabel: String
        /// Vignette du lieu, en fond du panneau.
        var scene: String?
    }

    /// Le héros, tel qu'il était à la dernière mise à jour.
    struct Hero: Codable, Hashable {
        var name: String
        var portrait: String
        /// Parts de 0 à 1.
        var hp: Double
        var hunger: Double
        var mood: Double
        /// Absente des activités lancées avant la soif.
        var thirst: Double?
    }

    struct ContentState: Codable, Hashable {
        var now: Panel
        /// Affiché une fois la date de péremption passée.
        var later: Panel?
        var hero: Hero?
    }
}
