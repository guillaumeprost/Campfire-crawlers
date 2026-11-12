import SwiftUI

/// Premier onglet : il suit le héros. Au camp et à la boutique on choisit où l'envoyer ;
/// en route ou en donjon, on suit ce qui se passe et on peut seulement le rappeler.
struct MapPanel: View {
    let game: GameState

    /// Nom et icône de l'onglet selon l'endroit où se trouve le héros.
    static func tab(for activity: Activity) -> (title: String, icon: String) {
        switch activity {
        case .resting: ("Camp", "flame.fill")
        case .shopping: ("Boutique", "cart.fill")
        case .tavern: ("Taverne", "mug.fill")
        case .traveling: ("Trajet", "figure.walk")
        case .exploring: ("Donjon", "shield.lefthalf.filled")
        case .roaming: ("Balade", "figure.hiking")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch game.activity {
            case .resting:
                CareCard(game: game)
                RoamRow(game: game)
                CampUpgradeRow(game: game)

            case .shopping:
                ShopPanel(game: game)

            case .tavern(let visit):
                TavernCard(game: game, visit: visit)

            case .traveling(let trip):
                TripCard(game: game, trip: trip)

            case .exploring(let run):
                RunCard(game: game, run: run)

            case .roaming(let roam):
                RoamCard(game: game, roam: roam)
                PantryCard(game: game)
            }
        }
    }

}

/// Le menu « Destinations » : où envoyer le héros — le feu de camp, la boutique,
/// la taverne et les donjons. Toujours accessible ; chaque bouton se grise quand
/// le héros est déjà sur place (« Ici ») ou en déplacement (« Occupé »).
struct DestinationsPanel: View {
    let game: GameState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlaceRow(game: game, place: .camp, sprite: "camp_fire_1", title: "Feu de camp",
                     subtitle: "Les PV et l'énergie remontent avec le temps")
            PlaceRow(game: game, place: .shop, sprite: "shop_sign", title: "Boutique",
                     subtitle: "Équipement, potions et vente du butin")
            PlaceRow(game: game, place: .tavern, sprite: "mug.fill", title: "Taverne",
                     subtitle: "Une chope, un ragoût, le barde : son moral remonte")
            Text("Donjons")
                .font(.headline.weight(.heavy))
                .padding(.top, 4)
            ForEach(Dungeon.all) { dungeon in
                DungeonRow(game: game, dungeon: dungeon)
            }
        }
    }
}

