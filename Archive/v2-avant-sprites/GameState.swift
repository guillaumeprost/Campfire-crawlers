import Foundation
import Observation

// MARK: - Évènements envoyés à la scène

enum GameEvent {
    case roomResolved(Room)
    case loot(item: Item, outcome: LootOutcome)
    case levelUp(Int)
    case potionUsed(Double)
    case fled(TripReason)
    case dungeonCleared(String)
}

// MARK: - État du jeu

/// Tout le jeu avance sur une horloge interne (`clock`, en secondes de jeu).
/// Elle suit le temps réel, même application fermée : au retour on rejoue
/// d'un coup tout ce qui s'est passé pendant l'absence.
@Observable
final class GameState {
    static let bagCapacity = 20
    static let maxPotions = 3
    static let maxEnergy = 100.0
    /// Sous cette part de PV, le héros refuse de continuer.
    static let fleeThreshold = 0.25
    /// Part d'une salle passée à marcher avant la rencontre.
    static let walkShare = 0.3
    static let testTimeScale = 30.0

    // Héros
    private(set) var gold: Double = 0
    private(set) var level = 1
    private(set) var xp: Double = 0
    private(set) var hp: Double = 100
    private(set) var energy: Double = GameState.maxEnergy
    private(set) var potions = 0
    private(set) var scrollReady = false
    private(set) var hasBedroll = false
    private(set) var equipped: [ItemSlot: Item] = [:]
    private(set) var bag: [Item] = []
    /// Objets ramassés depuis la dernière visite de l'onglet Équipement.
    private(set) var unseenLoot = 0

    // Monde
    private(set) var activity: Activity = .resting
    private(set) var clears: [Int] = Array(repeating: 0, count: Dungeon.all.count)
    private(set) var shopStock: [Item] = []
    private(set) var journal: [JournalEntry] = []
    /// Copie de l'horloge rafraîchie quelques fois par seconde, pour l'interface.
    private(set) var uiClock: TimeInterval = 0
    /// 1 en jeu normal. Le mode test accélère tout.
    private(set) var timeScale: Double = 1
    var awayReport: AwayReport?

    @ObservationIgnored var onEvent: ((GameEvent) -> Void)?
    @ObservationIgnored private(set) var clock: TimeInterval = 0
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var lastUIRefresh = Date.distantPast
    @ObservationIgnored private var lastSave = Date()
    /// Temps de repos pas encore converti en PV et en énergie.
    @ObservationIgnored private var restDebt: TimeInterval = 0
    @ObservationIgnored private var journalSerial = 0
    /// Source de tous les tirages. Son état est sauvegardé avec la partie.
    @ObservationIgnored private var rng = SeededGenerator(state: UInt64.random(in: 0...UInt64.max))
    /// Vrai pour la copie du jeu qui sert à prévoir la suite : elle ne sauvegarde ni ne notifie rien.
    @ObservationIgnored private var isForecast = false

    private static let saveKey = "save.v2"
    private static let timeScaleKey = "testTimeScale"

    init() {
        let defaults = UserDefaults.standard
        #if DEBUG
        if defaults.bool(forKey: "debugReset") { defaults.removeObject(forKey: Self.saveKey) }
        #endif
        timeScale = defaults.bool(forKey: Self.timeScaleKey) ? Self.testTimeScale : 1
        let hadSave = load()
        #if DEBUG
        let scale = defaults.double(forKey: "debugTimeScale")
        if scale > 0 { timeScale = scale }
        gold += defaults.double(forKey: "debugGold")
        #endif
        if hadSave {
            catchUp()
        } else {
            log("flame.fill", "Le héros s'installe au feu de camp. Choisissez un donjon sur la carte.", .neutral)
        }
        uiClock = clock
        replan()
    }

    /// Copie silencieuse du jeu, utilisée pour prévoir la suite.
    private init(twinOf data: SaveData, timeScale: Double) {
        isForecast = true
        self.timeScale = timeScale
        apply(data)
    }

    // MARK: Caractéristiques

    private func gear(_ slot: ItemSlot) -> Double { equipped[slot]?.bonus ?? 0 }

    var maxHP: Double { 100 + 20 * Double(level - 1) + gear(.amulet) }
    var attack: Double { 10 + 3 * Double(level - 1) + gear(.weapon) }
    /// Fraction : 0.2 pour +20 %.
    var speedBonus: Double { gear(.boots) / 100 }
    var luck: Double { gear(.ring) / 100 }
    var xpNeeded: Double { (30 * pow(1.3, Double(level - 1))).rounded() }

    private var restBoost: Double { hasBedroll ? 1.5 : 1 }
    /// PV et énergie regagnés par seconde de jeu au feu de camp.
    private var hpRegen: Double { maxHP * 0.06 / 60 * restBoost }
    private var energyRegen: Double { 10.0 / 60 * restBoost }

    var isRecovering: Bool { hp < maxHP || energy < Self.maxEnergy }

