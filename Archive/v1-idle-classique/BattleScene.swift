import SpriteKit
import UIKit

/// Scène de combat : le héros à gauche, le monstre à droite.
/// Elle fait avancer la logique du jeu à chaque image et anime les évènements reçus.
final class BattleScene: SKScene {
    private let game: GameState
    private var lastUpdate: TimeInterval = 0

    private let background = SKSpriteNode()
    private let hero = SKSpriteNode()
    private let heroShadow = SKShapeNode()
    private let monsterShadow = SKShapeNode()
    private var monsterNode: SKSpriteNode?

    private let hpBar = SKNode()
    private let hpFill = SKSpriteNode(color: .systemRed, size: CGSize(width: 150, height: 12))
    private let hpText = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let nameText = SKLabelNode()
    private var shownName = ""
    private let banner = SKLabelNode()

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let successHaptic = UINotificationFeedbackGenerator()

    /// Un décor par zone, en boucle.
    private static let backgrounds = ["bg_forest", "bg_desert", "bg_cave", "bg_ice", "bg_volcano"]
    /// Taille des décors en pixels, et hauteur de leur bande de sol.
    private static let backgroundPixels = CGSize(width: 180, height: 120)
    private static let groundPixels: CGFloat = 32
    /// Taille à l'écran d'un pixel de personnage.
    private static let pixel: CGFloat = 5

    private static var textures: [String: SKTexture] = [:]

    /// Texture en pixel art, sans lissage.
    static func texture(_ name: String) -> SKTexture {
        if let cached = textures[name] { return cached }
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .nearest
        textures[name] = texture
        return texture
    }

    init(game: GameState) {
        self.game = game
        super.init(size: CGSize(width: 390, height: 250))
        scaleMode = .resizeFill
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) non utilisé") }

    // MARK: - Mise en place

    override func didMove(to view: SKView) {
        guard background.parent == nil else { return }

        background.zPosition = -10
        background.anchorPoint = CGPoint(x: 0.5, y: 0)
        addChild(background)

        for shadow in [heroShadow, monsterShadow] {
            shadow.fillColor = UIColor(white: 0, alpha: 0.28)
            shadow.strokeColor = .clear
            shadow.zPosition = 1
            addChild(shadow)
        }
        heroShadow.path = CGPath(ellipseIn: CGRect(x: -30, y: -6, width: 60, height: 12), transform: nil)

        hero.texture = Self.texture("hero")
        hero.size = CGSize(width: 16 * Self.pixel, height: 16 * Self.pixel)
        hero.anchorPoint = CGPoint(x: 0.5, y: 0)
        hero.zPosition = 2
        addChild(hero)

        buildHPBar()

        banner.zPosition = 20
        banner.alpha = 0
        addChild(banner)

        applyBackground()
        layout()
        spawnMonsterNode(animated: false)

        game.onEvent = { [weak self] event in self?.handle(event) }
    }

    private func buildHPBar() {
        let width: CGFloat = 150
        let back = SKShapeNode(rectOf: CGSize(width: width + 4, height: 16), cornerRadius: 4)
        back.fillColor = UIColor(white: 0, alpha: 0.6)
        back.strokeColor = UIColor(white: 1, alpha: 0.3)
        back.lineWidth = 1
        hpBar.addChild(back)

        hpFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpFill.position = CGPoint(x: -width / 2, y: 0)
        hpBar.addChild(hpFill)

        hpText.fontSize = 11
        hpText.fontColor = .white
        hpText.verticalAlignmentMode = .center
        hpText.zPosition = 1
        hpBar.addChild(hpText)

        nameText.position = CGPoint(x: 0, y: 13)
        hpBar.addChild(nameText)

        hpBar.zPosition = 10
        addChild(hpBar)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard background.parent != nil else { return }
        layout()
    }

    /// Le décor remplit la scène, calé en bas : son échelle fixe la hauteur du sol.
    private var backgroundScale: CGFloat {
        max(size.width / Self.backgroundPixels.width, size.height / Self.backgroundPixels.height)
    }
    /// Ligne où les personnages posent les pieds, un peu sous l'horizon.
    private var feetY: CGFloat { Self.groundPixels * backgroundScale * 0.7 }
    private var heroPosition: CGPoint { CGPoint(x: size.width * 0.22, y: feetY) }
    private var monsterPosition: CGPoint { CGPoint(x: size.width * 0.74, y: feetY) }

    private func layout() {
        guard size.width > 0, size.height > 0 else { return }
        background.size = CGSize(width: Self.backgroundPixels.width * backgroundScale,
                                 height: Self.backgroundPixels.height * backgroundScale)
        background.position = CGPoint(x: size.width / 2, y: 0)

        hero.removeAction(forKey: "idle")
        hero.position = heroPosition
        hero.run(Self.idleBob(period: 0.5), withKey: "idle")
        heroShadow.position = heroPosition

        if let node = monsterNode {
            node.removeAction(forKey: "idle")
            node.position = monsterPosition
            node.run(Self.idleBob(period: 0.42), withKey: "idle")
        }
        monsterShadow.position = monsterPosition

        hpBar.position = CGPoint(x: monsterPosition.x, y: size.height - 40)
        banner.position = CGPoint(x: size.width * 0.30, y: size.height * 0.66)
    }

