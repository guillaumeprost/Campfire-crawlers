import XCTest
@testable import IdleRPG

/// Tests de la logique de jeu de `GameState`.
///
/// `GameState` lit `UserDefaults.standard` à l'initialisation. Dans le bundle de
/// tests ce domaine est isolé de l'app réelle, mais on le nettoie quand même entre
/// chaque test pour partir d'un état connu, via les crochets de debug déjà présents
/// dans `init` (`debugReset`, `debugGold`, `debugTimeScale`).
@MainActor
final class GameStateTests: XCTestCase {

    private let debugKeys = ["save.v2", "debugReset", "debugGold", "debugTimeScale",
                             "debugHero", "debugGo", "debugHeal", "debugSkill",
                             "debugWeather", "debugNight", "debugVisitor", "debugRelic",
                             "debugLevel", "debugUnlock", "debugFeats", "debugSky", "debugSeed"]

    override func setUp() {
        super.setUp()
        clearDefaults()
    }

    override func tearDown() {
        clearDefaults()
        super.tearDown()
    }

    private func clearDefaults() {
        let d = UserDefaults.standard
        for key in debugKeys { d.removeObject(forKey: key) }
    }

    /// Une partie neuve, sans sauvegarde, avec éventuellement de l'or de départ.
    /// Le temps est figé (jour, ciel dégagé) pour que les chiffres ne dépendent pas de l'heure du test.
    private func makeGame(gold: Double = 0, timeScale: Double = 1, weather: String? = "clear", night: Bool? = false,
                          visitor: String? = nil, relic: String? = nil,
                          level: Int = 1, unlock: Bool = false, feats: Bool = false, seed: Int? = nil) -> GameState {
        let d = UserDefaults.standard
        for key in debugKeys { d.removeObject(forKey: key) }
        d.set(true, forKey: "debugReset")
        d.set(gold, forKey: "debugGold")
        d.set(timeScale, forKey: "debugTimeScale")
        // nil : on laisse l'heure et la météo du jeu suivre la date, comme en vrai.
        if let weather { d.set(weather, forKey: "debugWeather") }
        if let night { d.set(night, forKey: "debugNight") }
        if let visitor { d.set(visitor, forKey: "debugVisitor") }
        if let relic { d.set(relic, forKey: "debugRelic") }
        if level > 1 { d.set(level, forKey: "debugLevel") }
        if unlock { d.set(true, forKey: "debugUnlock") }
        if feats { d.set(true, forKey: "debugFeats") }
        // Même graine : deux parties tirent les mêmes salles, les mêmes dégâts, le même butin.
        if let seed { d.set(seed, forKey: "debugSeed") }
        return GameState()
    }

    // MARK: Le vrai ciel

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testNightFollowsTheRealSun() {
        // Paris, solstice d'été 2026 : lever à 3 h 47 TU, coucher à 19 h 58 TU.
        let paris = Sky(latitude: 48.85, longitude: 2.35)
        XCTAssertTrue(Ambient.isNight(utc(2026, 6, 21, 3, 40), sky: paris), "Sept minutes avant le lever, il fait nuit.")
        XCTAssertFalse(Ambient.isNight(utc(2026, 6, 21, 3, 54), sky: paris), "Sept minutes après le lever, il fait jour.")
        XCTAssertFalse(Ambient.isNight(utc(2026, 6, 21, 19, 51), sky: paris), "Sept minutes avant le coucher, il fait jour.")
        XCTAssertTrue(Ambient.isNight(utc(2026, 6, 21, 20, 5), sky: paris), "Sept minutes après le coucher, il fait nuit.")
        // Solstice d'hiver : lever à 7 h 41 TU, coucher à 15 h 56 TU.
        XCTAssertTrue(Ambient.isNight(utc(2026, 12, 21, 7, 34), sky: paris))
        XCTAssertFalse(Ambient.isNight(utc(2026, 12, 21, 7, 48), sky: paris))
        XCTAssertFalse(Ambient.isNight(utc(2026, 12, 21, 15, 49), sky: paris))
        XCTAssertTrue(Ambient.isNight(utc(2026, 12, 21, 16, 3), sky: paris))
        // Au-delà du cercle polaire, le soleil de minuit ne se couche pas.
        XCTAssertFalse(Ambient.isNight(utc(2026, 6, 21, 23, 0), sky: Sky(latitude: 69.65, longitude: 18.96)))
    }

    func testTimeIsCutAtSunriseAndSunset() {
        let paris = Sky(latitude: 48.85, longitude: 2.35)
        let before = utc(2026, 6, 21, 3, 10)
        let wait = Ambient.untilNextChange(before, sky: paris)
        XCTAssertEqual(wait, 37 * 60, accuracy: 120, "Le temps se coupe au lever du soleil, pas à l'heure pile.")
        XCTAssertTrue(Ambient.isNight(before.addingTimeInterval(wait - 2), sky: paris))
        XCTAssertFalse(Ambient.isNight(before.addingTimeInterval(wait), sky: paris), "À la coupure, le jour est déjà levé.")
        XCTAssertEqual(Ambient.untilNextChange(before.addingTimeInterval(wait), sky: paris), 3_000 - wait, accuracy: 0.01,
                       "Ensuite, on vise l'heure pile.")
        XCTAssertEqual(Ambient.untilNextChange(before), 3_000, accuracy: 0.01, "Sans position, seules les heures comptent.")
    }

