// Fichier généré par Art/import_vfx.py : ne pas modifier à la main.
import CoreGraphics

/// Effets visuels animés : nombre d'images, cadence, point d'ancrage (repère SpriteKit)
/// et hauteur d'une image en pixels.
enum FXAnims {
    static let table: [String: (count: Int, fps: Double, anchor: CGPoint, height: CGFloat)] = [
        "aura_fire": (8, 12.0, CGPoint(x: 0.5, y: 0.168), 107),
        "aura_ice": (8, 12.0, CGPoint(x: 0.5, y: 0.168), 107),
        "aura_shadow": (12, 12.0, CGPoint(x: 0.506, y: 0.118), 119),
        "coins": (11, 13.0, CGPoint(x: 0.42, y: 0.593), 81),
        "crit": (7, 15.9, CGPoint(x: 0.528, y: 0.57), 93),
        "fire": (11, 14.1, CGPoint(x: 0.487, y: 0.5), 78),
        "heal": (9, 11.0, CGPoint(x: 0.5, y: 0.304), 102),
        "hit": (5, 15.9, CGPoint(x: 0.5, y: 0.5), 64),
        "ice": (10, 12.0, CGPoint(x: 0.487, y: 0.635), 96),
        "levelup": (11, 12.0, CGPoint(x: 0.5, y: 0.128), 117),
        "shadow": (7, 15.9, CGPoint(x: 0.486, y: 0.493), 67),
        "slash": (6, 15.9, CGPoint(x: 0.5, y: 0.5), 96),
    ]
}
