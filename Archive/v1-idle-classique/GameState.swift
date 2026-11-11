import Foundation
import Observation

// MARK: - Améliorations

enum UpgradeKind: String, CaseIterable, Codable, Identifiable {
    case damage, speed, crit, gold, tap

    var id: String { rawValue }

    var name: String {
        switch self {
        case .damage: "Bâton runique"
        case .speed: "Incantation rapide"
        case .crit: "Œil du faucon"
        case .gold: "Bourse sans fond"
        case .tap: "Gants de foudre"
        }
    }

    var icon: String {
        switch self {
        case .damage: "wand.and.stars"
        case .speed: "bolt.fill"
        case .crit: "scope"
        case .gold: "bag.fill"
        case .tap: "hand.tap.fill"
        }
    }

    var baseCost: Double {
        switch self {
        case .damage: 5
        case .speed: 40
        case .crit: 80
        case .gold: 60
        case .tap: 25
        }
    }

    var growth: Double {
        switch self {
        case .damage: 1.15
        case .speed: 1.35
        case .crit: 1.4
        case .gold: 1.3
        case .tap: 1.25
        }
    }

    var maxLevel: Int? {
        switch self {
        case .speed: 30
        case .crit: 25
        default: nil
        }
    }
}

// MARK: - Monstres

struct Monster {
    /// Nom de l'image dans le catalogue d'assets.
    let sprite: String
    let name: String
    let isBoss: Bool
    let maxHP: Double
    var hp: Double

    static let normals: [(String, String)] = [
        ("monster_rat", "Rat géant"), ("monster_bat", "Chauve-souris"), ("monster_spider", "Araignée"),
        ("monster_snake", "Vipère"), ("monster_wolf", "Loup"), ("monster_zombie", "Zombie"),
        ("monster_skeleton", "Squelette"), ("monster_ghost", "Spectre"), ("monster_ogre", "Ogre"),
        ("monster_troll", "Troll"),
    ]
    static let bosses: [(String, String)] = [
        ("boss_dragon", "Dragon"), ("boss_demon", "Démon"), ("boss_kraken", "Kraken"),
        ("boss_vampire", "Vampire"), ("boss_scorpion", "Scorpion royal"),
    ]
}

// MARK: - Évènements envoyés à la scène de combat

enum GameEvent {
    case heroAttack(damage: Double, crit: Bool)
    case tap(damage: Double)
    case monsterDied(gold: Double, boss: Bool)
    case monsterSpawned
    case stageCleared(stage: Int)
    case loot(item: Item, outcome: LootOutcome)
}

struct OfflineReport: Identifiable {
    let id = UUID()
    let seconds: TimeInterval
    let gold: Double
}

// MARK: - État du jeu

@Observable
final class GameState {
    static let monstersPerStage = 10
    static let critMultiplier = 3.0
    static let maxOfflineSeconds: TimeInterval = 8 * 3600
    static let offlineEfficiency = 0.5
    static let bagCapacity = 20
    static let dropChance = 0.12

    private(set) var gold: Double = 0
    private(set) var stage = 1
    /// Nombre de monstres déjà vaincus dans la zone. Le dernier est un boss.
    private(set) var killsInStage = 0
    private(set) var totalKills = 0
    private(set) var levels: [UpgradeKind: Int] = [:]
    private(set) var monster: Monster
    private(set) var equipped: [ItemSlot: Item] = [:]
    private(set) var bag: [Item] = []
    /// Objets ramassés depuis la dernière visite de l'onglet Équipement.
    private(set) var unseenLoot = 0
    var offlineReport: OfflineReport?

    @ObservationIgnored var onEvent: ((GameEvent) -> Void)?
    @ObservationIgnored private var attackTimer = 0.0
    @ObservationIgnored private var respawnTimer = 0.0
    @ObservationIgnored private var saveTimer = 0.0
    @ObservationIgnored private var lastSeen = Date()
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var dropChance = GameState.dropChance

    private static let saveKey = "save.v1"
    private static let respawnDelay = 0.35

