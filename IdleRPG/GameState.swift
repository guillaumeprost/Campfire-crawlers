import Foundation
import Observation
import WidgetKit

// MARK: - Évènements envoyés à la scène

enum GameEvent {
    case roomResolved(Room)
    case loot(item: Item, outcome: LootOutcome)
    case levelUp(Int)
    case potionUsed(Double)
    case fled(TripReason)
    case dungeonCleared(String)
    /// Coup spécial déclenché par le joueur pendant un combat.
    case skill
    /// Soin donné au camp : repas ou encouragement.
    case cared(fed: Bool)
    /// Bénédiction obtenue à un carrefour.
    case blessed(Blessing)
    /// Le héros est mort pour de bon : au combat, de faim, de soif, ou abandonné.
    case died(String)
    /// Itinérance : une trouvaille en chemin.
    case found(Provision?, gold: Double)
    /// Itinérance : un compagnon rencontré et apprivoisé en chemin.
    case companionFound(CompanionKind)
    /// Taverne : une commande servie au héros.
    case treated(TavernOrder)
    /// Achat payé au marchand, au forgeron ou pour le feu : image de l'achat, prix et légende.
    case bought(sprite: String, price: Double, caption: String)
    /// Vente au marchand.
    case sold(gold: Double)
    /// Un piège se déclenche : le joueur a un court instant pour le désamorcer.
    case trapTriggered
    /// Piège désamorcé à temps : aucun dégât.
    case trapDisarmed
    /// Une relique rejoint le héros : boss vaincu, marchand ambulant ou héritage.
    case relicFound(Relic)
    /// Le joueur a répondu à un visiteur du camp.
    case visited(symbol: String, good: Bool)
}

/// Défi de désamorçage : un curseur balaie une barre, le joueur tape quand il passe sur la zone verte.
/// Purement temps réel (non sauvegardé) : s'il n'est pas relevé, le piège se déclenche normalement.
struct TrapPrompt: Equatable {
    /// Début du balayage, en temps réel.
    let start: Date
    /// Durée d'un passage complet du curseur, de gauche à droite.
    let sweep: TimeInterval
    /// Bord gauche de la zone verte, en fraction de la barre (0…1).
    let zoneStart: Double
    /// Largeur de la zone verte, en fraction de la barre.
    let zoneWidth: Double

    /// Instant où le défi expire et le piège se déclenche de lui-même.
    var deadline: Date { start.addingTimeInterval(sweep) }

    /// Le curseur touche-t-il la zone verte à l'instant `now` ?
    func isHit(at now: Date) -> Bool {
        let frac = now.timeIntervalSince(start) / sweep
        return frac >= zoneStart && frac <= zoneStart + zoneWidth
    }
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
    /// Mode test rapide : tout va 240 fois plus vite, un donjon se joue en quelques secondes.
    static let testTimeScale = 240.0
    /// Mode test lent : assez accéléré pour essayer sans attendre, mais assez lent pour
    /// observer les combats, les sprites et les animations (un donjon de 12 min ≈ 36 s).
    static let testTimeScaleSlow = 20.0

    // Héros
    private(set) var gold: Double = 0
    private(set) var level = 1
    private(set) var xp: Double = 0
    private(set) var hp: Double = 100
    private(set) var energy: Double = GameState.maxEnergy
    private(set) var potions = 0
    private(set) var scrollReady = false
    private(set) var hasBedroll = false
    /// Améliorations du feu de camp achetées : chacune accélère le repos.
    private(set) var campLevel = 0
    /// Après une fuite, les PV remontent deux fois moins vite jusqu'à guérison complète.
    private(set) var injured = false

    // Besoins du héros, de 0 à 100 : ils baissent avec le temps, comme un Tamagotchi.
    private(set) var hunger: Double = 80
    /// Hydratation, de 0 à 100. Elle baisse plus vite que la satiété.
    private(set) var thirst: Double = 80
    /// Comment est mort le dernier héros, pour la notification.
    private(set) var lastFate = ""
    private(set) var mood: Double = 70
    /// Provisions dans le sac, à donner au camp.
    private(set) var pantry: [Provision: Int] = [.ration: 2]
    var rations: Int { pantry[.ration] ?? 0 }
    func count(_ provision: Provision) -> Int { pantry[provision] ?? 0 }
    var isRoaming: Bool { if case .roaming = activity { true } else { false } }
    /// Nom donné par le joueur.
    private(set) var heroName: String?
    /// Jauge du coup spécial, de 0 à 1 : elle se remplit en gagnant des combats.
    private(set) var skillCharge: Double = 0
    #if DEBUG
    @ObservationIgnored private var debugAutoSkill = false
    /// Partagé avec la copie qui prévoit la suite : la prévision doit voir les mêmes élites.
    static var debugElite = false
    static var debugStray = false
    static var debugBoss = false
    #endif
    /// Mode Hardcore : un héros vaincu meurt pour de bon et laisse un héritage.
    /// Numéro du héros de la lignée, en mode Hardcore.
    private(set) var generation = 1
    // Exploits qui forgent le caractère du héros.
    private(set) var bossKills = 0
    private(set) var flees = 0
    private(set) var meals = 0
    private(set) var cares = 0
    // Exploits : ils survivent à la mort du héros, c'est la mémoire de la lignée.
    /// Monstres vaincus, par image.
    private(set) var kills: [String: Int] = [:]
    private(set) var fightsWon = 0
    private(set) var roams = 0
    private(set) var provisionsFound = 0
    private(set) var goldEarned: Double = 0
    private(set) var dungeonsCleared = 0
    private(set) var claimedAchievements: Set<String> = []
    /// Quêtes du jour : le jour, les quêtes tirées, leur avancée et celles déjà réclamées.
    private(set) var questDay = 0
    private(set) var quests: [QuestKind] = []
    private(set) var questProgress: [String: Int] = [:]
    private(set) var questClaimed: Set<String> = []
    /// Dernier encouragement, sur l'horloge du jeu.
    @ObservationIgnored private var lastCare: TimeInterval = -1_000_000
    private(set) var equipped: [ItemSlot: Item] = [:]
    private(set) var bag: [Item] = []
    /// Objets ramassés depuis la dernière visite de l'onglet Équipement.
    private(set) var unseenLoot = 0
    /// Nil tant que le joueur n'a pas choisi son héros.
    private(set) var heroClass: HeroClass?
    /// Compagnon qui accompagne le héros, s'il en a un d'actif.
    private(set) var activeCompanion: CompanionKind?
    /// Compagnons déjà rencontrés et apprivoisés (stockés par `rawValue`).
    private(set) var unlockedCompanions: Set<String> = []
    /// Reliques du héros : il les garde jusqu'à sa mort.
    private(set) var relics: [Relic] = []
    /// Traits reçus en héritage d'un héros tombé.
    private(set) var inheritedTraits: [Trait] = []
    /// Le cimetière de la lignée, du plus ancien au plus récent.
    private(set) var graves: [Grave] = []
    /// Legs du dernier héros tombé, tant que le joueur n'a pas choisi.
    private(set) var pendingLegacy: PendingLegacy?
    /// Visites du camp auxquelles le joueur a déjà répondu.
    private(set) var answeredVisits: [String] = []
    /// Ce qu'a donné la dernière rencontre au camp. Transitoire : jamais sauvegardé.
    var visitOutcome: VisitOutcome?
    /// Départ du héros sur l'horloge du jeu, et combats de la lignée à ce moment-là.
    @ObservationIgnored private var heroBorn: TimeInterval?
    @ObservationIgnored private var fightsAtBirth = 0
    /// Repère qui relie l'horloge du jeu à la date : il donne l'heure et la météo de n'importe quel instant.
    @ObservationIgnored private var anchorDate = Date()
    @ObservationIgnored private var anchorClock: TimeInterval = 0
    /// Le vrai ciel du joueur, s'il partage sa position : soleil et météo relevée (voir `SkyWatcher`).
    private(set) var sky = Sky()
    #if DEBUG
    @ObservationIgnored private var debugVisitor: VisitorKind?
    /// Partagé avec la copie qui prévoit la suite, pour qu'elle voie le même temps figé.
    private static var debugAmbient: Ambient?
    #endif

    // Monde
    private(set) var activity: Activity = .resting
    /// Défi de piège en cours, le cas échéant. Transitoire : jamais sauvegardé.
    private(set) var trapPrompt: TrapPrompt?
    private(set) var clears: [Int] = Array(repeating: 0, count: Dungeon.all.count)
    /// Meilleur rang terminé dans chaque donjon, 0 si aucun.
    private(set) var bestRanks: [Int] = Array(repeating: 0, count: Dungeon.all.count)
    /// Rang choisi par le joueur pour chaque donjon.
    private(set) var chosenRanks: [Int] = Array(repeating: 1, count: Dungeon.all.count)
    private(set) var shopStock: [Item] = []
    private(set) var journal: [JournalEntry] = []
    /// Copie de l'horloge rafraîchie quelques fois par seconde, pour l'interface.
    private(set) var uiClock: TimeInterval = 0
    /// 1 en jeu normal. Le mode test accélère tout.
    private(set) var timeScale: Double = 1
    var awayReport: AwayReport?

    @ObservationIgnored var onEvent: ((GameEvent) -> Void)?
    /// Récompense à fêter à l'écran, puis effacée par l'interface.
    var celebration: Celebration?
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
    /// Chances de réussite déjà calculées, par état du héros.
    @ObservationIgnored private var chanceCache: [String: (success: Double, death: Double)] = [:]

    private static let saveKey = "save.v2"
    private static let timeScaleKey = "testTimeScale"

    init() {
        let defaults = UserDefaults.standard
        #if DEBUG
        if defaults.bool(forKey: "debugReset") { defaults.removeObject(forKey: Self.saveKey) }
        #endif
        let storedScale = defaults.double(forKey: Self.timeScaleKey)
        timeScale = storedScale > 1 ? storedScale : 1
        let hadSave = load()
        #if DEBUG
        // Tests : `-debugSeed 42` fixe le hasard de la partie, pour comparer deux parties par ailleurs identiques.
        if defaults.object(forKey: "debugSeed") != nil { rng.state = UInt64(max(defaults.integer(forKey: "debugSeed"), 1)) }
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
        #if DEBUG
        if defaults.bool(forKey: "debugHeal") { hp = maxHP; energy = Self.maxEnergy; injured = false }
        // Tests : `-debugSkill YES` recharge le coup spécial et le déclenche à chaque combat.
        debugAutoSkill = defaults.bool(forKey: "debugSkill")
        // Tests : `-debugElite YES` fait de chaque monstre (hors première salle) un élite.
        Self.debugElite = defaults.bool(forKey: "debugElite")
        // Tests : `-debugStray YES` fait de chaque trouvaille en balade la rencontre d'un compagnon inconnu.
        Self.debugStray = defaults.bool(forKey: "debugStray")
        Self.debugBoss = defaults.bool(forKey: "debugBoss")
        // Tests : `-debugWeapon rare|epic|legendary` met en main une arme de cette rareté (même bonus
        // que l'arme portée), pour voir l'aura et les impacts de son élément.
        if let wanted = defaults.string(forKey: "debugWeapon"),
           let rarity = ["common": Rarity.common, "rare": .rare, "epic": .epic, "legendary": .legendary][wanted] {
            let old = equipped[.weapon]
            equipped[.weapon] = Item(id: UUID(), slot: .weapon, rarity: rarity, sprite: old?.sprite ?? ItemSlot.weapon.bases[0].0,
                                     name: "Arme d'essai \(rarity.suffix)", bonus: old?.bonus ?? 3, tier: old?.tier ?? 1,
                                     sellValue: old?.sellValue ?? 1, rank: old?.rank ?? 1, forge: old?.forge ?? 0,
                                     heroClass: heroClass)
        }
        // Tests : `-debugLevel 40` monte le héros à ce niveau, `-debugUnlock YES` ouvre tous les donjons
        // (rang 5 partout sauf le dernier), `-debugFeats YES` donne les quatre traits de caractère.
        let wanted = defaults.integer(forKey: "debugLevel")
        if wanted > level { level = wanted; hp = maxHP }
        if defaults.bool(forKey: "debugUnlock") {
            for index in 0..<Dungeon.all.count - 1 {
                bestRanks[index] = max(bestRanks[index], Dungeon.unlockRank)
                clears[index] = max(clears[index], 1)
            }
        }
        if defaults.bool(forKey: "debugFeats") { (bossKills, flees, meals, cares) = (5, 3, 10, 15) }
        // Tests : `-debugVisitor merchant` fait venir ce visiteur au camp, `-debugWeather storm`
        // et `-debugNight YES|NO` figent le temps, `-debugRelic moonCharm` donne une relique.
        debugVisitor = defaults.string(forKey: "debugVisitor").flatMap(VisitorKind.init(rawValue:))
        Self.debugAmbient = nil
        if defaults.string(forKey: "debugWeather") != nil || defaults.object(forKey: "debugNight") != nil {
            let real = Ambient.at(Date(), sky: sky)
            Self.debugAmbient = Ambient(
                night: defaults.object(forKey: "debugNight") != nil ? defaults.bool(forKey: "debugNight") : real.night,
                weather: defaults.string(forKey: "debugWeather").flatMap(Weather.init(rawValue:)) ?? real.weather)
        }
        // Tests : `-debugSky 48.85,2.35` place le joueur à cet endroit, sans demander sa position.
        if let spot = defaults.string(forKey: "debugSky")?.split(separator: ",").compactMap({ Double($0) }), spot.count == 2 {
            sky = Sky(latitude: spot[0], longitude: spot[1])
        }
        if let relic = defaults.string(forKey: "debugRelic").flatMap(Relic.init(rawValue:)), !relics.contains(relic) {
            relics.append(relic)
            hp = min(hp, maxHP)
        }
        // Tests : `-debugGo 0` envoie le héros dans la Cave au lancement, `-debugGo shop` à la boutique.
        if let hero = defaults.string(forKey: "debugHero").flatMap(HeroClass.init(rawValue:)), hero != heroClass {
            // Tests : change de héros où qu'il soit, en gardant la même part de PV.
            let ratio = min(hp / maxHP, 1)
            heroClass = hero
            hp = max((maxHP * ratio).rounded(), 1)
            save()
        }
        // Tests : `-debugCamp YES` ramène d'abord le héros au feu de camp, rassasié, où qu'il soit.
        if defaults.bool(forKey: "debugCamp"), heroClass != nil {
            activity = .resting
            hunger = 100; thirst = 100; injured = false
        }
        // Tests : `-debugCampLevel 5` monte le feu de camp à ce niveau, pour voir le camp aménagé.
        if defaults.object(forKey: "debugCampLevel") != nil {
            campLevel = min(max(defaults.integer(forKey: "debugCampLevel"), 0), Self.campPrices.count)
        }
        // Tests : `-debugSleepy YES` mine le moral : au camp, héros et compagnon s'endorment.
        if defaults.bool(forKey: "debugSleepy") { mood = 20 }
        // Avec `-debugStray`, les compagnons déjà connus sont oubliés (sauf celui qui accompagne le héros).
        if Self.debugStray { unlockedCompanions = Set([activeCompanion?.rawValue].compactMap { $0 }) }
        // Tests : `-debugCompanion fox` apprivoise ce compagnon et le met aux côtés du héros.
        if let companion = defaults.string(forKey: "debugCompanion").flatMap(CompanionKind.init(rawValue:)) {
            unlockedCompanions.insert(companion.rawValue)
            activeCompanion = companion
        }
        if let go = defaults.string(forKey: "debugGo") {
            if go == "shop" { travel(to: .shop) }
            if go == "tavern" { travel(to: .tavern) }
            else if go == "roam" { roam(for: Roam.durations[0]) }
            else if let index = Int(go) { travel(to: .dungeon(index)) }
        }
        #endif
        replan()
    }

    /// Copie silencieuse du jeu, utilisée pour prévoir la suite.
    private init(twinOf data: SaveData, timeScale: Double) {
        isForecast = true
        self.timeScale = timeScale
        apply(data)
    }

    // MARK: Caractéristiques

    private func gear(_ slot: ItemSlot) -> Double { equipped[slot]?.power ?? 0 }

    /// Classe utilisée pour l'affichage et les calculs tant qu'aucune n'est choisie.
    var heroLook: HeroClass { heroClass ?? .mage }

    /// Le bonus de classe s'applique au total, équipement compris : il garde son poids toute la partie.
    var maxHP: Double { maxHP(at: level) }
    var attack: Double { attack(at: level) }
    private func maxHP(at level: Int) -> Double {
        ((100 + 20 * Double(level - 1) + gear(.amulet)) * heroLook.hpFactor * companionHPFactor
            * (has(.glassBlade) ? Relic.glassHP : 1)).rounded()
    }
    private func attack(at level: Int) -> Double {
        ((10 + 3 * Double(level - 1) + gear(.weapon)) * heroLook.attackFactor * condition * companionAttackFactor
            * relicAttackFactor).rounded()
    }

    // MARK: Reliques

    func has(_ relic: Relic) -> Bool { relics.contains(relic) }

    /// Effet des reliques sur les coups : l'éclat de verre, la patte de lapin, et l'amulette selon l'heure.
    private var relicAttackFactor: Double {
        var factor = 1.0
        if has(.glassBlade) { factor *= Relic.glassAttack }
        if has(.rabbitFoot) { factor *= Relic.rabbitAttack }
        if has(.moonCharm) { factor *= ambientNow.night ? Relic.moonNight : Relic.moonDay }
        return factor
    }