    func testRealWeatherReplacesTheImaginedOne() {
        let noon = Ambient.date(day: 9_500, hour: 12)
        var sky = Sky()
        sky.hours[Sky.hourKey(noon)] = .snow
        XCTAssertEqual(Ambient.weather(at: noon.addingTimeInterval(1_800), sky: sky), .snow, "L'heure relevée suit le vrai temps.")
        XCTAssertEqual(Ambient.weather(at: noon.addingTimeInterval(3_600), sky: sky), Ambient.weather(at: noon.addingTimeInterval(3_600)),
                       "Au-delà du relevé, le temps redevient imaginaire.")
        // Un relevé plus récent ne réécrit pas les heures déjà jouées.
        var fresh = Sky(latitude: 48.85, longitude: 2.35)
        fresh.hours = [Sky.hourKey(noon) - 1: .storm, Sky.hourKey(noon): .rain, Sky.hourKey(noon) + 1: .fog]
        sky.hours[Sky.hourKey(noon) - 1] = .clear
        sky.adopt(fresh, from: noon.addingTimeInterval(600))
        XCTAssertEqual(sky.hours[Sky.hourKey(noon) - 1], .clear)
        XCTAssertEqual(sky.hours[Sky.hourKey(noon)], .rain)
        XCTAssertEqual(sky.hours[Sky.hourKey(noon) + 1], .fog)
        XCTAssertTrue(sky.followsSun)
    }

    func testForecastReplaysTheRecordedSky() {
        // Sans temps figé : le jeu suit le ciel enregistré, et la prévision doit le rejouer à l'identique.
        let game = makeGame(weather: nil, night: nil)
        game.chooseHero(.warrior)
        var sky = Sky(latitude: 48.85, longitude: 2.35)
        let now = Sky.hourKey(game.gameDate(at: 0))
        for hour in 0..<120 { sky.hours[now + hour] = hour % 2 == 0 ? .storm : .snow }
        game.updateSky(sky)
        XCTAssertTrue(game.followsRealSun)
        XCTAssertTrue(game.followsRealWeather)
        XCTAssertTrue([Weather.storm, .snow].contains(game.ambient.weather))
        let start = Date()
        game.tick(now: start)
        game.travel(to: .dungeon(0))
        guard let lands = game.forecast().landsAt else { return XCTFail("Pas d'arrivée prévue.") }
        XCTAssertEqual(game.forecast().landsAt, lands, "Même ciel enregistré, même prévision.")
        // Juste avant l'heure annoncée il est encore en route (ou mort en chemin) ; juste après, il est arrivé.
        let wait = lands - game.clock
        game.tick(now: start.addingTimeInterval(wait - 1))
        let early = game.forecast().landsAt
        XCTAssertTrue(early == nil || abs(early! - lands) < 0.01, "La partie suit le chemin prévu sous le ciel enregistré.")
        game.tick(now: start.addingTimeInterval(wait + 2))
        XCTAssertNil(game.forecast().landsAt, "À l'heure annoncée, le héros est arrivé.")
    }

    // MARK: Classes de héros

    func testHeroClassScalesMaxHP() {
        let warrior = makeGame()
        warrior.chooseHero(.warrior)
        XCTAssertEqual(warrior.maxHP, 130, "Le Guerrier a +30 % de PV.")

        let archer = makeGame()
        archer.chooseHero(.archer)
        XCTAssertEqual(archer.maxHP, 110, "L'Archer a un léger +10 % de PV.")

        let mage = makeGame()
        mage.chooseHero(.mage)
        XCTAssertEqual(mage.maxHP, 95, "Le Mage a -5 % de PV.")
    }

    func testMageHitsHarderThanWarrior() {
        let warrior = makeGame(); warrior.chooseHero(.warrior)
        let mage = makeGame(); mage.chooseHero(.mage)
        XCTAssertGreaterThan(mage.attack, warrior.attack, "Le Mage frappe plus fort.")
        XCTAssertGreaterThan(warrior.attack, 0)
    }

