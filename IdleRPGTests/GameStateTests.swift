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
                             "debugHero", "debugGo", "debugHeal", "debugSkill"]

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
    private func makeGame(gold: Double = 0, timeScale: Double = 1) -> GameState {
        let d = UserDefaults.standard
        for key in debugKeys { d.removeObject(forKey: key) }
        d.set(true, forKey: "debugReset")
        d.set(gold, forKey: "debugGold")
        d.set(timeScale, forKey: "debugTimeScale")
        return GameState()
    }

    // MARK: Classes de héros

    func testHeroClassScalesMaxHP() {
        let warrior = makeGame()
        warrior.chooseHero(.warrior)
        XCTAssertEqual(warrior.maxHP, 130, "Le Guerrier a +30 % de PV.")

        let archer = makeGame()
        archer.chooseHero(.archer)
        XCTAssertEqual(archer.maxHP, 100, "L'Archer a des PV de base.")

        let mage = makeGame()
        mage.chooseHero(.mage)
        XCTAssertEqual(mage.maxHP, 90, "Le Mage a -10 % de PV.")
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
}