/// En route : la destination et ce qui attend le héros à l'arrivée.
private struct TripCard: View {
    let game: GameState
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PixelImage(name: sprite, size: 40)
                    .frame(width: 54, height: 54)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(.subheadline.weight(.heavy))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if case .dungeon(let index) = trip.to {
                let dungeon = Dungeon.all[index]
                let rank = trip.rank ?? 1
                let chance = Int((game.successChance(of: dungeon, rank: rank) * 100).rounded())
                let risk = game.risk(of: dungeon, rank: rank)
                HStack(spacing: 8) {
                    Text("Rang \(rank)")
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
                    Text("\(risk.label) · \(chance)\u{00A0}%")
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(risk.color.opacity(0.22), in: Capsule())
                        .foregroundStyle(risk.color)
                    Spacer(minLength: 0)
                    Text("\(dungeon.rooms) salles · \((game.explorationTime(dungeon) / game.timeScale).shortDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Le héros ne peut pas changer de cap en chemin.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var sprite: String {
        switch trip.to {
        case .camp: "camp_fire_1"
        case .shop: "shop_sign"
        case .tavern: "mug.fill"
        case .dungeon(let index): Dungeon.all[index].boss.sprite
        }
    }

    private var headline: String {
        switch trip.to {
        case .camp: "Vers le feu de camp"
        case .shop: "Vers la boutique"
        case .tavern: "Vers la taverne"
        case .dungeon(let index): "Vers \(Dungeon.all[index].name)"
        }
    }

    private var detail: String {
        switch (trip.to, trip.reason) {
        case (.camp, .fled): "Blessé dans sa fuite, il a perdu sa sacoche. Le repos sera long."
        case (.camp, .victory): "Victorieux, il rapporte tout son butin."
        case (.camp, .exhausted): "À bout de forces, il rentre se reposer avec son butin."
        case (.camp, _): "Il rentre se reposer au coin du feu."
        case (.shop, _): "Le marchand l'attend pour acheter et vendre."
        case (.tavern, _): "Une chope et un bon feu l'attendent au village."
        case (.dungeon(let index), _): "Il entrera dans le donjon. Boss : \(Dungeon.all[index].boss.name)."
        }
    }
}

/// Au camp : le héros, son caractère, et les soins qu'on peut lui donner.
private struct CareCard: View {
    let game: GameState
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PixelImage(name: game.heroLook.portrait, size: 44)
                    .frame(width: 54, height: 54)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(game.name)
                            .font(.headline.weight(.heavy))
                        Button {
                            newName = game.name
                            renaming = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Renommer le héros")
                    }
                    Text(mood)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !game.traits.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(game.traits) { trait in
                        Label("\(trait.name) · \(trait.detail)", systemImage: trait.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            PantryButtons(game: game)
            Button {
                game.encourage()
            } label: {
                Label(cheerLabel, systemImage: "heart.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .actionGlass(game.canEncourage, tint: .pink)
            .disabled(!game.canEncourage)
            if Provision.allCases.allSatisfy({ game.count($0) == 0 }) {
                Text("Sac vide : partez en balade ou passez chez le marchand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .alert("Nom du héros", isPresented: $renaming) {
            TextField("Nom", text: $newName)
            Button("Valider") { game.rename(newName) }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var mood: String {
        if game.isStarving { return "Il dépérit et perd des PV d'heure en heure. Donnez-lui à manger et à boire, vite !" }
        return switch game.feeling {
        case .thirsty: "Il a soif : -15\u{00A0}% d'attaque et fuite plus difficile. Donnez-lui sa gourde."
        case .hungry: "Il a faim : -20\u{00A0}% d'attaque et fuite plus difficile. Donnez-lui à manger."
        case .sad: "Il a le cafard : encouragez-le ou emmenez-le à l'aventure."
        case .hurt: "Il soigne ses blessures."
        case .tired: "Il est fatigué et se repose."
        case .happy: "Il est de très bonne humeur : +6\u{00A0}% d'attaque."
        case .content: "Il est en forme."
        }
    }

    private var cheerLabel: String {
        let left = game.cheerCooldown / game.timeScale
        return left > 0 ? "Encourager · \(left.shortDuration)" : "Encourager"
    }
}

/// En donjon : l'avancée, l'or récolté, la sacoche, et le rappel au camp.
private struct RunCard: View {
    let game: GameState
    let run: Run

    var body: some View {
        let dungeon = Dungeon.all[run.dungeon]
        let loot = run.loot ?? []
        VStack(alignment: .leading, spacing: 10) {
            if let fork = run.fork {
                ForkCard(game: game, fork: fork, choice: run.forkChoice)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    PixelImage(name: dungeon.boss.sprite, size: 44)
                        .frame(width: 54, height: 54)
                        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(dungeon.name) · rang \(run.level)")
                            .font(.subheadline.weight(.heavy))
                        Text("Salle \(run.roomIndex + 1) sur \(dungeon.rooms) · boss : \(dungeon.boss.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    CoinIcon(size: 16)
                    Text("\(run.gold.short) or récolté")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if run.boosted {
                        PixelImage(name: "s_scroll", size: 16)
                        Text("Parchemin actif")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("Sacoche · \(GameState.count(loot.count, "objet"))")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
                if loot.isEmpty {
                    Text("Rien pour l'instant. Coffres et boss en remplissent la sacoche.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(loot) { item in
                                PixelImage(name: item.image(for: game.heroLook), size: 30)
                                    .frame(width: 46, height: 46)
                                    .background(item.rarity.color.opacity(0.18),
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(item.rarity.color, lineWidth: 1.5))
                                    .accessibilityLabel("\(item.title(for: game.heroLook)), \(item.bonusText)")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                if let blessings = run.blessings, !blessings.isEmpty {
                    Divider()
                    ForEach(blessings) { blessing in
                        Label("\(blessing.name) · \(blessing.detail)", systemImage: blessing.symbol)
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                Label("S'il doit fuir : \(Int((game.escapeChance() * 100).rounded()))\u{00A0}% de chances d'en réchapper, sacoche et moitié de l'or perdues. Sinon, la mort.",
                      systemImage: "skull.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))

            Button {
                game.recall()
            } label: {
                VStack(spacing: 2) {
                    Label("Rappeler le héros au camp", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.bold))
                    Text("Il rentre avec tout son butin")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(.orange)
        }
    }
}

/// Bouton de départ, avec la durée réelle du trajet.
private struct GoButton: View {
    let game: GameState
    let place: Place
    var blocker: String?

    var body: some View {
        let here = game.currentPlace
        let label: String = {
            if here == place { return "Ici" }
            if let blocker { return blocker }
            guard let here else { return "Occupé" }
            return (game.travelTime(from: here, to: place) / game.timeScale).shortDuration
        }()
        let enabled = here != nil && here != place && blocker == nil

        Button {
            game.travel(to: place)
        } label: {
            VStack(spacing: 1) {
                if enabled {
                    Text("Partir")
                        .font(.subheadline.weight(.heavy))
                }
                Text(label)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            .frame(minWidth: 64)
            .padding(.vertical, 2)
        }
        .actionGlass(enabled)
        .disabled(!enabled)
        .accessibilityLabel(enabled ? "Partir, trajet de \(label)" : label)
    }
}

private struct PlaceRow: View {
    let game: GameState
    let place: Place
    let sprite: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            PixelImage(name: sprite, size: 36)
                .frame(width: 48, height: 48)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            GoButton(game: game, place: place)
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

private struct DungeonRow: View {
    let game: GameState
    let dungeon: Dungeon

    var body: some View {
        let unlocked = game.isUnlocked(dungeon)
        let scale = game.timeScale

        HStack(spacing: 12) {
            PixelImage(name: dungeon.boss.sprite, size: 44)
                .frame(width: 48, height: 48)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(unlocked ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 4) {
                Text(dungeon.name)
                    .font(.subheadline.weight(.bold))
                if unlocked {
                    let rank = game.chosenRank(dungeon)
                    let chance = Int((game.successChance(of: dungeon, rank: rank) * 100).rounded())
                    let risk = game.risk(of: dungeon, rank: rank)
                    HStack(spacing: 3) {
                        Text("\((game.explorationTime(dungeon) / scale).shortDuration) · \(dungeon.rooms) salles ·")
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                        Text("\(Int(dungeon.energyCost))")
                            .accessibilityLabel("\(Int(dungeon.energyCost)) énergie")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    Text("\(risk.label) · \(chance)\u{00A0}%")
                        .font(.caption2.weight(.heavy))
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(risk.color.opacity(0.22), in: Capsule())
                        .foregroundStyle(risk.color)
                        .accessibilityLabel("\(risk.label), \(chance) pour cent de chances de réussite")
                    if let shortage = game.supplyShortage(for: dungeon) {
                        Label(shortage, systemImage: "takeoutbag.and.cup.and.straw.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    // Une fuite ratée tue : le joueur voit le risque avant de partir.
                    let death = Int((game.deathChance(of: dungeon, rank: rank) * 100).rounded())
                    if death > 0 {
                        Label("Mort \(death)\u{00A0}%", systemImage: "skull.fill")
                            .font(.caption2.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.red)
                            .accessibilityLabel("\(death) pour cent de risque de mourir")
                    }
                } else {
                    Label("Terminez \(Dungeon.all[dungeon.id - 1].name) au rang \(Dungeon.unlockRank)", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if unlocked {
                VStack(spacing: 6) {
                    GoButton(game: game, place: .dungeon(dungeon.id), blocker: game.entryBlocker(dungeon))
                    RankStepper(game: game, dungeon: dungeon, rank: game.chosenRank(dungeon))
                }
            }
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// Choix du rang : plus haut, les monstres sont plus forts et le butin meilleur.
private struct RankStepper: View {
    let game: GameState
    let dungeon: Dungeon
    let rank: Int

    var body: some View {
        let top = game.highestRank(dungeon)
        HStack(spacing: 0) {
            Button {
                game.chooseRank(rank - 1, for: dungeon)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 22, height: 24)
                    .contentShape(Rectangle())
            }
            .disabled(rank <= 1)
            .accessibilityLabel("Rang inférieur")

            Text("Rang \(rank)")
                .font(.caption2.weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()

            Button {
                game.chooseRank(rank + 1, for: dungeon)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 22, height: 24)
                    .contentShape(Rectangle())
            }
            .disabled(rank >= top)
            .accessibilityLabel("Rang supérieur")
        }
        .font(.caption2.weight(.bold))
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
    }
}

/// Au camp : améliorer le feu pour se reposer plus vite.
private struct CampUpgradeRow: View {
    let game: GameState

    var body: some View {
        HStack(spacing: 12) {
            PixelImage(name: "camp_fire_1", size: 36)
                .frame(width: 48, height: 48)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Feu de camp, niveau \(game.campLevel)")
                    .font(.subheadline.weight(.bold))
                Text(game.campUpgradePrice == nil
                     ? "Feu au maximum : repos \(Int((game.restBoost * 100).rounded()))\u{00A0}%"
                     : "Raviver le feu : repos 25\u{00A0}% plus rapide")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let price = game.campUpgradePrice {
                PriceButton(price: price, enabled: game.canUpgradeCamp()) {
                    game.upgradeCamp()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                .accessibilityLabel("Améliorer le feu de camp pour \(price.short) or")
            }
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// L'étal du marchand : provisions et équipement du moment.
private struct ShopPanel: View {
    let game: GameState
    /// Achats par ligne : chaque achat fait sauter l'icône de la ligne.
    @State private var hops: [String: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Provisions")
                .font(.headline.weight(.heavy))
            ForEach(Supply.allCases) { supply in
                HStack(spacing: 12) {
                    PixelImage(name: supply.sprite, size: 36)
                        .modifier(Hop(trigger: hops[supply.rawValue, default: 0]))
                        .frame(width: 48, height: 48)
                        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(supply.name)
                            .font(.subheadline.weight(.bold))
                        Text(supply.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    PriceButton(price: game.price(of: supply), enabled: game.canBuy(supply),
                                blocker: game.purchaseBlocker(supply)) {
                        game.buy(supply)
                        hops[supply.rawValue, default: 0] += 1
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    .accessibilityLabel("Acheter \(supply.name) pour \(game.price(of: supply).short) or")
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
            }

            Text("Équipement en vente")
                .font(.headline.weight(.heavy))
                .padding(.top, 4)
            if game.shopStock.isEmpty {
                Text("Tout est vendu. Le marchand aura du nouveau à votre prochain passage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(game.shopStock) { item in
                HStack(spacing: 12) {
                    PixelImage(name: item.image(for: game.heroLook), size: 34)
                        .frame(width: 48, height: 48)
                        .background(item.rarity.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(item.rarity.color, lineWidth: 1.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title(for: game.heroLook))
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        HStack(spacing: 5) {
                            Text(item.bonusText)
                            if game.isUpgrade(item) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Meilleur que l'objet porté")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    PriceButton(price: game.gearPrice(item), enabled: game.canBuyGear(item)) {
                        withAnimation(.spring(duration: 0.4)) { game.buyGear(item) }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    .accessibilityLabel("Acheter \(item.title(for: game.heroLook)) pour \(game.gearPrice(item).short) or")
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                // L'objet acheté quitte l'étal en grossissant, comme s'il sautait dans le sac.
                .transition(.asymmetric(insertion: .opacity,
                                        removal: .scale(scale: 1.15).combined(with: .opacity)))
            }
        }
    }
}


/// Carrefour : trois bénédictions, à choisir avant la fin de la salle.
private struct ForkCard: View {
    let game: GameState
    let fork: [Blessing]
    let choice: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Carrefour : choisissez une bénédiction", systemImage: "signpost.right.and.left.fill")
                .font(.subheadline.weight(.heavy))
            Text(choice == nil ? "Sans réponse avant la fin de la salle, \(game.name) choisira selon son caractère."
                               : "Choix noté : il prendra effet à la fin de la salle.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(fork.enumerated()), id: \.offset) { index, blessing in
                let picked = choice == index
                Button {
                    game.chooseBlessing(index)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: blessing.symbol)
                            .font(.title3)
                            .foregroundStyle(.yellow)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(blessing.name)
                                .font(.subheadline.weight(.bold))
                            Text(blessing.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if picked {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(picked ? 0.16 : 0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.yellow.opacity(0.12)), in: .rect(cornerRadius: 22))
    }
}


/// Les provisions du sac, à donner au héros d'une touche.
private struct PantryButtons: View {
    let game: GameState

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Provision.allCases) { provision in
                let usable = game.canUse(provision)
                Button {
                    game.use(provision)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: provision.symbol)
                            .font(.body.weight(.bold))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(provision.verb) · \(game.count(provision))")
                                .font(.caption.weight(.heavy))
                            Text(provision.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .opacity(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
                .actionGlass(usable, tint: tint(provision))
                .disabled(!usable)
                .accessibilityLabel("\(provision.verb) : \(provision.name), \(game.count(provision)) dans le sac. \(provision.detail)")
            }
        }
    }

    private func tint(_ provision: Provision) -> Color {
        switch provision {
        case .fruit: .green
        case .ration: .orange
        case .tea: .teal
        case .herbs: .red
        case .water: .cyan
        }
    }
}

/// Au camp : partir en balade, sans danger, pour ramasser des provisions.
private struct RoamRow: View {
    let game: GameState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "figure.hiking")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Itinérance")
                        .font(.subheadline.weight(.bold))
                    Text("Une balade sans danger dans les champs et les villages : fruits, tisanes, herbes et quelques pièces.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                ForEach(Roam.durations, id: \.self) { duration in
                    Button {
                        game.roam(for: duration)
                    } label: {
                        Text((duration / game.timeScale).shortDuration)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                    }
                    .actionGlass(game.canRoam)
                    .disabled(!game.canRoam)
                }
            }
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// En balade : les trouvailles, et le retour anticipé au camp.
private struct RoamCard: View {
    let game: GameState
    let roam: Roam

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Label("En balade dans la campagne", systemImage: "figure.hiking")
                    .font(.subheadline.weight(.heavy))
                Text("Aucun danger : \(game.name) ramasse ce qu'il trouve et revient de bonne humeur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                let finds = Provision.allCases.filter { (roam.found[$0.rawValue] ?? 0) > 0 }
                if finds.isEmpty && (roam.found["or"] ?? 0) == 0 {
                    Text("Rien pour l'instant : une trouvaille toutes les 5 minutes environ.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        ForEach(finds) { provision in
                            Label("\(Int(roam.found[provision.rawValue] ?? 0))", systemImage: provision.symbol)
                        }
                        if let coins = roam.found["or"], coins > 0 {
                            HStack(spacing: 4) { CoinIcon(size: 14); Text(coins.short) }
                        }
                    }
                    .font(.subheadline.weight(.bold))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))

            Button {
                game.recall()
            } label: {
                Label("Rentrer au camp", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
        }
    }
}

/// En balade aussi, on peut donner à manger ou à boire au héros.
private struct PantryCard: View {
    let game: GameState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sac de provisions")
                .font(.headline.weight(.heavy))
            PantryButtons(game: game)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// À la taverne : les commandes, servies contre de l'or.
private struct TavernCard: View {
    let game: GameState
    let visit: TavernVisit
    /// Commandes passées par ligne : chacune fait sauter l'icône.
    @State private var hops: [String: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "mug.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("La taverne")
                        .font(.subheadline.weight(.bold))
                    Text("Le moral monte tout seul près de l'âtre. Une commande l'aide encore plus.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            ForEach(TavernOrder.allCases) { order in
                Divider().padding(.leading, 48)
                row(order)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func row(_ order: TavernOrder) -> some View {
        let blocker = game.orderBlocker(order)
        return HStack(spacing: 12) {
            Image(systemName: order.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .modifier(Hop(trigger: hops[order.rawValue, default: 0]))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(order.name + (order == .ale ? " · \(visit.drinks)/\(TavernOrder.maxDrinks)" : ""))
                    .font(.subheadline.weight(.semibold))
                Text(blocker ?? order.detail)
                    .font(.caption)
                    .foregroundStyle(blocker == nil ? Color.secondary : Color.orange.opacity(0.85))
            }
            Spacer(minLength: 4)
            PriceButton(price: game.price(of: order), enabled: blocker == nil) {
                game.order(order)
                hops[order.rawValue, default: 0] += 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            .accessibilityLabel("Commander \(order.name) pour \(game.price(of: order).short) or")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
