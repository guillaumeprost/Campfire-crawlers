import SpriteKit
import UIKit

/// Bande d'images répétées qui défile sans couture : une image sur deux est retournée,
/// si bien que chaque bord se raccorde à lui-même.
final class TileStrip: SKNode {
    private var tiles: [SKSpriteNode] = []
    private var tileWidth: CGFloat = 1

    func configure(texture: SKTexture, height: CGFloat, sceneWidth: CGFloat, tint: UIColor? = nil, mirror: Bool = true) {
        clear()
        let size = texture.size()
        tileWidth = max((size.width / size.height * height).rounded(), 1)
        let count = Int((sceneWidth / tileWidth).rounded(.up)) + 3
        for index in 0..<count {
            let tile = SKSpriteNode(texture: texture, size: CGSize(width: tileWidth + 1, height: height))
            tile.anchorPoint = CGPoint(x: 0.5, y: 0)
            // Décors tileables (bords raccord) : on répète à l'identique. Sinon on alterne
            // en miroir pour masquer la jointure (ancien comportement).
            tile.xScale = (mirror && index % 2 == 1) ? -1 : 1
            if let tint {
                tile.color = tint
                tile.colorBlendFactor = 1
            }
            addChild(tile)
            tiles.append(tile)
        }
        update(offset: 0)
    }

    func clear() {
        removeAllChildren()
        tiles = []
    }

    func update(offset: CGFloat) {
        let period = 2 * tileWidth
        var shift = offset.truncatingRemainder(dividingBy: period)
        if shift < 0 { shift += period }
        for (index, tile) in tiles.enumerated() {
            tile.position.x = CGFloat(index) * tileWidth - shift + tileWidth / 2
        }
    }
}

/// Montre ce que fait le héros en ce moment : repos au camp, marche,
/// exploration d'un donjon ou passage à la boutique.
final class WorldScene: SKScene {
    private let game: GameState
    private var lastUpdate: TimeInterval = 0

    /// Identifie ce qui est affiché. Quand il change, on reconstruit le décor.
    private var modeKey = ""
    private var scroll: CGFloat = 0
    private var facing: CGFloat = 1
    private var heroSlot: CGFloat = 0.22
    private var encounterShown = false
    private var attackTimer: TimeInterval = 0
    /// Les coups du combat en cours, et le prochain à jouer.
    private var blows: [GameState.Blow] = []
    private var blowIndex = 0
    private var restTimer: TimeInterval = 0
    /// Au camp, le héros s'endort au lieu de s'occuper quand il est à bout :
    /// énergie sous un quart, ou PV ou moral sous la moitié.
    private var sleepsAtCamp: Bool {
        guard case .resting = game.activity else { return false }
        return game.energy < GameState.maxEnergy / 4
            || game.hp < game.maxHP / 2
            || game.mood < 50
    }
    private var feelingTimer: TimeInterval = 6

    private let sky = SKSpriteNode()
    private let backdrop = TileStrip()
    /// Reflet assombri de la scène, sous son bord bas : il remplit ce que cache le panneau.
    private let underStrip = TileStrip()
    private let underSky = SKSpriteNode()

    /// Hauteur cachée en bas par le panneau de l'interface : la scène est posée au-dessus.
    var bottomInset: CGFloat = 0 {
        didSet { if bottomInset != oldValue { modeKey = "" } }
    }
    /// Largeur cachée à droite par le panneau, en paysage : le décor passe dessous,
    /// mais les personnages restent dans la partie dégagée.
    var trailingInset: CGFloat = 0 {
        didSet { if trailingInset != oldValue { modeKey = "" } }
    }
    private var playWidth: CGFloat { max(size.width - trailingInset, 1) }
    /// Copie en miroir de la scène fixe, qui la prolonge à droite sous le panneau.
    private let sideSky = SKSpriteNode()
    private var paintingCenterX: CGFloat = 0
    /// Décor lointain, derrière le sol : seuls les arbres du fond y vont.
    private let farLayer = SKNode()
    /// Décor posé sur le sol, derrière les personnages.
    private let sceneryLayer = SKNode()
    private let ground = TileStrip()
    private let hero = SKSpriteNode()
    /// Sprite du coup spécial, plus grand que le héros, qui le remplace le temps de l'animation.
    private var specialSprite: SKSpriteNode?
    /// Pose de victoire : la scène du donjon reste en place jusqu'à cette heure-là.
    private var victoryUntil: TimeInterval = 0
    /// Compagnon affiché et son animation : un changement au camp se voit tout de suite.
    private var shownCompanion: CompanionKind?
    private var companionPose = "idle"
    /// Coups portés par le héros dans le combat en cours : le compagnon s'en mêle un coup sur deux.
    private var heroBlows = 0
    private let heroShadow = SKShapeNode()
    /// Compagnon animal qui suit le héros, quand un compagnon est actif.
    private let companion = SKSpriteNode()
    /// Éléments du lieu courant, vidés à chaque changement.
    private let props = SKNode()
    /// Effets qui survivent au changement de salle : monstre qui tombe, pièces, textes.
    private let effects = SKNode()
    /// Pluie, brume, éclairs et voile de nuit, par-dessus les personnages.
    private let weatherLayer = SKNode()
    private var weatherKey: Weather?
    /// Position du feu de camp, pour y placer le visiteur.
    private var campFire = CGPoint.zero
    /// Le marchand, quand la scène du marché est affichée : les achats partent de lui.
    private weak var merchant: SKSpriteNode?
    /// La serveuse, quand la taverne est affichée : les commandes partent d'elle.
    private weak var barmaid: SKSpriteNode?
    private var encounter: SKSpriteNode?
    private var encounterLift: CGFloat = 0
    /// Taille de la créature elle-même : le sprite animé est plus large qu'elle.
    private var encounterBody: CGSize = .zero
    private var encounterSprite = ""
    /// Aura de l'arme, posée derrière le héros (elle le suit et se retourne avec lui).
    private let aura = SKSpriteNode()
    private var auraName: String?
    private let encounterShadow = SKShapeNode()

    /// Décor qui défile avec le sol et revient en boucle.
    private var scenery: [(node: SKSpriteNode, home: CGFloat)] = []
    private var sceneryLoop: CGFloat = 1

    private let hpBar = SKNode()
    private let hpFill = SKSpriteNode(color: .systemRed, size: CGSize(width: 130, height: 10))
    private let nameText = SKLabelNode()
    private let banner = SKLabelNode()

    private let successHaptic = UINotificationFeedbackGenerator()

    /// Les décors sont exportés au pixel du héros : un pixel d'image vaut toujours
    /// deux points à l'écran, pour que tout ait le même grain.
    private static let pixel: CGFloat = 2
    /// Points à l'écran par pixel des sprites de héros (80 px de haut).
    private static let heroScale: CGFloat = 1.25
    /// Les créatures sont ramenées à la même échelle que le héros sur les scènes peintes.
    private static let actorScale: CGFloat = 0.78
    private static let walkSpeed: CGFloat = 70

    /// Taille à l'écran de chaque créature, retournement pour qu'elle regarde le héros,
    /// et hauteur de vol pour celles qui ne touchent pas le sol. Les monstres pixel art
    /// (`Art/import_monsters.py`) regardent déjà vers la gauche.
    private static let looks: [String: (height: CGFloat, flip: Bool, lift: CGFloat)] = [
        "m_rat": (44, false, 0), "m_bat": (42, false, 34), "m_spider": (44, false, 0),
        "m_spider_brown": (44, false, 0), "m_slime_green": (42, false, 0), "m_slime_blue": (42, false, 0),
        "m_slime_red": (42, false, 0), "m_skeleton": (82, false, 0), "m_skeleton_archer": (82, false, 0),
        "m_goblin": (62, false, 0), "m_imp": (56, false, 26), "m_orc": (86, false, 0),
        "m_ghost": (66, false, 12), "m_golem": (80, false, 0), "m_golem_gray": (80, false, 0),
        "m_plant": (80, false, 0), "m_scorpion": (58, false, 0), "m_werewolf": (88, false, 0),
        "m_gargoyle": (90, false, 0), "m_fire_imp": (64, false, 0), "m_beholder": (70, false, 24),
        "b_golem": (142, false, 0), "b_lich": (138, false, 0), "b_minotaur": (142, false, 0),
        "b_kraken": (128, false, 0), "b_dragon": (140, false, 0),
        "chest_closed": (52, false, 0), "trap_spikes": (52, false, 0), "shrine": (74, false, 0),
    ]

    private static var textures: [String: SKTexture] = [:]

    /// Texture en pixel art, agrandie sans lissage.
    static func texture(_ name: String) -> SKTexture {
        if let cached = textures[name] { return cached }
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .nearest
        textures[name] = texture
        return texture
    }