    /// Respiration en deux images, d'un pixel de haut, façon pixel art.
    private static func idleBob(period: TimeInterval) -> SKAction {
        .repeatForever(.sequence([
            .wait(forDuration: period),
            .moveBy(x: 0, y: pixel, duration: 0),
            .wait(forDuration: period),
            .moveBy(x: 0, y: -pixel, duration: 0),
        ]))
    }

    private func applyBackground() {
        let name = Self.backgrounds[(game.stage - 1) % Self.backgrounds.count]
        background.texture = Self.texture(name)
    }

    private static func outlined(_ text: String, size: CGFloat, color: UIColor, stroke: CGFloat = -4) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: UIFont(name: "AvenirNext-Heavy", size: size) ?? .boldSystemFont(ofSize: size),
            .foregroundColor: color,
            .strokeColor: UIColor(red: 0.10, green: 0.11, blue: 0.17, alpha: 1),
            .strokeWidth: stroke,
        ])
    }

    // MARK: - Boucle

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : currentTime - lastUpdate
        lastUpdate = currentTime
        game.tick(dt: dt)
        refreshHPBar()
    }

    private func refreshHPBar() {
        let monster = game.monster
        hpBar.isHidden = monsterNode == nil
        let fraction = max(0, min(1, monster.hp / monster.maxHP))
        hpFill.xScale = CGFloat(fraction)
        hpFill.color = monster.isBoss ? .systemPurple : .systemRed
        hpText.text = "\(max(monster.hp, 0).short) / \(monster.maxHP.short)"

        let title = monster.isBoss ? "BOSS · \(monster.name)" : monster.name
        if title != shownName {
            shownName = title
            nameText.attributedText = Self.outlined(title, size: 14, color: monster.isBoss ? .systemYellow : .white)
        }
    }

    // MARK: - Toucher

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            let ring = SKShapeNode(rectOf: CGSize(width: 22, height: 22))
            ring.strokeColor = .cyan
            ring.lineWidth = 4
            ring.fillColor = .clear
            ring.position = point
            ring.zRotation = .pi / 4
            ring.zPosition = 15
            addChild(ring)
            ring.run(.sequence([
                .group([.scale(to: 2.2, duration: 0.22), .fadeOut(withDuration: 0.22)]),
                .removeFromParent(),
            ]))
            game.tap()
        }
        lightHaptic.impactOccurred()
    }

    // MARK: - Évènements

    private func handle(_ event: GameEvent) {
        switch event {
        case let .heroAttack(damage, crit):
            animateHeroAttack(damage: damage, crit: crit)
        case let .tap(damage):
            hitMonster()
            showNumber(damage.short, color: .cyan, size: 20)
        case let .monsterDied(gold, boss):
            killMonsterNode(gold: gold, boss: boss)
        case .monsterSpawned:
            spawnMonsterNode(animated: true)
        case let .stageCleared(stage):
            applyBackground()
            showBanner("Zone \(stage)")
        case let .loot(item, outcome):
            showLoot(item, outcome: outcome)
        }
    }

    private func animateHeroAttack(damage: Double, crit: Bool) {
        hero.run(.sequence([
            .moveBy(x: 2 * Self.pixel, y: 0, duration: 0.04),
            .moveBy(x: -2 * Self.pixel, y: 0, duration: 0.09),
        ]))

        let target = CGPoint(x: monsterPosition.x, y: monsterPosition.y + 40)
        let side: CGFloat = crit ? 40 : 24
        let bolt = SKSpriteNode(texture: Self.texture("fireball"), size: CGSize(width: side, height: side))
        bolt.position = CGPoint(x: heroPosition.x + 38, y: heroPosition.y + 62)
        bolt.zPosition = 5
        addChild(bolt)
        bolt.run(.sequence([
            .group([.move(to: target, duration: 0.13), .rotate(byAngle: -.pi, duration: 0.13)]),
            .removeFromParent(),
        ]))

        run(.sequence([
            .wait(forDuration: 0.13),
            .run { [weak self] in
                self?.hitMonster()
                if crit {
                    self?.showNumber(damage.short + " !", color: .systemYellow, size: 26)
                } else {
                    self?.showNumber(damage.short, color: .white, size: 20)
                }
            },
        ]))
    }

    private func hitMonster() {
        guard let node = monsterNode, node.action(forKey: "spawn") == nil else { return }
        node.removeAction(forKey: "hit")
        node.position.x = monsterPosition.x
        node.run(.sequence([
            .moveBy(x: Self.pixel, y: 0, duration: 0.04),
            .moveBy(x: -Self.pixel, y: 0, duration: 0.08),
        ]), withKey: "hit")

        // Éclair blanc : une copie du sprite en mode additif, qui s'efface aussitôt.
        let flash = SKSpriteNode(texture: node.texture, size: node.size)
        flash.anchorPoint = node.anchorPoint
        flash.blendMode = .add
        flash.alpha = 0.75
        flash.zPosition = 1
        node.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
    }

    private func showNumber(_ text: String, color: UIColor, size: CGFloat) {
        let label = SKLabelNode()
        label.attributedText = Self.outlined(text, size: size, color: color)
        // Au-dessus du monstre, mais toujours sous la barre de vie.
        let height = monsterNode?.size.height ?? 80
        let top = min(monsterPosition.y + height, hpBar.position.y - 62)
        label.position = CGPoint(
            x: monsterPosition.x + .random(in: -40...40),
            y: top + .random(in: -8...8)
        )
        label.zPosition = 12
        addChild(label)
        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 30, duration: 0.6),
                .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.3)]),
            ]),
            .removeFromParent(),
        ]))
    }

    private func killMonsterNode(gold: Double, boss: Bool) {
        if let node = monsterNode {
            monsterNode = nil
            node.removeAllActions()
            node.run(.sequence([
                .group([
                    .fadeOut(withDuration: 0.25),
                    .moveBy(x: 0, y: -2 * Self.pixel, duration: 0.25),
                    .scaleY(to: 0.4, duration: 0.25),
                ]),
                .removeFromParent(),
            ]))
        }
        monsterShadow.run(.fadeOut(withDuration: 0.2))
        guard gold > 0 else { return }

        let origin = CGPoint(x: monsterPosition.x, y: monsterPosition.y + 30)
        for _ in 0..<(boss ? 12 : 4) {
            let coin = SKSpriteNode(texture: Self.texture("coin"), size: CGSize(width: 20, height: 20))
            coin.position = origin
            coin.zPosition = 8
            addChild(coin)
            let dx = CGFloat.random(in: -70...70)
            let up = CGFloat.random(in: 50...110)
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

        let label = SKLabelNode()
        label.attributedText = Self.outlined("+\(gold.short) or", size: 18, color: .systemYellow)
        label.position = CGPoint(x: origin.x, y: origin.y - 10)
        label.zPosition = 12
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 40, duration: 0.7), .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.3)])]),
            .removeFromParent(),
        ]))

        if boss { successHaptic.notificationOccurred(.success) }
    }

    private func spawnMonsterNode(animated: Bool) {
        monsterNode?.removeFromParent()
        let monster = game.monster
        let texture = Self.texture(monster.sprite)
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: texture.size().width * Self.pixel, height: texture.size().height * Self.pixel)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.position = monsterPosition
        node.zPosition = 3
        addChild(node)
        monsterNode = node

        let shadowWidth = node.size.width * 0.75
        monsterShadow.path = CGPath(ellipseIn: CGRect(x: -shadowWidth / 2, y: -7, width: shadowWidth, height: 14), transform: nil)
        monsterShadow.position = monsterPosition
        monsterShadow.removeAllActions()
        monsterShadow.alpha = 1

        if animated {
            node.alpha = 0
            node.position.y = monsterPosition.y + 6 * Self.pixel
            let drop = SKAction.moveTo(y: monsterPosition.y, duration: 0.16)
            drop.timingMode = .easeIn
            node.run(.sequence([
                .group([drop, .fadeIn(withDuration: 0.1)]),
                .run { [weak node] in node?.run(Self.idleBob(period: 0.42), withKey: "idle") },
            ]), withKey: "spawn")
        } else {
            node.run(Self.idleBob(period: 0.42), withKey: "idle")
        }
        if monster.isBoss, animated { showBanner("BOSS !") }
    }

    /// L'objet jaillit du monstre, s'affiche au centre avec son nom, puis file vers le sac.
    private func showLoot(_ item: Item, outcome: LootOutcome) {
        let color = item.rarity.uiColor
        let holder = SKNode()
        holder.position = CGPoint(x: monsterPosition.x, y: monsterPosition.y + 30)
        holder.zPosition = 18
        holder.setScale(0.3)
        addChild(holder)

        let plate = SKShapeNode(rectOf: CGSize(width: 60, height: 60), cornerRadius: 8)
        plate.fillColor = UIColor(red: 0.10, green: 0.11, blue: 0.17, alpha: 0.85)
        plate.strokeColor = color
        plate.lineWidth = 3
        holder.addChild(plate)

        let icon = SKSpriteNode(texture: Self.texture(item.sprite), size: CGSize(width: 48, height: 48))
        holder.addChild(icon)

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

        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let arrive = SKAction.group([.move(to: center, duration: 0.3), .scale(to: 1, duration: 0.3)])
        arrive.timingMode = .easeOut
        let leave = SKAction.group([
            .move(to: CGPoint(x: size.width * 0.75, y: -30), duration: 0.35),
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
        banner.alpha = 0
        banner.setScale(0.6)
        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.15)]),
            .wait(forDuration: 0.8),
            .fadeOut(withDuration: 0.3),
        ]))
    }
}