    /// Une relique rejoint le héros. Les PV sont ramenés sous le nouveau maximum si elle l'abaisse.
    private func gainRelic(_ relic: Relic, live: Bool, source: String) {
        guard !has(relic) else { return }
        relics.append(relic)
        hp = min(hp, maxHP)
        cheer(8)
        log(relic.symbol, "\(source) : \(relic.name). \(relic.boon)\(relic.bane.map { ", mais \($0.prefix(1).lowercased() + $0.dropFirst())" } ?? "").", .good)
        if live { onEvent?(.relicFound(relic)) }
    }

    // MARK: Heure et météo

    /// La date qui correspond à un instant de l'horloge du jeu. En jeu normal c'est l'heure réelle ;
    /// en mode test les jours défilent aussi vite que le reste.
    func gameDate(at time: TimeInterval) -> Date { anchorDate.addingTimeInterval(time - anchorClock) }

    private func ambient(at time: TimeInterval) -> Ambient {
        #if DEBUG
        if let frozen = Self.debugAmbient { return frozen }
        #endif
        return Ambient.at(gameDate(at: time), sky: sky)
    }

    /// Pour les règles : l'ambiance à l'instant exact de la simulation.
    private var ambientNow: Ambient { ambient(at: clock) }
    /// Pour l'interface : suit l'horloge rafraîchie plusieurs fois par seconde.
    var ambient: Ambient { ambient(at: uiClock) }

    /// Le temps se coupe à chaque heure pile, et au lever et au coucher du soleil : jour, nuit et
    /// météo ne changent qu'à ces moments-là.
    private var ambientEventTime: TimeInterval { clock + Ambient.untilNextChange(gameDate(at: clock), sky: sky) }

    /// Le soleil et la météo affichés sont-ils ceux de dehors ?
    var followsRealSun: Bool { sky.followsSun }
    var followsRealWeather: Bool { sky.hours[Sky.hourKey(gameDate(at: uiClock))] != nil }

    /// Un nouveau relevé du ciel est arrivé. Le passé garde son temps ; la suite est replanifiée.
    func updateSky(_ fresh: Sky) {
        guard !isForecast else { return }
        settleRest()
        sky.adopt(fresh, from: gameDate(at: clock))
        chanceCache.removeAll()
        refreshUI()
        replan()
        save()
    }

    /// Le joueur ne partage plus sa position : le ciel redevient imaginaire.
    func forgetSky() {
        guard !isForecast, sky != Sky() else { return }
        settleRest()
        sky = Sky()
        chanceCache.removeAll()
        refreshUI()
        replan()
        save()
    }

    /// Repos au feu de camp selon l'heure et le temps : on dort mieux la nuit, moins bien sous la pluie
    /// (sauf avec la braise éternelle, qui ne s'éteint jamais).
    private var campRestFactor: Double {
        let now = ambientNow
        return (now.night ? Ambient.nightRest : 1) * (has(.ember) ? 1 : now.weather.restFactor)
    }

    // MARK: Bonus du compagnon
    /// Le loup frappe plus fort, et plus encore une fois dans un donjon.
    private var companionAttackFactor: Double {
        guard let c = activeCompanion else { return 1 }
        return c.attackFactor * (isExploring ? c.dungeonAttackFactor : 1)
    }
    private var companionHPFactor: Double { activeCompanion?.hpFactor ?? 1 }
    private var companionSpeedBonus: Double { activeCompanion?.speedBonus ?? 0 }
    private var companionLuckBonus: Double { activeCompanion?.luckBonus ?? 0 }
    private var companionRestFactor: Double { activeCompanion?.restFactor ?? 1 }

    /// Effet de l'état du héros sur ses coups : la faim et le cafard l'affaiblissent,
    /// la bonne humeur le galvanise.
    var condition: Double {
        var factor = 1.0
        // Réglé avec Outils/equilibrage.py : un joueur attentif atteint le Volcan ~20 % plus vite
        // qu'avant ces mécaniques, un joueur absent un peu plus lentement.
        if hunger < 25 { factor *= 0.8 }
        if thirst < 25 { factor *= 0.85 }
        if mood >= 70 { factor *= 1.06 } else if mood < 25 { factor *= 0.85 }
        if traits.contains(.brave) { factor *= 1.03 }
        return factor
    }

    var name: String { heroName ?? heroLook.defaultName }

    var traits: [Trait] {
        var list: [Trait] = []
        if bossKills >= 5 { list.append(.brave) }
        if flees >= 3 { list.append(.careful) }
        if meals >= 10 { list.append(.glutton) }
        if cares >= 15 { list.append(.lovable) }
        // Un trait reçu en héritage compte dès le premier jour.
        return Trait.allCases.filter { list.contains($0) || inheritedTraits.contains($0) }
    }

    /// Part des PV sous laquelle le héros renonce : plus tôt s'il est prudent.
    var fleeLimit: Double { traits.contains(.careful) ? 0.35 : Self.fleeThreshold }

    /// Ce que ressent le héros, pour la bulle au-dessus de sa tête.
    enum Feeling { case thirsty, hungry, sad, hurt, tired, happy, content }

    var feeling: Feeling {
        if thirst < 25, thirst <= hunger { return .thirsty }
        if hunger < 25 { return .hungry }
        if thirst < 25 { return .thirsty }
        if injured { return .hurt }
        if mood < 30 { return .sad }
        if energy < 40 { return .tired }
        if mood >= 70 { return .happy }
        return .content
    }

    private func cheer(_ amount: Double) { mood = min(max(mood + amount, 0), 100) }
    /// Fraction : 0.2 pour +20 %.
    var speedBonus: Double {
        gear(.boots) / 100 + heroLook.speedBonus + companionSpeedBonus + (has(.shell) ? Relic.shellSpeed : 0)
    }
    var luck: Double { gear(.ring) / 100 + heroLook.luckBonus + companionLuckBonus }
    /// Part des dégâts évitée grâce à l'armure (0,2 pour 20 %).
    var defense: Double { gear(.armor) / 100 }
    /// Ce qui reste des dégâts une fois l'armure passée.
    private var armorFactor: Double { (1 - defense) * (has(.shell) ? Relic.shellArmor : 1) }

    /// Changer de héros, c'est abandonner l'actuel à son sort : il ne reviendra pas.
    var isAbandoning: Bool { heroClass != nil }

    func chooseHero(_ choice: HeroClass) {
        guard choice != heroClass else { return }
        settleRest()
        if heroClass != nil {
            die(fate: "a été abandonné à son sort", live: true)
        }
        heroClass = choice
        heroBorn = clock
        fightsAtBirth = fightsWon
        hp = maxHP
        log("person.fill", "\(choice.theName.prefix(1).uppercased() + choice.theName.dropFirst()) part à l'aventure.", .neutral)
        refreshUI()
        save()
        replan()
    }

    // MARK: Héritage

    /// Le dernier héros tombé, pour l'écran de succession.
    var lastGrave: Grave? { graves.last }

    /// Le joueur choisit ce que le héros tombé laisse à son successeur : un seul legs.
    func chooseLegacy(_ legacy: Legacy) {
        guard let offer = pendingLegacy, offer.options.contains(legacy) else { return }
        pendingLegacy = nil
        let ratio = hp / max(maxHP, 1)
        switch legacy {
        case .purse(let extra):
            gold += extra
            log("dollarsign.circle.fill", "Héritage : \(extra.short) or de plus dans la bourse.", .good)
        case .relic(let relic):
            gainRelic(relic, live: true, source: "Héritage")
        case .trait(let trait):
            if !inheritedTraits.contains(trait) { inheritedTraits.append(trait) }
            log(trait.symbol, "Héritage : le caractère « \(trait.name) » se transmet.", .good)
        }
        // Un legs qui change les PV max garde la même proportion de vie.
        if heroClass != nil { hp = max((maxHP * ratio).rounded(), 1) }
        if let index = graves.firstIndex(where: { $0.id == offer.grave }) { graves[index].legacy = legacy.title }
        chanceCache.removeAll()
        refreshUI()
        save()
        replan()
    }

    // MARK: Visiteurs du camp

    /// Le visiteur présent au feu de camp, tant que le joueur ne lui a pas répondu.
    var visitor: CampVisit? {
        guard case .resting = activity, heroClass != nil else { return nil }
        let now = gameDate(at: uiClock)
        var visit = CampVisit.current(at: now)
        #if DEBUG
        if let debugVisitor {
            visit = CampVisit(id: "debug.\(debugVisitor.rawValue)", kind: debugVisitor, start: now, end: now.addingTimeInterval(3_600), seed: 42)
        }
        #endif
        guard let visit, !answeredVisits.contains(visit.id) else { return nil }
        return settled(visit)
    }

    /// Tous les compagnons sont déjà là : la bête égarée laisse la place à un pèlerin.
    private func settled(_ visit: CampVisit) -> CampVisit {
        guard visit.kind == .stray, strayCompanion(for: visit) == nil else { return visit }
        return CampVisit(id: visit.id, kind: .pilgrim, start: visit.start, end: visit.end, seed: visit.seed)
    }

    /// Prix des visiteurs : ils suivent l'avancée dans les donjons, comme la boutique.
    private func visitPrice(_ base: Double) -> Double { (base * pow(3, Double(shopTier - 1))).rounded() }

    /// La relique que propose ce marchand : toujours la même pendant sa visite.
    func merchantRelic(for visit: CampVisit) -> Relic? {
        let pool = Relic.allCases.filter { !has($0) }
        return pool.isEmpty ? nil : pool[Int(visit.seed % UInt64(pool.count))]
    }

    /// L'animal qui rôde : un compagnon pas encore apprivoisé.
    func strayCompanion(for visit: CampVisit) -> CompanionKind? {
        let pool = CompanionKind.allCases.filter { !owns($0) }
        return pool.isEmpty ? nil : pool[Int(visit.seed % UInt64(pool.count))]
    }

    /// Ce que le joueur peut répondre au visiteur.
    func visitOptions(_ visit: CampVisit) -> [VisitOption] {
        func poor(_ price: Double) -> String? { gold >= price ? nil : "Pas assez d'or" }
        switch visit.kind {
        case .merchant:
            var options: [VisitOption] = []
            if let relic = merchantRelic(for: visit) {
                let price = visitPrice(250)
                options.append(VisitOption(id: 0, title: relic.name,
                                           detail: [relic.boon, relic.bane].compactMap { $0 }.joined(separator: " · "),
                                           price: price, blocker: poor(price)))
            }
            let price = visitPrice(55)
            let full = rations >= Self.packSize && count(.water) >= Self.packSize
            options.append(VisitOption(id: 1, title: "Lot de voyage", detail: "2 rations et 2 gourdes d'eau",
                                       price: price, blocker: full ? "Sac plein" : poor(price)))
            options.append(VisitOption(id: 2, title: "Le saluer", detail: "Il repart en sifflotant"))
            return options
        case .wounded:
            return [
                VisitOption(id: 0, title: "Le soigner", detail: "1 herbes médicinales · il saura vous remercier",
                            blocker: count(.herbs) > 0 ? nil : "Pas d'herbes"),
                VisitOption(id: 1, title: "Partager une ration", detail: "1 ration · il laisse une tisane",
                            blocker: rations > 0 ? nil : "Pas de ration"),
                VisitOption(id: 2, title: "Passer son chemin", detail: "\(name) aura mauvaise conscience"),
            ]
        case .gambler:
            let small = visitPrice(25), big = visitPrice(100)
            let odds = Int((gambleChance * 100).rounded())
            return [
                VisitOption(id: 0, title: "Miser petit", detail: "\(odds)\u{00A0}% de doubler la mise",
                            price: small, blocker: poor(small)),
                VisitOption(id: 1, title: "Miser gros", detail: "\(odds)\u{00A0}% de doubler la mise",
                            price: big, blocker: poor(big)),
                VisitOption(id: 2, title: "Décliner", detail: "Les dés ne sont pas pour tout le monde"),
            ]
        case .pilgrim:
            let offering = visitPrice(40), healing = visitPrice(30)
            return [
                VisitOption(id: 0, title: "Faire une offrande", detail: "+25\u{00A0}% d'attaque au prochain donjon",
                            price: offering, blocker: scrollReady ? "Déjà béni" : poor(offering)),
                VisitOption(id: 1, title: "Demander ses soins", detail: "Guérit les blessures, +20\u{00A0}% de PV",
                            price: healing, blocker: injured || hp < maxHP ? poor(healing) : "En pleine forme"),
                VisitOption(id: 2, title: "Écouter ses récits", detail: "+12 de moral"),
            ]
        case .minstrel:
            let song = visitPrice(15)
            return [
                VisitOption(id: 0, title: "Commander une ballade", detail: "+30 de moral",
                            price: song, blocker: poor(song)),
                VisitOption(id: 1, title: "Partager une ration", detail: "1 ration · il joue pour vous, +18 de moral",
                            blocker: rations > 0 ? nil : "Pas de ration"),
                VisitOption(id: 2, title: "L'écouter de loin", detail: "+6 de moral"),
            ]
        case .herbalist:
            let bundle = visitPrice(35)
            return [
                VisitOption(id: 0, title: "Acheter des herbes", detail: "2 herbes médicinales",
                            price: bundle, blocker: poor(bundle)),
                VisitOption(id: 1, title: "Troquer des fruits", detail: "2 fruits des bois contre 1 tisane",
                            blocker: count(.fruit) >= 2 ? nil : "Pas assez de fruits"),
                VisitOption(id: 2, title: "La saluer", detail: "Elle reprend sa cueillette"),
            ]
        case .stray:
            let beast = strayCompanion(for: visit)?.theName ?? "la bête"
            return [
                VisitOption(id: 0, title: "Offrir une ration", detail: "1 ration · 40\u{00A0}% d'apprivoiser \(beast)",
                            blocker: rations > 0 ? nil : "Pas de ration"),
                VisitOption(id: 1, title: "Offrir des fruits", detail: "1 fruits des bois · 20\u{00A0}% de l'apprivoiser",
                            blocker: count(.fruit) > 0 ? nil : "Pas de fruits"),
                VisitOption(id: 2, title: "La laisser tranquille", detail: "Elle retourne dans les bois"),
            ]
        }
    }

    /// Chance de gagner aux dés : un peu moins d'une sur deux, la chance du héros aide.
    private var gambleChance: Double { min(0.46 + luck * 0.15, 0.65) }

    /// Le joueur répond au visiteur : une seule réponse par visite, puis il s'en va.
    func answerVisit(_ visit: CampVisit, option id: Int) {
        guard let current = visitor, current.id == visit.id,
              let option = visitOptions(current).first(where: { $0.id == id }), option.blocker == nil else { return }
        settleRest()
        answeredVisits.append(current.id)
        if answeredVisits.count > 8 { answeredVisits.removeFirst(answeredVisits.count - 8) }
        #if DEBUG
        debugVisitor = nil
        #endif
        if let price = option.price { gold -= price }
        var outcome = VisitOutcome(symbol: current.kind.symbol, text: "", good: true)
        switch (current.kind, id) {
        case (.merchant, 0):
            if let relic = merchantRelic(for: current) {
                gainRelic(relic, live: true, source: "Achetée au marchand ambulant")
                outcome = VisitOutcome(symbol: relic.symbol, text: "\(relic.name) est à vous. \(relic.boon).", good: true)
            }
        case (.merchant, 1):
            pantry[.ration] = min(rations + 2, Self.packSize)
            pantry[.water] = min(count(.water) + 2, Self.packSize)
            outcome.text = "Deux rations et deux gourdes rejoignent le sac."
        case (.merchant, _):
            cheer(3)
            outcome.text = "Le marchand soulève son chapeau et reprend la route."
        case (.wounded, 0):
            pantry[.herbs, default: 0] -= 1
            let thanks = (questReward * 1.5).rounded()
            gold += thanks
            goldEarned += thanks
            cares += 1
            cheer(15)
            outcome.text = "Pansé, il repart debout et laisse \(thanks.short) or en remerciement."
        case (.wounded, 1):
            pantry[.ration, default: 0] -= 1
            pantry[.tea, default: 0] += 1
            cheer(8)
            outcome.text = "Il mange en silence, puis glisse une tisane dans le sac de \(name)."
        case (.wounded, _):
            cheer(-8)
            outcome = VisitOutcome(symbol: "cloud.rain.fill", text: "\(name) le regarde s'éloigner en boitant. Le cœur n'y est pas.", good: false)
        case (.gambler, 0), (.gambler, 1):
            let stake = option.price ?? 0
            if Double.random(in: 0..<1, using: &rng) < gambleChance {
                gold += stake * 2
                goldEarned += stake
                cheer(8)
                outcome.text = "Double six ! \(name) empoche \((stake * 2).short) or."
            } else {
                cheer(-4)
                outcome = VisitOutcome(symbol: "dice.fill", text: "Les dés roulent mal : \(stake.short) or perdus.", good: false)
            }
        case (.gambler, _):
            outcome.text = "Le joueur hausse les épaules et range ses dés."
        case (.pilgrim, 0):
            scrollReady = true
            cheer(5)
            outcome.text = "Le pèlerin bénit l'arme de \(name) : +25\u{00A0}% d'attaque au prochain donjon."
        case (.pilgrim, 1):
            injured = false
            hp = min(hp + (maxHP * 0.2).rounded(), maxHP)
            outcome.text = "Ses mains sont chaudes : les plaies de \(name) se referment."
        case (.pilgrim, _):
            cheer(12)
            outcome.text = "Il raconte les routes du monde. \(name) en oublie la fatigue."
        case (.minstrel, 0):
            cheer(30)
            outcome.text = "Une ballade rien que pour \(name) : le camp tout entier semble plus léger."
        case (.minstrel, 1):
            pantry[.ration, default: 0] -= 1
            cheer(18)
            outcome.text = "Le ménestrel mange, puis joue jusqu'à ce que les braises rougissent."
        case (.minstrel, _):
            cheer(6)
            outcome.text = "Quelques notes portées par le vent suffisent à faire sourire \(name)."
        case (.herbalist, 0):
            pantry[.herbs, default: 0] += 2
            outcome.text = "Deux bottes d'herbes médicinales rejoignent le sac."
        case (.herbalist, 1):
            pantry[.fruit, default: 0] -= 2
            pantry[.tea, default: 0] += 1
            cheer(4)
            outcome.text = "Elle goûte les fruits, hoche la tête et tend une tisane encore tiède."
        case (.herbalist, _):
            cheer(3)
            outcome.text = "L'herboriste salue d'un signe et disparaît entre les fougères."
        case (.stray, 0), (.stray, 1):
            let ration = id == 0
            pantry[ration ? .ration : .fruit, default: 0] -= 1
            if let beast = strayCompanion(for: current), Double.random(in: 0..<1, using: &rng) < (ration ? 0.4 : 0.2) {
                tameCompanion(beast, live: true)
                outcome = VisitOutcome(symbol: "pawprint.fill", text: "\(beast.theName.prefix(1).uppercased() + beast.theName.dropFirst()) mange dans la main de \(name), et reste.", good: true)
            } else {
                cheer(4)
                outcome.text = "La bête avale tout et file dans la nuit. Elle reviendra peut-être."
            }
        case (.stray, _):
            outcome.text = "La bête s'éloigne sans bruit."
        }
        log(outcome.symbol, "\(current.kind.name) : \(outcome.text)", outcome.good ? .good : .bad)
        visitOutcome = outcome
        onEvent?(.visited(symbol: outcome.symbol, good: outcome.good))
        chanceCache.removeAll()
        refreshUI()
        save()
        replan()
    }

