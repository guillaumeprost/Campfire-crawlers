// Fichier généré par Art/import_companions.py : ne pas modifier à la main.
import CoreGraphics

/// Largeur du corps de chaque compagnon debout, en pixels de ses images.
enum CompanionArt {
    static let bodyWidth: [String: CGFloat] = [
        "wolf": 81,
        "panther": 78,
        "bear": 62,
        "fox": 82,
        "stag": 60,
    ]
    /// Largeur une fois assis ou couché : certains s'allongent de tout leur long.
    static let restWidth: [String: CGFloat] = [
        "wolf": 83,
        "panther": 82,
        "bear": 56,
        "fox": 84,
        "stag": 84,
    ]
}
