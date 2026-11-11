import SpriteKit
import UIKit

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
    private var restTimer: TimeInterval = 0

    private let backgroundA = SKSpriteNode()
    private let backgroundB = SKSpriteNode()
    private let hero = SKSpriteNode()
    private let heroShadow = SKShapeNode()
    /// Éléments du lieu courant, vidés à chaque changement.
    private let props = SKNode()
    /// Effets qui survivent au changement de salle : monstre qui tombe, pièces, textes.
    private let effects = SKNode()
    private var encounter: SKSpriteNode?
    private let encounterShadow = SKShapeNode()

    private let hpBar = SKNode()
    private let hpFill = SKSpriteNode(color: .systemRed, size: CGSize(width: 130, height: 10))
    private let nameText = SKLabelNode()
    private let banner = SKLabelNode()

    private let successHaptic = UINotificationFeedbackGenerator()

    /// Taille des décors en pixels, et hauteur de leur bande de sol.
    private static let backgroundPixels = CGSize(width: 180, height: 120)
    private static let groundPixels: CGFloat = 32
    /// Taille à l'écran d'un pixel de personnage.
    private static let pixel: CGFloat = 5
    private static let walkSpeed: CGFloat = 70

    private static var textures: [String: SKTexture] = [:]

    /// Texture en pixel art, sans lissage.
    static func texture(_ name: String) -> SKTexture {
        if let cached = textures[name] { return cached }
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .nearest
        textures[name] = texture
        return texture
    }

    private static func sprite(_ name: String) -> SKSpriteNode {
        let texture = texture(name)
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: texture.size().width * pixel, height: texture.size().height * pixel)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        return node
    }

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

        for background in [backgroundA, backgroundB] {
            background.zPosition = -10
            background.anchorPoint = .zero
            addChild(background)
        }

        for shadow in [heroShadow, encounterShadow] {
            shadow.fillColor = UIColor(white: 0, alpha: 0.28)
            shadow.strokeColor = .clear
            shadow.zPosition = 1
            addChild(shadow)
        }
        heroShadow.path = CGPath(ellipseIn: CGRect(x: -30, y: -6, width: 60, height: 12), transform: nil)
        encounterShadow.isHidden = true

        props.zPosition = 2
        addChild(props)

        hero.texture = Self.texture("hero")
        hero.size = CGSize(width: 16 * Self.pixel, height: 16 * Self.pixel)
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

    private var backgroundScale: CGFloat {
        max(size.width / Self.backgroundPixels.width, size.height / Self.backgroundPixels.height)
    }
    private var backgroundWidth: CGFloat { Self.backgroundPixels.width * backgroundScale }
    /// Ligne où les personnages posent les pieds, un peu sous l'horizon.
    private var feetY: CGFloat { Self.groundPixels * backgroundScale * 0.7 }
    private var heroPosition: CGPoint { CGPoint(x: size.width * heroSlot, y: feetY) }
    private var encounterPosition: CGPoint { CGPoint(x: size.width * 0.74, y: feetY) }

    private func setBackground(_ name: String) {
        let texture = Self.texture(name)
        let tile = CGSize(width: backgroundWidth, height: Self.backgroundPixels.height * backgroundScale)
        for background in [backgroundA, backgroundB] {
            background.texture = texture
            background.size = tile
        }
        placeBackground()
    }

    /// Deux copies du décor côte à côte : elles défilent et se relaient sans couture.
    private func placeBackground() {
        let width = backgroundWidth
        guard width > 0 else { return }
        var offset = scroll.truncatingRemainder(dividingBy: width)
        if offset < 0 { offset += width }
        backgroundA.position = CGPoint(x: -offset, y: 0)
        backgroundB.position = CGPoint(x: width - offset, y: 0)
    }

    // MARK: - Boucle

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.1)
        lastUpdate = currentTime
        game.tick()

        guard size.width > 0, size.height > 0 else { return }
        let key = Self.key(for: game.activity)
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
        case .traveling(let trip): "trip:\(trip.start)"
        case .exploring(let run): "run:\(run.dungeon):\(run.roomIndex)"
        }
    }

    private func rebuild() {
        props.removeAllChildren()
        encounter = nil
        encounterShown = false
        encounterShadow.isHidden = true
        hpBar.isHidden = true
        attackTimer = 0

        var walking = false
        facing = 1
        switch game.activity {
        case .resting:
            setBackground("bg_forest")
            heroSlot = 0.44
            buildCamp()
        case .shopping:
            setBackground("bg_meadow")
            heroSlot = 0.2
            let stall = Self.sprite("shop_stall")
            stall.position = CGPoint(x: size.width * 0.66, y: feetY + 4)
            props.addChild(stall)
        case .traveling(let trip):
            setBackground("bg_meadow")
            walking = true
            if trip.to == .camp {
                facing = -1
                heroSlot = 0.62
            } else {
                heroSlot = 0.3
            }
        case .exploring(let run):
            setBackground(Dungeon.all[run.dungeon].background)
            heroSlot = 0.22
            walking = true
        }

        hero.xScale = facing
        hero.position = heroPosition
        heroShadow.position = heroPosition
        setHeroBob(walking: walking)
    }

    private func buildCamp() {
        let tent = Self.sprite("tent")
        tent.position = CGPoint(x: size.width * 0.15, y: feetY + 6)
        props.addChild(tent)

        let firePosition = CGPoint(x: size.width * 0.70, y: feetY - 4)
        let glow = SKShapeNode(circleOfRadius: 52)
        glow.fillColor = UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 0.11)
        glow.strokeColor = .clear
        glow.position = CGPoint(x: firePosition.x, y: firePosition.y + 30)
        glow.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.5), .scale(to: 0.94, duration: 0.5)])))
        props.addChild(glow)

        let fire = Self.sprite("campfire_1")
        fire.position = firePosition
        fire.run(.repeatForever(.animate(with: [Self.texture("campfire_1"), Self.texture("campfire_2")], timePerFrame: 0.2)))
        props.addChild(fire)
    }

    /// Respiration lente au repos, pas rapides en marche : deux images, un pixel de haut.
    private func setHeroBob(walking: Bool) {
        hero.removeAction(forKey: "bob")
        hero.position.y = feetY
        let period = walking ? 0.14 : 0.5
        hero.run(.repeatForever(.sequence([
            .wait(forDuration: period),
            .moveBy(x: 0, y: Self.pixel, duration: 0),
            .wait(forDuration: period),
            .moveBy(x: 0, y: -Self.pixel, duration: 0),
        ])), withKey: "bob")
    }

    private func animate(_ dt: TimeInterval) {
        switch game.activity {
        case .traveling:
            scroll += facing * Self.walkSpeed * dt
        case .exploring(let run):
            let span = run.roomEnd - run.roomStart
            let part = span > 0 ? (game.clock - run.roomStart) / span : 1
            if part < GameState.walkShare {
                scroll += Self.walkSpeed * dt
            } else {
                if !encounterShown { showEncounter(run.room) }
                if run.room.kind == .monster || run.room.kind == .boss {
                    let fight = min(max((part - GameState.walkShare) / (1 - GameState.walkShare), 0), 1)
                    let remaining = run.room.knockedOut ? 1 - 0.35 * fight : 1 - fight
                    hpFill.xScale = CGFloat(max(remaining, 0.02))
                    attackTimer += dt
                    if attackTimer >= 0.75 {
                        attackTimer = 0
                        castFireball()
                    }
                }
            }
        case .resting:
            restTimer += dt
            if restTimer >= 1.1 {
                restTimer = 0
                if game.isRecovering { floatText("+", color: .systemGreen, size: 20, over: heroPosition, height: 80) }
            }
        case .shopping:
            break
        }
        placeBackground()
    }

    // MARK: - Rencontres

    private func showEncounter(_ room: Room) {
        encounterShown = true
        setHeroBob(walking: false)

        let node = Self.sprite(room.sprite)
        node.zPosition = 3
        node.position = CGPoint(x: size.width + node.size.width, y: feetY)
        props.addChild(node)
        encounter = node
        let arrive = SKAction.moveTo(x: encounterPosition.x, duration: 0.25)
        arrive.timingMode = .easeOut
        node.run(arrive)

        let shadowWidth = node.size.width * 0.75
        encounterShadow.path = CGPath(ellipseIn: CGRect(x: -shadowWidth / 2, y: -7, width: shadowWidth, height: 14), transform: nil)
        encounterShadow.position = encounterPosition
        encounterShadow.isHidden = false

        guard room.kind == .monster || room.kind == .boss else { return }
        let boss = room.kind == .boss
        hpFill.color = boss ? .systemPurple : .systemRed
        hpFill.xScale = 1
        nameText.attributedText = Self.outlined(boss ? "BOSS · \(room.name)" : room.name, size: 14,
                                                color: boss ? .systemYellow : .white)
        hpBar.position = CGPoint(x: encounterPosition.x, y: size.height - 34)
        hpBar.isHidden = false
        if boss { showBanner("BOSS !") }
    }

    private func castFireball() {
        guard let target = encounter else { return }
        hero.run(.sequence([
            .moveBy(x: 2 * Self.pixel, y: 0, duration: 0.04),
            .moveBy(x: -2 * Self.pixel, y: 0, duration: 0.09),
        ]))
        let bolt = SKSpriteNode(texture: Self.texture("fireball"), size: CGSize(width: 24, height: 24))
        bolt.position = CGPoint(x: heroPosition.x + 38, y: heroPosition.y + 62)
        bolt.zPosition = 5
        effects.addChild(bolt)
        let aim = CGPoint(x: encounterPosition.x, y: encounterPosition.y + min(target.size.height * 0.5, 50))
        bolt.run(.sequence([
            .group([.move(to: aim, duration: 0.14), .rotate(byAngle: -.pi, duration: 0.14)]),
            .removeFromParent(),
        ]))
        run(.sequence([.wait(forDuration: 0.14), .run { [weak self, weak target] in
            guard let self, let target, target === self.encounter else { return }
            self.flash(target)
        }]))
    }

    /// Éclair blanc : une copie du sprite en mode additif, qui s'efface aussitôt.
    private func flash(_ node: SKSpriteNode) {
        let copy = SKSpriteNode(texture: node.texture, size: node.size)
        copy.anchorPoint = node.anchorPoint
        copy.blendMode = .add
        copy.alpha = 0.75
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
            showBanner("Niveau \(level) !")
        case .potionUsed(let healed):
            floatText("+\(Int(healed)) PV", color: .systemGreen, size: 18, over: heroPosition, height: 96)
        case .fled(let reason):
            showBanner(reason == .exhausted ? "Épuisé !" : "Fuite !")
        case .dungeonCleared:
            showBanner("Donjon terminé !")
            successHaptic.notificationOccurred(.success)
        }
    }

    private func resolve(_ room: Room) {
        hpBar.isHidden = true
        encounterShadow.isHidden = true

        if room.hpDelta < 0 {
            floatText("\(Int(room.hpDelta)) PV", color: .systemRed, size: 18, over: heroPosition, height: 88)
            hero.run(.sequence([
                .colorize(with: .red, colorBlendFactor: 0.7, duration: 0.05),
                .colorize(withColorBlendFactor: 0, duration: 0.2),
            ]))
        } else if room.hpDelta > 0, room.usesPotion != true {
            floatText("+\(Int(room.hpDelta)) PV", color: .systemGreen, size: 18, over: heroPosition, height: 88)
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
                        .moveBy(x: 0, y: -2 * Self.pixel, duration: 0.25),
                        .scaleY(to: 0.4, duration: 0.25),
                    ]),
                    .removeFromParent(),
                ]))
                burstCoins(count: room.kind == .boss ? 12 : 4, gold: room.gold)
            }
        case .chest:
            node.texture = Self.texture("chest_open")
            burstCoins(count: 8, gold: room.gold)
            node.run(.sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.3), .removeFromParent()]))
        case .trap, .fountain:
            node.run(.sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.3), .removeFromParent()]))
        }
    }

    private func burstCoins(count: Int, gold: Double) {
        guard gold > 0 else { return }
        let origin = CGPoint(x: encounterPosition.x, y: encounterPosition.y + 30)
        for _ in 0..<count {
            let coin = SKSpriteNode(texture: Self.texture("coin"), size: CGSize(width: 20, height: 20))
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
        holder.addChild(SKSpriteNode(texture: Self.texture(item.sprite), size: CGSize(width: 48, height: 48)))

        let detail: String
        switch outcome {
        case .equipped: detail = "\(item.name) · équipé"
        case .stored: detail = item.name
        case .sold: detail = "Sac plein · vendu \(item.sellValue.short) or"
        }
        let caption = SKLabelNode()
        caption.attributedText = Self.outlined(detail, size: 15, color: color)
        caption.position = CGPoint(x: 0, y: -54)
        holder.addChild(caption)

        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.56)
        let arrive = SKAction.group([.move(to: center, duration: 0.3), .scale(to: 1, duration: 0.3)])
        arrive.timingMode = .easeOut
        let leave = SKAction.group([
            .move(to: CGPoint(x: size.width * 0.5, y: -30), duration: 0.35),
            .scale(to: 0.4, duration: 0.35),
            .fadeOut(withDuration: 0.35),
        ])
        leave.timingMode = .easeIn
        holder.run(.sequence([arrive, .wait(forDuration: 1.1), leave, .removeFromParent()]))

        if item.rarity.rawValue >= Rarity.epic.rawValue {
            successHaptic.notificationOccurred(.success)
        }
    }

    private func showBanner(_ text: String) {
        banner.removeAllActions()
        banner.attributedText = Self.outlined(text, size: 28, color: .white, stroke: -5)
        banner.position = CGPoint(x: size.width * 0.5, y: size.height * 0.74)
        banner.alpha = 0
        banner.setScale(0.6)
        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.15)]),
            .wait(forDuration: 1.0),
            .fadeOut(withDuration: 0.3),
        ]))
    }
}