    var isShopping: Bool { if case .shopping = activity { true } else { false } }
    var isExploring: Bool { if case .exploring = activity { true } else { false } }

    /// Le héros est libre de partir : il est au camp ou à la boutique.
    var currentPlace: Place? {
        switch activity {
        case .resting: .camp
        case .shopping: .shop
        default: nil
        }
    }

    /// PV affichés : pendant un combat ils baissent peu à peu jusqu'à l'issue de la salle.
    var shownHP: Double {
        guard case .exploring(let run) = activity, run.room.hpDelta < 0 else { return hp }
        let span = run.roomEnd - run.roomStart
        guard span > 0 else { return hp }
        let progress = (uiClock - run.roomStart) / span
        let fight = min(max((progress - Self.walkShare) / (1 - Self.walkShare), 0), 1)
        return max(hp + run.room.hpDelta * fight, 1)
    }

    // MARK: Donjons

    func isUnlocked(_ dungeon: Dungeon) -> Bool {
        dungeon.id == 0 || clears[dungeon.id - 1] > 0
    }

    /// Palier du dernier donjon terminé : il fixe l'offre et les prix de la boutique.
    var shopTier: Int {
        Dungeon.all.last(where: { clears[$0.id] > 0 })?.tier ?? 1
    }

    /// Raison qui empêche d'entrer dans un donjon, ou nil si tout va bien.
    func entryBlocker(_ dungeon: Dungeon) -> String? {
        if hp <= maxHP * Self.fleeThreshold { return "Trop blessé" }
        if energy < dungeon.roomEnergy * 2 { return "Trop fatigué" }
        return nil
    }

    /// Compare les dégâts attendus aux PV que le héros peut perdre avant de fuir.
    func risk(of dungeon: Dungeon) -> Risk {
        let power = attack * (scrollReady ? 1.25 : 1)
        let others = Double(dungeon.rooms - 1)
        let perMonster = dungeon.monsterDamage * max(ceil(dungeon.monsterHP / power) - 1, 0.25)
        let boss = dungeon.monsterDamage * 1.5 * max(ceil(dungeon.monsterHP * 3 / power) - 1, 0.25)
        let traps = others * 0.10 * dungeon.monsterDamage * 1.5
        let healing = others * 0.15 * maxHP * 0.15 + Double(potions) * maxHP * 0.4
        let expected = others * 0.55 * perMonster + boss + traps - healing * 0.7
        let budget = max(hp - maxHP * Self.fleeThreshold, 1)
        switch expected / budget {
        case ..<0.55: return .easy
        case ..<0.9: return .fair
        case ..<1.2: return .risky
        default: return .deadly
        }
    }

    // MARK: Déplacements

    /// Durée d'un trajet en secondes de jeu. Tout passe par le camp.
    func travelTime(from: Place, to: Place) -> TimeInterval {
        (from.distance + to.distance) / (1 + speedBonus)
    }

    /// Envoie le héros quelque part. Possible seulement au camp ou à la boutique.
    func travel(to destination: Place) {
        guard let here = currentPlace, here != destination else { return }
        if case .dungeon(let index) = destination {
            let dungeon = Dungeon.all[index]
            guard isUnlocked(dungeon), entryBlocker(dungeon) == nil else { return }
        }
        settleRest()
        let duration = travelTime(from: here, to: destination)
        activity = .traveling(Trip(from: here, to: destination, start: clock, end: clock + duration, reason: .normal))
        log("figure.walk", "Départ pour \(destination.name), \(duration.shortDuration) de marche.", .neutral)
        refreshUI()
        save()
        Outreach.askPermission()
        replan()
    }

    /// Rappelle le héros au camp en pleine exploration. Il garde son butin.
    func recall() {
        guard case .exploring(let run) = activity else { return }
        log("arrow.uturn.backward", "Rappelé au camp avec \(run.gold.short) or et \(Self.count(run.items, "objet")).", .neutral)
        headHome(from: run.dungeon, at: clock, reason: .recalled)
        refreshUI()
        save()
        replan()
    }

    private func headHome(from dungeon: Int, at time: TimeInterval, reason: TripReason) {
        let place = Place.dungeon(dungeon)
        let duration = travelTime(from: place, to: .camp)
        activity = .traveling(Trip(from: place, to: .camp, start: time, end: time + duration, reason: reason))
    }

    // MARK: Horloge

    /// Appelé à chaque image par la scène.
    func tick(now: Date = Date()) {
        let real = now.timeIntervalSince(lastTick)
        guard real > 0 else { return }
        lastTick = now
        advance(by: real * timeScale, live: real < 2)
        if now.timeIntervalSince(lastUIRefresh) >= 0.2 {
            lastUIRefresh = now
            settleRest()
            uiClock = clock
        }
        if now.timeIntervalSince(lastSave) >= 10 { save() }
    }

    private func refreshUI() {
        lastUIRefresh = Date()
        uiClock = clock
    }

