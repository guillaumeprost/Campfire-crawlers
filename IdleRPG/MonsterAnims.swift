// Fichier généré par Art/import_monster_anims.py : ne pas modifier à la main.
import CoreGraphics

/// Animations disponibles pour chaque créature : nombre d'images par animation, et hauteur
/// (en pixels du cadre des animations) du sprite fixe, pour garder la même taille à l'écran.
enum MonsterAnims {
    static let table: [String: (idle: Int, attack: Int, death: Int, base: CGFloat)] = [
        "b_dragon": (4, 8, 8, 114),
        "b_golem": (4, 8, 8, 112),
        "b_kraken": (4, 8, 8, 109),
        "b_lich": (4, 8, 8, 121),
        "b_minotaur": (4, 8, 8, 119),
        "m_bat": (4, 8, 8, 49),
        "m_fire_imp": (4, 8, 8, 59),
        "m_gargoyle": (4, 8, 8, 77),
        "m_ghost": (4, 8, 8, 66),
        "m_goblin": (4, 8, 8, 59),
        "m_golem_gray": (4, 8, 8, 76),
        "m_imp": (4, 8, 8, 49),
        "m_orc": (4, 8, 8, 74),
        "m_plant": (4, 8, 8, 74),
        "m_rat": (4, 8, 8, 53),
        "m_scorpion": (4, 8, 8, 58),
        "m_skeleton": (4, 8, 8, 68),
        "m_skeleton_archer": (4, 8, 8, 71),
        "m_slime_blue": (4, 8, 8, 48),
        "m_slime_green": (4, 8, 8, 58),
        "m_slime_red": (4, 8, 8, 47),
        "m_spider": (4, 8, 8, 57),
        "m_spider_brown": (4, 8, 8, 59),
        "m_werewolf": (4, 8, 8, 77),
    ]
}