    // MARK: Compagnons

    /// Compagnons déjà apprivoisés, dans l'ordre de l'enum.
    var ownedCompanions: [CompanionKind] { CompanionKind.allCases.filter { unlockedCompanions.contains($0.rawValue) } }
    func owns(_ companion: CompanionKind) -> Bool { unlockedCompanions.contains(companion.rawValue) }
    /// On ne change de compagnon qu'au feu de camp.
    var canSwapCompanion: Bool { if case .resting = activity { true } else { false } }

    /// Choisit le compagnon actif (ou aucun avec `nil`). Sans effet hors du camp
    /// ou pour un compagnon non débloqué.
    func setCompanion(_ choice: CompanionKind?) {
        guard canSwapCompanion, choice != activeCompanion else { return }
        if let choice, !owns(choice) { return }
        activeCompanion = choice
        if let choice {
            let named = choice.theName.prefix(1).uppercased() + choice.theName.dropFirst()
            log("pawprint.fill", "\(named) accompagne désormais \(name).", .good)
        } else {
            log("pawprint", "\(name) repart seul, sans compagnon.", .neutral)
        }
        refreshUI()
        save()
        replan()
    }

    /// Rencontre d'un compagnon en balade : il est apprivoisé, et équipé s'il n'y en avait aucun.
    private func tameCompanion(_ companion: CompanionKind, live: Bool) {
        unlockedCompanions.insert(companion.rawValue)
        if activeCompanion == nil { activeCompanion = companion }
        cheer(15)
        note(.find)
        let named = companion.theName.prefix(1).uppercased() + companion.theName.dropFirst()
        log("pawprint.fill", "\(named) se joint à \(name) en chemin !", .good)
        // Une rencontre est un événement : on la fête, même découverte au retour dans le jeu.
        if !isForecast {
            celebration = Celebration(symbol: "pawprint.fill", headline: "Nouveau compagnon", title: companion.name,
                                      gold: 0, image: "companion_\(companion.rawValue)_idle_1",
                                      details: [companion.motto] + companion.perks)
        }
        if live { onEvent?(.companionFound(companion)) }
    }

    var xpNeeded: Double { Self.xpNeeded(at: level) }
    private static func xpNeeded(at level: Int) -> Double { (30 * pow(1.35, Double(level - 1))).rounded() }

    /// Accélération du repos : sac de couchage et améliorations du feu.
    var restBoost: Double {
        (hasBedroll ? 1.5 : 1) * (1 + 0.25 * Double(campLevel)) * companionRestFactor * (has(.ember) ? Relic.emberRest : 1)
    }
    /// PV et énergie regagnés par seconde de jeu au feu de camp : 2,2 % des PV
    /// et 1,8 point d'énergie par minute, avant bonus.
    /// Le repos reste calé sur le rythme des donjons, mais plus court qu'avant : on en avait assez
    /// d'attendre une sortie entière pour repartir, surtout après les petits donjons.
    private var hpRegen: Double { maxHP * 0.022 / 60 / Dungeon.pace * restBoost * (injured ? 0.5 : 1) * (hunger <= 0 ? 0.5 : 1) }
    private var energyRegen: Double { 1.8 / 60 / Dungeon.pace * restBoost }

    /// Prix des améliorations successives du feu de camp.
    static let campPrices: [Double] = [500, 2_500, 10_000, 40_000, 160_000]
    var campUpgradePrice: Double? { campLevel < Self.campPrices.count ? Self.campPrices[campLevel] : nil }

    func canUpgradeCamp() -> Bool {
        guard case .resting = activity, let price = campUpgradePrice else { return false }
        return gold >= price
    }

    func upgradeCamp() {
        guard canUpgradeCamp(), let price = campUpgradePrice else { return }
        settleRest()
        gold -= price
        campLevel += 1
        onEvent?(.bought(sprite: "camp_fire_1", price: price, caption: "Feu niveau \(campLevel)"))
        log("flame.fill", "Feu de camp amélioré, niveau \(campLevel) : le repos est plus rapide.", .good)
        refreshUI()
        save()
        replan()
    }

    var isRecovering: Bool { hp < maxHP || energy < Self.maxEnergy }

    var isShopping: Bool { if case .shopping = activity { true } else { false } }
    var isExploring: Bool { if case .exploring = activity { true } else { false } }

    /// Le héros est libre de partir : il est au camp ou à la boutique.
    var currentPlace: Place? {
        switch activity {
        case .resting: .camp
        case .shopping: .shop
        case .tavern: .tavern
        default: nil
        }
    }

    /// PV affichés : pendant un combat ils baissent peu à peu jusqu'à l'issue de la salle.
    var shownHP: Double {
        guard case .exploring(let run) = activity else { return hp }
        let span = run.roomEnd - run.roomStart
        guard span > 0 else { return hp }
        let progress = (uiClock - run.roomStart) / span
        let fight = (progress - Self.walkShare) / (1 - Self.walkShare)
        switch run.room.kind {
        case .monster, .boss:
            // Les PV ne baissent qu'au moment où le monstre frappe.
            let taken = blows(in: run).filter { !$0.byHero && $0.at <= fight }
            let healed = taken.contains { $0.potion } ? potionHeal : 0
            return max(hp - taken.reduce(0) { $0 + $1.damage } + healed, 1)
        default:
            return fight >= 0 ? max(hp + run.room.hpDelta, 1) : hp
        }
    }

    /// Un coup porté pendant un combat : à quel moment (part du combat, de 0 à 1),
    /// par qui, combien de dégâts, et ce qu'il reste ensuite au monstre (de 0 à 1).
    struct Blow {
        var at: Double
        var byHero: Bool
        var damage: Double
        var foeLeft: Double
        /// Le héros boit une potion juste avant ce coup.
        var potion = false
    }

    /// Les échanges d'un combat, reconstitués à partir de son issue : le héros frappe le
    /// premier, puis chacun son tour. Le total des dégâts reçus est exactement celui de la salle.
    func blows(in run: Run) -> [Blow] {
        let room = run.room
        guard room.kind == .monster || room.kind == .boss else { return [] }
        let dungeon = Dungeon.all[run.dungeon]
        let foeHP = dungeon.monsterHP * Dungeon.rankScale(run.level) * (room.kind == .boss ? 3 : 1)
            * (room.elite == true ? Room.eliteHP : 1)
        let power = attack * (run.boosted ? 1.25 : 1) * (run.has(.sharp) ? Blessing.sharpBonus : 1)
        let rounds = max(Int(ceil(foeHP / max(power, 1))), 1)
        let taken = room.knockedOut ? -room.hpDelta : -room.hpDelta + (room.usesPotion == true ? potionHeal : 0)

        // Au-delà de quelques coups, on regroupe : un long combat garde un rythme lisible.
        var heroHits = room.knockedOut ? max(rounds - 1, 1) : rounds
        var foeHits = max(rounds - 1, taken > 0 ? 1 : 0)
        if room.knockedOut { foeHits = max(foeHits, 1) }
        let heroDealt = room.knockedOut ? min(power * Double(heroHits), foeHP * 0.85) : foeHP
        // Un combat se lit en quelques échanges : au moins 3 coups du héros et 2 du monstre
        // (s'il fait mal), au plus 8 chacun. Les dégâts sont répartis entre eux.
        heroHits = min(max(heroHits, 3), 8)
        foeHits = taken > 0 ? min(max(foeHits, 2), 8, Int(taken)) : 0

        var order: [Bool] = []
        var h = heroHits, f = foeHits
        while h > 0 || f > 0 {
            if h > 0 { order.append(true); h -= 1 }
            if f > 0 { order.append(false); f -= 1 }
        }
        // En cas de victoire, c'est le héros qui porte le dernier coup.
        if !room.knockedOut, let last = order.lastIndex(of: true), last != order.count - 1 {
            order.remove(at: last)
            order.append(true)
        }

        var result: [Blow] = []
        var foeLeft = 1.0, heroLeft = hp, heroDone = 0, foeDone = 0
        var potionUsed = false
        for (index, byHero) in order.enumerated() {
            let at = 0.1 + 0.8 * Double(index) / Double(max(order.count - 1, 1))
            if byHero {
                heroDone += 1
                let share = heroDealt * Double(heroDone) / Double(heroHits)
                let before = foeLeft
                foeLeft = max(1 - share / foeHP, 0)
                result.append(Blow(at: at, byHero: true, damage: ((before - foeLeft) * foeHP).rounded(), foeLeft: foeLeft))
            } else {
                foeDone += 1
                let previous = (taken * Double(foeDone - 1) / Double(foeHits)).rounded()
                let damage = (taken * Double(foeDone) / Double(foeHits)).rounded() - previous
                var blow = Blow(at: at, byHero: false, damage: damage, foeLeft: foeLeft)
                if room.usesPotion == true, !potionUsed, damage >= heroLeft {
                    blow.potion = true
                    potionUsed = true
                    heroLeft += potionHeal
                }
                heroLeft -= damage
                result.append(blow)
            }
        }
        return result
    }

    // MARK: Donjons

    /// Un donjon s'ouvre quand le précédent est terminé au rang 3.
    /// Ceux déjà visités dans une ancienne partie restent ouverts.
    func isUnlocked(_ dungeon: Dungeon) -> Bool {
        dungeon.id == 0 || bestRanks[dungeon.id - 1] >= Dungeon.unlockRank || clears[dungeon.id] > 0
    }

    /// Rang le plus haut accessible : un de plus que le meilleur terminé.
    func highestRank(_ dungeon: Dungeon) -> Int {
        min(bestRanks[dungeon.id] + 1, dungeon.maxRank)
    }

    func chosenRank(_ dungeon: Dungeon) -> Int {
        min(max(chosenRanks[dungeon.id], 1), highestRank(dungeon))
    }

    func chooseRank(_ rank: Int, for dungeon: Dungeon) {
        let clamped = min(max(rank, 1), highestRank(dungeon))
        guard clamped != chosenRanks[dungeon.id] else { return }
        chosenRanks[dungeon.id] = clamped
        save()
    }

    /// Palier du dernier donjon terminé : il fixe l'offre et les prix de la boutique.
    var shopTier: Int {
        Dungeon.all.last(where: { clears[$0.id] > 0 })?.tier ?? 1
    }

    /// Raison qui empêche d'entrer dans un donjon, ou nil si tout va bien.
    func entryBlocker(_ dungeon: Dungeon) -> String? {
        if hp <= maxHP * fleeLimit { return "Trop blessé" }
        if energy < dungeon.energyCost { return "Trop fatigué" }
        return nil
    }

    /// Durée d'une salle : la vitesse du héros raccourcit aussi l'exploration.
    func roomDuration(_ dungeon: Dungeon) -> TimeInterval {
        dungeon.roomDuration / (1 + speedBonus)
    }

    /// Un coffre s'ouvre vite : sa salle dure moins qu'un combat. Réglé avec Outils/equilibrage.py.
    static let chestShare = 0.4

    /// Durée d'une salle selon ce qu'elle contient. Un carrefour garde la durée pleine, pour laisser le temps de choisir.
    func roomDuration(_ dungeon: Dungeon, for room: Room, fork: Bool = false) -> TimeInterval {
        roomDuration(dungeon) * (room.kind == .chest && !fork ? Self.chestShare : 1)
    }

    func explorationTime(_ dungeon: Dungeon) -> TimeInterval {
        dungeon.duration / (1 + speedBonus)
    }

    /// Ce qui manque dans le sac pour tenir toute l'expédition, aller et retour compris, ou nil.
    func supplyShortage(for dungeon: Dungeon) -> String? {
        guard let here = currentPlace else { return nil }
        let span = explorationTime(dungeon) + travelTime(from: here, to: .dungeon(dungeon.id)) * 2
        // Il mange quand la jauge passe sous 35 : ce qui manque au-delà doit venir du sac.
        let food = max(span * hungerRate - (hunger - 35), 0)
        let drink = max(span * thirstRate - (thirst - 35), 0)
        let rations = Int((food - Double(count(.fruit)) * 15) / 40 + 0.99)
        let gourds = Int((drink - Double(count(.tea)) * 25) / 50 + 0.99)
        let missing = [rations > count(.ration) ? "\(rations - count(.ration)) ration\(rations - count(.ration) > 1 ? "s" : "")" : nil,
                       gourds > count(.water) ? "\(gourds - count(.water)) gourde\(gourds - count(.water) > 1 ? "s" : "")" : nil]
            .compactMap { $0 }
        return missing.isEmpty ? nil : "Il manque " + missing.joined(separator: " et ")
    }

    /// Chance de terminer le donjon si le héros part maintenant. On joue 60 sorties fictives
    /// avec les vraies règles de combat, sur un tirage à part qui ne touche pas à la partie.
    func successChance(of dungeon: Dungeon, rank: Int) -> Double { odds(of: dungeon, rank: rank).success }

    /// Risque de mourir pendant la sortie : une fuite ratée, à terre ou trop blessé.
    func deathChance(of dungeon: Dungeon, rank: Int) -> Double { odds(of: dungeon, rank: rank).death }

    private func odds(of dungeon: Dungeon, rank: Int) -> (success: Double, death: Double) {
        let key = "\(dungeon.id).\(rank).\(level).\(Int(hp)).\(Int(energy)).\(potions).\(scrollReady).\(attack).\(maxHP)"
            + ".\(Int(hunger / 25)).\(Int(thirst / 25)).\(injured).\(Int(escapeChance() * 100)).\(Int(armorFactor * 100))"
            + ".\(relics.map(\.rawValue).joined()).\(Ambient.hourIndex(gameDate(at: clock))).\(ambientNow.night)"
        if let known = chanceCache[key] { return known }
        var generator = SeededGenerator(state: UInt64(dungeon.id * 7_919 + rank * 104_729))
        let trials = 60
        var wins = 0.0, deaths = 0.0
        for _ in 0..<trials {
            switch rehearse(dungeon, rank: rank, using: &generator) {
            case .cleared: wins += 1
            case .safe: break
            case let .fled(energy, knockedOut, boss):
                deaths += 1 - escapeChance(knockedOut: knockedOut, boss: boss, energy: energy)
            }
        }
        let result = (success: wins / Double(trials), death: deaths / Double(trials))
        if chanceCache.count > 300 { chanceCache.removeAll() }
        chanceCache[key] = result
        return result
    }

    private enum Rehearsal {
        case cleared, safe
        case fled(energy: Double, knockedOut: Bool, boss: Bool)
    }

    /// Le danger tient compte des deux calculs faits sur les stats actuelles du héros :
    /// ses chances de finir le donjon, et ses chances d'y laisser la vie.
    func risk(of dungeon: Dungeon, rank: Int) -> Risk {
        let (success, death) = odds(of: dungeon, rank: rank)
        if success < 0.45 || death >= 0.20 { return .deadly }
        if success < 0.75 || death >= 0.08 { return .risky }
        if success < 0.95 || death > 0.02 { return .fair }
        return .easy
    }