    /// Avance l'horloge en traitant dans l'ordre chaque arrivée et chaque fin de salle.
    private func advance(by delta: TimeInterval, live: Bool) {
        let target = clock + delta
        while true {
            let event = nextEventTime
            let until = min(event ?? target, target)
            if until > clock {
                if case .resting = activity { restDebt += until - clock }
                clock = until
            }
            guard let event, event <= target else { break }
            handleEvent(live: live)
        }
    }

    private var nextEventTime: TimeInterval? {
        switch activity {
        case .traveling(let trip): trip.end
        case .exploring(let run): run.roomEnd
        case .resting, .shopping: nil
        }
    }

    private func handleEvent(live: Bool) {
        switch activity {
        case .traveling(let trip):
            arrive(trip)
            if live { replan() }
        case .exploring(let run): resolve(run, live: live)
        case .resting, .shopping: break
        }
    }

    /// Convertit le temps de repos accumulé en PV et en énergie.
    private func settleRest() {
        guard restDebt > 0 else { return }
        let rested = restDebt
        restDebt = 0
        if hp < maxHP { hp = min(maxHP, hp + hpRegen * rested) }
        if energy < Self.maxEnergy { energy = min(Self.maxEnergy, energy + energyRegen * rested) }
    }

    // MARK: Arrivées

    private func arrive(_ trip: Trip) {
        switch trip.to {
        case .camp:
            activity = .resting
            log("flame.fill", "De retour au feu de camp. Le héros se repose.", .neutral)
        case .shop:
            restock()
            activity = .shopping
            log("cart.fill", "Arrivé à la boutique.", .neutral)
        case .dungeon(let index):
            let dungeon = Dungeon.all[index]
            let boosted = scrollReady
            scrollReady = false
            let room = makeRoom(dungeon, index: 0, boosted: boosted)
            activity = .exploring(Run(dungeon: index, roomIndex: 0, roomStart: trip.end,
                                      roomEnd: trip.end + dungeon.roomDuration, room: room,
                                      gold: 0, items: 0, boosted: boosted))
            log("door.left.hand.open", "Entre dans \(dungeon.name)\(boosted ? ", parchemin de force actif" : "").", .neutral)
        }
    }

    // MARK: Salles

    private func makeRoom(_ dungeon: Dungeon, index: Int, boosted: Bool) -> Room {
        let kind: RoomKind
        if index == dungeon.rooms - 1 {
            kind = .boss
        } else if index == 0 {
            kind = .monster
        } else {
            switch Double.random(in: 0..<1, using: &rng) {
            case ..<0.55: kind = .monster
            case ..<0.75: kind = .chest
            case ..<0.85: kind = .trap
            default: kind = .fountain
            }
        }
        let spread = Double.random(in: 0.8...1.2, using: &rng)

        switch kind {
        case .monster, .boss:
            let boss = kind == .boss
            let foe = boss ? dungeon.boss : (dungeon.monsters.randomElement(using: &rng) ?? dungeon.monsters[0])
            let foeHP = dungeon.monsterHP * (boss ? 3 : 1)
            let foeDamage = dungeon.monsterDamage * (boss ? 1.5 : 1)
            // Le héros frappe le premier : le monstre riposte une fois de moins.
            let rounds = ceil(foeHP / (attack * (boosted ? 1.25 : 1)))
            let damage = (foeDamage * max(rounds - 1, 0.25) * spread).rounded()
            let needsPotion = damage >= hp
            if needsPotion, potions == 0 || damage >= hp + potionHeal {
                return Room(kind: kind, sprite: foe.sprite, name: foe.name, hpDelta: -(hp - woundedHP),
                            gold: 0, xp: 0, item: nil, knockedOut: true)
            }
            var item: Item?
            if boss {
                item = Item.random(tier: dungeon.tier, floor: .rare, luck: luck, using: &rng)
            } else if Double.random(in: 0..<1, using: &rng) < 0.08 * (1 + luck) {
                item = Item.random(tier: dungeon.tier, luck: luck, using: &rng)
            }
            return Room(kind: kind, sprite: foe.sprite, name: foe.name,
                        hpDelta: needsPotion ? potionHeal - damage : -damage,
                        gold: (dungeon.gold * (boss ? 10 : 1) * spread).rounded(),
                        xp: dungeon.xp * (boss ? 5 : 1), item: item, knockedOut: false,
                        usesPotion: needsPotion)
        case .chest:
            let lucky = Double.random(in: 0..<1, using: &rng) < min(0.5 * (1 + luck), 0.95)
            return Room(kind: .chest, sprite: "chest_closed", name: "Coffre", hpDelta: 0,
                        gold: (dungeon.gold * 4 * spread).rounded(), xp: 0,
                        item: lucky ? Item.random(tier: dungeon.tier, luck: luck, using: &rng) : nil, knockedOut: false)
        case .trap:
            let damage = (dungeon.monsterDamage * 1.5 * spread).rounded()
            let fatal = damage >= hp
            return Room(kind: .trap, sprite: "spikes", name: "Piège",
                        hpDelta: fatal ? -(hp - woundedHP) : -damage,
                        gold: 0, xp: 0, item: nil, knockedOut: fatal)
        case .fountain:
            return Room(kind: .fountain, sprite: "fountain", name: "Fontaine",
                        hpDelta: (maxHP * 0.15).rounded(), gold: 0, xp: 0, item: nil, knockedOut: false)
        }
    }