    func testArcherIsFasterAndLuckier() {
        let warrior = makeGame(); warrior.chooseHero(.warrior)
        let archer = makeGame(); archer.chooseHero(.archer)
        XCTAssertEqual(archer.speedBonus, 0.25, accuracy: 0.0001)
        XCTAssertEqual(warrior.speedBonus, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(archer.luck, warrior.luck)
    }

    func testChoosingHeroStartsAtFullHP() {
        let game = makeGame()
        XCTAssertNil(game.heroClass)
        game.chooseHero(.warrior)
        XCTAssertEqual(game.heroClass, .warrior)
        XCTAssertEqual(game.hp, game.maxHP)
        XCTAssertFalse(game.isRecovering, "Un héros tout neuf est au maximum.")
        XCTAssertEqual(game.name, HeroClass.warrior.defaultName)
    }

    // MARK: Soins et provisions

    func testFeedingConsumesARationAndFillsHunger() {
        let game = makeGame(); game.chooseHero(.warrior)
        XCTAssertEqual(game.count(.ration), 2)
        XCTAssertTrue(game.canFeed)

        game.feed()

        XCTAssertEqual(game.count(.ration), 1, "Une ration a été consommée.")
        XCTAssertEqual(game.hunger, 100, "La satiété grimpe (et se plafonne à 100).")
    }

    func testCannotDrinkWaterWithoutAny() {
        let game = makeGame(); game.chooseHero(.warrior)
        XCTAssertEqual(game.count(.water), 0)
        XCTAssertFalse(game.canUse(.water))
        XCTAssertTrue(game.canUse(.ration))
    }

    func testCannotCareWhileTraveling() {
        let game = makeGame(); game.chooseHero(.warrior)
        XCTAssertTrue(game.canFeed, "On nourrit au camp.")

        game.travel(to: .dungeon(0))

        XCTAssertNil(game.currentPlace, "En chemin, le héros n'est plus à un lieu.")
        XCTAssertFalse(game.canFeed, "On ne nourrit pas un héros en déplacement.")
    }

    // MARK: Donjons

    func testOnlyFirstDungeonIsUnlockedAtStart() {
        let game = makeGame(); game.chooseHero(.warrior)
        XCTAssertTrue(game.isUnlocked(Dungeon.all[0]))
        XCTAssertFalse(game.isUnlocked(Dungeon.all[1]))
        XCTAssertFalse(game.isUnlocked(Dungeon.all[4]))
    }

    func testRankBoundsAndMaxRank() {
        let game = makeGame(); game.chooseHero(.warrior)
        XCTAssertEqual(game.highestRank(Dungeon.all[0]), 1, "Sans exploit, seul le rang 1 est ouvert.")
        XCTAssertEqual(Dungeon.all[0].maxRank, 5)
        XCTAssertEqual(Dungeon.all[4].maxRank, 999, "Le Volcan n'a pas de plafond.")
    }

    func testChosenRankIsClampedToWhatIsUnlocked() {
        let game = makeGame(); game.chooseHero(.warrior)
        let cave = Dungeon.all[0]
        game.chooseRank(3, for: cave)
        XCTAssertEqual(game.chosenRank(cave), 1, "Un rang trop haut est ramené au plus haut ouvert.")
        game.chooseRank(-5, for: cave)
        XCTAssertEqual(game.chosenRank(cave), 1, "Un rang négatif est ramené à 1.")
    }

    func testEntryBlockerLetsAHealthyHeroIn() {
        let game = makeGame(); game.chooseHero(.warrior)
        XCTAssertNil(game.entryBlocker(Dungeon.all[0]), "Reposé et en forme, le héros peut entrer.")
    }

    // MARK: Déplacements

    func testTravelTimeIsDistanceDividedBySpeed() {
        let warrior = makeGame(); warrior.chooseHero(.warrior)
        XCTAssertEqual(warrior.travelTime(from: .camp, to: .shop), 45, accuracy: 0.001)
        XCTAssertEqual(warrior.travelTime(from: .camp, to: .tavern), 50, accuracy: 0.001)

        let archer = makeGame(); archer.chooseHero(.archer)
        XCTAssertEqual(archer.travelTime(from: .camp, to: .shop), 36, accuracy: 0.001,
                       "L'Archer, +25 % de vitesse, marche plus vite : 45 / 1,25.")
    }

    // MARK: Besoins vitaux dans le temps

    func testNeedsDecayOverTime() {
        let game = makeGame(); game.chooseHero(.warrior)
        let start = Date()
        game.tick(now: start)                               // cale l'horloge
        game.tick(now: start.addingTimeInterval(3_600))     // une heure plus tard

        XCTAssertEqual(game.hunger, 73.75, accuracy: 1.0, "La satiété se vide en 16 h.")
        XCTAssertEqual(game.thirst, 70, accuracy: 1.0, "L'hydratation se vide en 10 h.")
        XCTAssertLessThan(game.thirst, game.hunger, "La soif baisse plus vite que la faim.")
    }

    func testAbandonedHeroDiesAndLineageContinues() {
        let game = makeGame(gold: 1_000); game.chooseHero(.warrior)
        XCTAssertEqual(game.generation, 1)

        let start = Date()
        game.tick(now: start)
        game.tick(now: start.addingTimeInterval(500_000))   // des jours sans soins

        XCTAssertNil(game.heroClass, "Oublié, le héros finit par mourir.")
        XCTAssertEqual(game.generation, 2, "Un successeur reprend le flambeau.")
        XCTAssertEqual(game.gold, 250, "Il hérite d'un quart de l'or (25 % de 1000).")
    }

    // MARK: Sauvegarde

    func testStateSurvivesReload() {
        let first = makeGame(gold: 500)
        first.chooseHero(.archer)
        first.rename("Lara")
        // chooseHero et rename sauvegardent déjà dans UserDefaults.

        // On relance sans les crochets de debug : la sauvegarde doit être relue telle quelle.
        for key in ["debugReset", "debugGold", "debugTimeScale", "debugHero"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let second = GameState()

        XCTAssertEqual(second.heroClass, .archer)
        XCTAssertEqual(second.name, "Lara")
        XCTAssertEqual(second.gold, 500)
    }

    func testResetClearsEverything() {
        let game = makeGame(gold: 1_000); game.chooseHero(.mage)
        game.reset()
        XCTAssertNil(game.heroClass)
        XCTAssertEqual(game.gold, 0)
        XCTAssertEqual(game.level, 1)
        XCTAssertEqual(game.generation, 1)
    }

    // MARK: Chances d'un donjon

    func testOddsStayWithinBounds() {
        let game = makeGame(); game.chooseHero(.warrior)
        let cave = Dungeon.all[0]
        let success = game.successChance(of: cave, rank: 1)
        let death = game.deathChance(of: cave, rank: 1)
        XCTAssertTrue((0...1).contains(success), "Une probabilité reste entre 0 et 1.")
        XCTAssertTrue((0...1).contains(death))
        XCTAssertGreaterThan(success, 0.5, "La Cave au rang 1 reste abordable pour un héros neuf.")
    }

    // MARK: Heure et météo

    func testAmbientDependsOnlyOnTheDate() {
        let noon = Ambient.date(day: 9_500, hour: 12), deepNight = Ambient.date(day: 9_500, hour: 3)
        XCTAssertFalse(Ambient.isNight(noon), "À midi, il fait jour.")
        XCTAssertTrue(Ambient.isNight(deepNight), "À 3 h, il fait nuit.")
        XCTAssertEqual(Ambient.at(noon), Ambient.at(noon), "Même date, même temps : la prévision reste exacte.")
        XCTAssertEqual(Ambient.weather(at: noon), Ambient.weather(at: noon.addingTimeInterval(1_800)),
                       "Le temps tient trois heures.")
        let wait = Ambient.untilNextHour(noon.addingTimeInterval(600))
        XCTAssertEqual(wait, 3_000, accuracy: 0.01, "La prochaine heure pile est dans 50 minutes.")
        XCTAssertEqual(Ambient.untilNextHour(noon), 3_600, accuracy: 0.01, "À l'heure pile, on vise la suivante.")
    }

    func testWeatherSlowsTravelAndRest() {
        let clear = makeGame(); clear.chooseHero(.warrior)
        XCTAssertEqual(clear.travelTime(from: .camp, to: .shop), 45, accuracy: 0.001)
        // Le temps figé est partagé par toutes les parties : on relève la valeur avant d'en changer.
        let clearEscape = clear.escapeChance()
        let storm = makeGame(weather: "storm"); storm.chooseHero(.warrior)
        XCTAssertEqual(storm.travelTime(from: .camp, to: .shop), 45 * 1.25, accuracy: 0.001,
                       "Sous l'orage, les trajets durent un quart de plus.")
        let fog = makeGame(weather: "fog"); fog.chooseHero(.warrior)
        XCTAssertEqual(fog.escapeChance() - clearEscape, 0.10, accuracy: 0.001,
                       "Dans la brume, on fuit plus facilement.")
    }

    func testRainSlowsThirst() {
        let game = makeGame(weather: "rain"); game.chooseHero(.warrior)
        let start = Date()
        game.tick(now: start)
        game.tick(now: start.addingTimeInterval(3_600))
        XCTAssertEqual(game.thirst, 73, accuracy: 1.0, "Sous la pluie, la soif vient 30 % moins vite.")
    }

    func testNightMakesDungeonsDeadlier() {
        let day = makeGame(); day.chooseHero(.mage)
        let night = makeGame(night: true); night.chooseHero(.mage)
        let crypt = Dungeon.all[2]
        XCTAssertLessThanOrEqual(night.successChance(of: crypt, rank: 1), day.successChance(of: crypt, rank: 1),
                                 "La nuit, les monstres frappent plus fort.")
    }

    // MARK: Prévision

    /// La prévision rejoue la sortie sur une copie : avec l'heure et la météo réelles (nuits, pluie,
    /// brume traversées en route), la vraie partie doit arriver au même instant avec le même butin.
    func testForecastMatchesRealityThroughNightsAndWeather() {
        for (index, hero) in HeroClass.allCases.enumerated() {
            let game = makeGame(weather: nil, night: nil); game.chooseHero(hero)
            let start = Date().addingTimeInterval(Double(index) * 5 * 3_600)   // des heures de départ variées
            game.tick(now: start)
            let goldBefore = game.gold
            game.travel(to: .dungeon(0))
            let ahead = game.forecast()
            guard let lands = ahead.landsAt else { return XCTFail("La prévision devrait donner une arrivée.") }

            // Un seul grand saut, comme au retour d'une longue absence : rien n'est joué en direct.
            game.tick(now: start.addingTimeInterval(lands - game.clock + 1))
            // La prévision regarde quatre jours devant : une mort de soif bien après le retour ne compte pas ici.
            if let death = ahead.diesAt, !ahead.starved {
                game.tick(now: start.addingTimeInterval(death - game.clock + 1))
                XCTAssertNil(game.heroClass, "\(hero) : la mort prévue à \(death) doit arriver.")
            } else {
                XCTAssertEqual(game.currentPlace, .camp, "\(hero) : il doit être rentré à l'heure prévue.")
                XCTAssertEqual(game.gold - goldBefore, ahead.gold, accuracy: 0.001, "\(hero) : même butin que prévu.")
            }
        }
    }

    /// Les longs donjons (jusqu'au Volcan, plus d'une journée) traversent nuits, météo, carrefours et
    /// reliques de boss : la prévision doit toujours tomber juste, que le héros gagne, fuie ou meure.
    func testForecastMatchesRealityInDeepDungeons() {
        for dungeon in Dungeon.all.dropFirst() {
            for (hero, level) in [(HeroClass.warrior, 12 * dungeon.tier), (.mage, 6 * dungeon.tier)] {
                let game = makeGame(weather: nil, night: nil, level: level, unlock: true); game.chooseHero(hero)
                let start = Date()
                game.tick(now: start)
                let goldBefore = game.gold, lineage = game.generation
                game.travel(to: .dungeon(dungeon.id))
                guard case .traveling = game.activity else { XCTFail("\(dungeon.name) : départ refusé."); continue }
                let ahead = game.forecast()
                let label = "\(dungeon.name), \(hero) niveau \(level)"
                // Une mort prévue pendant la sortie : au combat, ou de soif sur le chemin du retour
                // (sorti du donjon à bout de forces, il ne rentre jamais). Morte de faim au camp
                // des jours plus tard, elle n'empêche pas de vérifier le retour.
                if let death = ahead.diesAt, !ahead.starved || ahead.diesOnTheWay {
                    game.tick(now: start.addingTimeInterval(death - game.clock + 1))
                    XCTAssertEqual(game.generation, lineage + 1, "\(label) : la mort prévue doit arriver.")
                    XCTAssertEqual(game.graves.count, 1, "\(label) : sa tombe rejoint le cimetière.")
                } else if let lands = ahead.landsAt {
                    game.tick(now: start.addingTimeInterval(lands - game.clock + 1))
                    XCTAssertEqual(game.generation, lineage, "\(label) : il ne devait pas mourir.")
                    XCTAssertEqual(game.currentPlace, .camp, "\(label) : rentré à l'heure prévue.")
                    XCTAssertEqual(game.gold - goldBefore, ahead.gold, accuracy: 0.001, "\(label) : même butin que prévu.")
                } else {
                    XCTFail("\(label) : ni arrivée ni mort prévue.")
                }
            }
        }
    }

    /// L'alerte « il dépérit » tombe au bon moment même si la pluie, qui ralentit la soif, va et vient.
    func testStarvationForecastFollowsTheWeather() {
        let game = makeGame(weather: nil, night: nil); game.chooseHero(.warrior)
        let start = Date()
        game.tick(now: start)
        guard let starves = game.forecast().starvesAt else { return XCTFail("Un héros oublié finit par dépérir.") }
        let left = starves - game.clock
        XCTAssertGreaterThan(left, 3_600 * 6, "Parti à 80 d'hydratation, il tient plusieurs heures.")
        game.tick(now: start.addingTimeInterval(left - 60))
        XCTAssertFalse(game.isStarving, "Une minute avant, il tient encore.")
        game.tick(now: start.addingTimeInterval(left + 60))
        XCTAssertTrue(game.isStarving, "Une minute après, il dépérit.")
    }

    /// Le premier boss vaincu d'un donjon laisse une relique, et elle se retrouve après rechargement.
    func testFirstBossGivesARelic() {
        let game = makeGame(level: 30); game.chooseHero(.warrior)
        let start = Date()
        game.tick(now: start)
        game.travel(to: .dungeon(0))
        guard let lands = game.forecast().landsAt else { return XCTFail("Pas d'arrivée prévue.") }
        game.tick(now: start.addingTimeInterval(lands - game.clock + 1))
        XCTAssertEqual(game.bestRanks[0], 1, "Un héros de niveau 30 termine la Cave.")
        XCTAssertEqual(game.relics.count, 1, "Le premier boss de la Cave garde une relique.")
    }

    /// Le repos prévu heure par heure (nuit plus rapide, pluie plus lente) tombe juste.
    func testRestForecastFollowsNightAndWeather() {
        let game = makeGame(weather: nil, night: nil); game.chooseHero(.warrior)
        let start = Date()
        game.tick(now: start)
        game.travel(to: .dungeon(0))
        guard let lands = game.forecast().landsAt else { return XCTFail("Pas d'arrivée prévue.") }
        let home = start.addingTimeInterval(lands - game.clock + 1)
        game.tick(now: home)
        guard game.heroClass != nil, game.isRecovering else { return }   // mort ou déjà en forme : rien à vérifier
        // Nourri et abreuvé, pour que seul le repos compte.
        game.use(.ration); game.use(.water)
        guard let rested = game.forecast().restedAt else { return XCTFail("Le repos devrait avoir une fin prévue.") }
        let left = rested - game.clock
        game.tick(now: home.addingTimeInterval(left - 60))
        XCTAssertTrue(game.isRecovering, "Une minute avant l'heure prévue, il récupère encore.")
        game.tick(now: home.addingTimeInterval(left + 60))
        XCTAssertFalse(game.isRecovering, "Une minute après, il est reposé.")
    }

    func testNightSpeedsUpRestAndRainSlowsIt() {
        func restTime(weather: String, seed: Int, relic: String? = nil) -> TimeInterval? {
            let game = makeGame(weather: weather, night: false, relic: relic, seed: seed); game.chooseHero(.warrior)
            let start = Date()
            game.tick(now: start)
            game.travel(to: .dungeon(0))
            guard let lands = game.forecast().landsAt else { return nil }
            game.tick(now: start.addingTimeInterval(lands - game.clock + 1))
            // Le boss de la Cave laisse une relique au hasard : si c'est la braise éternelle, la pluie
            // ne compte plus et la comparaison n'a pas de sens. On passe à une autre sortie.
            if relic == nil, game.relics.contains(.ember) { return nil }
            guard game.heroClass != nil, let rested = game.forecast().restedAt else { return nil }
            return (rested - game.clock) / max(game.maxHP - game.hp, GameState.maxEnergy - game.energy, 1)
        }
        // Même graine, donc même sortie et même fatigue au retour : seule la vitesse du repos change.
        // On prend la première sortie d'où le héros rentre fatigué, sans la braise.
        for seed in 1...40 {
            guard let day = restTime(weather: "clear", seed: seed),
                  let rain = restTime(weather: "rain", seed: seed) else { continue }
            XCTAssertGreaterThan(rain, day, "Sous la pluie, le feu faiblit.")
            if let ember = restTime(weather: "rain", seed: seed, relic: "ember") {
                XCTAssertLessThan(ember, rain, "La braise éternelle protège le feu de la pluie.")
            }
            return
        }
        XCTFail("Aucune sortie comparable sur 40 graines.")
    }

    func testSaveRoundTripKeepsRelicsAndAnsweredVisits() {
        let first = makeGame(gold: 500, visitor: "merchant"); first.chooseHero(.archer)
        guard let visit = first.visitor else { return XCTFail("Le marchand devrait être là.") }
        first.answerVisit(visit, option: 0)   // achète sa relique
        XCTAssertEqual(first.relics.count, 1)
        XCTAssertEqual(first.gold, 250)
        for key in ["debugReset", "debugGold", "debugTimeScale", "debugHero", "debugVisitor"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let second = GameState()
        XCTAssertEqual(second.relics, first.relics)
        XCTAssertEqual(second.answeredVisits, first.answeredVisits)
        XCTAssertEqual(second.gold, 250)
    }

    func testEveryVisitorOffersUsableChoices() {
        for kind in VisitorKind.allCases {
            let game = makeGame(gold: 10_000, visitor: kind.rawValue); game.chooseHero(.warrior)
            guard let visit = game.visitor else { XCTFail("\(kind) devrait être au camp."); continue }
            let options = game.visitOptions(visit)
            XCTAssertEqual(options.count, 3, "\(kind) : trois réponses.")
            XCTAssertEqual(Set(options.map(\.id)).count, 3)
            // La dernière réponse (refuser, saluer, écouter) est toujours possible.
            XCTAssertNil(options.last?.blocker, "\(kind) : on peut toujours décliner.")
            for option in options where option.blocker == nil {
                let trial = makeGame(gold: 10_000, visitor: kind.rawValue); trial.chooseHero(.warrior)
                guard let again = trial.visitor else { continue }
                trial.answerVisit(again, option: option.id)
                XCTAssertNotNil(trial.visitOutcome, "\(kind), réponse \(option.id) : un résultat s'affiche.")
                XCTAssertFalse(trial.visitOutcome?.text.isEmpty ?? true)
                XCTAssertGreaterThanOrEqual(trial.gold, 0)
                XCTAssertLessThanOrEqual(trial.hp, trial.maxHP)
            }
        }
    }

    func testEveryRelicKeepsStatsSane() {
        for relic in Relic.allCases {
            let game = makeGame(relic: relic.rawValue); game.chooseHero(.mage)
            XCTAssertTrue(game.has(relic))
            XCTAssertGreaterThan(game.attack, 0)
            XCTAssertGreaterThan(game.maxHP, 0)
            XCTAssertLessThanOrEqual(game.hp, game.maxHP)
            XCTAssertTrue((0.05...0.97).contains(game.escapeChance()))
            XCTAssertGreaterThan(game.travelTime(from: .camp, to: .shop), 0)
            let odds = game.successChance(of: Dungeon.all[0], rank: 1)
            XCTAssertTrue((0...1).contains(odds), "\(relic) : chances valides.")
        }
    }

    func testInheritedTraitAppliesFromDayOne() {
        let game = makeGame(gold: 400, feats: true); game.chooseHero(.warrior)
        XCTAssertEqual(Set(game.traits), Set(Trait.allCases))
        UserDefaults.standard.removeObject(forKey: "debugFeats")
        game.chooseHero(.mage)
        XCTAssertTrue(game.traits.isEmpty, "Le successeur repart sans caractère.")
        XCTAssertEqual(game.graves.first?.traits.count, 4, "La tombe garde les traits du défunt.")
        XCTAssertTrue(game.pendingLegacy?.options.contains(.trait(.careful)) ?? false)

        game.chooseLegacy(.trait(.careful))
        XCTAssertEqual(game.traits, [.careful])
        XCTAssertEqual(game.fleeLimit, 0.35, accuracy: 0.001, "Prudent : il se replie plus tôt.")
        XCTAssertEqual(game.gold, 100, "Choisir un trait, c'est renoncer à la bourse.")

        // Le trait hérité survit à un rechargement.
        for key in ["debugReset", "debugGold", "debugTimeScale", "debugHero"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        XCTAssertEqual(GameState().traits, [.careful])
    }

    func testTraitLegacyIsInherited() {
        // Trois fuites donnent le trait Prudent ; on le simule par une lignée : pas d'accès direct aux
        // compteurs, donc on vérifie au moins que le legs d'un trait inconnu est refusé.
        let game = makeGame(gold: 400); game.chooseHero(.warrior)
        game.chooseHero(.mage)
        game.chooseLegacy(.trait(.brave))   // pas dans l'offre : ignoré
        XCTAssertNotNil(game.pendingLegacy, "Un legs qui n'est pas proposé ne se choisit pas.")
        XCTAssertTrue(game.traits.isEmpty)
    }

    // MARK: Économie

    func testLootResellsForAThirdOfItsValue() {
        var generator = SeededGenerator(state: 7)
        let item = Item.random(tier: 3, rank: 2, hero: .warrior, using: &generator)
        XCTAssertEqual(item.resaleValue, (item.sellValue * Item.resaleShare).rounded(.up))
        XCTAssertLessThan(item.resaleValue, item.sellValue, "Le marchand ne rend qu'une part de la valeur.")
        XCTAssertGreaterThan(item.forgePrice, item.resaleValue * 9, "La forge reste indexée sur la valeur pleine.")
    }

    func testGoldGrowsSlowerThanMonstersWithRank() {
        XCTAssertEqual(Dungeon.goldRankScale(1), 1)
        XCTAssertLessThan(Dungeon.goldRankScale(5), Dungeon.rankScale(5), "Au rang 5, l'or suit moins vite que le danger.")
    }

    func testPricesFollowTheShopTier() {
        let game = makeGame(); game.chooseHero(.warrior)
        XCTAssertEqual(game.price(of: .potion), 45)
        XCTAssertEqual(game.price(of: .ration), 25)
        XCTAssertEqual(game.questReward, 25)
        let far = makeGame(unlock: true); far.chooseHero(.warrior)
        XCTAssertEqual(far.price(of: .potion), 45 * 27, "Au quatrième palier, les prix sont multipliés par 27.")
    }

    // MARK: Reliques

    func testRelicGivesItsBoonAndItsBane() {
        let plain = makeGame(); plain.chooseHero(.warrior)
        let glass = makeGame(relic: "glassBlade"); glass.chooseHero(.warrior)
        XCTAssertTrue(glass.has(.glassBlade))
        XCTAssertEqual(glass.attack, (plain.attack * Relic.glassAttack).rounded(), "+20 % d'attaque.")
        XCTAssertEqual(glass.maxHP, (plain.maxHP * Relic.glassHP).rounded(), "-10 % de PV max.")
        XCTAssertLessThanOrEqual(glass.hp, glass.maxHP)
    }

    func testMoonCharmFollowsTheHour() {
        let day = makeGame(relic: "moonCharm"); day.chooseHero(.warrior)
        let dayAttack = day.attack
        let night = makeGame(night: true, relic: "moonCharm"); night.chooseHero(.warrior)
        XCTAssertGreaterThan(night.attack, dayAttack, "L'amulette de lune frappe plus fort la nuit.")
    }

    // MARK: Cimetière et héritage

    func testDeathLeavesAGraveAndALegacyToChoose() {
        let game = makeGame(gold: 1_000, relic: "ember"); game.chooseHero(.warrior)
        game.rename("Bjorn")
        game.chooseHero(.mage)   // abandon : mort définitive

        XCTAssertEqual(game.graves.count, 1)
        XCTAssertEqual(game.graves.first?.name, "Bjorn")
        XCTAssertEqual(game.graves.first?.heroClass, .warrior)
        XCTAssertEqual(game.graves.first?.relics, [.ember])
        XCTAssertTrue(game.relics.isEmpty, "Les reliques reposent avec lui, sauf celle qu'on choisit.")
        XCTAssertEqual(game.gold, 250)
        XCTAssertEqual(game.pendingLegacy?.options, [.relic(.ember), .purse(250)])

        game.chooseLegacy(.relic(.ember))
        XCTAssertTrue(game.has(.ember), "La relique léguée passe au successeur.")
        XCTAssertNil(game.pendingLegacy, "Un seul legs.")
        XCTAssertEqual(game.gold, 250, "Choisir la relique, c'est renoncer à la bourse.")
        XCTAssertEqual(game.graves.first?.legacy, Relic.ember.name)
    }

    func testPurseLegacyDoublesTheInheritance() {
        let game = makeGame(gold: 1_000); game.chooseHero(.warrior)
        game.chooseHero(.archer)
        game.chooseLegacy(.purse(250))
        XCTAssertEqual(game.gold, 500)
    }

    func testGraveyardSurvivesReload() {
        let first = makeGame(gold: 400); first.chooseHero(.warrior)
        first.chooseHero(.mage)
        for key in ["debugReset", "debugGold", "debugTimeScale", "debugHero"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let second = GameState()
        XCTAssertEqual(second.graves.count, 1)
        XCTAssertEqual(second.pendingLegacy?.purse, 100)
    }

    // MARK: Visiteurs du camp

    func testVisitsAreTheSameForAGivenDay() {
        let visits = CampVisit.visits(onDay: 9_500)
        XCTAssertEqual(visits.count, 2)
        XCTAssertEqual(visits, CampVisit.visits(onDay: 9_500), "Tirées d'après la date seule.")
        for visit in visits {
            XCTAssertEqual(visit.end.timeIntervalSince(visit.start), CampVisit.stay * 3_600, accuracy: 0.01)
            XCTAssertEqual(CampVisit.current(at: visit.start.addingTimeInterval(60)), visit)
        }
        XCTAssertNil(CampVisit.current(at: Ambient.date(day: 9_500, hour: 2)), "Personne ne passe en pleine nuit.")
    }

    func testAnsweringAVisitorEndsTheVisit() {
        let game = makeGame(gold: 100, visitor: "pilgrim"); game.chooseHero(.warrior)
        guard let visit = game.visitor else { return XCTFail("Le pèlerin devrait être au camp.") }
        XCTAssertEqual(visit.kind, .pilgrim)
        let before = game.mood
        game.answerVisit(visit, option: 2)   // écouter ses récits
        XCTAssertEqual(game.mood, min(before + 12, 100), accuracy: 0.001)
        XCTAssertNotEqual(game.visitor?.id, visit.id, "Une seule réponse par visite.")
        XCTAssertNotNil(game.visitOutcome)
    }

    func testVisitorOfferingBlessesTheNextDungeon() {
        let game = makeGame(gold: 100, visitor: "pilgrim"); game.chooseHero(.warrior)
        guard let visit = game.visitor else { return XCTFail("Le pèlerin devrait être au camp.") }
        game.answerVisit(visit, option: 0)
        XCTAssertTrue(game.scrollReady)
        XCTAssertEqual(game.gold, 60, "L'offrande coûte 40 or au premier palier.")
    }

    func testNoVisitorWhileAway() {
        let game = makeGame(visitor: "merchant"); game.chooseHero(.warrior)
        XCTAssertNotNil(game.visitor)
        game.travel(to: .shop)
        XCTAssertNil(game.visitor, "Le visiteur ne trouve personne si le héros est parti.")
    }

    // MARK: Pièges

    /// La détection du tap : le curseur touche la zone verte quand sa position tombe dedans.
    func testTrapPromptHitDetection() {
        // Zone verte sur [0,4 ; 0,6] de la barre, balayée en 2 s.
        let prompt = TrapPrompt(start: Date(), sweep: 2, zoneStart: 0.4, zoneWidth: 0.2)
        // À 1,0 s le curseur est à mi-course (0,5) : en plein dans le vert.
        XCTAssertTrue(prompt.isHit(at: prompt.start.addingTimeInterval(1.0)), "Tap au centre du vert : réussi.")
        // À 0,4 s (0,2) : avant le vert.
        XCTAssertFalse(prompt.isHit(at: prompt.start.addingTimeInterval(0.4)), "Tap trop tôt : raté.")
        // À 1,8 s (0,9) : après le vert.
        XCTAssertFalse(prompt.isHit(at: prompt.start.addingTimeInterval(1.8)), "Tap trop tard : raté.")
    }
}