    init() {
        monster = Self.makeMonster(stage: 1, killsInStage: 0)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugReset") {
            UserDefaults.standard.removeObject(forKey: Self.saveKey)
        }
        #endif
        load()
        #if DEBUG
        let fakeAbsence = UserDefaults.standard.double(forKey: "debugOfflineSeconds")
        if fakeAbsence > 0 { lastSeen = Date().addingTimeInterval(-fakeAbsence) }
        let forcedDropRate = UserDefaults.standard.double(forKey: "debugDropRate")
        if forcedDropRate > 0 { dropChance = forcedDropRate }
        #endif
        applyOfflineProgress()
    }

    // MARK: Statistiques dérivées

    func level(_ kind: UpgradeKind) -> Int { levels[kind] ?? 0 }

    var damage: Double { damage(atLevel: level(.damage)) }
    var attacksPerSecond: Double { attacksPerSecond(atLevel: level(.speed)) }
    var critChance: Double { critChance(atLevel: level(.crit)) }
    var goldMultiplier: Double { goldMultiplier(atLevel: level(.gold)) }
    var tapDamage: Double { (damage * Self.tapMultiplier(atLevel: level(.tap))).rounded() }

    /// Bonus de l'objet équipé dans un emplacement, en fraction (0.25 pour +25 %).
    private func gear(_ slot: ItemSlot) -> Double { (equipped[slot]?.bonus ?? 0) / 100 }

    private func damage(atLevel level: Int) -> Double {
        (Self.baseDamage(atLevel: level) * (1 + gear(.weapon))).rounded()
    }
    private func attacksPerSecond(atLevel level: Int) -> Double {
        Self.baseAttacksPerSecond(atLevel: level) * (1 + gear(.boots))
    }
    private func critChance(atLevel level: Int) -> Double {
        min(Self.baseCritChance(atLevel: level) + gear(.ring), 1)
    }
    private func goldMultiplier(atLevel level: Int) -> Double {
        Self.baseGoldMultiplier(atLevel: level) * (1 + gear(.amulet))
    }

    var dps: Double {
        damage * attacksPerSecond * (1 + critChance * (Self.critMultiplier - 1))
    }

    var isBossFight: Bool { monster.isBoss }

    /// Estimation de l'or gagné par seconde en combat automatique dans la zone actuelle.
    var goldPerSecond: Double {
        let hp = Self.monsterHP(stage: stage, boss: false)
        let secondsPerKill = max(hp / max(dps, 0.01), 0.1) + Self.respawnDelay
        return reward(maxHP: hp, boss: false) / secondsPerKill
    }

    static func baseDamage(atLevel level: Int) -> Double {
        let l = Double(level)
        return (1 + l) * pow(1.06, l)
    }
    static func baseAttacksPerSecond(atLevel level: Int) -> Double { 1 + 0.1 * Double(level) }
    static func baseCritChance(atLevel level: Int) -> Double { 0.05 + 0.02 * Double(level) }
    static func baseGoldMultiplier(atLevel level: Int) -> Double { 1 + 0.15 * Double(level) }
    static func tapMultiplier(atLevel level: Int) -> Double { 1 + 0.5 * Double(level) }

    static func monsterHP(stage: Int, boss: Bool) -> Double {
        (8 * pow(1.5, Double(stage - 1)) * (boss ? 6 : 1)).rounded()
    }

    private func reward(maxHP: Double, boss: Bool) -> Double {
        (maxHP * 0.35 * (boss ? 1.5 : 1) * goldMultiplier).rounded(.up)
    }

    private static func makeMonster(stage: Int, killsInStage: Int) -> Monster {
        let boss = killsInStage == monstersPerStage - 1
        let hp = monsterHP(stage: stage, boss: boss)
        if boss {
            let (sprite, name) = Monster.bosses[(stage - 1) % Monster.bosses.count]
            return Monster(sprite: sprite, name: name, isBoss: true, maxHP: hp, hp: hp)
        }
        let (sprite, name) = Monster.normals[(stage - 1 + killsInStage) % Monster.normals.count]
        return Monster(sprite: sprite, name: name, isBoss: false, maxHP: hp, hp: hp)
    }

    // MARK: Boucle de jeu

    /// Appelé à chaque image par la scène de combat.
    func tick(dt rawDt: TimeInterval) {
        guard !isSuspended else { return }
        let dt = min(max(rawDt, 0), 0.25)

        saveTimer += dt
        if saveTimer >= 10 {
            saveTimer = 0
            save()
        }

        if respawnTimer > 0 {
            respawnTimer -= dt
            if respawnTimer <= 0 { onEvent?(.monsterSpawned) }
            return
        }

        attackTimer += dt
        let interval = 1 / attacksPerSecond
        while attackTimer >= interval, respawnTimer <= 0 {
            attackTimer -= interval
            let crit = Double.random(in: 0..<1) < critChance
            let dealt = crit ? damage * Self.critMultiplier : damage
            onEvent?(.heroAttack(damage: dealt, crit: crit))
            hit(dealt)
        }
    }

    /// Attaque manuelle du joueur.
    func tap() {
        guard !isSuspended, respawnTimer <= 0 else { return }
        let dealt = tapDamage
        onEvent?(.tap(damage: dealt))
        hit(dealt)
    }

    private func hit(_ amount: Double) {
        monster.hp -= amount
        guard monster.hp <= 0 else { return }

        let earned = reward(maxHP: monster.maxHP, boss: monster.isBoss)
        gold += earned
        totalKills += 1
        killsInStage += 1
        onEvent?(.monsterDied(gold: earned, boss: monster.isBoss))
        rollLoot(boss: monster.isBoss)

        if killsInStage >= Self.monstersPerStage {
            stage += 1
            killsInStage = 0
            onEvent?(.stageCleared(stage: stage))
        }
        monster = Self.makeMonster(stage: stage, killsInStage: killsInStage)
        respawnTimer = Self.respawnDelay
        attackTimer = 0
    }

    // MARK: Boutique

    func cost(of kind: UpgradeKind) -> Double {
        (kind.baseCost * pow(kind.growth, Double(level(kind)))).rounded(.up)
    }

    func isMaxed(_ kind: UpgradeKind) -> Bool {
        guard let max = kind.maxLevel else { return false }
        return level(kind) >= max
    }

    func canBuy(_ kind: UpgradeKind) -> Bool {
        !isMaxed(kind) && gold >= cost(of: kind)
    }

    @discardableResult
    func buy(_ kind: UpgradeKind) -> Bool {
        guard canBuy(kind) else { return false }
        gold -= cost(of: kind)
        levels[kind] = level(kind) + 1
        save()
        return true
    }

    /// Texte de l'effet actuel et de l'effet au niveau suivant.
    func effect(of kind: UpgradeKind) -> (current: String, next: String) {
        let l = level(kind)
        func percent(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }
        switch kind {
        case .damage:
            return ("\(damage(atLevel: l).short) dégâts", damage(atLevel: l + 1).short)
        case .speed:
            return (String(format: "%.1f att./s", attacksPerSecond(atLevel: l)),
                    String(format: "%.1f", attacksPerSecond(atLevel: l + 1)))
        case .crit:
            return ("\(percent(critChance(atLevel: l))) de critique ×3", percent(critChance(atLevel: l + 1)))
        case .gold:
            return ("+\(percent(goldMultiplier(atLevel: l) - 1)) d'or", "+" + percent(goldMultiplier(atLevel: l + 1) - 1))
        case .tap:
            let now = (damage * Self.tapMultiplier(atLevel: l)).rounded()
            let next = (damage * Self.tapMultiplier(atLevel: l + 1)).rounded()
            return ("\(now.short) dégâts au toucher", next.short)
        }
    }

    // MARK: Butin et équipement

    private func rollLoot(boss: Bool) {
        guard boss || Double.random(in: 0..<1) < dropChance else { return }
        let item = Item.random(stage: stage, boss: boss)
        if equipped[item.slot] == nil {
            equipped[item.slot] = item
            onEvent?(.loot(item: item, outcome: .equipped))
        } else if bag.count < Self.bagCapacity {
            bag.append(item)
            unseenLoot += 1
            onEvent?(.loot(item: item, outcome: .stored))
        } else {
            gold += item.sellValue
            onEvent?(.loot(item: item, outcome: .sold))
        }
    }

    /// Vrai si l'objet est meilleur que celui porté dans le même emplacement.
    func isUpgrade(_ item: Item) -> Bool {
        item.bonus > (equipped[item.slot]?.bonus ?? 0)
    }

    func isEquipped(_ item: Item) -> Bool {
        equipped[item.slot]?.id == item.id
    }

    /// Équipe un objet du sac. L'ancien objet retourne dans le sac.
    func equip(_ item: Item) {
        guard let index = bag.firstIndex(where: { $0.id == item.id }) else { return }
        bag.remove(at: index)
        if let previous = equipped[item.slot] { bag.insert(previous, at: index) }
        equipped[item.slot] = item
        save()
    }

    func sell(_ item: Item) {
        guard let index = bag.firstIndex(where: { $0.id == item.id }) else { return }
        bag.remove(at: index)
        gold += item.sellValue
        save()
    }

    var bagSellValue: Double { bag.reduce(0) { $0 + $1.sellValue } }

    func sellBag() {
        gold += bagSellValue
        bag.removeAll()
        save()
    }

    func markLootSeen() {
        if unseenLoot != 0 { unseenLoot = 0 }
    }

    // MARK: Hors ligne

    /// L'application passe en arrière-plan.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        save()
    }

    /// L'application revient au premier plan.
    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        applyOfflineProgress()
    }

    private func applyOfflineProgress(now: Date = Date()) {
        let elapsed = min(now.timeIntervalSince(lastSeen), Self.maxOfflineSeconds)
        lastSeen = now
        guard elapsed >= 60 else { return }
        let earned = (goldPerSecond * elapsed * Self.offlineEfficiency).rounded(.down)
        guard earned >= 1 else { return }
        gold += earned
        offlineReport = OfflineReport(seconds: elapsed, gold: earned)
        save()
    }

    // MARK: Sauvegarde

    private struct SaveData: Codable {
        var gold: Double
        var stage: Int
        var killsInStage: Int
        var totalKills: Int
        var levels: [String: Int]
        var lastSeen: Date
        // Ajoutés après la première version : absents des anciennes sauvegardes.
        var equipped: [String: Item]?
        var bag: [Item]?
    }

    func save() {
        lastSeen = Date()
        let data = SaveData(
            gold: gold,
            stage: stage,
            killsInStage: killsInStage,
            totalKills: totalKills,
            levels: Dictionary(uniqueKeysWithValues: levels.map { ($0.key.rawValue, $0.value) }),
            lastSeen: lastSeen,
            equipped: Dictionary(uniqueKeysWithValues: equipped.map { ($0.key.rawValue, $0.value) }),
            bag: bag
        )
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: Self.saveKey)
        }
    }

    private func load() {
        guard let raw = UserDefaults.standard.data(forKey: Self.saveKey),
              let data = try? JSONDecoder().decode(SaveData.self, from: raw) else { return }
        gold = data.gold
        stage = max(data.stage, 1)
        killsInStage = min(max(data.killsInStage, 0), Self.monstersPerStage - 1)
        totalKills = data.totalKills
        levels = [:]
        for (key, value) in data.levels {
            if let kind = UpgradeKind(rawValue: key) { levels[kind] = value }
        }
        equipped = [:]
        for (key, item) in data.equipped ?? [:] {
            if let slot = ItemSlot(rawValue: key) { equipped[slot] = item }
        }
        bag = Array((data.bag ?? []).prefix(Self.bagCapacity))
        lastSeen = data.lastSeen
        monster = Self.makeMonster(stage: stage, killsInStage: killsInStage)
    }

    /// Efface la progression et repart de zéro.
    func reset() {
        gold = 0
        stage = 1
        killsInStage = 0
        totalKills = 0
        levels = [:]
        equipped = [:]
        bag = []
        unseenLoot = 0
        attackTimer = 0
        respawnTimer = Self.respawnDelay
        monster = Self.makeMonster(stage: 1, killsInStage: 0)
        onEvent?(.monsterDied(gold: 0, boss: false))
        save()
    }
}