    /// Sprite posé au sol, mis à la hauteur demandée en gardant ses proportions.
    private static func sprite(_ name: String, height: CGFloat) -> SKSpriteNode {
        let texture = texture(name)
        let size = texture.size()
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: size.width / max(size.height, 1) * height, height: height)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        return node
    }

    /// Images d'une animation de créature (`idle`, `attack`, `death`), vides s'il n'y en a pas.
    private static func creatureFrames(_ name: String, _ anim: String) -> [SKTexture] {
        guard let entry = MonsterAnims.table[name] else { return [] }
        let count: Int
        switch anim {
        case "idle": count = entry.idle
        case "attack": count = entry.attack
        default: count = entry.death
        }
        return count > 0 ? (1...count).map { texture("\(name)_\(anim)_\($0)") } : []
    }

    /// Créature animée : ses images partagent un cadre plus large que le sprite fixe (pour
    /// laisser la place aux gestes), centré sur elle, pieds en bas. `height` reste la hauteur
    /// de la créature elle-même, pas celle du cadre.
    private static func creature(_ name: String, height: CGFloat) -> SKSpriteNode {
        let idle = creatureFrames(name, "idle")
        guard let first = idle.first, let base = MonsterAnims.table[name]?.base, base > 0 else {
            return sprite(name, height: height)
        }
        let scale = height / base
        let size = first.size()
        let node = SKSpriteNode(texture: first)
        node.size = CGSize(width: size.width * scale, height: size.height * scale)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        return node
    }

    /// Élément de décor à sa taille d'origine, ancré en bas au centre.
    private static func prop(_ name: String) -> SKSpriteNode {
        let texture = texture(name)
        let size = texture.size()
        let node = SKSpriteNode(texture: texture, size: CGSize(width: size.width * pixel, height: size.height * pixel))
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        return node
    }

    /// Ombre de contact en pixel art : une ellipse plate, sans bord lissé.
    private static let shadowTexture: SKTexture = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 6), format: format).image { context in
            context.cgContext.setShouldAntialias(false)
            UIColor(white: 0, alpha: 0.32).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 32, height: 6))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }()

    /// Glisse une ombre sous un élément posé au sol. `width` est en pixels de décor.
    private static func ground(_ node: SKSpriteNode, shadow width: CGFloat) {
        guard width > 0 else { return }
        let height = max(2, (width / 7).rounded())
        let shadow = SKSpriteNode(texture: shadowTexture, size: CGSize(width: width * pixel, height: height * pixel))
        shadow.position = CGPoint(x: 0, y: pixel)
        shadow.zPosition = -0.05
        node.addChild(shadow)
    }

    /// Halo du feu en pixel art : des disques pleins, sans dégradé lissé.
    private static let glowTexture: SKTexture = {
        let side: CGFloat = 80
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            context.cgContext.setShouldAntialias(false)
            for (radius, alpha) in [(40.0, 0.06), (30.0, 0.07), (20.0, 0.09), (11.0, 0.12)] {
                UIColor(red: 1, green: 0.6, blue: 0.25, alpha: alpha).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: side / 2 - radius, y: side / 2 - radius,
                                                         width: radius * 2, height: radius * 2))
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }()

    init(game: GameState) {
        self.game = game
        super.init(size: CGSize(width: 390, height: 230))
        scaleMode = .resizeFill
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) non utilisé") }

    // MARK: - Mise en place

    override func didMove(to view: SKView) {
        guard hero.parent == nil else { return }
        backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)

        sky.zPosition = -10
        sky.anchorPoint = CGPoint(x: 0.5, y: 0)
        addChild(sky)
        backdrop.zPosition = -9
        addChild(backdrop)
        for under in [underStrip, underSky] as [SKNode] {
            under.zPosition = -9.5
            under.yScale = -1
            addChild(under)
        }
        underSky.anchorPoint = CGPoint(x: 0.5, y: 0)
        sideSky.anchorPoint = CGPoint(x: 0.5, y: 0)
        sideSky.xScale = -1
        sideSky.zPosition = -10
        addChild(sideSky)
        underSky.color = .black
        underSky.colorBlendFactor = 0.45
        farLayer.zPosition = -8.5
        addChild(farLayer)
        ground.zPosition = -8
        addChild(ground)
        sceneryLayer.zPosition = -7
        addChild(sceneryLayer)

        for shadow in [heroShadow, encounterShadow] {
            shadow.fillColor = UIColor(white: 0, alpha: 0.3)
            shadow.strokeColor = .clear
            shadow.zPosition = 1
            addChild(shadow)
        }
        heroShadow.path = CGPath(ellipseIn: CGRect(x: -26, y: -2, width: 52, height: 10), transform: nil)
        encounterShadow.isHidden = true

        props.zPosition = 2
        addChild(props)

        hero.anchorPoint = CGPoint(x: 0.5, y: 0)
        hero.zPosition = 4
        addChild(hero)
        aura.zPosition = -0.5
        aura.isHidden = true
        hero.addChild(aura)

        companion.anchorPoint = CGPoint(x: 0.5, y: 0)
        companion.zPosition = 4.5   // au premier plan : dans le dos du héros, mais devant lui
        companion.isHidden = true
        addChild(companion)

        effects.zPosition = 8
        addChild(effects)
        weatherLayer.zPosition = 6
        addChild(weatherLayer)

        buildHPBar()

        banner.zPosition = 20
        banner.alpha = 0
        addChild(banner)

        game.onEvent = { [weak self] event in self?.handle(event) }
    }

    private func buildHPBar() {
        let width: CGFloat = 130
        let back = SKShapeNode(rectOf: CGSize(width: width + 4, height: 14), cornerRadius: 4)
        back.fillColor = UIColor(white: 0, alpha: 0.6)
        back.strokeColor = UIColor(white: 1, alpha: 0.3)
        back.lineWidth = 1
        hpBar.addChild(back)

        hpFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpFill.position = CGPoint(x: -width / 2, y: 0)
        hpBar.addChild(hpFill)

        nameText.position = CGPoint(x: 0, y: 12)
        hpBar.addChild(nameText)

        hpBar.zPosition = 10
        hpBar.isHidden = true
        addChild(hpBar)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        modeKey = ""
    }

    // MARK: - Géométrie

    private var heroPosition: CGPoint { CGPoint(x: playWidth * heroSlot, y: feetY) }
    /// En portrait le monstre se tient plus près du héros : contre le bord droit, lui et sa jauge
    /// passeraient sous les boutons de combat.
    private var encounterPosition: CGPoint { CGPoint(x: playWidth * (isPortrait ? 0.60 : 0.72), y: feetY) }

    /// Ligne où les personnages posent les pieds : elle suit le sol de la scène peinte.
    private var feetY: CGFloat = 22
    /// Part de la hauteur visible gardée comme sol sous les pieds, pour les scènes qui
    /// défilent. Plus c'est petit, plus les personnages descendent vers le bord bas.
    private static let scrollForeground: CGFloat = 0.09
    /// Hauteur minimale des pieds au-dessus du bas réservé en portrait, en points : le panneau
    /// replié dépasse ce bas d'environ 74 points (son recouvrement, plus la marge basse de l'écran).
    private static let portraitFeetClearance: CGFloat = 96
    private var backdropSize = CGSize(width: 1, height: 1)
    private var backdropScale: CGFloat = 1
    /// Les personnages suivent la taille de la scène peinte : plus la vue est grande, plus ils grandissent.
    /// Plafonné : le trajet n'a pas de version verticale, et son image agrandie
    /// pour remplir un écran en portrait ferait des personnages géants.
    private var zoom: CGFloat { min(backdropScale / 0.256, 1.4) }

    // MARK: - Décors

    /// Une scène peinte : l'image, la hauteur du sol (part de l'image depuis le haut)
    /// et si elle défile, pour les trajets et les donjons.
    private struct Backdrop {
        let image: String
        let floor: CGFloat
        let scrolls: Bool
    }

    /// Le camp s'éclaire le jour : du lever au coucher du soleil, ou de 7 h à 19 h sans position connue.
    static var isDaytime: Bool {
        if let ambient = shownAmbient { return !ambient.night }
        return !Ambient.isNight(Date())
    }

    /// L'heure et le temps du jeu, recopiés à chaque image : en mode test les jours défilent plus vite
    /// que l'horloge du téléphone, et le décor doit suivre le jeu.
    private(set) static var shownAmbient: Ambient?

    /// Image du camp, du jour ou de la nuit. Le paysage a sa propre version de jour, plus brumeuse.
    static var campImage: String { isDaytime ? "scene_camp_brume" : "scene_camp" }

    private var isPortrait: Bool { size.height > size.width }

    /// Scène du lieu. Seules les scènes **fixes** prennent une version verticale recadrée en portrait ;
    /// les scènes qui **défilent** gardent l'image 16:9 en portrait comme en paysage, pour que le
    /// scroll horizontal soit cohérent d'une orientation à l'autre.
    /// `portraitFloor` : la ligne du sol de l'image verticale.
    private func backdrop(_ image: String, floor: CGFloat, portraitFloor: CGFloat, scrolls: Bool) -> Backdrop {
        var name = image
        if image == "scene_camp_brume" { name = "scene_camp_jour" }
        if !scrolls, isPortrait, UIImage(named: name + "_portrait") != nil {
            return Backdrop(image: name + "_portrait", floor: portraitFloor, scrolls: scrolls)
        }
        return Backdrop(image: image, floor: floor, scrolls: scrolls)
    }

    private func backdrop(for style: DungeonStyle) -> Backdrop {
        switch style {
        case .cave: backdrop("scene_cave", floor: 0.83, portraitFloor: 0.83, scrolls: true)
        case .forest: backdrop("scene_bois_hante", floor: 0.86, portraitFloor: 0.88, scrolls: true)
        case .crypt: backdrop("scene_crypte", floor: 0.86, portraitFloor: 0.83, scrolls: true)
        case .ice: backdrop("scene_glacier", floor: 0.85, portraitFloor: 0.86, scrolls: true)
        case .volcano: backdrop("scene_volcan", floor: 0.91, portraitFloor: 0.91, scrolls: true)
        }
    }

    private static var paintings: [String: SKTexture] = [:]

    /// Les scènes sont plus grandes que l'écran : on les réduit avec lissage.
    private static func painting(_ name: String) -> SKTexture {
        if let cached = paintings[name] { return cached }
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .linear
        paintings[name] = texture
        return texture
    }

    /// Les scènes fixes couvrent toute la vue, calées en bas. Celles qui défilent prennent
    /// toute la hauteur et se répètent en miroir.
    private func setBackdrop(_ scene: Backdrop) {
        let texture = Self.painting(scene.image)
        let source = texture.size()
        backdropSize = source
        ground.clear()
        let visible = max(size.height - bottomInset, 1)
        sideSky.isHidden = true
        paintingCenterX = size.width / 2
        // Bas du décor peint à l'écran : abaissé pour les scènes qui défilent (voir plus bas).
        var groundY = bottomInset
        if scene.scrolls {
            sky.isHidden = true
            underSky.isHidden = true
            // Le décor défilant remplit toute la hauteur : les pieds se posent alors à ~16 %
            // du bas, laissant une large bande de sol vide sous les personnages. On agrandit
            // un peu l'image et on fait déborder cet excédent de premier plan sous l'écran,
            // pour que les pieds touchent presque le bord visible — le sol peint reste pile
            // sous eux. `scrollForeground` = bande de sol gardée sous les pieds.
            // Seulement en paysage : en portrait, `bottomInset` réserve déjà le bas pour le
            // panneau replié, et le sol se cale juste au-dessus de lui.
            let band = (1 - scene.floor) * visible
            let extra = bottomInset <= 0 && scene.floor > 0
                ? max(band - Self.scrollForeground * visible, 0) / scene.floor : 0
            let drawn = visible + extra
            // Portrait : le panneau replié recouvre le bas du décor. Quand le sol peint est trop
            // bas (le Volcan), on remonte l'image pour que les pieds restent au-dessus de lui ;
            // le reflet sous le décor comble le vide, caché derrière le panneau.
            let lift = bottomInset > 0 ? max(Self.portraitFeetClearance - band, 0) : 0
            groundY = bottomInset - extra + lift
            backdropScale = drawn / max(source.height, 1)
            backdrop.configure(texture: texture, height: drawn, sceneWidth: size.width, mirror: false)
            backdrop.position = CGPoint(x: 0, y: groundY)
            underStrip.configure(texture: texture, height: drawn, sceneWidth: size.width,
                                 tint: UIColor(white: 0.55, alpha: 1), mirror: false)
            underStrip.position = CGPoint(x: 0, y: groundY)
        } else {
            backdrop.clear()
            underStrip.clear()
            backdropScale = max(visible / max(source.height, 1), size.width / max(source.width, 1))
            let painted = CGSize(width: source.width * backdropScale, height: source.height * backdropScale)
            if trailingInset > 0 {
                // Paysage : le cœur de la scène se cale dans la partie dégagée,
                // et un reflet en miroir prolonge le décor sous le panneau.
                paintingCenterX = (playWidth / 2 + 0.05 * painted.width).rounded()
                sideSky.texture = texture
                sideSky.size = painted
                sideSky.position = CGPoint(x: paintingCenterX + painted.width, y: bottomInset)
                sideSky.isHidden = paintingCenterX + painted.width / 2 >= size.width
            }
            sky.texture = texture
            sky.colorBlendFactor = 0
            sideSky.colorBlendFactor = 0
            sky.size = painted
            sky.position = CGPoint(x: paintingCenterX, y: bottomInset)
            sky.isHidden = false
            underSky.texture = texture
            underSky.size = painted
            underSky.position = sky.position
            underSky.isHidden = bottomInset <= 0
        }
        feetY = (groundY + (1 - scene.floor) * source.height * backdropScale).rounded()
    }

    /// Point de la scène peinte fixe, en fractions de l'image (u de gauche à droite, v de haut en bas).
    private func scenePoint(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        CGPoint(x: (paintingCenterX + (u - 0.5) * backdropSize.width * backdropScale).rounded(),
                y: (bottomInset + (1 - v) * backdropSize.height * backdropScale).rounded())
    }

    private func placeScrolling() {
        backdrop.update(offset: scroll)
        underStrip.update(offset: scroll)
        ground.update(offset: scroll)
        for item in scenery {
            var x = (item.home - scroll).truncatingRemainder(dividingBy: sceneryLoop)
            if x < 0 { x += sceneryLoop }
            item.node.position.x = x - 130
        }
    }

    // MARK: - Boucle

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.1)
        lastUpdate = currentTime
        game.tick()
        let ambient = game.ambient
        Self.shownAmbient = ambient

        guard size.width > 0, size.height > 0 else { return }
        let key = Self.key(for: game.activity) + "|" + game.heroLook.rawValue + (game.injured ? "|blessé" : "")
            + (Self.isDaytime ? "|jour" : "|nuit") + (sleepsAtCamp ? "|dort" : "")
            + "|" + (game.visitor?.id ?? "")
        if key != modeKey, currentTime < victoryUntil {
            // Donjon terminé : le héros savoure sa victoire avant de reprendre la route.
            return
        }
        if key != modeKey {
            modeKey = key
            weatherKey = ambient.weather
            rebuild()
        } else if game.activeCompanion != shownCompanion {
            // Compagnon changé au camp : il prend sa place sans attendre.
            layoutCompanion(animation: companionPose)
        } else if ambient.weather != weatherKey {
            // Le temps tourne : seule la météo se redessine, sans interrompre ce qui se joue.
            weatherKey = ambient.weather
            buildWeather()
        }
        animate(dt)
    }

    private static func key(for activity: Activity) -> String {
        switch activity {
        case .resting: "rest"
        case .shopping: "shop"
        case .tavern: "tavern"
        case .traveling(let trip): "trip:\(trip.start)"
        case .exploring(let run): "run:\(run.dungeon):\(run.roomIndex)"
        case .roaming(let roam): "roam:\(roam.start)"
        }
    }

    // MARK: - Météo et visiteurs

    /// Le héros est-il dehors ? Sous terre et à la taverne, il ne pleut pas.
    private var isOutdoors: Bool {
        switch game.activity {
        case .resting, .shopping, .traveling, .roaming: true
        case .tavern: UIImage(named: "scene_taverne") == nil   // décor provisoire : la place du village
        case .exploring(let run): Dungeon.all[run.dungeon].style == .forest
        }
    }

    private static let dropTexture: SKTexture = {
        let size = CGSize(width: 2, height: 14)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(white: 1, alpha: 0.9).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }()

    private static let flakeTexture: SKTexture = {
        let size = CGSize(width: 3, height: 3)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }()

    /// Pluie, neige, brume, éclairs et pénombre de la nuit, par-dessus le décor quand le héros est dehors.
    private func buildWeather() {
        weatherLayer.removeAllChildren()
        weatherLayer.removeAllActions()
        guard isOutdoors else { return }
        let ambient = game.ambient
        let full = CGRect(x: 0, y: 0, width: size.width, height: size.height)

        // La nuit : un voile bleu sombre. Le camp a déjà sa propre peinture de nuit.
        var isCamp = false
        if case .resting = game.activity { isCamp = true }
        if ambient.night, !isCamp {
            let dusk = SKSpriteNode(color: UIColor(red: 0.03, green: 0.06, blue: 0.22, alpha: 1), size: full.size)
            dusk.anchorPoint = .zero
            dusk.alpha = 0.42
            dusk.zPosition = -1
            weatherLayer.addChild(dusk)
        }

        switch ambient.weather {
        case .clear:
            break
        case .cloudy:
            // Un ciel bouché : la lumière baisse, sans rien qui tombe.
            let gloom = SKSpriteNode(color: UIColor(red: 0.16, green: 0.19, blue: 0.26, alpha: 1), size: full.size)
            gloom.anchorPoint = .zero
            gloom.alpha = 0.16
            gloom.zPosition = -0.5
            weatherLayer.addChild(gloom)
        case .snow:
            let pale = SKSpriteNode(color: UIColor(red: 0.72, green: 0.78, blue: 0.88, alpha: 1), size: full.size)
            pale.anchorPoint = .zero
            pale.alpha = 0.14
            pale.zPosition = -0.5
            weatherLayer.addChild(pale)
            // Des flocons carrés, lents, qui dérivent de travers.
            let snow = SKEmitterNode()
            snow.particleTexture = Self.flakeTexture
            snow.particleBirthRate = 70
            snow.particleLifetime = 9
            snow.particleSpeed = 110
            snow.particleSpeedRange = 50
            snow.emissionAngle = -.pi / 2 - 0.25
            snow.emissionAngleRange = 0.5
            snow.xAcceleration = -6
            snow.particleAlpha = 0.85
            snow.particleAlphaRange = 0.3
            snow.particleScale = 1
            snow.particleScaleRange = 0.8
            snow.position = CGPoint(x: size.width * 0.6, y: size.height + 10)
            snow.particlePositionRange = CGVector(dx: size.width * 1.7, dy: 0)
            snow.advanceSimulationTime(9)
            weatherLayer.addChild(snow)
        case .fog:
            // Deux nappes pâles qui dérivent lentement en sens contraire.
            for (index, alpha) in [0.20, 0.14].enumerated() {
                let veil = SKSpriteNode(texture: Self.glowTexture,
                                        size: CGSize(width: size.width * 2.2, height: size.height * 0.75))
                veil.color = UIColor(white: 0.86, alpha: 1)
                veil.colorBlendFactor = 1
                veil.alpha = alpha
                veil.position = CGPoint(x: size.width * (index == 0 ? 0.3 : 0.8), y: feetY + size.height * 0.16)
                let drift = size.width * 0.25 * (index == 0 ? 1 : -1)
                veil.run(.repeatForever(.sequence([.moveBy(x: drift, y: 0, duration: 14),
                                                   .moveBy(x: -drift, y: 0, duration: 14)])))
                weatherLayer.addChild(veil)
            }
            let haze = SKSpriteNode(color: UIColor(white: 0.8, alpha: 1), size: full.size)
            haze.anchorPoint = .zero
            haze.alpha = 0.12
            weatherLayer.addChild(haze)
        case .rain, .storm:
            let storm = ambient.weather == .storm
            // Le ciel se couvre.
            let gloom = SKSpriteNode(color: UIColor(red: 0.10, green: 0.14, blue: 0.22, alpha: 1), size: full.size)
            gloom.anchorPoint = .zero
            gloom.alpha = storm ? 0.34 : 0.2
            gloom.zPosition = -0.5
            weatherLayer.addChild(gloom)

            let rain = SKEmitterNode()
            rain.particleTexture = Self.dropTexture
            rain.particleBirthRate = storm ? 420 : 190
            rain.particleLifetime = 1.1
            rain.particleSpeed = storm ? 1_050 : 780
            rain.particleSpeedRange = 160
            rain.emissionAngle = -.pi / 2 - (storm ? 0.30 : 0.14)
            rain.particleRotation = storm ? -0.30 : -0.14
            rain.particleAlpha = storm ? 0.5 : 0.36
            rain.particleAlphaRange = 0.2
            rain.particleScale = 0.9
            rain.particleScaleRange = 0.5
            rain.particleColor = UIColor(red: 0.78, green: 0.88, blue: 1, alpha: 1)
            rain.particleColorBlendFactor = 1
            rain.position = CGPoint(x: size.width * 0.6, y: size.height + 20)
            rain.particlePositionRange = CGVector(dx: size.width * 1.6, dy: 0)
            rain.advanceSimulationTime(1.5)
            weatherLayer.addChild(rain)

            if storm {
                // Un éclair de temps en temps : la scène blanchit un instant.
                let bolt = SKSpriteNode(color: .white, size: full.size)
                bolt.anchorPoint = .zero
                bolt.alpha = 0
                bolt.zPosition = 1
                weatherLayer.addChild(bolt)
                bolt.run(.repeatForever(.sequence([
                    .wait(forDuration: 7, withRange: 8),
                    .fadeAlpha(to: 0.55, duration: 0.04), .fadeAlpha(to: 0.1, duration: 0.08),
                    .fadeAlpha(to: 0.4, duration: 0.04), .fadeOut(withDuration: 0.35),
                ])))
            }
        }
    }

    /// Le visiteur du camp se réchauffe derrière le feu, une bulle au-dessus de la tête.
    /// L'animal égaré prend l'apparence du compagnon qu'il peut devenir.
    private func buildVisitor() {
        guard case .resting = game.activity, let visit = game.visitor else { return }
        // Juste derrière le feu, un peu à droite : il s'y réchauffe sans cacher les flammes.
        // Quand la marmite est installée, il se décale pour ne pas disparaître derrière le trépied.
        let aside: CGFloat = game.campLevel >= 3 ? 58 : 32
        let spot = CGPoint(x: min(campFire.x + aside * zoom, playWidth - 50), y: feetY + 6)
        var top = spot.y + 70 * zoom
        var figure: SKSpriteNode?
        switch visit.kind {
        case .merchant:
            let merchant = npc("merchant_idle_1")
            merchant.xScale = -1
            merchant.run(.repeatForever(.sequence([
                .repeat(.animate(with: (1...4).map { Self.texture("merchant_idle_\($0)") }, timePerFrame: 0.45), count: 3),
                .animate(with: (1...4).map { Self.texture("merchant_wave_\($0)") }, timePerFrame: 0.22),
            ])))
            figure = merchant
        case .minstrel:
            // Le barde de la taverne, luth en main (dessiné tourné vers la droite).
            guard UIImage(named: "npc_bard_play_1") != nil else { break }
            let bard = npc("npc_bard_play_1")
            bard.xScale = -1
            bard.run(.repeatForever(.animate(with: Self.npcFrames("npc_bard_play", 8), timePerFrame: 0.18)))
            figure = bard
        case .wounded, .gambler, .pilgrim, .herbalist:
            // Sprites PixelLab installés par `Art/import_visitors.py`, dessinés tournés vers le héros.
            let name = "npc_\(visit.kind.rawValue)_idle"
            guard UIImage(named: "\(name)_1") != nil else { break }
            let visitor = npc("\(name)_1")
            visitor.run(.repeatForever(.animate(with: Self.npcFrames(name, 4), timePerFrame: 0.3)))
            figure = visitor
        case .stray:
            guard let beast = game.strayCompanion(for: visit), UIImage(named: beast.frames("sit")[0]) != nil else { break }
            let frames = beast.frames("sit").map { Self.texture($0) }
            let animal = SKSpriteNode(texture: frames[0])
            // Même taille que le compagnon qui suit le héros ; ses images regardent déjà vers la gauche.
            let base = Self.texture(beast.frames("walk")[0]).size()
            let scale = Self.heroScale * zoom * 0.72
            animal.size = CGSize(width: base.width * scale, height: base.height * scale)
            animal.anchorPoint = CGPoint(x: 0.5, y: 0)
            animal.run(.repeatForever(.animate(with: frames, timePerFrame: 0.35)))
            figure = animal
        }
        if let figure {
            figure.position = spot
            // Aucun visiteur ne doit être coupé par le bord : les plus larges (marchand, joueur de dés,
            // ménestrel) reculent d'autant.
            figure.position.x = min(spot.x, playWidth - figure.size.width * 0.5 - 6)
            figure.zPosition = 1.5
            props.addChild(figure)
            // Le canevas des animaux garde du vide au-dessus d'eux : la bulle descend d'autant.
            top = spot.y + figure.size.height * (visit.kind == .stray ? 0.72 : 1) + 16
        }
        // Une bulle qui sautille : quelqu'un attend une réponse.
        let bubble = SKShapeNode(circleOfRadius: 17)
        bubble.fillColor = UIColor(white: 0.08, alpha: 0.85)
        bubble.strokeColor = UIColor(red: 1, green: 0.82, blue: 0.3, alpha: 1)
        bubble.lineWidth = 2
        bubble.position = CGPoint(x: figure?.position.x ?? spot.x, y: top)
        bubble.zPosition = 5
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        if let symbol = UIImage(systemName: visit.kind.symbol, withConfiguration: configuration)?
            .withTintColor(UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 1), renderingMode: .alwaysOriginal) {
            // Redessiné dans une image : passé tel quel, un symbole perd sa couleur dans SpriteKit.
            let image = UIGraphicsImageRenderer(size: symbol.size).image { _ in symbol.draw(at: .zero) }
            let icon = SKSpriteNode(texture: SKTexture(image: image))
            icon.size = CGSize(width: image.size.width * 20 / max(image.size.height, 1), height: 20)
            bubble.addChild(icon)
        }
        bubble.run(.repeatForever(.sequence([.moveBy(x: 0, y: 6, duration: 0.5), .moveBy(x: 0, y: -6, duration: 0.5)])))
        props.addChild(bubble)
    }

    private func rebuild() {
        victoryUntil = 0
        endSpecial()
        refreshAura()
        // Au camp, à la boutique ou à la taverne, l'aura se fait oublier : elle ne brûle qu'en route et au combat.
        switch game.activity {
        case .resting, .shopping, .tavern: aura.isHidden = true
        default: aura.isHidden = auraName == nil
        }
        props.removeAllChildren()
        props.removeAllActions()   // les braises du camp sont lancées par ce nœud
        hero.removeAction(forKey: "bob")
        encounter = nil
        encounterShown = false
        encounterShadow.isHidden = true
        hpBar.isHidden = true
        attackTimer = 0
        blows = []
        blowIndex = 0
        facing = 1


        switch game.activity {
        case .resting:
            setBackdrop(backdrop(Self.campImage, floor: 0.86, portraitFloor: 0.86, scrolls: false))
            if game.injured {
                // Blessé : un voile gris-vert sur le camp, le temps de guérir.
                sky.color = UIColor(red: 0.62, green: 0.76, blue: 0.74, alpha: 1)
                sky.colorBlendFactor = 0.4
            }
            if isPortrait {
                heroSlot = scenePoint(0.42, 0).x / playWidth
                buildCamp(fire: (0.768, 0.872), fireflies: (0.80, 0.48))
            } else {
                heroSlot = scenePoint(0.40, 0).x / playWidth
                buildCamp(fire: (0.606, 0.845), fireflies: (0.84, 0.62))
            }
            // À bout (énergie, PV ou moral), il s'endort au coin du feu.
            if sleepsAtCamp {
                hero.run(.repeatForever(.animate(with: heroFrames("sleep"), timePerFrame: 0.7)), withKey: "anim")
                break
            }
            // Au coin du feu : il se repose un moment, puis s'occupe (lecture, flèches, épée).
            let rest = heroFrames("rest")
            let half = max(rest.count / 2, 1)
            let calm = Array(rest.prefix(half)), busy = Array(rest.suffix(rest.count - half))
            let loop = busy.isEmpty ? [SKAction.animate(with: calm, timePerFrame: 1.2)] : [
                .repeat(.animate(with: calm, timePerFrame: 1.1), count: 4),
                .repeat(.animate(with: busy, timePerFrame: 1.1), count: 4),
            ]
            hero.run(.repeatForever(.sequence(loop)), withKey: "anim")
        case .shopping:
            setBackdrop(backdrop("scene_marche", floor: 0.86, portraitFloor: 0.87, scrolls: false))
            heroSlot = scenePoint(isPortrait ? 0.30 : 0.36, 0).x / playWidth
            buildShop()
            // Devant l'étal, il reste debout (et non en pleine foulée).
            hero.run(.repeatForever(.animate(with: heroFrames("idle"), timePerFrame: 0.2)), withKey: "anim")
        case .tavern(let visit):
            setBackdrop(backdrop(Self.tavernImage, floor: 0.83, portraitFloor: 0.83, scrolls: false))
            if UIImage(named: "scene_taverne") == nil {
                // Provisoire, en attendant une vraie salle de taverne : le village à la nuit tombée,
                // baigné de la lueur chaude des fenêtres.
                for node in [sky, sideSky] {
                    node.color = UIColor(red: 1.0, green: 0.62, blue: 0.36, alpha: 1)
                    node.colorBlendFactor = 0.5
                }
            }
            heroSlot = scenePoint(isPortrait ? 0.38 : 0.32, 0).x / playWidth
            // Debout au comptoir, chope en main : une bonne gorgée de temps en temps.
            let drink = heroFrames("tavern")
            hero.texture = drink[0]
            hero.run(.repeatForever(.sequence([.animate(with: drink, timePerFrame: 0.16),
                                               .wait(forDuration: 2.5, withRange: 1.5)])), withKey: "anim")
            buildTavern(bardPlaying: visit.sang)
        case .traveling(let trip):
            setBackdrop(Backdrop(image: "scene_trajet", floor: 0.84, scrolls: true))
            if trip.to == .camp {
                facing = -1
                heroSlot = 0.62
            } else {
                heroSlot = 0.3
            }
            let fleeing = trip.reason == .fled
            hero.run(.repeatForever(.animate(with: heroFrames(fleeing ? "flee" : "walk"), timePerFrame: fleeing ? 0.1 : 0.16)),
                     withKey: "anim")
            bob(fast: fleeing)
        case .roaming:
            // Une scène « champs et villages » viendra ; en attendant, le chemin de campagne.
            setBackdrop(backdrop(UIImage(named: "scene_campagne") != nil ? "scene_campagne" : "scene_trajet",
                                 floor: 0.84, portraitFloor: 0.86, scrolls: true))
            if UIImage(named: "scene_campagne") == nil {
                // Provisoire : le chemin de forêt baigné d'une lumière dorée de fin d'après-midi.
                for case let tile as SKSpriteNode in backdrop.children {
                    tile.color = UIColor(red: 1.0, green: 0.82, blue: 0.5, alpha: 1)
                    tile.colorBlendFactor = 0.45
                }
            }
            heroSlot = 0.35
            hero.run(.repeatForever(.animate(with: heroFrames("walk"), timePerFrame: 0.2)), withKey: "anim")
            bob(fast: false)
        case .exploring(let run):
            setBackdrop(backdrop(for: Dungeon.all[run.dungeon].style))
            heroSlot = 0.22
            hero.run(.repeatForever(.animate(with: heroFrames("walk"), timePerFrame: 0.16)), withKey: "anim")
            bob(fast: false)
        }
        makeRoomForCompanion()
        switch game.activity {
        case .resting: Audio.shared.play(music: "camp")
        case .shopping: Audio.shared.play(music: "shop")
        case .tavern: Audio.shared.play(music: "tavern")
        case .traveling, .roaming: Audio.shared.play(music: "road")
        case .exploring(let run): Audio.shared.play(music: run.room.kind == .boss ? "boss" : "dungeon")
        }

        buildWeather()
        buildVisitor()

        endSpecial()
        let frame = Self.texture(game.heroLook.frames("walk")[0]).size()
        let scale = Self.heroScale * zoom
        hero.size = CGSize(width: frame.width * scale, height: frame.height * scale)
        heroShadow.setScale(zoom)
        hero.xScale = facing
        hero.position = heroPosition
        heroShadow.position = heroPosition
        let companionAnim: String
        switch game.activity {
        case .traveling, .roaming, .exploring: companionAnim = "walk"
        case .resting: companionAnim = sleepsAtCamp ? "sleep" : "sit"   // dort avec le héros, sinon assis au feu
        default: companionAnim = "idle"                                  // boutique, taverne : debout
        }
        companionPose = companionAnim
        layoutCompanion(animation: companionAnim)
        placeScrolling()
    }

    /// Largeur à l'écran du compagnon actif, ou nil s'il n'y en a pas (ou pas encore de sprites).
    private var companionWidth: CGFloat? {
        guard let kind = game.activeCompanion, UIImage(named: kind.frames("walk")[0]) != nil else { return nil }
        // Largeur de l'animal lui-même : son cadre est bien plus large, pour le bond de l'attaque.
        let pixels = CompanionArt.bodyWidth[kind.rawValue] ?? Self.texture(kind.frames("walk")[0]).size().width
        return pixels * Self.heroScale * zoom * 0.72
    }

    /// Écart entre le milieu du héros et celui du compagnon qui le suit.
    /// Le cadre du héros est bien plus large que lui : on compte son corps (une cinquantaine
    /// de pixels), pas son sprite, pour que l'animal se tienne juste derrière sans passer dessous.
    private func companionGap(_ width: CGFloat) -> CGFloat { 22 * Self.heroScale * zoom + width * 0.5 }

    /// Le héros se tient près du bord, surtout en portrait : avec un compagnon dans son dos, il
    /// avance d'un pas pour que l'animal tienne à l'écran au lieu de se cacher derrière lui.
    private func makeRoomForCompanion() {
        guard let width = companionWidth else { return }
        // À la taverne et à la boutique rien ne bouge : il peut s'avancer davantage qu'en donjon,
        // où il faut garder la distance avec le monstre.
        let limit: CGFloat
        switch game.activity {
        // Le compagnon passe au premier plan : un petit pas suffit, sans coller la serveuse ou le marchand.
        case .tavern: limit = 36
        case .shopping: limit = 22
        // En donjon, l'écart avec le monstre passe avant tout : le héros n'avance que d'un pas, et
        // l'animal se glisse en partie derrière lui (en portrait, tout ne tient pas en entier).
        case .exploring: limit = 20
        case .roaming: limit = 46
        default: return
        }
        let wanted = heroPosition.x - facing * companionGap(width)
        let half = width * 0.5
        let shift = facing > 0 ? half - wanted : wanted - (size.width - half)
        if shift > 0 { heroSlot += facing * min(shift, limit * zoom) / playWidth }
    }

    /// Place et anime le compagnon derrière le héros, ou le cache s'il n'y en a pas
    /// (ou tant que ses sprites ne sont pas installés).
    private func layoutCompanion(animation: String) {
        companion.removeAction(forKey: "anim")
        companion.removeAction(forKey: "bob")
        companion.removeAction(forKey: "strike")
        companion.yScale = 1
        shownCompanion = game.activeCompanion
        guard let kind = game.activeCompanion,
              UIImage(named: kind.frames("walk")[0]) != nil else {
            companion.isHidden = true
            return
        }
        companion.isHidden = false
        let moving = animation == "walk"
        // Repli sur idle si l'animation demandée n'est pas encore installée.
        let anim = UIImage(named: kind.frames(animation)[0]) != nil ? animation : "idle"
        let frames = kind.frames(anim).map(Self.texture)
        let settled = anim == "sit" || anim == "sleep"
        if settled, let last = frames.last {
            // Assis ou endormi : une seule pose, la dernière (posture installée). Les images
            // d'avant le montrent encore en train de s'installer et le feraient se relever
            // et glisser à chaque boucle. Il respire, c'est tout.
            companion.texture = last
            let slow = anim == "sleep"
            companion.run(.repeatForever(.sequence([
                .scaleY(to: slow ? 1.035 : 1.02, duration: slow ? 1.3 : 0.9),
                .scaleY(to: 1, duration: slow ? 1.3 : 0.9),
            ])), withKey: "anim")
        } else {
            companion.run(.repeatForever(.animate(with: frames, timePerFrame: moving ? 0.12 : 0.3)), withKey: "anim")
        }

        let base = Self.texture(kind.frames("walk")[0]).size()
        let scale = Self.heroScale * zoom * 0.72   // un peu plus petit que le héros
        companion.size = CGSize(width: base.width * scale, height: base.height * scale)
        // Les compagnons sont dessinés tournés vers la gauche, le héros vers la droite :
        // retournés, ils regardent dans le même sens que lui.
        companion.xScale = -facing
        // Derrière le héros, du côté opposé à celui qu'il regarde, sans sortir de l'écran.
        // Au camp, cela le met côté tente, tourné vers le feu.
        var body = companionWidth ?? companion.size.width
        // Couché, il prend plus de place que debout : on s'écarte d'autant du héros.
        if settled, let rest = CompanionArt.restWidth[kind.rawValue] {
            body = max(body, rest * Self.heroScale * zoom * 0.72)
        }
        let half = body * 0.5
        // Assis au camp, le héros est plus large que debout : l'animal s'écarte un peu plus.
        var gap = companionGap(body)
        if case .resting = game.activity { gap += 12 * zoom }
        // Dans le dos du héros mais au premier plan, un demi-pas vers nous : là où ils se
        // recouvrent, c'est l'animal qu'on voit, jamais l'inverse.
        companion.zPosition = hero.zPosition + 0.5
        companion.position = CGPoint(x: min(max(heroPosition.x - facing * gap, half), size.width - half), y: feetY - 4 * zoom)
        if moving {
            let lift = max(companion.size.height * 0.02, 1).rounded()
            companion.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: lift, duration: 0.16), .moveBy(x: 0, y: -lift, duration: 0.16),
            ])), withKey: "bob")
        }
    }

    private func heroFrames(_ animation: String) -> [SKTexture] {
        game.heroLook.frames(animation).map(Self.texture)
    }

    /// Petit rebond à chaque pas : il marque le rythme de la marche.
    private func bob(fast: Bool) {
        let step = fast ? 0.1 : 0.16
        let lift = max(hero.size.height * 0.025, 1).rounded()
        hero.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: lift, duration: step), .moveBy(x: 0, y: -lift, duration: step),
        ])), withKey: "bob")
    }

    /// Fige le héros sur une pose.
    private func pose(_ texture: SKTexture) {
        hero.removeAction(forKey: "anim")
        hero.texture = texture
    }

    /// Le camp peint : on y ajoute le feu animé dans le cercle de pierres et des lucioles.
    /// `fire` : pied du feu dans la scène ; `fireflies` : centre de l'essaim, près du grand arbre.
    /// Le camp s'étoffe à chaque amélioration du feu : un aménagement par niveau, posé autour des
    /// flammes (`Art/import_camp.py`). Décalages en points depuis le feu, avant zoom.
    private func buildCampProps() {
        let layout: [(level: Int, dx: CGFloat, dy: CGFloat, z: CGFloat, scale: CGFloat)] = [
            (1, 46, 6, 2.8, 0.55),     // tas de bûches, à droite du feu
            (2, -56, 24, 1.4, 0.68),   // râtelier d'armes, en retrait entre le héros et le feu
            (3, 0, 0, 3.3, 0.6),       // marmite sur son trépied, au-dessus des flammes
            (4, 72, 28, 1.2, 0.72),    // lanterne sur son poteau, au fond à droite
            (5, 8, 36, 1.0, 0.66),     // trophées, derrière le feu
        ]
        for item in layout where item.level <= game.campLevel {
            let name = "camp_prop_\(item.level)"
            guard UIImage(named: name) != nil else { continue }
            let texture = Self.texture(name)
            let grain = Self.heroScale * zoom * item.scale
            let node = SKSpriteNode(texture: texture)
            node.size = CGSize(width: texture.size().width * grain, height: texture.size().height * grain)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            let x = campFire.x + item.dx * zoom
            node.position = CGPoint(x: min(x, size.width - node.size.width * 0.5 - 2), y: campFire.y + item.dy * zoom - 8 * zoom)
            node.zPosition = item.z
            props.addChild(node)
        }
    }

    private func buildCamp(fire spot: (CGFloat, CGFloat), fireflies swarm: (CGFloat, CGFloat)) {
        let firePos = scenePoint(spot.0, spot.1)
        campFire = firePos

        // Feu en pixel art (PixelLab, `Art/import_pixellab.py`) : des bûches qui flambent,
        // posées dans le cercle de pierres peint.
        let flame = Self.sprite("fx_campfire_1", height: 56 * zoom)
        flame.position = CGPoint(x: firePos.x, y: firePos.y - 6 * zoom)
        flame.zPosition = 3
        flame.run(.repeatForever(.animate(with: Self.npcFrames("fx_campfire", 8), timePerFrame: 0.1)))
        props.addChild(flame)
        let tree = SKNode()
        tree.position = scenePoint(swarm.0, swarm.1)

        // Halo qui vacille, par paliers, comme les flammes.
        let glow = SKSpriteNode(texture: Self.glowTexture, size: CGSize(width: 150, height: 150))
        glow.blendMode = .add
        glow.position = CGPoint(x: firePos.x, y: firePos.y + 22)
        glow.zPosition = 3.5
        glow.run(.repeatForever(.sequence([
            .wait(forDuration: 0.16), .fadeAlpha(to: 0.82, duration: 0),
            .wait(forDuration: 0.16), .fadeAlpha(to: 1, duration: 0),
            .wait(forDuration: 0.32), .fadeAlpha(to: 0.9, duration: 0),
        ])))
        props.addChild(glow)

        // Braises qui montent du feu.
        let ember = SKAction.run { [weak self] in
            guard let self else { return }
            let spark = SKSpriteNode(color: UIColor(red: 1, green: 0.72, blue: 0.3, alpha: 1),
                                     size: CGSize(width: Self.pixel, height: Self.pixel))
            spark.position = CGPoint(x: firePos.x + .random(in: -8...8), y: firePos.y + 36)
            spark.zPosition = 4
            self.props.addChild(spark)
            spark.run(.sequence([
                .group([.moveBy(x: .random(in: -14...14), y: .random(in: 34...60), duration: 1.4),
                        .sequence([.wait(forDuration: 0.8), .fadeOut(withDuration: 0.6)])]),
                .removeFromParent(),
            ]))
        }
        props.run(.repeatForever(.sequence([ember, .wait(forDuration: 0.45, withRange: 0.4)])), withKey: "embers")
        buildCampProps()

        // Lucioles autour du grand arbre.
        for index in 0..<7 {
            let fly = SKSpriteNode(color: UIColor(red: 0.82, green: 1, blue: 0.5, alpha: 1),
                                   size: CGSize(width: Self.pixel, height: Self.pixel))
            fly.position = CGPoint(x: tree.position.x + .random(in: -60...60), y: tree.position.y + .random(in: 0...90))
            fly.zPosition = 3
            fly.alpha = 0
            let drift = SKAction.sequence([
                .moveBy(x: .random(in: -12...12), y: .random(in: -8...8), duration: 2.4),
                .moveBy(x: .random(in: -12...12), y: .random(in: -8...8), duration: 2.4),
            ])
            fly.run(.repeatForever(.sequence([drift, drift.reversed()])))
            fly.run(.sequence([.wait(forDuration: Double(index) * 0.5), .repeatForever(.sequence([
                .fadeAlpha(to: 0.95, duration: 0.5), .wait(forDuration: 1.1),
                .fadeOut(withDuration: 0.7), .wait(forDuration: .random(in: 0.6...2.2)),
            ]))]))
            props.addChild(fly)
        }

        // Le sac de couchage, une fois acheté : déroulé au sol près de la tente.
        if game.hasBedroll {
            let bedroll = Self.sprite("sc_bedroll", height: 26 * zoom)
            bedroll.anchorPoint = CGPoint(x: 0.5, y: 0)
            bedroll.position = CGPoint(x: scenePoint(isPortrait ? 0.26 : 0.24, 0).x, y: feetY)
            bedroll.zPosition = 2
            props.addChild(bedroll)
        }
    }

    /// Le marché peint : le marchand attend devant son étal.
    /// Personnage non joueur en pixel art, au même grain que le héros, ancré en bas au centre.
    private func npc(_ name: String) -> SKSpriteNode {
        let texture = Self.texture(name)
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: texture.size().width * Self.heroScale * zoom,
                           height: texture.size().height * Self.heroScale * zoom)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        let shadow = SKShapeNode(ellipseIn: CGRect(x: -18, y: -3, width: 36, height: 7))
        shadow.fillColor = UIColor(white: 0, alpha: 0.3)
        shadow.strokeColor = .clear
        shadow.zPosition = -0.1
        node.addChild(shadow)
        return node
    }

    private static func npcFrames(_ name: String, _ count: Int) -> [SKTexture] {
        (1...count).map { texture("\(name)_\($0)") }
    }

    /// La taverne : la serveuse passe avec son plateau, et le barde joue si on le lui a demandé.
    private func buildTavern(bardPlaying: Bool) {
        let barmaid = npc("npc_barmaid_idle_1")
        barmaid.xScale = -1   // dessinée tournée vers la droite : elle regarde le héros
        // Placés dans la partie visible, comme les monstres : le décor déborde de l'écran en portrait.
        // Bien à droite du héros pour ne pas se chevaucher avec lui.
        barmaid.position = CGPoint(x: playWidth * (isPortrait ? 0.68 : 0.70), y: feetY)
        barmaid.zPosition = 1.5
        barmaid.run(.repeatForever(.animate(with: Self.npcFrames("npc_barmaid_idle", 4), timePerFrame: 0.4)))
        props.addChild(barmaid)
        self.barmaid = barmaid
        if bardPlaying { bardArrives(walking: false) }
    }

    private weak var bard: SKSpriteNode?

    /// Le barde entre par la droite, se place et joue du luth jusqu'à la fin de la soirée.
    private func bardArrives(walking: Bool) {
        guard bard == nil else { return }
        let bard = npc("npc_bard_play_1")
        bard.xScale = -1
        let spot = CGPoint(x: playWidth * 0.86, y: feetY)
        bard.zPosition = 1.4
        let play = SKAction.repeatForever(.animate(with: Self.npcFrames("npc_bard_play", 8), timePerFrame: 0.14))
        if walking {
            bard.position = CGPoint(x: size.width + bard.size.width, y: spot.y)
            let distance = bard.position.x - spot.x
            bard.run(.sequence([
                .group([.repeat(.animate(with: Self.npcFrames("npc_bard_walk", 8), timePerFrame: 0.12),
                                count: max(Int(distance / 90), 1)),
                        .moveTo(x: spot.x, duration: TimeInterval(distance / 90) * 0.96)]),
                play,
            ]))
        } else {
            bard.position = spot
            bard.run(play)
        }
        props.addChild(bard)
        self.bard = bard
    }

    private func buildShop() {
        let merchant = npc("merchant_idle_1")
        merchant.xScale = -1   // tourné vers le héros, qui arrive par la gauche
        let idle = (1...4).map { Self.texture("merchant_idle_\($0)") }
        let wave = (1...4).map { Self.texture("merchant_wave_\($0)") }
        // Il patiente, et salue de la main de temps en temps.
        merchant.run(.repeatForever(.sequence([
            .repeat(.animate(with: idle, timePerFrame: 0.45), count: 3),
            .animate(with: wave, timePerFrame: 0.22),
        ])), withKey: "anim")
        merchant.position = isPortrait ? scenePoint(0.62, 0.87) : scenePoint(0.6, 0.86)
        merchant.zPosition = 1.5
        props.addChild(merchant)
        self.merchant = merchant
    }

    private func animate(_ dt: TimeInterval) {
        switch game.activity {
        case .traveling:
            scroll += facing * Self.walkSpeed * dt
        case .roaming:
            // On flâne : on avance plus lentement qu'en voyage.
            scroll += Self.walkSpeed * 0.6 * dt
        case .exploring(let run):
            let span = run.roomEnd - run.roomStart
            let part = span > 0 ? (game.clock - run.roomStart) / span : 1
            if part < GameState.walkShare {
                scroll += Self.walkSpeed * dt
            } else {
                if !encounterShown { showEncounter(run.room) }
                if run.room.kind == .monster || run.room.kind == .boss {
                    // Chaque coup arrive à son heure : la vie ne baisse qu'à l'impact.
                    let fight = (part - GameState.walkShare) / (1 - GameState.walkShare)
                    if blows.isEmpty { blows = game.blows(in: run) }
                    var due: [GameState.Blow] = []
                    while blowIndex < blows.count, blows[blowIndex].at <= fight {
                        due.append(blows[blowIndex])
                        blowIndex += 1
                    }
                    // Après une absence, on rattrape sans rejouer chaque coup.
                    for blow in due.dropLast() { hpFill.xScale = CGFloat(max(blow.foeLeft, 0.02)) }
                    if let blow = due.last { strike(blow) }
                }
            }
        case .resting:
            restTimer += dt
            feelingTimer += dt
            if restTimer >= 1.2 {
                restTimer = 0
                if game.isRecovering { floatText("+", color: .systemGreen, size: 20, over: heroPosition, height: 84) }
            }
            if feelingTimer >= 9 {
                feelingTimer = 0
                showFeeling()
            }
        case .tavern:
            feelingTimer += dt
            if feelingTimer >= 7 {
                feelingTimer = 0
                // Il trinque, fredonne ou rit avec les habitués.
                let moods: [(String, UIColor)] = [("mug.fill", .systemOrange), ("music.note", .systemGreen),
                                                  ("face.smiling.inverse", .systemYellow)]
                let pick = moods.randomElement()!
                react(pick.0, color: pick.1)
            }
        case .shopping:
            break
        }
        placeScrolling()
    }

    // MARK: - Rencontres

    private func showEncounter(_ room: Room) {
        encounterShown = true
        heroBlows = 0
        // Le héros s'arrête : son compagnon aussi, au lieu de marcher sur place.
        if !companion.isHidden, room.kind == .monster || room.kind == .boss {
            companionPose = "idle"
            layoutCompanion(animation: "idle")
        }
        pose(heroFrames(room.kind == .monster || room.kind == .boss ? "attack" : "idle")[0])
        // Arrivé sur place, il s'arrête : plus de balancement de marche.
        hero.removeAction(forKey: "bob")
        hero.position = heroPosition

        let look = Self.looks[room.sprite] ?? (80, false, 0)
        let creature = room.kind == .monster || room.kind == .boss
        let elite = room.elite == true
        let bodyHeight = look.height * Self.actorScale * zoom * (elite ? 1.22 : 1)
        let node = creature ? Self.creature(room.sprite, height: bodyHeight) : Self.sprite(room.sprite, height: bodyHeight)
        let still = Self.texture(room.sprite).size()
        encounterBody = creature ? CGSize(width: still.width / max(still.height, 1) * bodyHeight, height: bodyHeight) : node.size
        node.xScale = look.flip ? -1 : 1
        node.zPosition = 3
        encounterLift = look.lift * Self.actorScale * zoom
        node.position = CGPoint(x: size.width + node.size.width, y: feetY + encounterLift)
        props.addChild(node)
        encounter = node
        encounterSprite = room.sprite
        if !creature {
            // Coffre, piège, autel : posés là, immobiles. Ils n'arrivent pas en glissant.
            node.position.x = encounterPosition.x
            node.alpha = 0
            node.run(.fadeIn(withDuration: 0.2))
            if room.kind == .fountain {
                // Le cristal du sanctuaire flotte et pulse.
                node.run(.repeatForever(.animate(with: Self.npcFrames("shrine", 6), timePerFrame: 0.14)))
            }
        } else {
            // Un boss prend son temps : il entre lentement, et le sol tremble quand il s'arrête.
            let entrance: TimeInterval = room.kind == .boss ? 0.9 : 0.25
            let arrive = SKAction.moveTo(x: encounterPosition.x, duration: entrance)
            arrive.timingMode = .easeOut
            if room.kind == .boss { bossEntrance(after: entrance) }
            // Ce qui vole se balance en l'air ; ce qui marche respire sans quitter le sol.
            let idle: SKAction = look.lift > 0
                ? .sequence([.wait(forDuration: 0.45), .moveBy(x: 0, y: 3, duration: 0),
                             .wait(forDuration: 0.45), .moveBy(x: 0, y: -3, duration: 0)])
                : .sequence([.wait(forDuration: 0.45), .scaleY(to: 1.03, duration: 0),
                             .wait(forDuration: 0.45), .scaleY(to: 1, duration: 0)])
            let frames = Self.creatureFrames(room.sprite, "idle")
            if frames.isEmpty {
                node.run(.sequence([arrive, .repeatForever(idle)]))
            } else {
                // Créature animée : elle respire image par image ; ce qui vole se balance en plus.
                node.run(arrive)
                if look.lift > 0 { node.run(.repeatForever(idle)) }
                idleCreature(node, room.sprite)
            }
        }

        let shadowWidth = min(encounterBody.width * 0.7, 120)
        encounterShadow.path = CGPath(ellipseIn: CGRect(x: -shadowWidth / 2, y: -3, width: shadowWidth, height: 12), transform: nil)
        encounterShadow.position = encounterPosition
        encounterShadow.isHidden = false

        guard room.kind == .monster || room.kind == .boss else { return }
        let boss = room.kind == .boss
        hpFill.color = boss ? .systemPurple : elite ? .systemOrange : .systemRed
        hpFill.xScale = 1
        nameText.attributedText = Self.outlined(boss ? "BOSS · \(room.name)" : elite ? "ÉLITE · \(room.name)" : room.name,
                                                size: 14, color: boss ? .systemYellow : elite ? .systemOrange : .white)
        // Au-dessus du monstre, sans monter sous l'en-tête posé en haut de la scène.
        let barTop = feetY + encounterLift + encounterBody.height + 24
        // La jauge s'arrête avant les boutons de combat, rangés contre le bord droit de la zone libre.
        hpBar.position = CGPoint(x: min(encounterPosition.x, playWidth - 147), y: min(barTop, size.height - 120))
        hpBar.isHidden = false
        if boss {
            showBanner("BOSS !")
            Audio.shared.play("boss")
        }
        if elite {
            showBanner("Élite !")
            Audio.shared.play("elite")
            // Une teinte orangée qui pulse le distingue du monstre ordinaire.
            node.run(.repeatForever(.sequence([
                .colorize(with: .systemOrange, colorBlendFactor: 0.4, duration: 0.6),
                .colorize(withColorBlendFactor: 0.08, duration: 0.6),
            ])), withKey: "elite")
        }
    }

    /// Images d'un effet animé (`Art/import_vfx.py`).
    private static func fxFrames(_ name: String) -> [SKTexture] {
        guard let entry = FXAnims.table[name] else { return [] }
        return (1...entry.count).map { texture("fx_\(name)_\($0)") }
    }

    /// Joue un effet animé une fois, à l'échelle des sprites du héros, puis l'efface.
    /// `sound` : bruitage joué avec l'effet (par défaut celui du même nom, s'il existe) ; "" pour aucun.
    private func playFX(_ name: String, at point: CGPoint, scale: CGFloat = 1, sound: String? = nil) {
        let noise = sound ?? name
        if !noise.isEmpty { Audio.shared.play(noise) }
        guard let entry = FXAnims.table[name] else { return }
        let frames = Self.fxFrames(name)
        let grain = Self.heroScale * zoom * scale
        let size = frames[0].size()
        let node = SKSpriteNode(texture: frames[0], size: CGSize(width: size.width * grain, height: size.height * grain))
        node.anchorPoint = entry.anchor
        node.position = point
        effects.addChild(node)
        let step = 1 / entry.fps
        // Les dernières images s'estompent : certains effets ne finissent pas tout à fait vides.
        node.run(.sequence([.wait(forDuration: step * Double(max(frames.count - 2, 1))), .fadeOut(withDuration: step * 2)]))
        node.run(.sequence([.animate(with: frames, timePerFrame: step), .removeFromParent()]))
    }

    /// Élément de l'arme portée, d'après sa rareté : glace, ombre ou feu. Rien pour une arme commune.
    private var weaponElement: String? {
        switch game.equipped[.weapon]?.rarity {
        case .rare: "ice"
        case .epic: "shadow"
        case .legendary: "fire"
        default: nil
        }
    }

    /// Une arme rare ou mieux entoure le héros d'une aura à son élément, derrière lui.
    private func refreshAura() {
        let wanted = weaponElement.map { "aura_\($0)" }
        guard wanted != auraName else { return }
        auraName = wanted
        aura.removeAllActions()
        guard let wanted, let entry = FXAnims.table[wanted] else { aura.isHidden = true; return }
        let frames = Self.fxFrames(wanted)
        let grain = Self.heroScale * zoom * 0.9
        let size = frames[0].size()
        aura.texture = frames[0]
        aura.size = CGSize(width: size.width * grain, height: size.height * grain)
        aura.anchorPoint = entry.anchor
        // Discrète : le héros doit rester lisible devant.
        aura.alpha = wanted == "aura_ice" ? 0.7 : 0.5
        aura.isHidden = false
        aura.run(.repeatForever(.animate(with: frames, timePerFrame: 1 / entry.fps)))
    }

    /// Entrée d'un boss : la salle s'assombrit pendant qu'il approche, puis tout tremble à son arrêt.
    private func bossEntrance(after delay: TimeInterval) {
        let veil = SKSpriteNode(color: .black, size: CGSize(width: size.width * 2, height: size.height * 2))
        veil.position = CGPoint(x: size.width / 2, y: size.height / 2)
        veil.zPosition = 2.5   // derrière le héros et le boss, devant le décor
        veil.alpha = 0
        addChild(veil)
        veil.run(.sequence([.fadeAlpha(to: 0.45, duration: delay * 0.6), .wait(forDuration: delay * 0.4 + 0.25),
                            .fadeOut(withDuration: 0.5), .removeFromParent()]))
        run(.sequence([.wait(forDuration: delay), .run { [weak self] in self?.shake(strength: 7) }]))
    }

    /// Secousse de l'écran : le décor et ce qui est posé dessus tressautent un instant.
    private func shake(strength: CGFloat) {
        var steps: [SKAction] = []
        var back = CGVector.zero
        for index in 0..<6 {
            let power = strength * (1 - CGFloat(index) / 6)
            let move = CGVector(dx: (index % 2 == 0 ? -1 : 1) * power, dy: .random(in: -power...power) * 0.5)
            steps.append(.moveBy(x: move.dx, y: move.dy, duration: 0.04))
            back.dx -= move.dx
            back.dy -= move.dy
        }
        steps.append(.moveBy(x: back.dx, y: back.dy, duration: 0.04))
        for layer in [backdrop, props] as [SKNode] {
            layer.removeAction(forKey: "shake")
            layer.run(.sequence(steps), withKey: "shake")
        }
        successHaptic.notificationOccurred(.warning)
    }

    /// Le compagnon se jette sur le monstre, mord ou griffe, puis revient à sa place.
    /// Pour le plaisir des yeux : ses bonus sont déjà comptés dans les coups du héros.
    private func companionStrike() {
        guard !companion.isHidden, let kind = game.activeCompanion, encounter != nil,
              companion.action(forKey: "strike") == nil,
              UIImage(named: kind.frames("attack")[0]) != nil else { return }
        let frames = kind.frames("attack").map(Self.texture)
        let home = companion.position.x
        let reach = encounterPosition.x - encounterBody.width * 0.5 - (companionWidth ?? companion.size.width) * 0.45
        guard reach > home + 20 else { return }
        companion.removeAction(forKey: "anim")
        companion.zPosition = hero.zPosition + 0.5   // il passe devant le héros
        let leap = SKAction.moveTo(x: reach, duration: 0.16)
        leap.timingMode = .easeOut
        let bite = CGPoint(x: encounterPosition.x - encounterBody.width * 0.25,
                           y: encounterPosition.y + encounterLift + min(encounterBody.height * 0.4, 40))
        companion.run(.sequence([
            .group([leap, .animate(with: frames, timePerFrame: 0.055)]),
            .run { [weak self] in self?.playFX("hit", at: bite, scale: 0.45, sound: "bite") },
            .wait(forDuration: 0.08),
            .moveTo(x: home, duration: 0.2),
            .run { [weak self] in
                guard let self else { return }
                self.layoutCompanion(animation: self.companionPose)
            },
        ]), withKey: "strike")
    }

    /// Boucle de respiration d'une créature animée.
    private func idleCreature(_ node: SKSpriteNode, _ sprite: String) {
        let frames = Self.creatureFrames(sprite, "idle")
        guard !frames.isEmpty else { return }
        node.run(.repeatForever(.animate(with: frames, timePerFrame: 0.22)), withKey: "pose")
    }

    /// Joue un coup : celui du héros (animation de classe), ou celui du monstre qui bondit.
    /// Les dégâts s'affichent à l'impact, et la jauge ne bouge qu'à ce moment-là.
    private func strike(_ blow: GameState.Blow) {
        guard let target = encounter else { return }
        if blow.byHero {
            let impact = attack()
            heroBlows += 1
            // Un coup sur deux, le compagnon suit l'assaut du héros.
            if heroBlows % 2 == 0 {
                run(.sequence([.wait(forDuration: impact + 0.12), .run { [weak self] in self?.companionStrike() }]))
            }
            run(.sequence([.wait(forDuration: impact), .run { [weak self, weak target] in
                guard let self, let target, target === self.encounter else { return }
                self.hpFill.run(.scaleX(to: CGFloat(max(blow.foeLeft, 0.02)), duration: 0.15))
                self.floatText("-\(Int(blow.damage))", color: .white, size: 22, over: self.encounterPosition,
                               height: self.encounterLift + encounterBody.height * 0.55)
                // Le monstre encaisse : il recule d'un cran, puis reprend sa place.
                if target.action(forKey: "lunge") == nil {
                    target.run(.sequence([.moveBy(x: 7, y: 0, duration: 0.05), .moveBy(x: -7, y: 0, duration: 0.12)]),
                               withKey: "recoil")
                }
                // L'impact prend l'élément de l'arme : glace, ombre ou feu.
                self.playFX(self.weaponElement ?? "hit", at: CGPoint(
                    x: self.encounterPosition.x,
                    y: self.encounterPosition.y + self.encounterLift + min(self.encounterBody.height * 0.5, 54)),
                    // Mesuré sur la créature : un rat ne disparaît pas sous l'explosion.
                    scale: min(max(self.encounterBody.height / 110, 0.5), 0.9))
            }]))
        } else {
            // Le monstre bondit vers le héros, puis revient à sa place.
            let lunge = min(max(target.position.x - heroPosition.x - encounterBody.width * 0.5 - 30, 10), 60)
            target.run(.sequence([
                .moveBy(x: -lunge, y: 0, duration: 0.12),
                .moveBy(x: lunge, y: 0, duration: 0.18),
            ]), withKey: "lunge")
            let sprite = encounterSprite
            let swing = Self.creatureFrames(sprite, "attack")
            if !swing.isEmpty {
                // Son geste d'attaque tient dans le bond, puis elle reprend son souffle.
                target.run(.sequence([.animate(with: swing, timePerFrame: 0.3 / Double(swing.count)),
                                      .run { [weak self, weak target] in
                                          guard let self, let target else { return }
                                          self.idleCreature(target, sprite)
                                      }]), withKey: "pose")
            }
            run(.sequence([.wait(forDuration: 0.12), .run { [weak self] in
                guard let self else { return }
                if blow.potion {
                    self.floatText("+\(Int(self.game.potionHeal)) PV", color: .systemGreen, size: 18,
                                   over: self.heroPosition, height: self.hero.size.height + 26)
                    self.burst("fx_heal", height: 60, at: self.heroPosition)
                }
                self.floatText("-\(Int(blow.damage))", color: UIColor(red: 1, green: 0.32, blue: 0.3, alpha: 1), size: 22,
                               over: self.heroPosition, height: self.hero.size.height + 4)
                self.flash(self.hero)
                self.playFX("hit", at: CGPoint(x: self.heroPosition.x + 6, y: self.heroPosition.y + self.hero.size.height * 0.5),
                            scale: 0.55, sound: "hurt")
                let pose = self.heroFrames("attack")[0]
                self.hero.run(.sequence([.setTexture(self.heroFrames("hurt")[0]), .moveBy(x: -6, y: 0, duration: 0.06),
                                         .moveBy(x: 6, y: 0, duration: 0.1), .wait(forDuration: 0.15),
                                         .setTexture(pose)]), withKey: "anim")
            }]))
        }
    }

    /// Coup spécial : une animation à part par classe (grand coup d'épée, flèche chargée,
    /// boule de magie), jouée sur un sprite dédié plus grand que le héros pour laisser
    /// la place aux effets. Le monstre s'effondre à l'impact.
    private func specialStrike() {
        blowIndex = blows.count
        guard let target = encounter else { return }
        successHaptic.notificationOccurred(.success)
        showBanner("Coup spécial !")

        let tempo = 1 / (1 + max(game.speedBonus, 0) * 0.5)
        let step = 0.085 * tempo
        let frames = heroFrames("special")
        let scale = Self.heroScale * zoom
        let size = frames[0].size()
        let special = SKSpriteNode(texture: frames[0], size: CGSize(width: size.width * scale, height: size.height * scale))
        special.anchorPoint = CGPoint(x: 0.5, y: 0)
        special.position = heroPosition
        special.xScale = facing
        special.zPosition = hero.zPosition + 0.1
        endSpecial()
        specialSprite = special
        addChild(special)
        hero.removeAction(forKey: "anim")
        hero.alpha = 0

        // Image où le coup part, propre à chaque animation (cf. `_special` dans Art/import_pixellab.py).
        let release: Int
        switch game.heroLook {
        case .warrior: release = 4
        case .archer: release = 6
        case .mage: release = 7
        }
        let aim = CGPoint(x: encounterPosition.x, y: encounterPosition.y + encounterLift + min(encounterBody.height * 0.5, 54))
        let hand = CGPoint(x: heroPosition.x + hero.size.width * 0.35, y: heroPosition.y + hero.size.height * 0.5)
        var travel: TimeInterval = 0

        switch game.heroLook {
        case .warrior:
            // Il bondit vers le monstre pendant qu'il lève l'épée, frappe, puis revient.
            let reach = max(encounterPosition.x - heroPosition.x - encounterBody.width * 0.35 - 70, 20)
            special.run(.sequence([
                .wait(forDuration: step * 2),
                .moveBy(x: reach, y: 0, duration: step * Double(release - 2)),
                .wait(forDuration: step * Double(frames.count - release - 2)),
                .moveTo(x: heroPosition.x, duration: step * 2),
            ]))
        case .archer:
            travel = 0.12
            let arrow = SKShapeNode(rectOf: CGSize(width: 34, height: 4), cornerRadius: 2)
            arrow.fillColor = UIColor(red: 0.6, green: 1, blue: 0.45, alpha: 1)
            arrow.strokeColor = UIColor(red: 0.2, green: 0.9, blue: 0.2, alpha: 1)
            arrow.glowWidth = 4
            arrow.position = CGPoint(x: hand.x + 20, y: hand.y + 6)
            arrow.zRotation = atan2(aim.y - arrow.position.y, aim.x - arrow.position.x)
            arrow.alpha = 0
            effects.addChild(arrow)
            arrow.run(.sequence([.wait(forDuration: step * Double(release)), .fadeIn(withDuration: 0),
                                 .move(to: aim, duration: travel), .removeFromParent()]))
        case .mage:
            travel = 0.18
            let orb = SKSpriteNode(texture: Self.texture("fx_fireball"), size: CGSize(width: 78, height: 34))
            orb.color = UIColor(red: 0.35, green: 0.7, blue: 1, alpha: 1)
            orb.colorBlendFactor = 0.85
            orb.position = CGPoint(x: hand.x + 34, y: hand.y + 4)
            orb.zRotation = atan2(aim.y - orb.position.y, aim.x - orb.position.x)
            orb.alpha = 0
            effects.addChild(orb)
            orb.run(.sequence([.wait(forDuration: step * Double(release)), .fadeIn(withDuration: 0),
                               .move(to: aim, duration: travel), .removeFromParent()]))
        }

        special.run(.sequence([.animate(with: frames, timePerFrame: step), .wait(forDuration: 0.15),
                               .run { [weak self, weak special] in
            guard let self, let special, self.specialSprite === special else { return }
            self.endSpecial()
            self.hero.texture = self.heroFrames("attack")[0]
        }]))

        let impact = step * Double(release) + travel
        run(.sequence([.wait(forDuration: impact), .run { [weak self, weak target] in
            guard let self, let target else { return }
            self.flash(target)
            self.hpFill.run(.scaleX(to: 0.02, duration: 0.2))
            self.playFX("crit", at: aim, scale: 1.2)
            self.floatText("CRITIQUE !", color: .systemYellow, size: 24, over: self.encounterPosition,
                           height: self.encounterLift + encounterBody.height * 0.6)
            target.run(.sequence([.moveBy(x: 8, y: 0, duration: 0.04), .moveBy(x: -16, y: 0, duration: 0.08),
                                  .moveBy(x: 8, y: 0, duration: 0.04)]))
        }]))
    }

    /// Rend la main au héros si un coup spécial est en cours (fin de l'animation, changement de scène).
    /// Donjon terminé : le héros brandit son arme quelques instants, dans la salle du boss,
    /// avant que la scène ne passe au trajet du retour (le voyage, lui, a déjà commencé).
    private func celebrate() {
        let hold: TimeInterval = 2.6
        victoryUntil = lastUpdate + hold
        endSpecial()
        hero.removeAction(forKey: "anim")
        hero.removeAction(forKey: "dash")
        hero.position = heroPosition
        let names = game.heroLook.frames("victory")
        guard UIImage(named: names[0]) != nil else {
            // Pas encore d'animation : il saute de joie.
            let hop = SKAction.sequence([.moveBy(x: 0, y: 14, duration: 0.14), .moveBy(x: 0, y: -14, duration: 0.18),
                                         .wait(forDuration: 0.12)])
            hero.run(.repeat(hop, count: 5), withKey: "anim")
            return
        }
        let frames = names.map(Self.texture)
        let scale = Self.heroScale * zoom
        let size = frames[0].size()
        let pose = SKSpriteNode(texture: frames[0], size: CGSize(width: size.width * scale, height: size.height * scale))
        pose.anchorPoint = CGPoint(x: 0.5, y: 0)
        pose.position = heroPosition
        pose.xScale = facing
        pose.zPosition = hero.zPosition + 0.1
        specialSprite = pose
        addChild(pose)
        hero.alpha = 0
        // Il lève son arme, puis la tient levée en trépignant jusqu'au départ.
        let cheer = SKAction.sequence([.moveBy(x: 0, y: 5, duration: 0.12), .moveBy(x: 0, y: -5, duration: 0.14),
                                       .wait(forDuration: 0.1)])
        pose.run(.sequence([.wait(forDuration: 0.35), .animate(with: frames, timePerFrame: 0.09),
                            .repeatForever(cheer)]))
        playFX("levelup", at: heroPosition, scale: 0.9, sound: "victory")
    }

    private func endSpecial() {
        specialSprite?.removeFromParent()
        specialSprite = nil
        hero.alpha = 1
    }

    /// Bulle au-dessus du héros, avec un pictogramme : ce qu'il ressent ou ce qu'il veut.
    private func react(_ symbol: String, color: UIColor) {
        props.childNode(withName: "bulle")?.removeFromParent()
        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .bold)
        guard let image = UIImage(systemName: symbol, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        let bubble = SKShapeNode(rectOf: CGSize(width: 40, height: 34), cornerRadius: 12)
        bubble.name = "bulle"
        bubble.fillColor = UIColor(white: 1, alpha: 0.92)
        bubble.strokeColor = UIColor(white: 0, alpha: 0.25)
        bubble.lineWidth = 1
        let tail = SKShapeNode(path: {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -5, y: -16)); path.addLine(to: CGPoint(x: 5, y: -16))
            path.addLine(to: CGPoint(x: -2, y: -24)); path.closeSubpath()
            return path
        }())
        tail.fillColor = bubble.fillColor
        tail.strokeColor = .clear
        bubble.addChild(tail)
        let icon = SKSpriteNode(texture: SKTexture(image: image), size: CGSize(width: 22, height: 22))
        bubble.addChild(icon)
        bubble.position = CGPoint(x: heroPosition.x + hero.size.width * 0.18, y: heroPosition.y + hero.size.height * 0.95)
        bubble.zPosition = 9
        bubble.setScale(0.2)
        bubble.alpha = 0
        props.addChild(bubble)
        bubble.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.2)]),
            .wait(forDuration: 2.2),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 8, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    /// Au camp, le héros dit de temps en temps ce qu'il ressent.
    /// La taverne attend sa scène peinte ; d'ici là, le marché à la tombée de la nuit.
    static var tavernImage: String { UIImage(named: "scene_taverne") != nil ? "scene_taverne" : "scene_marche" }

    private func showFeeling() {
        switch game.feeling {
        case .thirsty: react("drop.fill", color: .systemCyan)
        case .hungry: react("fork.knife", color: .systemOrange)
        case .sad: react("cloud.rain.fill", color: .systemBlue)
        case .hurt: react("bandage.fill", color: .systemRed)
        case .tired: react("moon.zzz.fill", color: .systemIndigo)
        case .happy: react("music.note", color: .systemGreen)
        case .content: react("sparkles", color: .systemYellow)
        }
    }

    /// Une attaque du héros, propre à sa classe : coup d'épée, flèche ou boule de feu.
    /// Renvoie le délai avant l'impact.
    @discardableResult
    private func attack() -> TimeInterval {
        guard let target = encounter else { return 0 }
        // Un héros rapide (bottes, archer) frappe d'autant plus vite : toute l'attaque est accélérée.
        let tempo = 1 / (1 + max(game.speedBonus, 0))
        let frames = heroFrames("attack")
        hero.run(.sequence([.animate(with: frames, timePerFrame: 0.07 * tempo), .setTexture(frames[0])]), withKey: "anim")
        let aim = CGPoint(x: encounterPosition.x, y: encounterPosition.y + encounterLift + min(encounterBody.height * 0.5, 54))
        let hand = CGPoint(x: heroPosition.x + hero.size.width * 0.3, y: heroPosition.y + hero.size.height * 0.55)
        let impact: TimeInterval

        switch game.heroLook {
        case .warrior:
            impact = 0.14 * tempo
            let reach = max(encounterPosition.x - heroPosition.x - encounterBody.width * 0.35 - 60, 20)
            hero.run(.sequence([
                .moveTo(x: heroPosition.x + reach, duration: 0.12 * tempo),
                .wait(forDuration: 0.12 * tempo),
                .moveTo(x: heroPosition.x, duration: 0.16 * tempo),
            ]), withKey: "dash")
            // Le croissant de la lame part un peu avant l'impact.
            run(.sequence([.wait(forDuration: max(impact - 0.06, 0)), .run { [weak self] in
                self?.playFX("slash", at: aim, scale: 0.8)
            }]))
        case .archer:
            impact = 0.3 * tempo
            let arrow = SKShapeNode(rectOf: CGSize(width: 26, height: 3), cornerRadius: 1)
            arrow.fillColor = UIColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 1)
            arrow.strokeColor = UIColor(red: 0.25, green: 0.18, blue: 0.10, alpha: 1)
            arrow.lineWidth = 1
            arrow.position = hand
            arrow.zRotation = atan2(aim.y - hand.y, aim.x - hand.x)
            arrow.alpha = 0
            effects.addChild(arrow)
            arrow.run(.sequence([.wait(forDuration: 0.18 * tempo), .fadeIn(withDuration: 0),
                                 .move(to: aim, duration: 0.12 * tempo), .removeFromParent()]))
        case .mage:
            impact = 0.32 * tempo
            let bolt = SKSpriteNode(texture: Self.texture("fx_fireball"), size: CGSize(width: 46, height: 20))
            bolt.position = CGPoint(x: hand.x + 30, y: hand.y + 14)
            bolt.zRotation = atan2(aim.y - bolt.position.y, aim.x - bolt.position.x)
            bolt.alpha = 0
            effects.addChild(bolt)
            bolt.run(.sequence([.wait(forDuration: 0.16 * tempo), .fadeIn(withDuration: 0),
                                .move(to: aim, duration: 0.16 * tempo), .removeFromParent()]))
        }

        run(.sequence([.wait(forDuration: impact), .run { [weak self, weak target] in
            guard let self, let target, target === self.encounter else { return }
            self.flash(target)
        }]))
        return impact
    }

    /// Éclair blanc : une copie du sprite en mode additif, qui s'efface aussitôt.
    private func flash(_ node: SKSpriteNode) {
        let copy = SKSpriteNode(texture: node.texture, size: node.size)
        copy.anchorPoint = node.anchorPoint
        copy.blendMode = .add
        copy.alpha = 0.7
        copy.zPosition = 1
        node.addChild(copy)
        copy.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
    }

    // MARK: - Évènements

    private func handle(_ event: GameEvent) {
        switch event {
        case .roomResolved(let room):
            resolve(room)
        case let .loot(item, outcome):
            showLoot(item, outcome: outcome)
        case .levelUp(let level):
            // Discret : une petite étincelle et un texte qui monte, sans grande bannière.
            floatText("Niveau \(level) !", color: UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 1),
                      size: 18, over: heroPosition, height: hero.size.height + 40)
            burst("fx_levelup", height: 52, at: CGPoint(x: heroPosition.x, y: heroPosition.y + 6))
        case .potionUsed(let healed):
            floatText("+\(Int(healed)) PV", color: .systemGreen, size: 18, over: heroPosition, height: 96)
            burst("fx_heal", height: 60, at: heroPosition)
        case .fled(let reason):
            showBanner(reason == .exhausted ? "Épuisé !" : "Fuite !")
            Audio.shared.play("flee")
        case .dungeonCleared:
            showBanner("Donjon terminé !")
            successHaptic.notificationOccurred(.success)
            celebrate()
        case .skill:
            specialStrike()
        case .treated(let order):
            react(order.symbol, color: order == .bard ? .systemGreen : .systemOrange)
            hero.run(.sequence([.moveBy(x: 0, y: 8, duration: 0.12), .moveBy(x: 0, y: -8, duration: 0.16)]))
            if order == .bard { bardArrives(walking: true) }
            floatText(order == .stew ? "Miam" : "+ moral", color: .systemPink, size: 18, over: heroPosition, height: 96)
        case let .bought(sprite, price, caption):
            showPurchase(sprite: sprite, price: price, caption: caption)
            Audio.shared.play("buy")
        case .sold(let gold):
            showSale(gold)
        case .cared(let fed):
            react(fed ? "fork.knife" : "heart.fill", color: fed ? .systemOrange : .systemPink)
            hero.run(.sequence([.moveBy(x: 0, y: 8, duration: 0.12), .moveBy(x: 0, y: -8, duration: 0.16)]))
        case .blessed(let blessing):
            showBanner(blessing.name)
            burst("fx_levelup", height: 90, at: CGPoint(x: heroPosition.x, y: heroPosition.y - 4))
        case .died(let banner):
            showBanner(banner)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case let .found(provision, gold):
            if let provision {
                react(provision.symbol, color: .systemGreen)
                floatText("+1 \(provision.name.lowercased())", color: .systemGreen, size: 16,
                          over: heroPosition, height: hero.size.height + 50)
            } else if gold > 0 {
                burstCoins(count: 3, gold: gold)
            }
        case .companionFound(let companion):
            react("pawprint.fill", color: .systemYellow)
            showBanner("\(companion.name) rejoint l'aventure")
            floatText(companion.name, color: .systemYellow, size: 16,
                      over: heroPosition, height: hero.size.height + 50)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .relicFound(let relic):
            react(relic.symbol, color: .systemYellow)
            showBanner(relic.name)
            burst("fx_levelup", height: 90, at: CGPoint(x: heroPosition.x, y: heroPosition.y - 4))
            successHaptic.notificationOccurred(.success)
        case let .visited(symbol, good):
            react(symbol, color: good ? .systemGreen : .systemOrange)
        case .trapTriggered:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .trapDisarmed:
            react("checkmark.shield.fill", color: .systemGreen)
            floatText("Désamorcé !", color: .systemGreen, size: 18, over: heroPosition, height: hero.size.height + 50)
            burst("fx_heal", height: 50, at: heroPosition)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// Effet ponctuel posé au sol, qui grandit un peu puis s'efface.
    private func burst(_ sprite: String, height: CGFloat, at point: CGPoint) {
        // Soin et montée de niveau ont leur version animée ; `height` donne l'ampleur voulue.
        if sprite == "fx_heal", FXAnims.table["heal"] != nil {
            playFX("heal", at: CGPoint(x: point.x, y: point.y + 36 * zoom), scale: height / 60)
            return
        }
        if sprite == "fx_levelup", FXAnims.table["levelup"] != nil {
            playFX("levelup", at: point, scale: max(height / 90, 0.75))
            return
        }
        let node = Self.sprite(sprite, height: height)
        node.position = point
        node.alpha = 0.95
        effects.addChild(node)
        node.run(.sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }

    private func resolve(_ room: Room) {
        hpBar.isHidden = true
        encounterShadow.isHidden = true
        hero.removeAction(forKey: "dash")
        hero.position.x = heroPosition.x

        let fight = room.kind == .monster || room.kind == .boss
        if room.hpDelta < 0, !fight {
            // Les dégâts d'un combat ont déjà été affichés coup par coup.
            floatText("\(Int(room.hpDelta)) PV", color: .systemRed, size: 18, over: heroPosition, height: 92)
            hero.run(.sequence([.setTexture(heroFrames("hurt")[0]), .wait(forDuration: 0.4)]), withKey: "anim")
        } else if room.hpDelta > 0, room.usesPotion != true {
            floatText("+\(Int(room.hpDelta)) PV", color: .systemGreen, size: 18, over: heroPosition, height: 92)
            burst("fx_heal", height: 60, at: heroPosition)
        }

        guard let node = encounter else {
            if room.gold > 0 { burstCoins(count: 4, gold: room.gold) }
            return
        }
        encounter = nil
        node.removeAllActions()
        node.move(toParent: effects)

        switch room.kind {
        case .monster, .boss:
            if room.knockedOut {
                node.run(.sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.3), .removeFromParent()]))
            } else {
                Audio.shared.play("death")
                let death = Self.creatureFrames(room.sprite, "death")
                if death.isEmpty {
                    node.run(.sequence([
                        .group([
                            .fadeOut(withDuration: 0.25),
                            .moveBy(x: 0, y: -8, duration: 0.25),
                            .scaleY(to: 0.4, duration: 0.25),
                        ]),
                        .removeFromParent(),
                    ]))
                } else {
                    // Elle s'effondre image par image, reste un instant à terre, puis s'efface.
                    // Ce qui volait tombe au sol.
                    let fall = SKAction.moveBy(x: 0, y: -encounterLift, duration: 0.3)
                    fall.timingMode = .easeIn
                    node.run(fall)
                    node.run(.sequence([
                        .animate(with: death, timePerFrame: 0.06),
                        .wait(forDuration: 0.25),
                        .fadeOut(withDuration: 0.3),
                        .removeFromParent(),
                    ]))
                }
                burstCoins(count: room.kind == .boss ? 12 : 4, gold: room.gold)
            }
        case .chest:
            // Le coffre résiste : il tressaute pendant qu'on le force, puis s'ouvre d'un coup.
            let jostle = SKAction.sequence([.moveBy(x: 4, y: 0, duration: 0.04), .moveBy(x: -8, y: 0, duration: 0.06),
                                            .moveBy(x: 4, y: 0, duration: 0.04)])
            node.run(.sequence([
                .repeat(jostle, count: 3),
                .run { [weak self] in
                    node.texture = Self.texture("chest_open")
                    Audio.shared.play("chest")
                    self?.burstCoins(count: 8, gold: room.gold)
                },
                .wait(forDuration: 0.6), .fadeOut(withDuration: 0.3), .removeFromParent(),
            ]))
        case .trap:
            // Désamorcé : la dalle s'efface sans que les pics ne jaillissent.
            if room.trapDisarmed == true {
                node.run(.sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.3), .removeFromParent()]))
                return
            }
            // Les pics jaillissent d'un coup, la dalle tremble, puis tout s'efface.
            node.texture = Self.texture("trap_spikes_up")
            Audio.shared.play("trap")
            node.run(.sequence([
                .repeat(.sequence([.moveBy(x: 3, y: 0, duration: 0.03), .moveBy(x: -3, y: 0, duration: 0.03)]), count: 3),
                .wait(forDuration: 0.4), .fadeOut(withDuration: 0.3), .removeFromParent(),
            ]))
        case .fountain:
            burst("fx_heal", height: 60, at: CGPoint(x: node.position.x, y: node.position.y + node.size.height * 0.6))
            node.run(.sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.3), .removeFromParent()]))
        }
    }

    private func burstCoins(count: Int, gold: Double) {
        guard gold > 0 else { return }
        Audio.shared.play("coin")
        let origin = CGPoint(x: encounterPosition.x, y: encounterPosition.y + 30)
        for _ in 0..<count {
            let coin = SKSpriteNode(texture: Self.texture("ui_coin"), size: CGSize(width: 18, height: 18))
            coin.position = origin
            effects.addChild(coin)
            let dx = CGFloat.random(in: -70...70)
            let up = CGFloat.random(in: 50...100)
            let rise = SKAction.moveBy(x: dx * 0.5, y: up, duration: 0.25)
            rise.timingMode = .easeOut
            let fall = SKAction.moveBy(x: dx * 0.5, y: -up - 20, duration: 0.35)
            fall.timingMode = .easeIn
            coin.run(.sequence([
                rise,
                .group([fall, .sequence([.wait(forDuration: 0.2), .fadeOut(withDuration: 0.15)])]),
                .removeFromParent(),
            ]))
        }
        floatText("+\(gold.short) or", color: .systemYellow, size: 18, over: encounterPosition, height: 40)
    }

    // MARK: - Textes et butin

    private static func outlined(_ text: String, size: CGFloat, color: UIColor, stroke: CGFloat = -4) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: UIFont(name: "AvenirNext-Heavy", size: size) ?? .boldSystemFont(ofSize: size),
            .foregroundColor: color,
            .strokeColor: UIColor(red: 0.10, green: 0.11, blue: 0.17, alpha: 1),
            .strokeWidth: stroke,
        ])
    }

    private func floatText(_ text: String, color: UIColor, size: CGFloat, over point: CGPoint, height: CGFloat) {
        let label = SKLabelNode()
        label.attributedText = Self.outlined(text, size: size, color: color)
        label.position = CGPoint(x: point.x + .random(in: -10...10), y: point.y + height)
        label.zPosition = 4
        effects.addChild(label)
        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 30, duration: 0.9),
                .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.4)]),
            ]),
            .removeFromParent(),
        ]))
    }

    /// L'objet jaillit de la rencontre, s'affiche au centre avec son nom, puis file vers le sac.
    private func showLoot(_ item: Item, outcome: LootOutcome) {
        let color = item.rarity.uiColor
        let holder = SKNode()
        holder.position = CGPoint(x: encounterPosition.x, y: encounterPosition.y + 30)
        holder.zPosition = 10
        holder.setScale(0.3)
        effects.addChild(holder)

        let plate = SKShapeNode(rectOf: CGSize(width: 60, height: 60), cornerRadius: 8)
        plate.fillColor = UIColor(red: 0.10, green: 0.11, blue: 0.17, alpha: 0.85)
        plate.strokeColor = color
        plate.lineWidth = 3
        holder.addChild(plate)

        let texture = Self.texture(item.image(for: game.heroLook))
        let source = texture.size()
        let fit = 46 / max(source.width, source.height, 1)
        holder.addChild(SKSpriteNode(texture: texture, size: CGSize(width: source.width * fit, height: source.height * fit)))

        let title = item.title(for: game.heroLook)
        let detail: String
        switch outcome {
        case .equipped: detail = "\(title) · équipé"
        case .stored: detail = title
        case .carried: detail = "\(title) · dans la sacoche"
        case .sold: detail = "Sac plein · vendu \(item.resaleValue.short) or"
        }
        let caption = SKLabelNode()
        caption.attributedText = Self.outlined(detail, size: 15, color: color)
        caption.position = CGPoint(x: 0, y: -54)
        holder.addChild(caption)

        let center = CGPoint(x: playWidth * 0.5, y: size.height * 0.56)
        let arrive = SKAction.group([.move(to: center, duration: 0.3), .scale(to: 1, duration: 0.3)])
        arrive.timingMode = .easeOut
        let leave = SKAction.group([
            .move(to: CGPoint(x: playWidth * 0.5, y: -30), duration: 0.35),
            .scale(to: 0.4, duration: 0.35),
            .fadeOut(withDuration: 0.35),
        ])
        leave.timingMode = .easeIn
        holder.run(.sequence([arrive, .wait(forDuration: 1.1), leave, .removeFromParent()]))

        if item.rarity.rawValue >= Rarity.epic.rawValue {
            successHaptic.notificationOccurred(.success)
        }
    }

    // MARK: - Achats

    /// Image d'un achat : sprite du jeu, ou symbole système (gourde, commandes de la taverne) teinté.
    private static func purchaseTexture(_ name: String) -> SKTexture {
        if UIImage(named: name) != nil { return texture(name) }
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)
        let tint: UIColor = name == "drop.fill" ? .systemCyan : name == "music.note" ? .systemGreen : .systemOrange
        let image = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(tint, renderingMode: .alwaysOriginal) ?? UIImage()
        return SKTexture(image: image)
    }

    /// Point de départ des échanges : le marchand s'il est là, sinon un peu au-dessus du feu.
    private var counterPoint: CGPoint {
        if let seller = merchant ?? barmaid {
            return CGPoint(x: seller.position.x, y: seller.position.y + seller.size.height * 0.6)
        }
        return CGPoint(x: heroPosition.x + 70, y: heroPosition.y + 60)
    }

    /// Une pièce lancée en arc d'un point à un autre.
    private func tossCoin(from start: CGPoint, to end: CGPoint, delay: TimeInterval) {
        let coin = SKSpriteNode(texture: Self.texture("ui_coin"), size: CGSize(width: 16, height: 16))
        coin.position = start
        coin.zPosition = 9
        coin.alpha = 0
        effects.addChild(coin)
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + 70))
        let fly = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 0.42)
        fly.timingMode = .easeInEaseOut
        coin.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.04),
                            .group([fly, .rotate(byAngle: .pi * 4, duration: 0.42)]),
                            .fadeOut(withDuration: 0.08), .removeFromParent()]))
    }

    /// Le héros paie : les pièces filent vers le marchand, l'achat s'affiche au milieu de l'écran,
    /// au-dessus du panneau de la boutique qui cache souvent le bas de la scène, puis rejoint le héros.
    private func showPurchase(sprite: String, price: Double, caption: String) {
        let hand = CGPoint(x: heroPosition.x, y: heroPosition.y + hero.size.height * 0.55)
        let coins = min(max(Int(price / 15), 3), 7)
        for index in 0..<coins {
            tossCoin(from: hand, to: counterPoint, delay: Double(index) * 0.06)
        }
        // Le marchand salue la vente.
        if let merchant {
            let wave = (1...4).map { Self.texture("merchant_wave_\($0)") }
            merchant.run(.animate(with: wave, timePerFrame: 0.15), withKey: "thanks")
        }

        let holder = SKNode()
        holder.position = counterPoint
        holder.zPosition = 10
        holder.setScale(0.2)
        holder.alpha = 0
        effects.addChild(holder)

        let glow = SKShapeNode(circleOfRadius: 46)
        glow.fillColor = UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 0.28)
        glow.strokeColor = .clear
        glow.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.3), .scale(to: 0.95, duration: 0.3)])))
        holder.addChild(glow)
        let rays = SKShapeNode(rectOf: CGSize(width: 110, height: 6), cornerRadius: 3)
        rays.fillColor = UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 0.35)
        rays.strokeColor = .clear
        let cross = rays.copy() as! SKShapeNode
        cross.zRotation = .pi / 2
        rays.addChild(cross)
        rays.run(.repeatForever(.rotate(byAngle: .pi, duration: 1.6)))
        holder.addChild(rays)

        let plate = SKShapeNode(rectOf: CGSize(width: 64, height: 64), cornerRadius: 10)
        plate.fillColor = UIColor(red: 0.10, green: 0.11, blue: 0.17, alpha: 0.9)
        plate.strokeColor = UIColor(red: 1, green: 0.82, blue: 0.3, alpha: 1)
        plate.lineWidth = 3
        holder.addChild(plate)
        let texture = Self.purchaseTexture(sprite)
        let source = texture.size()
        let fit = 46 / max(source.width, source.height, 1)
        holder.addChild(SKSpriteNode(texture: texture, size: CGSize(width: source.width * fit, height: source.height * fit)))

        let title = SKLabelNode()
        title.attributedText = Self.outlined(caption, size: 16, color: .white)
        title.position = CGPoint(x: 0, y: -58)
        holder.addChild(title)
        let cost = SKLabelNode()
        cost.attributedText = Self.outlined("-\(price.short) or", size: 18, color: UIColor(red: 1, green: 0.78, blue: 0.25, alpha: 1))
        cost.position = CGPoint(x: 0, y: 48)
        holder.addChild(cost)

        let center = CGPoint(x: playWidth * 0.5, y: size.height * 0.66)
        let arrive = SKAction.group([.fadeIn(withDuration: 0.15), .move(to: center, duration: 0.32),
                                     .sequence([.scale(to: 1.2, duration: 0.24), .scale(to: 1, duration: 0.1)])])
        arrive.timingMode = .easeOut
        // L'objet file dans le sac (le panneau du bas), pas vers le héros.
        let bag = CGPoint(x: playWidth * 0.5, y: bottomInset + 6)
        let leave = SKAction.group([.move(to: bag, duration: 0.4), .scale(to: 0.18, duration: 0.4),
                                    .sequence([.wait(forDuration: 0.2), .fadeOut(withDuration: 0.2)])])
        leave.timingMode = .easeIn
        holder.run(.sequence([
            .wait(forDuration: 0.15), arrive, .wait(forDuration: 0.9), leave,
            .removeFromParent(),
        ]))
    }

    /// Le héros vend : les pièces viennent du marchand jusqu'à lui.
    private func showSale(_ gold: Double) {
        let hand = CGPoint(x: heroPosition.x, y: heroPosition.y + hero.size.height * 0.55)
        let coins = min(max(Int(gold / 15), 3), 8)
        for index in 0..<coins {
            tossCoin(from: counterPoint, to: hand, delay: Double(index) * 0.06)
        }
        run(.sequence([.wait(forDuration: Double(coins) * 0.06 + 0.4), .run { [weak self] in
            guard let self else { return }
            self.floatText("+\(gold.short) or", color: .systemYellow, size: 24,
                           over: CGPoint(x: self.playWidth * 0.5, y: self.size.height * 0.66), height: 0)
            self.hero.run(.sequence([.moveBy(x: 0, y: 8, duration: 0.1), .moveBy(x: 0, y: -8, duration: 0.14)]),
                          withKey: "hop")
        }]))
    }

    private func showBanner(_ text: String) {
        banner.removeAllActions()
        banner.attributedText = Self.outlined(text, size: 28, color: .white, stroke: -5)
        banner.position = CGPoint(x: playWidth * 0.5, y: min(size.height * 0.6, size.height - 130))
        banner.alpha = 0
        banner.setScale(0.6)
        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.15)]),
            .wait(forDuration: 1.0),
            .fadeOut(withDuration: 0.3),
        ]))
    }
}