    /// PV rendus par une potion.
    private var potionHeal: Double { (maxHP * 0.4).rounded() }

    /// PV restants après une fuite de justesse.
    private var woundedHP: Double { min(hp, max((maxHP * 0.05).rounded(), 1)) }

    private func resolve(_ finished: Run, live: Bool) {
        var run = finished
        let dungeon = Dungeon.all[run.dungeon]
        let room = run.room
        let label = room.kind == .boss ? "Boss" : "Salle \(run.roomIndex + 1)"

        if room.usesPotion == true, potions > 0 {
            potions -= 1
            log("cross.vial.fill", "Potion bue en plein combat : +\(Int(potionHeal)) PV.", .good)
            if live { onEvent?(.potionUsed(potionHeal)) }
        }
        hp = min(max(hp + room.hpDelta, 1), maxHP)
        energy = max(energy - dungeon.roomEnergy, 0)
        gold += room.gold
        run.gold += room.gold
        if live { onEvent?(.roomResolved(room)) }

        if room.knockedOut {
            log("heart.slash.fill", "\(label) · \(room.name) : défaite. Le héros fuit, gravement blessé.", .bad)
            flee(run, at: run.roomEnd, reason: .fled, live: live)
            return
        }

        let damage = Int(-room.hpDelta + (room.usesPotion == true ? potionHeal : 0))
        switch room.kind {
        case .monster, .boss:
            log("bolt.fill", "\(label) · \(room.name) : victoire, -\(damage) PV, +\(room.gold.short) or.", .good)
        case .chest:
            log("shippingbox.fill", "\(label) · Coffre : +\(room.gold.short) or.", .good)
        case .trap:
            log("exclamationmark.triangle.fill", "\(label) · Piège : -\(damage) PV.", .bad)
        case .fountain:
            log("drop.fill", "\(label) · Fontaine : +\(Int(room.hpDelta)) PV.", .good)
        }
        gainXP(room.xp, live: live)
        if let item = room.item {
            addLoot(item, live: live)
            run.items += 1
        }

        if run.roomIndex == dungeon.rooms - 1 {
            let first = clears[run.dungeon] == 0
            clears[run.dungeon] += 1
            var text = "Donjon terminé : \(dungeon.name). Butin : \(run.gold.short) or et \(Self.count(run.items, "objet"))."
            if first, run.dungeon + 1 < Dungeon.all.count {
                text += " Nouveau donjon : \(Dungeon.all[run.dungeon + 1].name)."
            }
            log("trophy.fill", text, .good)
            if live { onEvent?(.dungeonCleared(dungeon.name)) }
            headHome(from: run.dungeon, at: run.roomEnd, reason: .victory)
            return
        }

        if hp <= maxHP * Self.fleeThreshold {
            if potions > 0 {
                potions -= 1
                let healed = potionHeal
                hp = min(maxHP, hp + healed)
                log("cross.vial.fill", "Potion bue : +\(Int(healed)) PV.", .good)
                if live { onEvent?(.potionUsed(healed)) }
            } else {
                log("figure.run", "Trop blessé pour continuer : le héros fuit vers le camp.", .bad)
                flee(run, at: run.roomEnd, reason: .fled, live: live)
                return
            }
        }
        if energy < dungeon.roomEnergy {
            log("battery.0percent", "À bout de forces : le héros rentre au camp.", .bad)
            flee(run, at: run.roomEnd, reason: .exhausted, live: live)
            return
        }

        run.roomIndex += 1
        run.roomStart = run.roomEnd
        run.roomEnd = run.roomStart + dungeon.roomDuration
        run.room = makeRoom(dungeon, index: run.roomIndex, boosted: run.boosted)
        activity = .exploring(run)
    }

    private func flee(_ run: Run, at time: TimeInterval, reason: TripReason, live: Bool) {
        if live { onEvent?(.fled(reason)) }
        headHome(from: run.dungeon, at: time, reason: reason)
    }

    private func gainXP(_ amount: Double, live: Bool) {
        guard amount > 0 else { return }
        xp += amount
        while xp >= xpNeeded {
            xp -= xpNeeded
            level += 1
            hp += 20
            log("star.fill", "Niveau \(level) atteint : +3 attaque, +20 PV max.", .good)
            if live { onEvent?(.levelUp(level)) }
        }
    }

    // MARK: Butin et équipement