    /// Une sortie fictive : mêmes salles, mêmes dégâts, mêmes potions et mêmes fuites que la vraie.
    private func rehearse(_ dungeon: Dungeon, rank: Int, using generator: inout SeededGenerator) -> Rehearsal {
        let scale = Dungeon.rankScale(rank)
        var hp = self.hp, energy = self.energy, potions = self.potions
        var level = self.level, xp = self.xp
        var maxHP = self.maxHP, power = attack * (scrollReady ? 1.25 : 1)
        // Heure d'entrée estimée : la nuit, les monstres frappent plus fort.
        let entry = clock + (currentPlace.map { travelTime(from: $0, to: .dungeon(dungeon.id)) } ?? 0)
        let pace = roomDuration(dungeon)
        for index in 0..<dungeon.rooms {
            let kind = Self.roomKind(index: index, rooms: dungeon.rooms, using: &generator)
            let spread = Double.random(in: 0.8...1.2, using: &generator)
            let heal = (maxHP * potionShare).rounded()
            let night = ambient(at: entry + Double(index) * pace).night ? Ambient.nightDamage : 1
            switch kind {
            case .monster, .boss:
                let boss = kind == .boss
                let elite = !boss && index > 0 && Double.random(in: 0..<1, using: &generator) < Room.eliteChance
                let damage = Self.fightDamage(foeHP: dungeon.monsterHP * scale * (boss ? 3 : 1) * (elite ? Room.eliteHP : 1),
                                              foeDamage: dungeon.monsterDamage * scale * (boss ? 1.5 : 1)
                                                  * (elite ? Room.eliteDamage : 1) * night,
                                              attack: power, spread: spread) * armorFactor
                if damage >= hp {
                    guard potions > 0, damage < hp + heal else { return .fled(energy: energy, knockedOut: true, boss: boss) }
                    potions -= 1
                    hp += heal
                }
                hp = min(max(hp - damage, 1), maxHP)
                xp += dungeon.xp * scale * (boss ? 5 : 1) * (elite ? Room.eliteXP : 1)
                while xp >= Self.xpNeeded(at: level) {
                    xp -= Self.xpNeeded(at: level)
                    level += 1
                    hp += (20 * heroLook.hpFactor).rounded()
                    maxHP = self.maxHP(at: level)
                    power = attack(at: level) * (scrollReady ? 1.25 : 1)
                }
            case .trap:
                let damage = (dungeon.monsterDamage * scale * 1.5 * spread * armorFactor * trapFactor).rounded()
                if damage >= hp { return .fled(energy: energy, knockedOut: true, boss: false) }
                hp = max(hp - damage, 1)
            case .fountain:
                hp = min(hp + (maxHP * 0.15 * shrineFactor).rounded(), maxHP)
            case .chest:
                break
            }
            energy = max(energy - dungeon.roomEnergy, 0)
            if index == dungeon.rooms - 1 { return .cleared }
            if hp <= maxHP * fleeLimit {
                guard potions > 0 else { return .fled(energy: energy, knockedOut: false, boss: false) }
                potions -= 1
                hp = min(maxHP, hp + heal)
            }
            if energy < dungeon.roomEnergy { return .safe }
        }
        return .safe
    }

    /// Nature d'une salle : un monstre pour commencer, le boss pour finir, du hasard entre les deux.
    private static func roomKind<G: RandomNumberGenerator>(index: Int, rooms: Int, using rng: inout G) -> RoomKind {
        if index == rooms - 1 { return .boss }
        if index == 0 { return .monster }
        switch Double.random(in: 0..<1, using: &rng) {
        case ..<0.55: return .monster
        case ..<0.75: return .chest
        case ..<0.85: return .trap
        default: return .fountain
        }
    }

    /// Le héros frappe le premier : le monstre riposte une fois de moins qu'il ne faut de coups pour l'abattre.
    private static func fightDamage(foeHP: Double, foeDamage: Double, attack: Double, spread: Double) -> Double {
        let rounds = ceil(foeHP / max(attack, 1))
        return (foeDamage * max(rounds - 1, 0.25) * spread).rounded()
    }

    // MARK: Déplacements

    /// Durée d'un trajet en secondes de jeu. Tout passe par le camp.
    func travelTime(from: Place, to: Place) -> TimeInterval {
        (from.distance + to.distance) / (1 + speedBonus) * ambientNow.weather.travelFactor
            * (activeCompanion?.travelFactor ?? 1)
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
        var rank: Int?
        if case .dungeon(let index) = destination { rank = chosenRank(Dungeon.all[index]) }
        activity = .traveling(Trip(from: here, to: destination, start: clock, end: clock + duration,
                                   reason: .normal, rank: rank))
        let target = rank.map { "\(destination.name), rang \($0)" } ?? destination.name
        log("figure.walk", "Départ pour \(target), \(duration.shortDuration) de marche.", .neutral)
        refreshUI()
        save()
        Outreach.askPermission()
        replan()
    }

    /// Rappelle le héros au camp en pleine exploration. Il garde son butin.
    func recall() {
        if case .roaming(let roam) = activity {
            endRoam(roam, live: true)
            refreshUI()
            save()
            return
        }
        guard case .exploring(let run) = activity else { return }
        log("arrow.uturn.backward", "Rappelé au camp avec \(run.gold.short) or et \(Self.count(run.items, "objet")).", .neutral)
        bringBack(run, live: true)
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
        // Chrono écoulé (ou retour d'arrière-plan après l'échéance) : le piège se déclenche de lui-même.
        if let prompt = trapPrompt, now >= prompt.deadline { disarmTrap(success: false) }
        advance(by: real * timeScale, live: real < 2)
        if now.timeIntervalSince(lastUIRefresh) >= 0.2 {
            lastUIRefresh = now
            refreshQuests(now: now)
            settleRest()
            uiClock = clock
            #if DEBUG
            if debugAutoSkill && !isForecast {
                skillCharge = 1
                if canUseSkill { useSkill() }
            }
            #endif
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
            pass(to: until)
            guard let event, event <= target else { break }
            handleEvent(live: live)
        }
    }

    /// Le temps passe jusqu'à `time` : repos selon le lieu, puis faim, soif et moral.
    private func pass(to time: TimeInterval) {
        guard time > clock else { return }
        let span = time - clock
        // Affamé ou assoiffé, le corps ne récupère plus rien.
        if !isStarving {
            // Au camp, la nuit et la météo pèsent sur le repos : le temps est déjà coupé à chaque heure pile.
            if case .resting = activity { restDebt += span * campRestFactor }
            // En balade, le héros récupère à moitié moins vite qu'au camp.
            if case .roaming = activity { restDebt += span * 0.5 }
            // À la taverne aussi, assis près de l'âtre, mais l'ambiance compte plus que le sommeil.
            if case .tavern = activity { restDebt += span * 0.5 }
        }
        wearNeeds(over: span)
        clock = time
    }

    // MARK: Besoins vitaux

    /// Satiété et hydratation se vident en 16 h et 10 h au camp, deux fois plus vite en donjon.
    static let hungerSpan: TimeInterval = 57_600
    static let thirstSpan: TimeInterval = 36_000
    /// Part des PV max perdue par heure et par besoin vide : un héros oublié finit par mourir.
    static let starveDrain = 0.03

    /// Faim ou soif à zéro : le héros dépérit.
    var isStarving: Bool { heroClass != nil && (hunger <= 0 || thirst <= 0) }

    private var emptyNeeds: Double { (hunger <= 0 ? 1 : 0) + (thirst <= 0 ? 1 : 0) }
    /// En donjon, le héros mange et boit ce qu'il a emporté (`eatOnTheRoad`).
    private var needsPace: Double { 1 }
    /// En mode test, faim, soif et moral ralentissent d'autant : on teste sans le voir mourir de soif en une minute.
    private var needsDamp: Double { timeScale > 1 ? 30 / timeScale : 1 }
    private var hungerRate: Double {
        100 / Self.hungerSpan * needsPace * needsDamp * (has(.hermitFlask) ? Relic.hermitNeeds : 1)
    }
    /// Sous la pluie on a moins soif, sauf au fond d'un donjon où il ne pleut pas.
    private var thirstRate: Double {
        100 / Self.thirstSpan * needsPace * needsDamp * (has(.hermitFlask) ? Relic.hermitNeeds : 1)
            * (isExploring ? 1 : ambientNow.weather.thirstFactor)
    }

    /// Moment où l'hydratation passera sous `level` si le héros reste où il est. On avance heure par
    /// heure, parce que la pluie ralentit la soif et que le temps change.
    private func thirstReaches(_ level: Double) -> TimeInterval {
        let base = 100 / Self.thirstSpan * needsPace * needsDamp * (has(.hermitFlask) ? Relic.hermitNeeds : 1)
        var time = clock, left = thirst - level
        for _ in 0..<240 where left > 0 {
            let rate = base * (isExploring ? 1 : ambient(at: time).weather.thirstFactor)
            let span = Ambient.untilNextChange(gameDate(at: time), sky: sky)
            if left <= rate * span { return time + left / rate }
            left -= rate * span
            time += span
        }
        return time
    }

    /// Prochain seuil des besoins : un besoin qui tombe à zéro, ou la mort d'un héros oublié.
    private var needsEventTime: TimeInterval? {
        guard heroClass != nil else { return nil }
        var times: [TimeInterval] = []
        if hunger > 0 { times.append(clock + hunger / hungerRate) }
        if thirst > 0 { times.append(clock + thirst / thirstRate) }
        if emptyNeeds > 0 {
            times.append(clock + max(hp, 0) / (maxHP * Self.starveDrain / 3_600 * emptyNeeds * needsDamp))
        }
        return times.min()
    }

    private var nextEventTime: TimeInterval? {
        [activityEventTime, needsEventTime, heroClass == nil ? nil : ambientEventTime].compactMap { $0 }.min()
    }

    private var activityEventTime: TimeInterval? {
        switch activity {
        case .traveling(let trip): trip.end
        // Un défi de piège fige la salle : plus rien ne se résout tant que le joueur n'a pas tranché.
        case .exploring(let run): trapPrompt == nil ? run.roomEnd : nil
        case .roaming(let roam): min(roam.nextFind, roam.end)
        case .resting, .shopping, .tavern: nil
        }
    }

    private func handleEvent(live: Bool) {
        if isStarving, hp <= 0.01 {
            let fate = hunger <= 0 && thirst <= 0 ? "est mort de faim et de soif"
                : thirst <= 0 ? "est mort de soif" : "est mort de faim"
            die(fate: fate, live: live)
            return
        }
        // Un seuil des besoins coupe seulement le temps en morceaux.
        guard let due = activityEventTime, clock >= due else { return }
        switch activity {
        case .traveling(let trip):
            arrive(trip)
            if live { replan() }
        case .exploring(let run): resolve(run, live: live)
        case .roaming(var roam):
            if roam.nextFind <= roam.end, clock >= roam.nextFind {
                findSomething(&roam, live: live)
                roam.nextFind += Roam.findEvery
                activity = .roaming(roam)
            }
            if clock >= roam.end { endRoam(roam, live: live) }
        case .resting, .shopping, .tavern: break
        }
    }

    /// La faim se creuse (deux fois plus vite en donjon), et le moral s'use, surtout
    /// quand le héros tourne en rond au camp, reposé et sans rien à faire.
    private func wearNeeds(over seconds: TimeInterval) {
        guard seconds > 0, heroClass != nil else { return }
        // Un besoin vide au début du morceau le reste jusqu'au bout : les seuils coupent le temps.
        let empty = emptyNeeds
        if empty > 0 {
            settleRest()
            hp = max(hp - maxHP * Self.starveDrain / 3_600 * empty * needsDamp * seconds, 0)
            if hp < 0.01 { hp = 0 }
        }
        hunger = max(hunger - seconds * hungerRate, 0)
        if hunger < 0.001 { hunger = 0 }
        thirst = max(thirst - seconds * thirstRate, 0)
        if thirst < 0.001 { thirst = 0 }
        var rate = 3.0 / 3_600
        if case .resting = activity, hp >= maxHP, energy >= Self.maxEnergy { rate = 8.0 / 3_600 }
        if traits.contains(.lovable) { rate /= 2 }
        if has(.hermitFlask) { rate *= Relic.hermitMood }
        if case .tavern = activity {
            // L'ambiance de la taverne : le moral monte au lieu de s'user.
            mood = min(mood + seconds * TavernOrder.moodPerHour / 3_600, 100)
            return
        }
        mood = max(mood - seconds * rate * needsDamp, 0)
    }

    // MARK: Soins

    /// On donne les provisions au camp, ou en chemin pendant une balade.
    func canUse(_ provision: Provision) -> Bool {
        switch activity {
        case .resting, .roaming, .tavern: break
        default: return false
        }
        guard count(provision) > 0 else { return false }
        switch provision {
        case .fruit: return hunger < 95 || thirst < 95
        case .ration: return hunger < 95
        case .water: return thirst < 95
        case .tea: return mood < 95 || energy < Self.maxEnergy || thirst < 95
        case .herbs: return injured || hp < maxHP
        }
    }

    var canFeed: Bool { canUse(.ration) || canUse(.fruit) }

    func use(_ provision: Provision) {
        guard canUse(provision) else { return }
        settleRest()
        pantry[provision, default: 0] -= 1
        switch provision {
        case .fruit:
            meals += 1
            note(.feed)
            hunger = min(hunger + (traits.contains(.glutton) ? 22 : 15), 100)
            quench(10)
            cheer(2)
            log("leaf.fill", "\(name) croque des fruits des bois.", .good)
        case .ration:
            meals += 1
            note(.feed)
            hunger = min(hunger + (traits.contains(.glutton) ? 60 : 40), 100)
            energy = min(energy + 10, Self.maxEnergy)
            cheer(5)
            log("fork.knife", "\(name) mange une ration avec appétit.", .good)
        case .water:
            quench(50)
            log("drop.fill", "\(name) vide sa gourde d'un trait.", .good)
        case .tea:
            cheer(15)
            quench(25)
            energy = min(energy + 20, Self.maxEnergy)
            log("cup.and.saucer.fill", "\(name) boit une tisane bien chaude.", .good)
        case .herbs:
            injured = false
            hp = min(hp + (maxHP * 0.25).rounded(), maxHP)
            log("cross.case.fill", "\(name) panse ses plaies avec des herbes médicinales.", .good)
        }
        onEvent?(.cared(fed: provision == .fruit || provision == .ration))
        refreshUI()
        save()
        replan()
    }

    func feed() { use(canUse(.ration) ? .ration : .fruit) }

    private func quench(_ amount: Double) { thirst = min(thirst + amount, 100) }

    // MARK: Exploits

    /// Avancée d'un succès, sur sa cible.
    func progress(of achievement: Achievement) -> Double {
        let value: Double
        switch achievement {
        case .firstBlood, .slayer: value = Double(fightsWon)
        case .bossHunter: value = Double(Bestiary.bossSprites.reduce(0) { $0 + (kills[$1] ?? 0) })
        case .dragonSlayer: value = Double(kills["b_dragon"] ?? 0)
        case .explorer: value = Double(dungeonsCleared)
        case .gourmet: value = Double(meals)
        case .friend: value = Double(cares)
        case .wanderer: value = Double(roams)
        case .gatherer: value = Double(provisionsFound)
        case .rich: value = goldEarned
        case .veteran: value = Double(level)
        case .smith: value = equipped.values.contains { $0.forgeLevel >= Item.maxForge } ? 1 : 0
        case .campfire: value = Double(campLevel)
        case .collector: value = Double(Bestiary.all.filter { (kills[$0.sprite] ?? 0) > 0 }.count)
        }
        return min(value, achievement.target)
    }

    func isClaimable(_ achievement: Achievement) -> Bool {
        !claimedAchievements.contains(achievement.rawValue) && progress(of: achievement) >= achievement.target
    }

    func claim(_ achievement: Achievement) {
        guard isClaimable(achievement) else { return }
        claimedAchievements.insert(achievement.rawValue)
        gold += achievement.reward
        celebration = Celebration(symbol: achievement.symbol, headline: "Succès débloqué",
                                  title: achievement.title, gold: achievement.reward)
        log(achievement.symbol, "Succès « \(achievement.title) » : +\(achievement.reward.short) or.", .good)
        refreshUI()
        save()
    }

    /// Récompense d'une quête du jour : elle suit l'avancée dans les donjons.
    var questReward: Double { (25 * pow(3, Double(shopTier - 1))).rounded() }

    func questCount(_ kind: QuestKind) -> Int { min(questProgress[kind.rawValue] ?? 0, kind.target) }

    func isClaimable(_ kind: QuestKind) -> Bool {
        quests.contains(kind) && !questClaimed.contains(kind.rawValue) && questCount(kind) >= kind.target
    }

    func claim(_ kind: QuestKind) {
        guard isClaimable(kind) else { return }
        questClaimed.insert(kind.rawValue)
        gold += questReward
        celebration = Celebration(symbol: kind.symbol, headline: "Quête accomplie",
                                  title: kind.title, gold: questReward)
        cheer(5)
        log(kind.symbol, "Quête du jour accomplie : +\(questReward.short) or.", .good)
        refreshUI()
        save()
    }

    /// Nombre de récompenses en attente, pour la pastille de l'onglet.
    var claimableCount: Int {
        Achievement.allCases.filter(isClaimable).count + quests.filter(isClaimable).count
    }

    private func note(_ kind: QuestKind, _ amount: Int = 1) {
        guard quests.contains(kind) else { return }
        questProgress[kind.rawValue, default: 0] += amount
    }

    /// Chaque jour, trois nouvelles quêtes. Le tirage dépend du jour seul,
    /// pas du générateur de la partie : la prévision reste exacte.
    func refreshQuests(now: Date = Date()) {
        guard !isForecast else { return }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
        guard day != questDay else { return }
        questDay = day
        var generator = SeededGenerator(state: UInt64(day) &* 2_654_435_761)
        quests = Array(QuestKind.allCases.shuffled(using: &generator).prefix(3))
        questProgress = [:]
        questClaimed = []
        save()
    }

    // MARK: Taverne

    func price(of order: TavernOrder) -> Double {
        (order.basePrice * pow(3, Double(shopTier - 1))).rounded()
    }

    /// Ce qui empêche une commande, ou nil si le tavernier peut servir.
    func orderBlocker(_ order: TavernOrder) -> String? {
        guard case .tavern(let visit) = activity else { return "Seulement à la taverne" }
        switch order {
        case .ale where visit.drinks >= TavernOrder.maxDrinks: return "Le tavernier refuse de le resservir"
        case .stew where hunger >= 95: return "Il n'a plus faim"
        case .bard where visit.sang: return "Le barde se repose"
        default: break
        }
        return gold >= price(of: order) ? nil : "Pas assez d'or"
    }

