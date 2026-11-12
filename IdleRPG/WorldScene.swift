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
    private let heroShadow = SKShapeNode()
    /// Éléments du lieu courant, vidés à chaque changement.
    private let props = SKNode()
    /// Effets qui survivent au changement de salle : monstre qui tombe, pièces, textes.
    private let effects = SKNode()
    /// Le marchand, quand la scène du marché est affichée : les achats partent de lui.
    private weak var merchant: SKSpriteNode?
    /// La serveuse, quand la taverne est affichée : les commandes partent d'elle.
    private weak var barmaid: SKSpriteNode?
    private var encounter: SKSpriteNode?
    private var encounterLift: CGFloat = 0
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

        effects.zPosition = 8
        addChild(effects)

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
    private var encounterPosition: CGPoint { CGPoint(x: playWidth * 0.72, y: feetY) }

    /// Ligne où les personnages posent les pieds : elle suit le sol de la scène peinte.
    private var feetY: CGFloat = 22
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

    /// Le camp s'éclaire le jour, de 7 h à 19 h à l'heure du téléphone.
    static var isDaytime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return (7..<19).contains(hour)
    }

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
        if scene.scrolls {
            sky.isHidden = true
            underSky.isHidden = true
            backdropScale = visible / max(source.height, 1)
            backdrop.configure(texture: texture, height: visible, sceneWidth: size.width, mirror: false)
            backdrop.position = CGPoint(x: 0, y: bottomInset)
            underStrip.configure(texture: texture, height: visible, sceneWidth: size.width,
                                 tint: UIColor(white: 0.55, alpha: 1), mirror: false)
            underStrip.position = CGPoint(x: 0, y: bottomInset)
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
        feetY = (bottomInset + (1 - scene.floor) * source.height * backdropScale).rounded()
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

        guard size.width > 0, size.height > 0 else { return }
        let key = Self.key(for: game.activity) + "|" + game.heroLook.rawValue + (game.injured ? "|blessé" : "")
            + (Self.isDaytime ? "|jour" : "|nuit") + (sleepsAtCamp ? "|dort" : "")
        if key != modeKey {
            modeKey = key
            rebuild()
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

    private func rebuild() {
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
            heroSlot = scenePoint(isPortrait ? 0.42 : 0.44, 0).x / playWidth
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

        endSpecial()
        let frame = Self.texture(game.heroLook.frames("walk")[0]).size()
        let scale = Self.heroScale * zoom
        hero.size = CGSize(width: frame.width * scale, height: frame.height * scale)
        heroShadow.setScale(zoom)
        hero.xScale = facing
        hero.position = heroPosition
        heroShadow.position = heroPosition
        placeScrolling()
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
    private func buildCamp(fire spot: (CGFloat, CGFloat), fireflies swarm: (CGFloat, CGFloat)) {
        let firePos = scenePoint(spot.0, spot.1)

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
        barmaid.position = CGPoint(x: playWidth * 0.64, y: feetY)
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
        pose(heroFrames(room.kind == .monster || room.kind == .boss ? "attack" : "idle")[0])
        // Arrivé sur place, il s'arrête : plus de balancement de marche.
        hero.removeAction(forKey: "bob")
        hero.position = heroPosition

        let look = Self.looks[room.sprite] ?? (80, false, 0)
        let node = Self.sprite(room.sprite, height: look.height * Self.actorScale * zoom)
        node.xScale = look.flip ? -1 : 1
        node.zPosition = 3
        encounterLift = look.lift * Self.actorScale * zoom
        node.position = CGPoint(x: size.width + node.size.width, y: feetY + encounterLift)
        props.addChild(node)
        encounter = node
        let creature = room.kind == .monster || room.kind == .boss
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
            let arrive = SKAction.moveTo(x: encounterPosition.x, duration: 0.25)
            arrive.timingMode = .easeOut
            // Ce qui vole se balance en l'air ; ce qui marche respire sans quitter le sol.
            let idle: SKAction = look.lift > 0
                ? .sequence([.wait(forDuration: 0.45), .moveBy(x: 0, y: 3, duration: 0),
                             .wait(forDuration: 0.45), .moveBy(x: 0, y: -3, duration: 0)])
                : .sequence([.wait(forDuration: 0.45), .scaleY(to: 1.03, duration: 0),
                             .wait(forDuration: 0.45), .scaleY(to: 1, duration: 0)])
            node.run(.sequence([arrive, .repeatForever(idle)]))
        }

        let shadowWidth = min(node.size.width * 0.7, 120)
        encounterShadow.path = CGPath(ellipseIn: CGRect(x: -shadowWidth / 2, y: -3, width: shadowWidth, height: 12), transform: nil)
        encounterShadow.position = encounterPosition
        encounterShadow.isHidden = false

        guard room.kind == .monster || room.kind == .boss else { return }
        let boss = room.kind == .boss
        hpFill.color = boss ? .systemPurple : .systemRed
        hpFill.xScale = 1
        nameText.attributedText = Self.outlined(boss ? "BOSS · \(room.name)" : room.name, size: 14,
                                                color: boss ? .systemYellow : .white)
        // Au-dessus du monstre, sans monter sous l'en-tête posé en haut de la scène.
        let barTop = feetY + encounterLift + node.size.height + 24
        hpBar.position = CGPoint(x: min(encounterPosition.x, playWidth - 74), y: min(barTop, size.height - 120))
        hpBar.isHidden = false
        if boss { showBanner("BOSS !") }
    }

    /// Joue un coup : celui du héros (animation de classe), ou celui du monstre qui bondit.
    /// Les dégâts s'affichent à l'impact, et la jauge ne bouge qu'à ce moment-là.
    private func strike(_ blow: GameState.Blow) {
        guard let target = encounter else { return }
        if blow.byHero {
            let impact = attack()
            run(.sequence([.wait(forDuration: impact), .run { [weak self, weak target] in
                guard let self, let target, target === self.encounter else { return }
                self.hpFill.run(.scaleX(to: CGFloat(max(blow.foeLeft, 0.02)), duration: 0.15))
                self.floatText("-\(Int(blow.damage))", color: .white, size: 22, over: self.encounterPosition,
                               height: self.encounterLift + target.size.height * 0.55)
            }]))
        } else {
            // Le monstre bondit vers le héros, puis revient à sa place.
            let lunge = min(max(target.position.x - heroPosition.x - target.size.width * 0.5 - 30, 10), 60)
            target.run(.sequence([
                .moveBy(x: -lunge, y: 0, duration: 0.12),
                .moveBy(x: lunge, y: 0, duration: 0.18),
            ]), withKey: "lunge")
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
        let aim = CGPoint(x: encounterPosition.x, y: encounterPosition.y + encounterLift + min(target.size.height * 0.5, 54))
        let hand = CGPoint(x: heroPosition.x + hero.size.width * 0.35, y: heroPosition.y + hero.size.height * 0.5)
        var travel: TimeInterval = 0

        switch game.heroLook {
        case .warrior:
            // Il bondit vers le monstre pendant qu'il lève l'épée, frappe, puis revient.
            let reach = max(encounterPosition.x - heroPosition.x - target.size.width * 0.35 - 70, 20)
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
            self.floatText("CRITIQUE !", color: .systemYellow, size: 24, over: self.encounterPosition,
                           height: self.encounterLift + target.size.height * 0.6)
            target.run(.sequence([.moveBy(x: 8, y: 0, duration: 0.04), .moveBy(x: -16, y: 0, duration: 0.08),
                                  .moveBy(x: 8, y: 0, duration: 0.04)]))
        }]))
    }

    /// Rend la main au héros si un coup spécial est en cours (fin de l'animation, changement de scène).
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
        let aim = CGPoint(x: encounterPosition.x, y: encounterPosition.y + encounterLift + min(target.size.height * 0.5, 54))
        let hand = CGPoint(x: heroPosition.x + hero.size.width * 0.3, y: heroPosition.y + hero.size.height * 0.55)
        let impact: TimeInterval

        switch game.heroLook {
        case .warrior:
            impact = 0.14 * tempo
            let reach = max(encounterPosition.x - heroPosition.x - target.size.width * 0.35 - 60, 20)
            hero.run(.sequence([
                .moveTo(x: heroPosition.x + reach, duration: 0.12 * tempo),
                .wait(forDuration: 0.12 * tempo),
                .moveTo(x: heroPosition.x, duration: 0.16 * tempo),
            ]), withKey: "dash")
            let slash = SKSpriteNode(texture: Self.texture("fx_slash"), size: CGSize(width: 64, height: 56))
            slash.position = aim
            slash.alpha = 0
            effects.addChild(slash)
            slash.run(.sequence([.wait(forDuration: impact), .fadeIn(withDuration: 0.02),
                                 .group([.scale(to: 1.25, duration: 0.18), .fadeOut(withDuration: 0.18)]),
                                 .removeFromParent()]))
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
        case .dungeonCleared:
            showBanner("Donjon terminé !")
            successHaptic.notificationOccurred(.success)
        case .skill:
            specialStrike()
        case .treated(let order):
            react(order.symbol, color: order == .bard ? .systemGreen : .systemOrange)
            hero.run(.sequence([.moveBy(x: 0, y: 8, duration: 0.12), .moveBy(x: 0, y: -8, duration: 0.16)]))
            if order == .bard { bardArrives(walking: true) }
            floatText(order == .stew ? "Miam" : "+ moral", color: .systemPink, size: 18, over: heroPosition, height: 96)
        case let .bought(sprite, price, caption):
            showPurchase(sprite: sprite, price: price, caption: caption)
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
        }
    }

    /// Effet ponctuel posé au sol, qui grandit un peu puis s'efface.
    private func burst(_ sprite: String, height: CGFloat, at point: CGPoint) {
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
                node.run(.sequence([
                    .group([
                        .fadeOut(withDuration: 0.25),
                        .moveBy(x: 0, y: -8, duration: 0.25),
                        .scaleY(to: 0.4, duration: 0.25),
                    ]),
                    .removeFromParent(),
                ]))
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
                    self?.burstCoins(count: 8, gold: room.gold)
                },
                .wait(forDuration: 0.6), .fadeOut(withDuration: 0.3), .removeFromParent(),
            ]))
        case .trap:
            // Les pics jaillissent d'un coup, la dalle tremble, puis tout s'efface.
            node.texture = Self.texture("trap_spikes_up")
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
        case .sold: detail = "Sac plein · vendu \(item.sellValue.short) or"
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