    private func addLoot(_ item: Item, live: Bool) {
        let outcome: LootOutcome
        if equipped[item.slot] == nil {
            equipped[item.slot] = item
            outcome = .equipped
            log("sparkles", "Objet trouvé et équipé : \(item.name) (\(item.bonusText)).", .good)
        } else if bag.count < Self.bagCapacity {
            bag.append(item)
            unseenLoot += 1
            outcome = .stored
            log("sparkles", "Objet trouvé : \(item.name) (\(item.bonusText)).", .good)
        } else {
            gold += item.sellValue
            outcome = .sold
            log("sparkles", "Sac plein : \(item.name) vendu \(item.sellValue.short) or.", .neutral)
        }
        if live { onEvent?(.loot(item: item, outcome: outcome)) }
    }

    /// Vrai si l'objet est meilleur que celui porté dans le même emplacement.
    func isUpgrade(_ item: Item) -> Bool {
        item.bonus > (equipped[item.slot]?.bonus ?? 0)
    }

    /// Équipe un objet du sac. L'ancien objet retourne dans le sac.
    func equip(_ item: Item) {
        guard let index = bag.firstIndex(where: { $0.id == item.id }) else { return }
        let ratio = hp / maxHP
        bag.remove(at: index)
        if let previous = equipped[item.slot] { bag.insert(previous, at: index) }
        equipped[item.slot] = item
        // Changer d'amulette garde la même proportion de PV.
        if item.slot == .amulet { hp = max((maxHP * ratio).rounded(), 1) }
        hp = min(hp, maxHP)
        save()
        replan()
    }

    /// Vendre n'est possible qu'à la boutique.
    func sell(_ item: Item) {
        guard isShopping, let index = bag.firstIndex(where: { $0.id == item.id }) else { return }
        bag.remove(at: index)
        gold += item.sellValue
        save()
    }

    var bagSellValue: Double { bag.reduce(0) { $0 + $1.sellValue } }

    func sellBag() {
        guard isShopping else { return }
        gold += bagSellValue
        bag.removeAll()
        save()
    }

    func markLootSeen() {
        if unseenLoot != 0 { unseenLoot = 0 }
    }

    // MARK: Boutique

    private func restock() {
        let tier = shopTier
        shopStock = [
            Item.random(tier: tier, using: &rng),
            Item.random(tier: tier, using: &rng),
            Item.random(tier: tier, floor: .rare, using: &rng),
        ]
    }

    func price(of supply: Supply) -> Double {
        supply == .bedroll ? supply.basePrice : (supply.basePrice * pow(3, Double(shopTier - 1))).rounded()
    }

    /// Raison qui empêche l'achat, ou nil.
    func purchaseBlocker(_ supply: Supply) -> String? {
        switch supply {
        case .potion where potions >= Self.maxPotions: return "Maximum atteint"
        case .ration where energy >= Self.maxEnergy: return "Énergie pleine"
        case .scroll where scrollReady: return "Déjà prêt"
        case .bedroll where hasBedroll: return "Déjà acheté"
        default: return nil
        }
    }

    func canBuy(_ supply: Supply) -> Bool {
        isShopping && purchaseBlocker(supply) == nil && gold >= price(of: supply)
    }

    func buy(_ supply: Supply) {
        guard canBuy(supply) else { return }
        gold -= price(of: supply)
        switch supply {
        case .potion: potions += 1
        case .ration: energy = min(Self.maxEnergy, energy + 50)
        case .scroll: scrollReady = true
        case .bedroll: hasBedroll = true
        }
        save()
    }

    func gearPrice(_ item: Item) -> Double { item.sellValue * 4 }

    func canBuyGear(_ item: Item) -> Bool {
        isShopping && gold >= gearPrice(item) && (equipped[item.slot] == nil || bag.count < Self.bagCapacity)
    }

    func buyGear(_ item: Item) {
        guard canBuyGear(item), let index = shopStock.firstIndex(where: { $0.id == item.id }) else { return }
        gold -= gearPrice(item)
        shopStock.remove(at: index)
        if equipped[item.slot] == nil {
            equipped[item.slot] = item
        } else {
            bag.append(item)
        }
        save()
    }

    // MARK: Affichage de l'activité