    func order(_ order: TavernOrder) {
        guard orderBlocker(order) == nil, case .tavern(var visit) = activity else { return }
        settleRest()
        let cost = price(of: order)
        gold -= cost
        onEvent?(.bought(sprite: order.symbol, price: cost, caption: order.name))
        switch order {
        case .ale:
            visit.drinks += 1
            cheer(20)
            quench(30)
            log("mug.fill", visit.drinks == TavernOrder.maxDrinks
                ? "\(name) lève sa troisième chope. Le tavernier le surveille du coin de l'œil."
                : "\(name) savoure une chope de cervoise.", .good)
        case .stew:
            hunger = min(hunger + 45, 100)
            quench(10)
            meals += 1
            note(.feed)
            cheer(5)
            log("fork.knife", "Un ragoût fumant pour \(name). Il sauce l'assiette.", .good)
        case .bard:
            visit.sang = true
            cheer(10)
            log("music.note", "Le barde chante les exploits de \(name). Toute la salle reprend en chœur.", .good)
        }
        activity = .tavern(visit)
        onEvent?(.treated(order))
        refreshUI()
        save()
        replan()
    }

    // MARK: Itinérance

    var canRoam: Bool { currentPlace != nil }

    func roam(for duration: TimeInterval) {
        guard canRoam else { return }
        settleRest()
        activity = .roaming(Roam(start: clock, end: clock + duration, nextFind: clock + Roam.findEvery, found: [:]))
        log("figure.hiking", "\(name) part se promener dans la campagne pour \(duration.shortDuration).", .neutral)
        refreshUI()
        save()
        Outreach.askPermission()
        replan()
    }

    /// Une trouvaille : surtout des provisions, parfois quelques pièces.
    private func findSomething(_ roam: inout Roam, live: Bool) {
        // Rare rencontre (~5 %) : un compagnon encore inconnu croise la route du héros.
        let strays = CompanionKind.allCases.filter { !unlockedCompanions.contains($0.rawValue) }
        if !strays.isEmpty, Double.random(in: 0..<1, using: &rng) < 0.05 || Self.debugStray {
            let companion = strays[Int.random(in: 0..<strays.count, using: &rng)]
            tameCompanion(companion, live: live)
            roam.found["compagnon", default: 0] += 1
            gainXP(5 * Double(shopTier), live: live)
            return
        }
        let roll = Double.random(in: 0..<1, using: &rng)
        var provision: Provision?
        var coins = 0.0
        switch roll {
        case ..<0.28: provision = .fruit
        case ..<0.40: provision = .ration
        case ..<0.55: provision = .water
        case ..<0.66: provision = .tea
        case ..<0.75: provision = .herbs
        default: coins = (Double.random(in: 4...12, using: &rng) * Double(shopTier)).rounded()
        }
        if let provision {
            pantry[provision, default: 0] += 1
            roam.found[provision.rawValue, default: 0] += 1
            provisionsFound += 1
            note(.find)
        } else {
            gold += coins
            goldEarned += coins
            roam.found["or", default: 0] += coins
        }
        gainXP(2 * Double(shopTier), live: live)
        cheer(2)
        if live { onEvent?(.found(provision, gold: coins)) }
    }

    private func endRoam(_ roam: Roam, live: Bool) {
        let parts = Provision.allCases.compactMap { p -> String? in
            guard let n = roam.found[p.rawValue], n > 0 else { return nil }
            return "\(Int(n)) \(p.label(Int(n)))"
        } + ((roam.found["or"] ?? 0) > 0 ? ["\((roam.found["or"] ?? 0).short) or"] : [])
            + ((roam.found["compagnon"] ?? 0) > 0 ? ["un compagnon"] : [])
        activity = .resting
        cheer(10)
        roams += 1
        note(.roam)
        log("figure.hiking", "Retour de balade" + (parts.isEmpty ? "." : " : " + parts.joined(separator: ", ") + "."), .good)
        if live { replan() }
    }

    /// Temps de jeu avant de pouvoir encourager à nouveau le héros.
    var cheerCooldown: TimeInterval { max(lastCare + 1_800 - uiClock, 0) }

    var canEncourage: Bool {
        switch activity {
        case .resting, .roaming: return cheerCooldown <= 0
        default: return false
        }
    }

    func encourage() {
        guard canEncourage else { return }
        settleRest()
        lastCare = clock
        cares += 1
        note(.cheer)
        cheer(15)
        log("heart.fill", "Vous encouragez \(name). Son moral remonte.", .good)
        onEvent?(.cared(fed: false))
        refreshUI()
        save()
        replan()
    }

    func rename(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        heroName = trimmed.isEmpty ? nil : String(trimmed.prefix(16))
        save()
        replan()
    }

    // MARK: Actions en combat

    /// Avancée du combat de la salle en cours, de 0 à 1 (négative pendant l'approche).
    private func fightProgress(_ run: Run, at time: TimeInterval) -> Double {
        let span = run.roomEnd - run.roomStart
        guard span > 0 else { return 1 }
        return ((time - run.roomStart) / span - Self.walkShare) / (1 - Self.walkShare)
    }

    var canUseSkill: Bool {
        guard case .exploring(let run) = activity, skillCharge >= 1,
              run.room.kind == .monster || run.room.kind == .boss else { return false }
        // L'horloge de l'interface, rafraîchie plusieurs fois par seconde, rend le bouton réactif.
        let fight = fightProgress(run, at: uiClock)
        return fight >= 0 && fight < 0.95
    }

    /// Le coup spécial achève le monstre sur-le-champ : les coups qu'il n'a pas encore portés
    /// sont évités, et une défaite annoncée devient une victoire.
    func useSkill() {
        guard canUseSkill, case .exploring(var run) = activity else { return }
        let dungeon = Dungeon.all[run.dungeon]
        let fight = fightProgress(run, at: clock)
        let done = blows(in: run).filter { !$0.byHero && $0.at <= fight }
        let taken = done.reduce(0) { $0 + $1.damage }
        let potion = done.contains { $0.potion }
        var room = run.room
        if room.knockedOut {
            let scale = Dungeon.rankScale(run.level)
            let boss = room.kind == .boss
            room.knockedOut = false
            room.gold = (dungeon.gold * Dungeon.goldRankScale(run.level) * (boss ? 10 : 1) * Self.goldDropFactor).rounded()
            room.xp = dungeon.xp * scale * (boss ? 5 : 1)
        }
        room.hpDelta = (potion ? potionHeal : 0) - taken
        room.usesPotion = potion
        run.room = room
        // Le monstre tombe tout de suite : la salle se termine dans un instant.
        run.roomEnd = min(run.roomEnd, clock + 1.2 * timeScale)
        activity = .exploring(run)
        skillCharge = 0
        if has(.stormHeart) { hunger = max(hunger - Relic.stormHunger, 0) }
        cheer(5)
        log("bolt.circle.fill", "\(name) déclenche son coup spécial !", .good)
        onEvent?(.skill)
        refreshUI()
        save()
        replan()
    }

    var canDrinkPotion: Bool {
        guard case .exploring(let run) = activity, potions > 0, hp < maxHP else { return false }
        return run.room.usesPotion != true
    }

    func drinkPotion() {
        guard canDrinkPotion else { return }
        potions -= 1
        hp = min(hp + potionHeal, maxHP)
        log("cross.vial.fill", "Vous faites boire une potion à \(name) : +\(Int(potionHeal)) PV.", .good)
        onEvent?(.potionUsed(potionHeal))
        refreshUI()
        save()
        replan()
    }

    // MARK: Pièges

    /// Ouvre le défi de désamorçage : la salle est figée tant que le joueur n'a pas tranché.
    private func openTrapPrompt(_ run: Run) {
        // Zone verte confortable, placée au hasard pour que le timing ne soit pas appris par cœur.
        // (À resserrer plus tard selon le donjon pour des pièges plus retors en profondeur.)
        let width = 0.28
        let start = Double.random(in: 0.15...(0.85 - width), using: &rng)
        trapPrompt = TrapPrompt(start: Date(), sweep: 2.4, zoneStart: start, zoneWidth: width)
        onEvent?(.trapTriggered)
        refreshUI()
    }

    /// Le joueur a tapé (ou le chrono a expiré) : on applique le verdict puis on résout la salle.
    func disarmTrap(success: Bool) {
        guard trapPrompt != nil, case .exploring(var run) = activity, run.room.kind == .trap,
              run.room.trapDisarmed == nil else { trapPrompt = nil; return }
        trapPrompt = nil
        if success {
            run.room.hpDelta = 0
            run.room.knockedOut = false
            run.room.trapDisarmed = true
            cheer(2)
            onEvent?(.trapDisarmed)
        } else {
            run.room.trapDisarmed = false
        }
        activity = .exploring(run)
        resolve(run, live: true)
        refreshUI()
        save()
        replan()
    }

    /// Choix d'une bénédiction au carrefour en cours.
    func chooseBlessing(_ index: Int) {
        guard case .exploring(var run) = activity, let fork = run.fork, fork.indices.contains(index) else { return }
        run.forkChoice = index
        activity = .exploring(run)
        save()
        replan()
    }

    /// Choix du héros quand le joueur n'a pas tranché : selon son caractère.
    private func instinct(_ fork: [Blessing]) -> Int {
        let wish: Blessing? = traits.contains(.brave) ? .sharp
            : traits.contains(.careful) ? .stone
            : traits.contains(.glutton) ? .secondWind : nil
        if let wish, let index = fork.firstIndex(of: wish) { return index }
        return hp < maxHP * 0.5 ? (fork.firstIndex(of: .secondWind) ?? 0) : 0
    }