    /// Titre, détail, avancement et temps réel restant de ce que fait le héros.
    var activityInfo: ActivityInfo {
        let now = uiClock
        switch activity {
        case .resting:
            guard isRecovering else {
                return ActivityInfo(title: "Au feu de camp", detail: "Reposé, prêt à partir", progress: nil, eta: nil)
            }
            let left = max((maxHP - hp) / hpRegen, (Self.maxEnergy - energy) / energyRegen)
            return ActivityInfo(title: "Au feu de camp", detail: "Le héros reprend des forces",
                                progress: min(hp / maxHP, energy / Self.maxEnergy), eta: left / timeScale)
        case .shopping:
            return ActivityInfo(title: "À la boutique", detail: "Achetez, vendez, puis repartez", progress: nil, eta: nil)
        case .traveling(let trip):
            let span = max(trip.end - trip.start, 0.001)
            return ActivityInfo(title: Self.title(of: trip), detail: "Depuis \(trip.from.name)",
                                progress: min(max((now - trip.start) / span, 0), 1),
                                eta: max(trip.end - now, 0) / timeScale)
        case .exploring(let run):
            let dungeon = Dungeon.all[run.dungeon]
            let span = max(run.roomEnd - run.roomStart, 0.001)
            let part = min(max((now - run.roomStart) / span, 0), 1)
            let detail: String
            if part < Self.walkShare {
                detail = "Avance dans le donjon"
            } else {
                switch run.room.kind {
                case .monster: detail = "Combat : \(run.room.name)"
                case .boss: detail = "Combat de boss : \(run.room.name)"
                case .chest: detail = "Ouvre un coffre"
                case .trap: detail = "Tombe sur un piège"
                case .fountain: detail = "Boit à une fontaine"
                }
            }
            let roomsLeft = Double(dungeon.rooms - run.roomIndex - 1)
            return ActivityInfo(title: "\(dungeon.name) · salle \(run.roomIndex + 1)/\(dungeon.rooms)",
                                detail: detail,
                                progress: (Double(run.roomIndex) + part) / Double(dungeon.rooms),
                                eta: (max(run.roomEnd - now, 0) + roomsLeft * dungeon.roomDuration) / timeScale)
        }
    }

    private static func title(of trip: Trip) -> String {
        switch trip.reason {
        case .normal: "En route vers \(trip.to.name)"
        case .victory: "Retour victorieux au camp"
        case .fled: "Fuite vers le camp"
        case .exhausted: "Retour au camp, épuisé"
        case .recalled: "Retour au camp"
        }
    }

    // MARK: Journal