    /// Convertit le temps de repos accumulé en PV et en énergie.
    private func settleRest() {
        guard restDebt > 0 else { return }
        let rested = restDebt
        restDebt = 0
        if hp < maxHP { hp = min(maxHP, hp + hpRegen * rested) }
        if hp >= maxHP, injured {
            injured = false
            log("cross.fill", "Le héros est guéri de ses blessures.", .good)
        }
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
        case .tavern:
            activity = .tavern(TavernVisit(start: trip.end))
            log("mug.fill", "\(name) pousse la porte de la taverne.", .neutral)
        case .dungeon(let index):
            let dungeon = Dungeon.all[index]
            let boosted = scrollReady
            scrollReady = false
            let rank = min(max(trip.rank ?? 1, 1), dungeon.maxRank)
            let room = makeRoom(dungeon, index: 0, rank: rank, boosted: boosted)
            activity = .exploring(Run(dungeon: index, roomIndex: 0, roomStart: trip.end,
                                      roomEnd: trip.end + roomDuration(dungeon, for: room), room: room,
                                      gold: 0, items: 0, boosted: boosted, rank: rank, loot: []))
            log("door.left.hand.open",
                "Entre dans \(dungeon.name), rang \(rank)\(boosted ? ", parchemin de force actif" : "").", .neutral)
        }
    }

    // MARK: Salles

    /// Les pièces ramassées sur les monstres, boss et coffres sont réduites (−35 %) : on veut que
    /// le butin vienne surtout des objets, qu'on équipe ou qu'on revend. La valeur de revente des
    /// objets, elle, ne bouge pas (voir `Item.random`), donc elle pèse plus lourd qu'avant.
    static let goldDropFactor = 0.65

    private func makeRoom(_ dungeon: Dungeon, index: Int, rank: Int, boosted: Bool,
                          blessings: [Blessing] = [], forced: RoomKind? = nil) -> Room {
        var kind = Self.roomKind(index: index, rooms: dungeon.rooms, using: &rng)
        if let forced, kind != .boss { kind = forced }
        #if DEBUG
        // Tests : `-debugBoss YES` fait de chaque salle de combat un combat de boss.
        if Self.debugBoss, kind == .monster { kind = .boss }
        #endif
        let sharp = blessings.contains(.sharp) ? Blessing.sharpBonus : 1
        let stone = blessings.contains(.stone) ? Blessing.stoneFactor : 1
        // La nuit, les monstres frappent plus fort et leur butin est plus riche.
        let night = ambientNow.night
        let fortune = (blessings.contains(.fortune) ? Blessing.fortuneBonus : 1)
            * (has(.miserPurse) ? Relic.miserGold : 1) * (night ? Ambient.nightGold : 1)
        let spread = Double.random(in: 0.8...1.2, using: &rng)
        let scale = Dungeon.rankScale(rank)
        let goldScale = Dungeon.goldRankScale(rank)

        switch kind {
        case .monster, .boss:
            let boss = kind == .boss
            let foe = boss ? dungeon.boss : (dungeon.monsters.randomElement(using: &rng) ?? dungeon.monsters[0])
            // Passé la première salle, un monstre peut être un élite : plus dur, mais il paie mieux.
            let elite = !boss && index > 0 && (Double.random(in: 0..<1, using: &rng) < Room.eliteChance || Self.debugElite)
            let damage = (Self.fightDamage(foeHP: dungeon.monsterHP * scale * (boss ? 3 : 1) * (elite ? Room.eliteHP : 1),
                                           foeDamage: dungeon.monsterDamage * scale * (boss ? 1.5 : 1)
                                               * (elite ? Room.eliteDamage : 1)
                                               * (night ? Ambient.nightDamage : 1),
                                           attack: attack * (boosted ? 1.25 : 1) * sharp, spread: spread)
                          * stone * armorFactor).rounded()
            let needsPotion = damage >= hp
            if needsPotion, potions == 0 || damage >= hp + potionHeal {
                return Room(kind: kind, sprite: foe.sprite, name: foe.name, hpDelta: -(hp - woundedHP),
                            gold: 0, xp: 0, item: nil, knockedOut: true, elite: elite ? true : nil)
            }
            var item: Item?
            if boss {
                item = Item.random(tier: dungeon.tier, rank: rank, floor: .rare, luck: luck, hero: heroLook, using: &rng)
            } else if Double.random(in: 0..<1, using: &rng) < 0.11 * (1 + luck) * (elite ? Room.eliteItem : 1) {
                item = Item.random(tier: dungeon.tier, rank: rank, luck: luck, hero: heroLook, using: &rng)
            }
            // Un monstre sur huit laisse tomber quelque chose à manger ou à boire.
            let snack = Double.random(in: 0..<1, using: &rng) < 0.12
                ? [Provision.fruit, .ration, .tea, .water].randomElement(using: &rng) : nil
            // Le premier boss de chaque donjon garde une relique pour ce héros ; ensuite, c'est rare.
            var relic: Relic?
            if boss {
                let pool = Relic.allCases.filter { !has($0) }
                let first = clears[dungeon.id] == 0
                if !pool.isEmpty, first || Double.random(in: 0..<1, using: &rng) < Relic.bossChance {
                    relic = pool[Int.random(in: 0..<pool.count, using: &rng)]
                }
            }
            return Room(kind: kind, sprite: foe.sprite, name: foe.name,
                        hpDelta: needsPotion ? potionHeal - damage : -damage,
                        gold: (dungeon.gold * goldScale * (boss ? 10 : 1) * (elite ? Room.eliteGold : 1)
                               * spread * fortune * Self.goldDropFactor).rounded(),
                        xp: dungeon.xp * scale * (boss ? 5 : 1) * (elite ? Room.eliteXP : 1), item: item, knockedOut: false,
                        usesPotion: needsPotion, provision: snack, relic: relic, elite: elite ? true : nil)
        case .chest:
            let lucky = Double.random(in: 0..<1, using: &rng) < min(0.5 * (1 + luck), 0.95)
            let provision = Double.random(in: 0..<1, using: &rng) < 0.4 ? Provision.allCases.randomElement(using: &rng) : nil
            return Room(kind: .chest, sprite: "chest_closed", name: "Coffre", hpDelta: 0,
                        gold: (dungeon.gold * goldScale * 4 * spread * fortune * Self.goldDropFactor).rounded(), xp: 0,
                        item: lucky ? Item.random(tier: dungeon.tier, rank: rank, luck: luck, hero: heroLook, using: &rng) : nil,
                        knockedOut: false, provision: provision)
        case .trap:
            let damage = (dungeon.monsterDamage * scale * 1.5 * spread * stone * armorFactor * trapFactor).rounded()
            let fatal = damage >= hp
            return Room(kind: .trap, sprite: "trap_spikes", name: "Piège",
                        hpDelta: fatal ? -(hp - woundedHP) : -damage,
                        gold: 0, xp: 0, item: nil, knockedOut: fatal)
        case .fountain:
            return Room(kind: .fountain, sprite: "shrine", name: "Sanctuaire",
                        hpDelta: (maxHP * 0.15 * shrineFactor).rounded(), gold: 0, xp: 0, item: nil, knockedOut: false)
        }
    }

    /// PV rendus par une potion.
    var potionHeal: Double { (maxHP * potionShare).rounded() }
    private var potionShare: Double { has(.miserPurse) ? Relic.miserPotion : 0.4 }
    private var trapFactor: Double { (has(.chalice) ? Relic.chaliceTrap : 1) * (activeCompanion?.trapFactor ?? 1) }
    private var shrineFactor: Double { has(.chalice) ? Relic.chaliceHeal : 1 }

    /// PV restants après une fuite de justesse.
    private var woundedHP: Double { min(hp, max((maxHP * 0.05).rounded(), 1)) }

    private func resolve(_ finished: Run, live: Bool) {
        var run = finished
        let dungeon = Dungeon.all[run.dungeon]
        let room = run.room
        let label = room.kind == .boss ? "Boss" : "Salle \(run.roomIndex + 1)"

        // Piège rencontré en direct : on laisse au joueur un instant pour le désamorcer avant de trancher.
        if room.kind == .trap, room.trapDisarmed == nil, live, !isForecast {
            openTrapPrompt(run)
            return
        }

        if room.usesPotion == true, potions > 0 {
            potions -= 1
            // La scène a déjà montré la potion au moment du coup qui l'a rendue nécessaire.
            log("cross.vial.fill", "Potion bue en plein combat : +\(Int(potionHeal)) PV.", .good)
        }
        hp = min(max(hp + room.hpDelta, 1), maxHP)
        energy = max(energy - dungeon.roomEnergy, 0)
        gold += room.gold
        goldEarned += room.gold
        run.gold += room.gold
        if live { onEvent?(.roomResolved(room)) }

        eatOnTheRoad(live: live)

        if room.knockedOut {
            // À terre, il tente de fuir : sa forme et ses bottes décident s'il s'en sort.
            if Double.random(in: 0..<1, using: &rng) < escapeChance(knockedOut: true, boss: room.kind == .boss) {
                log("heart.slash.fill", "\(label) · \(room.name) : défaite. \(name) s'échappe de justesse, gravement blessé.", .bad)
                flee(run, at: run.roomEnd, reason: .fled, live: live)
            } else {
                log("heart.slash.fill", "\(label) · \(room.name) : défaite. \(name) n'a pas pu fuir.", .bad)
                die(fate: "est tombé dans \(dungeon.name)", live: live)
            }
            return
        }
        if room.kind == .monster || room.kind == .boss {
            kills[room.sprite, default: 0] += 1
            fightsWon += 1
            note(.fights)
            // Chaque victoire remplit la jauge du coup spécial et met du baume au cœur.
            skillCharge = min(skillCharge + (has(.stormHeart) ? 0.5 : 1.0 / 3), 1)
            cheer(room.kind == .boss ? 10 : 1)
            if room.kind == .boss { bossKills += 1 }
        }
        let rank = run.level

        let damage = Int(-room.hpDelta + (room.usesPotion == true ? potionHeal : 0))
        switch room.kind {
        case .monster, .boss:
            log("bolt.fill", "\(label) · \(room.name)\(room.elite == true ? " d'élite" : "") : victoire, -\(damage) PV, +\(room.gold.short) or.", .good)
        case .chest:
            log("shippingbox.fill", "\(label) · Coffre : +\(room.gold.short) or.", .good)
        case .trap:
            if room.trapDisarmed == true {
                log("checkmark.shield.fill", "\(label) · Piège désamorcé à temps : aucun dégât.", .good)
            } else {
                log("exclamationmark.triangle.fill", "\(label) · Piège : -\(damage) PV.", .bad)
            }
        case .fountain:
            log("drop.fill", "\(label) · Sanctuaire : +\(Int(room.hpDelta)) PV.", .good)
        }
        gainXP(room.xp, live: live)
        if let provision = room.provision {
            pantry[provision, default: 0] += 1
            provisionsFound += 1
            note(.find)
            log(provision.symbol, "Trouvé : \(provision.label(1)).", .good)
            if live { onEvent?(.found(provision, gold: 0)) }
        }
        if let item = room.item {
            // L'objet reste dans la sacoche : il n'est à l'abri qu'une fois sorti du donjon.
            run.loot = (run.loot ?? []) + [item]
            run.items += 1
            log("sparkles", "Objet trouvé : \(item.title(for: heroLook)) (\(item.bonusText)), dans la sacoche.", .good)
            if live { onEvent?(.loot(item: item, outcome: .carried)) }
        }
        if let relic = room.relic {
            gainRelic(relic, live: live, source: "Relique arrachée à \(room.name)")
        }

        if run.roomIndex == dungeon.rooms - 1 {
            let wasUnlocked = run.dungeon + 1 < Dungeon.all.count && isUnlocked(Dungeon.all[run.dungeon + 1])
            clears[run.dungeon] += 1
            let newRank = rank > bestRanks[run.dungeon]
            if newRank { bestRanks[run.dungeon] = rank }
            var text = "\(dungeon.name) terminé au rang \(rank). Butin : \(run.gold.short) or et \(Self.count(run.items, "objet"))."
            if newRank, rank < dungeon.maxRank {
                text += " Rang \(rank + 1) débloqué."
                // On propose d'office le rang suivant si le héros l'a bien en main.
                if chosenRanks[run.dungeon] == rank { chosenRanks[run.dungeon] = rank + 1 }
            }
            if !wasUnlocked, run.dungeon + 1 < Dungeon.all.count, isUnlocked(Dungeon.all[run.dungeon + 1]) {
                text += " Nouveau donjon : \(Dungeon.all[run.dungeon + 1].name)."
            }
            log("trophy.fill", text, .good)
            cheer(10)
            dungeonsCleared += 1
            note(.clear)
            if live { onEvent?(.dungeonCleared(dungeon.name)) }
            bringBack(run, live: live)
            headHome(from: run.dungeon, at: run.roomEnd, reason: .victory)
            return
        }

        if hp <= maxHP * fleeLimit {
            if potions > 0 {
                potions -= 1
                let healed = potionHeal
                hp = min(maxHP, hp + healed)
                log("cross.vial.fill", "Potion bue : +\(Int(healed)) PV.", .good)
                if live { onEvent?(.potionUsed(healed)) }
            } else {
                if Double.random(in: 0..<1, using: &rng) < escapeChance() {
                    log("figure.run", "Trop blessé pour continuer : \(name) fuit vers le camp.", .bad)
                    flee(run, at: run.roomEnd, reason: .fled, live: live)
                } else {
                    log("figure.run", "Trop blessé, \(name) tente de fuir, mais les monstres le rattrapent.", .bad)
                    die(fate: "est tombé dans \(dungeon.name)", live: live)
                }
                return
            }
        }
        if energy < dungeon.roomEnergy {
            log("battery.0percent", "À bout de forces : le héros rentre au camp avec son butin.", .bad)
            bringBack(run, live: live)
            flee(run, at: run.roomEnd, reason: .exhausted, live: live)
            return
        }

        // Fin d'un carrefour : la bénédiction choisie (ou celle du héros) prend effet.
        if let fork = run.fork {
            let blessing = fork[min(run.forkChoice ?? instinct(fork), fork.count - 1)]
            switch blessing {
            case .secondWind: hp = min(hp + (maxHP * Blessing.secondWindHeal).rounded(), maxHP)
            case .treasure: run.forcedKind = .chest
            case .sanctuary: run.forcedKind = .fountain
            default: run.blessings = (run.blessings ?? []) + [blessing]
            }
            log(blessing.symbol, "Carrefour : \(blessing.name), \(blessing.detail.lowercased()).", .good)
            if live { onEvent?(.blessed(blessing)) }
            run.fork = nil
            run.forkChoice = nil
        }

        run.roomIndex += 1
        run.roomStart = run.roomEnd
        run.roomEnd = run.roomStart + roomDuration(dungeon)
        run.room = makeRoom(dungeon, index: run.roomIndex, rank: rank, boosted: run.boosted,
                            blessings: run.blessings ?? [], forced: run.forcedKind)
        let blessed = run.forcedKind != nil
        run.forcedKind = nil
        // Une salle sur quatre est un carrefour : trois bénédictions à choisir pendant la salle.
        if run.roomIndex % 4 == 2, run.roomIndex < dungeon.rooms - 2, !blessed {
            var pool = Blessing.allCases
            var offer: [Blessing] = []
            for _ in 0..<3 {
                let pick = Int.random(in: 0..<pool.count, using: &rng)
                offer.append(pool.remove(at: pick))
            }
            run.fork = offer
        }
        run.roomEnd = run.roomStart + roomDuration(dungeon, for: run.room, fork: run.fork != nil)
        activity = .exploring(run)
    }

    // MARK: Provisions emportées

    /// Rations et gourdes que le sac peut contenir : de quoi tenir une longue expédition.
    static let packSize = 8

    /// En donjon, le héros puise dans les provisions emportées quand la faim ou la soif le tiraillent.
    /// Un sac vide, et il s'affaiblit, fuit mal, puis dépérit.
    private func eatOnTheRoad(live: Bool) {
        if thirst < 35 {
            if count(.water) > 0 {
                pantry[.water, default: 0] -= 1
                quench(50)
                log("drop.fill", "En chemin, \(name) boit à sa gourde.", .neutral)
            } else if count(.tea) > 0 {
                pantry[.tea, default: 0] -= 1
                quench(25)
                cheer(10)
                log("cup.and.saucer.fill", "En chemin, \(name) boit une tisane froide.", .neutral)
            }
        }
        if hunger < 35 {
            for food in [Provision.ration, .fruit] where count(food) > 0 {
                pantry[food, default: 0] -= 1
                hunger = min(hunger + (food == .ration ? 40 : 15), 100)
                if food == .fruit { quench(10) }
                log(food.symbol, "En chemin, \(name) mange \(food == .ration ? "une ration" : "quelques fruits").", .neutral)
                break
            }
        }
    }

    // MARK: Fuite

    /// Chances de fuite, réglées avec `Outils/equilibrage.py`.
    static let escapeBase = 0.75
    static let escapeKnockout = 0.35
    static let escapeBoss = 0.10
    static let escapeFatigue = 0.25

    /// Chance de s'en sortir quand le héros fuit. Elle baisse s'il est à terre, face au boss,
    /// fatigué, affamé, assoiffé ou déjà blessé, et monte avec le casque, de bonnes bottes et la chance.
    func escapeChance(knockedOut: Bool = false, boss: Bool = false, energy: Double? = nil) -> Double {
        var chance = Self.escapeBase
        if knockedOut { chance -= Self.escapeKnockout }
        if boss { chance -= Self.escapeBoss }
        chance -= Self.escapeFatigue * (1 - min(max((energy ?? self.energy) / Self.maxEnergy, 0), 1))
        chance -= hunger <= 0 ? 0.25 : hunger < 25 ? 0.15 : 0
        chance -= thirst <= 0 ? 0.25 : thirst < 25 ? 0.15 : 0
        if injured { chance -= 0.10 }
        if traits.contains(.careful) { chance += 0.05 }
        if has(.rabbitFoot) { chance += Relic.rabbitEscape }
        chance += activeCompanion?.escapeBonus ?? 0
        chance += ambientNow.weather.escapeBonus
        chance += gear(.boots) / 400 + gear(.ring) / 800 + gear(.helmet) / 100
        return min(max(chance, 0.05), 0.97)
    }

    /// Part de l'or de la sortie perdue dans une fuite.
    static let fleeGoldLoss = 0.5

    private func flee(_ run: Run, at time: TimeInterval, reason: TripReason, live: Bool) {
        if reason == .fled {
            flees += 1
            cheer(-20)
            // Une vraie fuite coûte cher : la sacoche reste sur place, avec la moitié de l'or,
            // et la blessure ralentit le repos.
            let lost = (run.gold * Self.fleeGoldLoss).rounded()
            gold = max(gold - lost, 0)
            injured = true
            let items = run.loot?.count ?? 0
            var text = "Dans sa fuite, le héros perd \(lost.short) or"
            text += items > 0 ? " et \(Self.count(items, "objet")) de sa sacoche." : "."
            log("bag.badge.minus", text, .bad)
        }
        if live { onEvent?(.fled(reason)) }
        headHome(from: run.dungeon, at: time, reason: reason)
    }

    /// La mort est définitive. Le suivant hérite du feu de camp, du sac de couchage
    /// et d'un quart de l'or ; tout le reste repart de zéro.
    private func die(fate: String, live: Bool) {
        let fallen = name
        lastFate = "\(fallen) \(fate)"
        let legacy = (gold * 0.25).rounded()
        // Sa tombe rejoint le cimetière, et ce qu'il peut transmettre attend le choix du joueur.
        let deepest = Dungeon.all.last { bestRanks[$0.id] > 0 }
        let grave = Grave(name: fallen, heroClass: heroLook, level: level, generation: generation, fate: fate,
                          date: gameDate(at: clock), days: heroBorn.map { Int((clock - $0) / 86_400) },
                          traits: traits, relics: relics, dungeon: deepest?.id,
                          rank: deepest.map { bestRanks[$0.id] }, fights: max(fightsWon - fightsAtBirth, 0),
                          companion: activeCompanion)
        graves.append(grave)
        if graves.count > 40 { graves.removeFirst(graves.count - 40) }
        let offer = PendingLegacy(grave: grave.id, purse: legacy, relics: relics, traits: traits)
        pendingLegacy = offer.options.isEmpty ? nil : offer
        relics = []
        inheritedTraits = []
        heroBorn = nil
        fightsAtBirth = fightsWon
        visitOutcome = nil
        gold = legacy
        level = 1
        xp = 0
        equipped = [:]
        bag = []
        potions = 0
        pantry = [.ration: 2, .water: 3]
        scrollReady = false
        clears = Array(repeating: 0, count: Dungeon.all.count)
        bestRanks = Array(repeating: 0, count: Dungeon.all.count)
        chosenRanks = Array(repeating: 1, count: Dungeon.all.count)
        injured = false
        hunger = 80
        thirst = 80
        mood = 50
        skillCharge = 0
        bossKills = 0
        flees = 0
        meals = 0
        cares = 0
        generation += 1
        heroName = nil
        hp = maxHP
        energy = Self.maxEnergy
        activity = .resting
        log("skull.fill", "\(fallen) \(fate). Son successeur hérite du camp et de \(legacy.short) or.", .bad)
        if live { onEvent?(.died(fate.hasPrefix("a été abandonné") ? "Abandonné…" : "Mort…")) }
        // On ne repart pas tout seul : la tombe bloque le jeu jusqu'au choix d'un successeur.
        // (L'abandon volontaire, lui, réassigne aussitôt la classe depuis chooseHero.)
        heroClass = nil
    }

    /// Le héros sort du donjon avec sa sacoche : le butin rejoint l'équipement ou le sac.
    private func bringBack(_ run: Run, live: Bool) {
        for item in run.loot ?? [] { addLoot(item, live: false) }
    }

    private func gainXP(_ amount: Double, live: Bool) {
        guard amount > 0 else { return }
        xp += amount
        while xp >= xpNeeded {
            xp -= xpNeeded
            level += 1
            hp += (20 * heroLook.hpFactor).rounded()
            cheer(5)
            log("star.fill", "Niveau \(level) atteint : +3 attaque, +20 PV max.", .good)
            if live { onEvent?(.levelUp(level)) }
        }
    }

    // MARK: Butin et équipement

    private func addLoot(_ item: Item, live: Bool) {
        let outcome: LootOutcome
        // L'équipement d'une autre classe ne s'équipe pas d'office : il part au sac.
        if canEquip(item), equipped[item.slot] == nil {
            equipped[item.slot] = item
            outcome = .equipped
            log("sparkles", "Équipé au retour : \(item.title(for: heroLook)) (\(item.bonusText)).", .good)
        } else if bag.count < Self.bagCapacity {
            bag.append(item)
            unseenLoot += 1
            outcome = .stored
        } else {
            gold += item.resaleValue
            outcome = .sold
            log("sparkles", "Sac plein : \(item.title(for: heroLook)) vendu \(item.resaleValue.short) or.", .neutral)
        }
        if live { onEvent?(.loot(item: item, outcome: outcome)) }
    }

    // MARK: Forge

    func canForge(_ slot: ItemSlot) -> Bool {
        guard isShopping, let item = equipped[slot], item.forgeLevel < Item.maxForge else { return false }
        return gold >= item.forgePrice
    }

    /// Le forgeron renforce un objet porté : +10 % de son bonus de base à chaque passage.
    func forge(_ slot: ItemSlot) {
        guard canForge(slot), var item = equipped[slot] else { return }
        let ratio = hp / maxHP
        gold -= item.forgePrice
        let price = item.forgePrice
        item.forge = item.forgeLevel + 1
        equipped[slot] = item
        onEvent?(.bought(sprite: item.image(for: heroLook), price: price, caption: "Forgé +\(item.forgeLevel)"))
        if slot == .amulet { hp = max((maxHP * ratio).rounded(), 1) }
        log("hammer.fill", "Forgé : \(item.title(for: heroLook)), \(item.bonusText).", .good)
        save()
        replan()
    }

    /// Vrai si l'objet est équipable et meilleur que celui porté dans le même emplacement.
    func isUpgrade(_ item: Item) -> Bool {
        canEquip(item) && item.power > (equipped[item.slot]?.power ?? 0)
    }

    /// Un objet réservé à une classe (arme, armure, casque) ne se porte que par elle ;
    /// bottes et bijoux (classe nil) vont à tout le monde. Les objets sans classe des
    /// anciennes sauvegardes restent équipables.
    func canEquip(_ item: Item) -> Bool {
        item.heroClass == nil || item.heroClass == heroClass
    }

    /// Équipe un objet du sac. L'ancien objet retourne dans le sac.
    func equip(_ item: Item) {
        guard canEquip(item), let index = bag.firstIndex(where: { $0.id == item.id }) else { return }
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
        gold += item.resaleValue
        onEvent?(.sold(gold: item.resaleValue))
        save()
    }

    var bagSellValue: Double { bag.reduce(0) { $0 + $1.resaleValue } }

    func sellBag() {
        guard isShopping, !bag.isEmpty else { return }
        let earned = bagSellValue
        gold += earned
        bag.removeAll()
        onEvent?(.sold(gold: earned))
        save()
    }

    func markLootSeen() {
        if unseenLoot != 0 { unseenLoot = 0 }
    }

    // MARK: Boutique

    private func restock() {
        let tier = shopTier
        let rank = max(bestRanks[tier - 1], 1)
        shopStock = [
            Item.random(tier: tier, rank: rank, hero: heroLook, ownClassOnly: true, using: &rng),
            Item.random(tier: tier, rank: rank, hero: heroLook, ownClassOnly: true, using: &rng),
            Item.random(tier: tier, rank: rank, floor: .rare, hero: heroLook, ownClassOnly: true, using: &rng),
        ]
    }

    func price(of supply: Supply) -> Double {
        supply == .bedroll ? supply.basePrice : (supply.basePrice * pow(3, Double(shopTier - 1))).rounded()
    }

    /// Raison qui empêche l'achat, ou nil.
    func purchaseBlocker(_ supply: Supply) -> String? {
        switch supply {
        case .potion where potions >= Self.maxPotions: return "Maximum atteint"
        case .ration where rations >= Self.packSize: return "Sac plein"
        case .water where count(.water) >= Self.packSize: return "Sac plein"
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
        let cost = price(of: supply)
        gold -= cost
        onEvent?(.bought(sprite: supply.sprite, price: cost, caption: supply.name))
        switch supply {
        case .potion: potions += 1
        case .ration: pantry[.ration, default: 0] += 1
        case .water: pantry[.water, default: 0] += 1
        case .scroll: scrollReady = true
        case .bedroll: hasBedroll = true
        }
        save()
    }

    func gearPrice(_ item: Item) -> Double { item.sellValue * 4 }

    func canBuyGear(_ item: Item) -> Bool {
        isShopping && canEquip(item) && gold >= gearPrice(item) && (equipped[item.slot] == nil || bag.count < Self.bagCapacity)
    }

    func buyGear(_ item: Item) {
        guard canBuyGear(item), let index = shopStock.firstIndex(where: { $0.id == item.id }) else { return }
        gold -= gearPrice(item)
        onEvent?(.bought(sprite: item.image(for: heroLook), price: gearPrice(item), caption: item.title(for: heroLook)))
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
            let left = max((maxHP - hp) / hpRegen, (Self.maxEnergy - energy) / energyRegen) / campRestFactor
            let now = ambient
            let detail = isStarving ? "Il dépérit : à boire et à manger, vite"
                : injured ? "Blessé, il guérit lentement"
                : !has(.ember) && now.weather.restFactor < 1 ? "La pluie étouffe le feu"
                : now.night ? "Il dort près des braises" : "Le héros reprend des forces"
            return ActivityInfo(title: "Au feu de camp",
                                detail: detail,
                                progress: min(hp / maxHP, energy / Self.maxEnergy), eta: left / timeScale)
        case .shopping:
            return ActivityInfo(title: "À la boutique", detail: "Achetez, vendez, puis repartez", progress: nil, eta: nil)
        case .tavern(let visit):
            let detail = mood >= 95 ? "Il est d'excellente humeur" : visit.drinks > 0 ? "Il trinque avec les habitués" : "Il se détend près de l'âtre"
            return ActivityInfo(title: "À la taverne", detail: detail, progress: nil, eta: nil)
        case .roaming(let roam):
            let found = Int(Provision.allCases.reduce(0) { $0 + (roam.found[$1.rawValue] ?? 0) })
            return ActivityInfo(title: "En balade dans la campagne",
                                detail: found == 0 ? "Il flâne sans danger" : "\(Self.count(found, "trouvaille")) en chemin",
                                progress: min(max((now - roam.start) / max(roam.end - roam.start, 1), 0), 1),
                                eta: max(roam.end - now, 0) / timeScale)
        case .traveling(let trip):
            let span = max(trip.end - trip.start, 0.001)
            return ActivityInfo(title: Self.title(of: trip), detail: "Depuis \(trip.from.name)",
                                progress: min(max((now - trip.start) / span, 0), 1),
                                eta: max(trip.end - now, 0) / timeScale)
        case .exploring(let run):
            let dungeon = Dungeon.all[run.dungeon]
            let span = max(run.roomEnd - run.roomStart, 0.001)
            let part = min(max((now - run.roomStart) / span, 0), 1)
            var detail: String
            if part < Self.walkShare {
                detail = "Avance dans le donjon"
            } else {
                switch run.room.kind {
                case .monster: detail = "Combat : \(run.room.name)\(run.room.elite == true ? " d'élite" : "")"
                case .boss: detail = "Combat de boss : \(run.room.name)"
                case .chest: detail = "Ouvre un coffre"
                case .trap: detail = "Tombe sur un piège"
                case .fountain: detail = "Se recueille dans un sanctuaire"
                }
            }
            let roomsLeft = Double(dungeon.rooms - run.roomIndex - 1)
            detail = "Rang \(run.level) · \(detail)"
            return ActivityInfo(title: "\(dungeon.name) · salle \(run.roomIndex + 1)/\(dungeon.rooms)",
                                detail: detail,
                                progress: (Double(run.roomIndex) + part) / Double(dungeon.rooms),
                                eta: (max(run.roomEnd - now, 0) + roomsLeft * roomDuration(dungeon)) / timeScale)
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
        /// Prochain carrefour sans choix du joueur.
        var forkAt: TimeInterval?
        /// Moment où le héros mourra si rien ne change, et comment.
        var diesAt: TimeInterval?
        var fate = ""
        /// Mort de faim ou de soif (sinon, en donjon), et moment où l'on prévient le joueur.
        var starved = false
        /// Il meurt avant d'être arrivé où que ce soit (de soif sur le chemin du retour, par exemple) :
        /// `landsAt` n'est alors que son dernier départ, pas une arrivée.
        var diesOnTheWay = false
        var warnAt: TimeInterval?
        /// Une fois arrêté : moment où la faim ou la soif commenceront à le ronger.
        var starvesAt: TimeInterval?
        /// Rencontre d'un compagnon en balade : quand, et lequel.
        var companionAt: TimeInterval?
        var companion: CompanionKind?
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
        let lineage = generation
        // Une fois le héros arrêté, on regarde encore quelques jours : s'il est oublié, quand mourra-t-il ?
        let horizon = clock + 4 * 86_400
        var parked = false
        func park() {
            parked = true
            settleRest()
            result.landing = currentPlace ?? .camp
            result.gold = gold - before.gold
            result.items = bag.count + equipped.count - before.items
            // S'il ne dépérit pas déjà, l'instant exact se lit plus bas, en avançant : la soif dépend de la météo.
            result.starvesAt = isStarving ? clock : nil
        }
        if activityEventTime == nil { park() }
        while let time = nextEventTime, steps < 1000, time <= horizon {
            steps += 1
            let moving = activityEventTime.map { time >= $0 } ?? false
            // Au camp, le repos avance heure par heure, au rythme de la nuit et de la météo.
            if parked, result.restedAt == nil, case .resting = activity, !isStarving {
                settleRest()
                if isRecovering {
                    let need = max((maxHP - hp) / hpRegen, (Self.maxEnergy - energy) / energyRegen)
                    let pace = campRestFactor
                    if need <= (time - clock) * pace { result.restedAt = clock + need / pace }
                }
            }
            pass(to: time)
            if result.forkAt == nil, case .exploring(let run) = activity, run.fork != nil, run.forkChoice == nil {
                result.forkAt = run.roomStart
            }
            let wasExploring = isExploring
            if case .traveling(let trip) = activity { result.reason = trip.reason }
            // Avant l'événement : de quoi prévenir le joueur si le héros meurt ici.
            let drainHP = maxHP
            let drain = drainHP * Self.starveDrain / 3_600 * emptyNeeds * needsDamp
            var room: TimeInterval = 0
            if case .exploring(let run) = activity { room = run.roomEnd - run.roomStart }
            if parked, result.starvesAt == nil, isStarving { result.starvesAt = time }
            let pack = unlockedCompanions
            handleEvent(live: false)
            if result.companionAt == nil, generation == lineage,
               let met = unlockedCompanions.subtracting(pack).first.flatMap(CompanionKind.init(rawValue:)) {
                result.companionAt = time
                result.companion = met
            }
            if generation != lineage {
                result.diesAt = time
                result.fate = lastFate
                result.starved = lastFate.contains("faim") || lastFate.contains("soif")
                result.diesOnTheWay = !parked
                // On prévient assez tôt pour agir : quand il ne lui reste qu'un quart de ses PV
                // s'il dépérit, deux salles avant le drame en donjon.
                result.warnAt = result.starved && drain > 0 ? time - 0.25 * drainHP / drain : time - room * 2
                break
            }
            if result.forkAt == nil, case .exploring(let run) = activity, run.fork != nil, run.forkChoice == nil {
                result.forkAt = run.roomStart
            }
            if moving {
                if wasExploring, case .traveling = activity { result.leavesDungeonAt = time }
                result.landsAt = time
            }
            if !parked, activityEventTime == nil { park() }
        }
        if !parked { park() }
        return result
    }

    /// Reprogramme les notifications et l'activité en direct d'après la prévision.
    func replan() {
        guard !isForecast else { return }
        Outreach.portrait = heroLook.portrait
        let plan = makePlan()
        Outreach.apply(plan)
        publishWidgets(upcoming: plan.notifications)
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
                       "\(name) est rentré au camp avec \(ahead.gold.short) or et \(Self.count(ahead.items, "objet")).",
                       "Donjon terminé : \(loot)")
        case .fled:
            outcome = ("\(name) a fui",
                       "Il est rentré au camp blessé, en laissant sa sacoche et la moitié de son or. Il a besoin de repos.",
                       "A fui, blessé : \(ahead.gold.short)\u{00A0}or")
        case .exhausted:
            outcome = ("\(name) est épuisé",
                       "Il est rentré au camp avec \(ahead.gold.short) or. Il a besoin de repos.",
                       "Rentré épuisé : \(loot)")
        case .recalled, .normal:
            outcome = ("De retour au camp", "\(name) s'installe au feu de camp.", "De retour au camp")
        }

        /// Ce que montre l'activité en direct une fois le héros au camp.
        func campPanel(arrival: TimeInterval) -> Panel {
            if let rested = ahead.restedAt, rested - arrival > 1 {
                return Panel(headline: "Au feu de camp", detail: outcome.short, sprite: "camp_fire_1",
                             steps: [step("Repos", arrival, rested)], end: date(rested), endLabel: "Reposé à")
            }
            return Panel(headline: "Au feu de camp", detail: outcome.short, sprite: "camp_fire_1",
                         steps: [], end: nil, endLabel: "")
        }
        func addLanding(_ lands: TimeInterval) {
            // Mort en chemin : pas de « rentré au camp » une minute avant le drame, l'alerte de mort suffit.
            guard !ahead.diesOnTheWay else {
                plan.staleDate = date(lands)
                return
            }
            plan.notifications.append(PlannedNotification(id: "hero.landing", date: date(lands),
                                                          title: outcome.title, body: outcome.body))
            if let rested = ahead.restedAt, (rested - lands) / scale >= 20 {
                plan.notifications.append(PlannedNotification(
                    id: "hero.rested", date: date(rested), title: "\(name) est reposé",
                    body: "PV et énergie au maximum. Prêt pour une nouvelle aventure."))
            }
            plan.staleDate = date(lands)
        }

        switch activity {
        case .shopping, .tavern:
            break

        case .roaming(let roam):
            plan.notifications.append(PlannedNotification(
                id: "hero.landing", date: date(roam.end), title: "Retour de balade",
                body: "\(name) rentre au camp, le sac plein de provisions."))
            plan.live = .init(
                now: Panel(headline: "En balade", detail: "\(name) flâne dans la campagne", sprite: heroLook.portrait,
                           steps: [step("Balade", roam.start, roam.end)], end: date(roam.end), endLabel: "Retour à"),
                later: Panel(headline: "Au feu de camp", detail: "De retour de balade", sprite: "camp_fire_1",
                             steps: [], end: nil, endLabel: ""))
            plan.staleDate = date(roam.end)

        case .resting:
            guard let rested = ahead.restedAt else { break }
            if (rested - clockNow) / scale >= 20 {
                plan.notifications.append(PlannedNotification(
                    id: "hero.rested", date: date(rested), title: "\(name) est reposé",
                    body: "PV et énergie au maximum. Prêt pour une nouvelle aventure."))
            }
            // La barre part du niveau de forme actuel, pas de zéro à chaque mise à jour.
            let fitness = min(hp / maxHP, energy / Self.maxEnergy, 0.95)
            let virtualStart = clockNow - fitness / (1 - fitness) * (rested - clockNow)
            plan.live = .init(
                now: Panel(headline: "Au feu de camp", detail: "\(name) reprend des forces", sprite: "camp_fire_1",
                           steps: [step("Repos", virtualStart, rested)], end: date(rested), endLabel: "Reposé à"),
                later: Panel(headline: "Au feu de camp", detail: "Reposé, prêt à repartir", sprite: "camp_fire_1",
                             steps: [], end: nil, endLabel: ""))
            plan.staleDate = date(rested)

        case .traveling(let trip):
            guard let lands = ahead.landsAt else { break }
            if trip.to == .shop {
                plan.notifications.append(PlannedNotification(
                    id: "hero.landing", date: date(lands), title: "Arrivé à la boutique",
                    body: "Le marchand attend \(name). Achetez, vendez, puis repartez."))
                plan.live = .init(
                    now: Panel(headline: "En route vers la boutique", detail: "Depuis \(trip.from.name)", sprite: heroLook.portrait,
                               steps: [step("Trajet", trip.start, trip.end)], end: date(lands), endLabel: "Arrivée à"),
                    later: Panel(headline: "À la boutique", detail: "Le marchand attend \(name)", sprite: "shop_sign",
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
                    now: Panel(headline: Self.title(of: trip), detail: "Depuis \(trip.from.name)", sprite: heroLook.portrait,
                               steps: [step("Retour", trip.start, trip.end)], end: date(lands), endLabel: "Arrivée à"),
                    later: campPanel(arrival: lands))
            }

        case .exploring(let run):
            guard let lands = ahead.landsAt else { break }
            let dungeon = Dungeon.all[run.dungeon]
            let entered = run.roomStart - Double(run.roomIndex) * roomDuration(dungeon)
            let leaves = ahead.leavesDungeonAt ?? run.roomEnd
            addLanding(lands)
            plan.live = .init(
                now: Panel(headline: dungeon.name, detail: "Exploration, puis retour au camp",
                           sprite: dungeon.boss.sprite,
                           steps: [step("Donjon", entered, leaves), step("Retour", leaves, lands)],
                           end: date(lands), endLabel: "Retour à"),
                later: campPanel(arrival: lands))
        }
        // Le héros a besoin de vous : faim au camp, carrefour à trancher, mort en Hardcore.
        if case .resting = activity, hunger > 25 {
            let hungry = clockNow + (hunger - 25) / hungerRate
            plan.notifications.append(PlannedNotification(
                id: "hero.hungry", date: date(hungry), title: "\(name) a faim",
                body: "Donnez-lui une ration au feu de camp, sinon il se battra moins bien."))
        }
        if case .resting = activity, thirst > 25 {
            let thirsty = thirstReaches(25)
            plan.notifications.append(PlannedNotification(
                id: "hero.thirsty", date: date(thirsty), title: "\(name) a soif",
                body: "Donnez-lui sa gourde au feu de camp. Assoiffé, il fuit mal et finit par dépérir."))
        }
        // Un visiteur passera au camp : on prévient, si le héros y est pour l'accueillir.
        if case .resting = activity, heroClass != nil,
           let visit = CampVisit.next(after: gameDate(at: clockNow)).map(settled), !answeredVisits.contains(visit.id) {
            let arrives = clockNow + visit.start.timeIntervalSince(gameDate(at: clockNow))
            if ahead.diesAt.map({ arrives < $0 }) ?? true {
                plan.notifications.append(PlannedNotification(
                    id: "hero.visitor", date: date(arrives), title: visit.kind.notice,
                    body: "Il ne restera que deux heures. À vous de voir ce que \(name) en fait."))
            }
        }
        if let met = ahead.companionAt, met > clockNow, let companion = ahead.companion {
            let named = companion.theName.prefix(1).uppercased() + companion.theName.dropFirst()
            plan.notifications.append(PlannedNotification(
                id: "hero.companion", date: date(met), title: "Un compagnon !",
                body: "\(named) s'est joint à \(name) en chemin. \(companion.motto)."))
        }
        if let fork = ahead.forkAt, fork > clockNow {
            plan.notifications.append(PlannedNotification(
                id: "hero.fork", date: date(fork), title: "Carrefour !",
                body: "\(name) hésite entre trois bénédictions. Choisissez, sinon il décidera seul."))
        }
        // Au camp, le moral s'use : on prévient avant que le héros ne broie du noir.
        if case .resting = activity, mood > 30 {
            let bored = clockNow + (mood - 30) / (6.0 / 3_600)
            plan.notifications.append(PlannedNotification(
                id: "hero.bored", date: date(bored), title: "\(name) s'ennuie",
                body: "Un encouragement, une balade ou un donjon lui remonteraient le moral."))
        }
        // Faim ou soif à zéro : il dépérit et peut en mourir.
        if let starves = ahead.starvesAt, starves > clockNow, ahead.diesAt.map({ starves < $0 }) ?? true {
            plan.notifications.append(PlannedNotification(
                id: "hero.starving", date: date(starves), title: "\(name) dépérit",
                body: "Sans eau ni nourriture, il perd des PV d'heure en heure. Oublié, il mourra."))
        }
        if let death = ahead.diesAt, let warn = ahead.warnAt, date(warn) > now.addingTimeInterval(5) {
            let left = ((death - warn) / scale).shortDuration
            plan.notifications.append(PlannedNotification(
                id: "hero.dying", date: date(warn), title: "\(name) va bientôt mourir",
                body: ahead.starved
                    ? "Il dépérit : il lui reste environ \(left). Donnez-lui à manger et à boire, vite !"
                    : "Il est en grand danger dans le donjon. Rappelez-le au camp tant qu'il est encore temps."))
        }
        if let death = ahead.diesAt {
            plan.notifications.removeAll { $0.id == "hero.landing" || $0.id == "hero.rested" }
            plan.notifications.append(PlannedNotification(
                id: "hero.landing", date: date(death), title: ahead.fate.isEmpty ? "\(name) est mort" : ahead.fate,
                body: "La mort est définitive. Son successeur hérite du camp et d'une part de l'or."))
        }
        // L'activité en direct montre le lieu en fond, et l'état du héros.
        if var live = plan.live {
            live.now.scene = liveScene(for: live.now, current: true)
            if var later = live.later {
                later.scene = liveScene(for: later, current: false)
                live.later = later
            }
            live.hero = .init(name: name, portrait: heroLook.portrait, hp: min(hp / maxHP, 1),
                              hunger: hunger / 100, mood: mood / 100, thirst: thirst / 100)
            plan.live = live
        }
        return plan
    }

    /// Vignette du lieu pour l'activité en direct.
    private func liveScene(for panel: HeroActivityAttributes.Panel, current: Bool) -> String {
        if panel.headline.hasPrefix("Au feu de camp") { return WorldScene.isDaytime ? "lw_camp_brume" : "lw_camp" }
        if panel.headline.hasPrefix("À la boutique") { return "lw_marche" }
        guard current else { return "lw_camp" }
        func dungeonScene(_ index: Int) -> String {
            switch Dungeon.all[index].style {
            case .cave: "lw_cave"
            case .forest: "lw_bois_hante"
            case .crypt: "lw_crypte"
            case .ice: "lw_glacier"
            case .volcano: "lw_volcan"
            }
        }
        switch activity {
        case .exploring(let run): return dungeonScene(run.dungeon)
        case .traveling(let trip):
            if case .dungeon(let index) = trip.to { return dungeonScene(index) }
            return "lw_trajet"
        case .roaming: return "lw_trajet"
        case .shopping, .tavern: return "lw_marche"
        case .resting: return WorldScene.isDaytime ? "lw_camp_brume" : "lw_camp"
        }
    }

    // MARK: Mode test

    var isTestSpeed: Bool { timeScale > 1 }

    /// Accélère tout le jeu pour essayer les longs donjons sans attendre.
    /// `scale` ≤ 1 désactive le mode test ; sinon c'est le facteur d'accélération.
    func setTestSpeed(_ scale: Double) {
        settleRest()
        timeScale = scale > 1 ? scale : 1
        // De retour en temps réel, l'heure du jeu se recale sur celle du téléphone.
        if timeScale == 1 { (anchorDate, anchorClock) = (Date(), clock) }
        UserDefaults.standard.set(timeScale, forKey: Self.timeScaleKey)
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
        /// Absent tant que le joueur n'a pas choisi son héros.
        var heroClass: HeroClass?
        /// Absents des sauvegardes d'avant les rangs et le feu amélioré.
        var bestRanks: [Int]?
        var chosenRanks: [Int]?
        var campLevel: Int?
        var injured: Bool?
        /// Absents des sauvegardes d'avant les besoins du héros.
        var hunger: Double?
        var mood: Double?
        var rations: Int?
        var pantry: [String: Int]?
        var heroName: String?
        var skillCharge: Double?
        /// Ancien mode Hardcore : la mort est désormais toujours définitive.
        var hardcore: Bool?
        /// Absent des sauvegardes d'avant la soif.
        var thirst: Double?
        var generation: Int?
        var feats: [Int]?
        var lastCare: TimeInterval?
        /// Absents des sauvegardes d'avant les exploits.
        var kills: [String: Int]?
        var exploits: [Double]?
        var claimedAchievements: [String]?
        var questDay: Int?
        var quests: [QuestKind]?
        var questProgress: [String: Int]?
        var questClaimed: [String]?
        /// Absents des sauvegardes d'avant les compagnons.
        var activeCompanion: CompanionKind?
        var unlockedCompanions: [String]?
        /// Absents des sauvegardes d'avant les reliques, le cimetière, les visiteurs et la météo.
        var relics: [Relic]?
        var inheritedTraits: [Trait]?
        var graves: [Grave]?
        var pendingLegacy: PendingLegacy?
        var answeredVisits: [String]?
        var heroBorn: TimeInterval?
        var fightsAtBirth: Int?
        var anchorDate: Date?
        var anchorClock: TimeInterval?
        /// Absent tant que le joueur n'a pas partagé sa position.
        var sky: Sky?
    }

    private func snapshot() -> SaveData {
        SaveData(
            gold: gold, level: level, xp: xp, hp: hp, energy: energy,
            potions: potions, scrollReady: scrollReady, hasBedroll: hasBedroll,
            equipped: Dictionary(uniqueKeysWithValues: equipped.map { ($0.key.rawValue, $0.value) }),
            bag: bag, activity: activity, clears: clears, shopStock: shopStock,
            journal: journal, clock: clock, lastTick: lastTick, rng: rng.state, heroClass: heroClass,
            bestRanks: bestRanks, chosenRanks: chosenRanks, campLevel: campLevel, injured: injured,
            hunger: hunger, mood: mood, rations: rations, pantry: Dictionary(uniqueKeysWithValues: pantry.map { ($0.key.rawValue, $0.value) }), heroName: heroName, skillCharge: skillCharge,
            hardcore: true, thirst: thirst, generation: generation, feats: [bossKills, flees, meals, cares], lastCare: lastCare,
            kills: kills, exploits: [Double(fightsWon), Double(roams), Double(provisionsFound), goldEarned, Double(dungeonsCleared)],
            claimedAchievements: Array(claimedAchievements), questDay: questDay, quests: quests,
            questProgress: questProgress, questClaimed: Array(questClaimed),
            activeCompanion: activeCompanion, unlockedCompanions: Array(unlockedCompanions),
            relics: relics, inheritedTraits: inheritedTraits, graves: graves, pendingLegacy: pendingLegacy,
            answeredVisits: answeredVisits, heroBorn: heroBorn, fightsAtBirth: fightsAtBirth,
            anchorDate: anchorDate, anchorClock: anchorClock, sky: sky == Sky() ? nil : sky
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
        heroClass = data.heroClass
        let count = Dungeon.all.count
        // Une ancienne partie compte chaque donjon terminé comme fait au rang 1.
        let ranks = data.bestRanks ?? clears.map { $0 > 0 ? 1 : 0 }
        bestRanks = Array((ranks + Array(repeating: 0, count: count)).prefix(count))
        chosenRanks = Array(((data.chosenRanks ?? []) + Array(repeating: 1, count: count)).prefix(count))
        campLevel = data.campLevel ?? 0
        injured = data.injured ?? false
        hunger = data.hunger ?? 80
        mood = data.mood ?? 70
        pantry = [.ration: data.rations ?? 2]
        for (key, value) in data.pantry ?? [:] {
            if let provision = Provision(rawValue: key) { pantry[provision] = value }
        }
        heroName = data.heroName
        skillCharge = data.skillCharge ?? 0
        thirst = data.thirst ?? 80
        // Une partie d'avant la soif reçoit de quoi boire pour commencer.
        if data.thirst == nil { pantry[.water, default: 0] += 3 }
        generation = data.generation ?? 1
        let feats = (data.feats ?? []) + [0, 0, 0, 0]
        (bossKills, flees, meals, cares) = (feats[0], feats[1], feats[2], feats[3])
        lastCare = data.lastCare ?? -1_000_000
        kills = data.kills ?? [:]
        let exploits = (data.exploits ?? []) + [0, 0, 0, 0, 0]
        fightsWon = Int(exploits[0]); roams = Int(exploits[1]); provisionsFound = Int(exploits[2])
        goldEarned = exploits[3]
        // Une ancienne partie compte ses donjons terminés.
        dungeonsCleared = data.exploits == nil ? clears.reduce(0, +) : Int(exploits[4])
        claimedAchievements = Set(data.claimedAchievements ?? [])
        questDay = data.questDay ?? 0
        quests = data.quests ?? []
        questProgress = data.questProgress ?? [:]
        questClaimed = Set(data.questClaimed ?? [])
        unlockedCompanions = Set(data.unlockedCompanions ?? [])
        // On ne garde un compagnon actif que s'il est bien débloqué.
        activeCompanion = data.activeCompanion.flatMap { unlockedCompanions.contains($0.rawValue) ? $0 : nil }
        relics = data.relics ?? []
        inheritedTraits = data.inheritedTraits ?? []
        graves = data.graves ?? []
        pendingLegacy = data.pendingLegacy
        answeredVisits = data.answeredVisits ?? []
        heroBorn = data.heroBorn
        fightsAtBirth = data.fightsAtBirth ?? 0
        // Sans repère sauvegardé, l'heure du jeu part de celle du dernier passage.
        anchorDate = data.anchorDate ?? data.lastTick
        anchorClock = data.anchorClock ?? data.clock
        sky = data.sky ?? Sky()
        hp = min(hp, maxHP)
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
        heroClass = nil
        activeCompanion = nil
        unlockedCompanions = []
        relics = []
        inheritedTraits = []
        graves = []
        pendingLegacy = nil
        answeredVisits = []
        visitOutcome = nil
        heroBorn = nil
        fightsAtBirth = 0
        activity = .resting
        clears = Array(repeating: 0, count: Dungeon.all.count)
        bestRanks = Array(repeating: 0, count: Dungeon.all.count)
        chosenRanks = Array(repeating: 1, count: Dungeon.all.count)
        campLevel = 0
        injured = false
        hunger = 80
        thirst = 80
        mood = 70
        pantry = [.ration: 2, .water: 3]
        heroName = nil
        skillCharge = 0
        generation = 1
        (bossKills, flees, meals, cares) = (0, 0, 0, 0)
        lastCare = -1_000_000
        kills = [:]
        (fightsWon, roams, provisionsFound, dungeonsCleared) = (0, 0, 0, 0)
        goldEarned = 0
        claimedAchievements = []
        questDay = 0
        shopStock = []
        journal = []
        restDebt = 0
        log("flame.fill", "Nouvelle aventure. Le héros s'installe au feu de camp.", .neutral)
        refreshUI()
        save()
        replan()
    }
}

// MARK: - Widgets

extension GameState {
    /// Écrit d'avance l'état du héros pour les widgets, puis les fait redessiner.
    fileprivate func publishWidgets(upcoming notes: [PlannedNotification]) {
        let now = Date()
        let symbols = ["hero.landing": "flag.checkered", "hero.rested": "bed.double.fill",
                       "hero.hungry": "fork.knife", "hero.thirsty": "drop.fill",
                       "hero.starving": "exclamationmark.triangle.fill", "hero.dying": "heart.slash.fill",
                       "hero.fork": "signpost.right.and.left.fill", "hero.bored": "cloud.rain.fill",
                       "hero.visitor": "person.fill.questionmark"]
        // La rencontre d'un compagnon reste une surprise : elle n'est pas annoncée d'avance.
        let upcoming = notes.filter { $0.date > now && $0.id != "hero.companion" }
            .sorted { $0.date < $1.date }
            .map { HeroWidgetData.Upcoming(date: $0.date, title: $0.title, symbol: symbols[$0.id] ?? "bell.fill") }
        var frames: [HeroWidgetData.Frame] = []
        if heroClass != nil {
            settleRest()
            frames = GameState(twinOf: snapshot(), timeScale: timeScale).sampleAhead(from: now)
        }
        let widgetData = HeroWidgetData(frames: frames, upcoming: Array(upcoming.prefix(4)))
        widgetData.save()
        WatchSync.shared.send(widgetData)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Joue la suite sur la copie et prend une image du héros à intervalles réguliers :
    /// toutes les cinq minutes sur quatorze heures, toutes les trente secondes en mode test,
    /// plus une image à l'instant de chaque événement du héros (arrivée, salle, sortie, retour).
    /// Un pas plus serré rafraîchit le widget et la complication deux fois plus souvent ; la
    /// fenêtre de 14 h couvre largement la nuit entre deux passages, et la chronologie envoyée
    /// à la montre reste bien sous la limite de l'`updateApplicationContext` (~262 ko).
    fileprivate func sampleAhead(from now: Date) -> [HeroWidgetData.Frame] {
        let testing = timeScale > 1
        let every: TimeInterval = testing ? 30 : 300
        let count = testing ? 120 : 168
        let lineage = generation
        let fallen = (name: name, portrait: heroLook.portrait, level: level)
        // Besoins figés sur l'état réel courant : le widget ne projette pas une fausse famine.
        let frozenNeeds = (hunger: hunger, thirst: thirst, mood: mood)
        let start = clock
        var frames: [HeroWidgetData.Frame] = []
        var eventFrames = 0
        for index in 0..<count {
            let target = start + Double(index) * every * timeScale
            var steps = 0
            var lastEvent = clock
            while generation == lineage, let time = nextEventTime, time <= target, steps < 500 {
                steps += 1
                lastEvent = time
                // Un événement du héros (arrivée au donjon, salle suivante, sortie, retour au camp),
                // et non un simple seuil de faim ou un changement de temps.
                let heroEvent = activityEventTime.map { $0 <= time } ?? false
                pass(to: time)
                handleEvent(live: false)
                // Le widget change à l'instant même de l'événement, sans attendre la prochaine image
                // de la grille (jusqu'à cinq minutes plus tard).
                if heroEvent, generation == lineage, time > start, eventFrames < 60 {
                    eventFrames += 1
                    settleRest()
                    uiClock = clock
                    frames.append(widgetFrame(at: now.addingTimeInterval((time - start) / timeScale), needs: frozenNeeds))
                    // Dans une salle, le héros marche puis se bat : une image aussi quand le combat commence.
                    if case .exploring(let run) = activity {
                        let fight = run.roomStart + (run.roomEnd - run.roomStart) * Self.walkShare + timeScale
                        if fight > clock, fight < target, fight < nextEventTime ?? .infinity {
                            pass(to: fight)
                            uiClock = clock
                            frames.append(widgetFrame(at: now.addingTimeInterval((fight - start) / timeScale), needs: frozenNeeds))
                        }
                    }
                }
            }
            if generation != lineage {
                // Le héros meurt avant la prochaine image : la dernière sera sa tombe.
                let date = now.addingTimeInterval((lastEvent - start) / timeScale)
                frames.append(HeroWidgetData.Frame(
                    date: date, name: fallen.name, portrait: fallen.portrait, level: fallen.level, gold: gold,
                    place: "Mort", title: lastFate, detail: "La mort est définitive.",
                    sprite: "camp_fire_1", scene: "lw_camp", start: nil, end: nil,
                    hp: 0, energy: 0, hunger: 0, thirst: 0, mood: 0, alert: "Mort", dead: true, pose: nil))
                break
            }
            pass(to: target)
            settleRest()
            uiClock = clock
            frames.append(widgetFrame(at: now.addingTimeInterval(Double(index) * every), needs: frozenNeeds))
        }
        return frames
    }

    /// `needs` fige la faim/soif/moral sur l'état réel courant : le widget projette le lieu et
    /// l'activité, mais ne crie pas « Dépérit » pour une famine simplement prévue loin dans le futur
    /// (les vraies échéances de besoins restent dans la liste « À venir »).
    private func widgetFrame(at date: Date, needs: (hunger: Double, thirst: Double, mood: Double)) -> HeroWidgetData.Frame {
        let info = activityInfo
        var start: Date?, end: Date?
        if let eta = info.eta, eta > 0 {
            end = date.addingTimeInterval(eta)
            if let progress = info.progress, progress < 0.999 {
                start = date.addingTimeInterval(-eta * progress / (1 - progress))
            }
        }
        let hour = Calendar.current.component(.hour, from: date)
        let day = (7..<19).contains(hour)
        func dungeonScene(_ index: Int) -> String {
            switch Dungeon.all[index].style {
            case .cave: "lw_cave"
            case .forest: "lw_bois_hante"
            case .crypt: "lw_crypte"
            case .ice: "lw_glacier"
            case .volcano: "lw_volcan"
            }
        }
        let camp = day ? "lw_camp_brume" : "lw_camp"
        let place: String, sprite: String, scene: String
        var fork = false
        var pose = "idle"
        switch activity {
        case .resting:
            (place, sprite, scene) = ("Camp", "camp_fire_1", camp)
            pose = "rest"
        case .shopping: (place, sprite, scene) = ("Boutique", "shop_sign", "lw_marche")
        case .tavern: (place, sprite, scene) = ("Taverne", "shop_sign", "lw_marche")
        case .roaming:
            (place, sprite, scene) = ("Balade", heroLook.portrait, "lw_trajet")
            pose = "walk"
        case .traveling(let trip):
            if case .dungeon(let index) = trip.to {
                (place, sprite, scene) = ("En route", Dungeon.all[index].boss.sprite, dungeonScene(index))
            } else {
                (place, sprite, scene) = ("En route", "camp_fire_1", "lw_trajet")
            }
            pose = trip.reason == .fled ? "flee" : "walk"
        case .exploring(let run):
            let dungeon = Dungeon.all[run.dungeon]
            (place, sprite, scene) = (dungeon.name, dungeon.boss.sprite, dungeonScene(run.dungeon))
            fork = run.fork != nil && run.forkChoice == nil
            // Il marche jusqu'à la salle, puis se bat, ouvre le coffre ou se recueille.
            let span = max(run.roomEnd - run.roomStart, 0.001)
            let walking = (clock - run.roomStart) / span < Self.walkShare
            switch run.room.kind {
            case _ where walking: pose = "walk"
            case .monster, .boss: pose = "attack"
            case .chest, .trap, .fountain: pose = "idle"
            }
        }
        let starving = heroClass != nil && (needs.hunger <= 0 || needs.thirst <= 0)
        let alert: String? = if starving { "Dépérit" }
            else if needs.thirst < 25 { "Assoiffé" }
            else if needs.hunger < 25 { "Affamé" }
            else if fork { "Carrefour" }
            else if needs.mood < 25 { "Cafard" }
            else if hp < maxHP * 0.3 { "Blessé" }
            else { nil }
        return HeroWidgetData.Frame(
            date: date, name: name, portrait: heroLook.portrait, level: level, gold: gold,
            place: place, title: info.title, detail: info.detail, sprite: sprite, scene: scene,
            start: start, end: end,
            hp: min(max(hp / maxHP, 0), 1), energy: min(max(energy / Self.maxEnergy, 0), 1),
            hunger: min(max(needs.hunger / 100, 0), 1), thirst: min(max(needs.thirst / 100, 0), 1),
            mood: min(max(needs.mood / 100, 0), 1), alert: alert, dead: false, pose: pose)
    }
}