    /// "1 objet", "2 objets".
    static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number > 1 ? "s" : "")"
    }

    private func log(_ icon: String, _ text: String, _ tone: JournalEntry.Tone) {
        journal.append(JournalEntry(icon: icon, text: text, tone: tone))
        journalSerial += 1
        if journal.count > 60 { journal.removeFirst(journal.count - 60) }
    }

    // MARK: Absence

    /// L'application passe en arrière-plan.
    func suspend() {
        settleRest()
        save()
        replan()
    }

    /// L'application revient au premier plan.
    func resume() {
        catchUp()
        replan()
    }

    /// Rejoue le temps écoulé depuis le dernier passage et prépare un résumé.
    private func catchUp(now: Date = Date()) {
        let away = now.timeIntervalSince(lastTick)
        let before = (gold: gold, items: bag.count + equipped.count, level: level, serial: journalSerial)
        tick(now: now)
        settleRest()
        refreshUI()
        let fresh = journalSerial - before.serial
        guard away >= 60, fresh > 0 else { return }
        awayReport = AwayReport(
            seconds: away,
            gold: gold - before.gold,
            items: bag.count + equipped.count - before.items,
            levels: level - before.level,
            lines: Array(journal.suffix(min(fresh, 6)))
        )
        save()
    }

    // MARK: Prévision

    /// Ce qui attend le héros jusqu'à son prochain arrêt, en heures de l'horloge du jeu.
    struct Forecast {
        /// Fin de l'exploration, si un donjon est en jeu.
        var leavesDungeonAt: TimeInterval?
        /// Arrivée au prochain arrêt. Nil si le héros est déjà arrêté.
        var landsAt: TimeInterval?
        var landing: Place = .camp
        /// Raison du dernier trajet : victoire, fuite, épuisement...
        var reason: TripReason = .normal
        var gold: Double = 0
        var items = 0
        /// Moment où le héros aura récupéré tous ses PV et son énergie.
        var restedAt: TimeInterval?
    }

    /// Rejoue la suite sur une copie du jeu. Les tirages étant reproductibles,
    /// la vraie partie suivra exactement le même chemin.
    func forecast() -> Forecast {
        settleRest()
        return GameState(twinOf: snapshot(), timeScale: timeScale).playAhead()
    }

    private func playAhead() -> Forecast {
        var result = Forecast()
        let before = (gold: gold, items: bag.count + equipped.count)
        var steps = 0
        while let time = nextEventTime, steps < 1000 {
            steps += 1
            clock = time
            let wasExploring = isExploring
            if case .traveling(let trip) = activity { result.reason = trip.reason }
            handleEvent(live: false)
            if wasExploring, case .traveling = activity { result.leavesDungeonAt = time }
            result.landsAt = time
        }
        result.landing = currentPlace ?? .camp
        result.gold = gold - before.gold
        result.items = bag.count + equipped.count - before.items
        if case .resting = activity, isRecovering {
            result.restedAt = clock + max((maxHP - hp) / hpRegen, (Self.maxEnergy - energy) / energyRegen)
        }
        return result
    }

    /// Reprogramme les notifications et l'activité en direct d'après la prévision.
    func replan() {
        guard !isForecast else { return }
        Outreach.apply(makePlan())
    }

    private func makePlan() -> OutreachPlan {
        typealias Panel = HeroActivityAttributes.Panel
        typealias Step = HeroActivityAttributes.Step

        let ahead = forecast()
        let now = Date()
        let scale = timeScale
        let clockNow = clock
        func date(_ time: TimeInterval) -> Date { now.addingTimeInterval((time - clockNow) / scale) }
        func step(_ label: String, _ start: TimeInterval, _ end: TimeInterval) -> Step {
            let from = date(start)
            return Step(label: label, start: from, end: max(date(end), from.addingTimeInterval(1)))
        }

        var plan = OutreachPlan()
        let loot = "+\(ahead.gold.short)\u{00A0}or, \(Self.count(ahead.items, "objet"))"
        let outcome: (title: String, body: String, short: String)
        switch ahead.reason {
        case .victory:
            outcome = ("Donjon terminé !",
                       "Le héros est rentré au camp avec \(ahead.gold.short) or et \(Self.count(ahead.items, "objet")).",
                       "Donjon terminé : \(loot)")
        case .fled:
            outcome = ("Le héros a fui",
                       "Il est rentré au camp blessé, avec \(ahead.gold.short) or. Il a besoin de repos.",
                       "A fui, blessé : \(loot)")
        case .exhausted:
            outcome = ("Le héros est épuisé",
                       "Il est rentré au camp avec \(ahead.gold.short) or. Il a besoin de repos.",
                       "Rentré épuisé : \(loot)")
        case .recalled, .normal:
            outcome = ("De retour au camp", "Le héros s'installe au feu de camp.", "De retour au camp")
        }

        /// Ce que montre l'activité en direct une fois le héros au camp.
        func campPanel(arrival: TimeInterval) -> Panel {
            if let rested = ahead.restedAt, rested - arrival > 1 {
                return Panel(headline: "Au feu de camp", detail: outcome.short, sprite: "campfire_1",
                             steps: [step("Repos", arrival, rested)], end: date(rested), endLabel: "Reposé à")
            }
            return Panel(headline: "Au feu de camp", detail: outcome.short, sprite: "campfire_1",
                         steps: [], end: nil, endLabel: "")
        }
        func addLanding(_ lands: TimeInterval) {
            plan.notifications.append(PlannedNotification(id: "hero.landing", date: date(lands),
                                                          title: outcome.title, body: outcome.body))
            if let rested = ahead.restedAt, (rested - lands) / scale >= 20 {
                plan.notifications.append(PlannedNotification(
                    id: "hero.rested", date: date(rested), title: "Héros reposé",
                    body: "PV et énergie au maximum. Prêt pour un nouveau donjon."))
            }
            plan.staleDate = date(lands)
        }

        switch activity {
        case .shopping:
            break

        case .resting:
            guard let rested = ahead.restedAt else { break }
            if (rested - clockNow) / scale >= 20 {
                plan.notifications.append(PlannedNotification(
                    id: "hero.rested", date: date(rested), title: "Héros reposé",
                    body: "PV et énergie au maximum. Prêt pour un nouveau donjon."))
            }
            // La barre part du niveau de forme actuel, pas de zéro à chaque mise à jour.
            let fitness = min(hp / maxHP, energy / Self.maxEnergy, 0.95)
            let virtualStart = clockNow - fitness / (1 - fitness) * (rested - clockNow)
            plan.live = .init(
                now: Panel(headline: "Au feu de camp", detail: "Le héros reprend des forces", sprite: "campfire_1",
                           steps: [step("Repos", virtualStart, rested)], end: date(rested), endLabel: "Reposé à"),
                later: Panel(headline: "Au feu de camp", detail: "Reposé, prêt à repartir", sprite: "campfire_1",
                             steps: [], end: nil, endLabel: ""))
            plan.staleDate = date(rested)

        case .traveling(let trip):
            guard let lands = ahead.landsAt else { break }
            if trip.to == .shop {
                plan.notifications.append(PlannedNotification(
                    id: "hero.landing", date: date(lands), title: "Arrivé à la boutique",
                    body: "Le marchand attend le héros. Achetez, vendez, puis repartez."))
                plan.live = .init(
                    now: Panel(headline: "En route vers la boutique", detail: "Depuis \(trip.from.name)", sprite: "hero",
                               steps: [step("Trajet", trip.start, trip.end)], end: date(lands), endLabel: "Arrivée à"),
                    later: Panel(headline: "À la boutique", detail: "Le marchand attend le héros", sprite: "icon_potion",
                                 steps: [], end: nil, endLabel: ""))
                plan.staleDate = date(lands)
            } else if case .dungeon(let index) = trip.to {
                let dungeon = Dungeon.all[index]
                let leaves = ahead.leavesDungeonAt ?? trip.end
                addLanding(lands)
                plan.live = .init(
                    now: Panel(headline: dungeon.name, detail: "Trajet, exploration, puis retour au camp",
                               sprite: dungeon.boss.sprite,
                               steps: [step("Trajet", trip.start, trip.end), step("Donjon", trip.end, leaves),
                                       step("Retour", leaves, lands)],
                               end: date(lands), endLabel: "Retour à"),
                    later: campPanel(arrival: lands))
            } else {
                addLanding(lands)
                plan.live = .init(
                    now: Panel(headline: Self.title(of: trip), detail: "Depuis \(trip.from.name)", sprite: "hero",
                               steps: [step("Retour", trip.start, trip.end)], end: date(lands), endLabel: "Arrivée à"),
                    later: campPanel(arrival: lands))
            }

        case .exploring(let run):
            guard let lands = ahead.landsAt else { break }
            let dungeon = Dungeon.all[run.dungeon]
            let entered = run.roomStart - Double(run.roomIndex) * dungeon.roomDuration
            let leaves = ahead.leavesDungeonAt ?? run.roomEnd
            addLanding(lands)
            plan.live = .init(
                now: Panel(headline: dungeon.name, detail: "Exploration, puis retour au camp",
                           sprite: dungeon.boss.sprite,
                           steps: [step("Donjon", entered, leaves), step("Retour", leaves, lands)],
                           end: date(lands), endLabel: "Retour à"),
                later: campPanel(arrival: lands))
        }
        return plan
    }

    // MARK: Mode test

    var isTestSpeed: Bool { timeScale > 1 }

    /// Accélère tout le jeu pour essayer les longs donjons sans attendre.
    func setTestSpeed(_ enabled: Bool) {
        settleRest()
        timeScale = enabled ? Self.testTimeScale : 1
        UserDefaults.standard.set(enabled, forKey: Self.timeScaleKey)
        refreshUI()
        replan()
    }

    // MARK: Sauvegarde

    private struct SaveData: Codable {
        var gold: Double
        var level: Int
        var xp: Double
        var hp: Double
        var energy: Double
        var potions: Int
        var scrollReady: Bool
        var hasBedroll: Bool
        var equipped: [String: Item]
        var bag: [Item]
        var activity: Activity
        var clears: [Int]
        var shopStock: [Item]
        var journal: [JournalEntry]
        var clock: TimeInterval
        var lastTick: Date
        /// Absent des sauvegardes d'avant les tirages reproductibles.
        var rng: UInt64?
    }

    private func snapshot() -> SaveData {
        SaveData(
            gold: gold, level: level, xp: xp, hp: hp, energy: energy,
            potions: potions, scrollReady: scrollReady, hasBedroll: hasBedroll,
            equipped: Dictionary(uniqueKeysWithValues: equipped.map { ($0.key.rawValue, $0.value) }),
            bag: bag, activity: activity, clears: clears, shopStock: shopStock,
            journal: journal, clock: clock, lastTick: lastTick, rng: rng.state
        )
    }

    func save() {
        guard !isForecast else { return }
        lastSave = Date()
        if let encoded = try? JSONEncoder().encode(snapshot()) {
            UserDefaults.standard.set(encoded, forKey: Self.saveKey)
        }
    }

    /// Renvoie vrai si une sauvegarde a été chargée.
    private func load() -> Bool {
        guard let raw = UserDefaults.standard.data(forKey: Self.saveKey),
              let data = try? JSONDecoder().decode(SaveData.self, from: raw) else { return false }
        apply(data)
        return true
    }

    private func apply(_ data: SaveData) {
        gold = data.gold
        level = max(data.level, 1)
        xp = data.xp
        hp = data.hp
        energy = data.energy
        potions = data.potions
        scrollReady = data.scrollReady
        hasBedroll = data.hasBedroll
        equipped = [:]
        for (key, item) in data.equipped {
            if let slot = ItemSlot(rawValue: key) { equipped[slot] = item }
        }
        bag = Array(data.bag.prefix(Self.bagCapacity))
        activity = data.activity
        clears = Array((data.clears + Array(repeating: 0, count: Dungeon.all.count)).prefix(Dungeon.all.count))
        shopStock = data.shopStock
        journal = data.journal
        journalSerial = journal.count
        clock = data.clock
        lastTick = data.lastTick
        if let seed = data.rng { rng.state = seed }
    }

    /// Efface la progression et repart de zéro.
    func reset() {
        gold = 0
        level = 1
        xp = 0
        hp = 100
        energy = Self.maxEnergy
        potions = 0
        scrollReady = false
        hasBedroll = false
        equipped = [:]
        bag = []
        unseenLoot = 0
        activity = .resting
        clears = Array(repeating: 0, count: Dungeon.all.count)
        shopStock = []
        journal = []
        restDebt = 0
        log("flame.fill", "Nouvelle aventure. Le héros s'installe au feu de camp.", .neutral)
        refreshUI()
        save()
        replan()
    }
}
