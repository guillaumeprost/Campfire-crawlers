import SwiftUI

/// Onglet Carte : où envoyer le héros. À la boutique, l'étal s'affiche en tête.
struct MapPanel: View {
    let game: GameState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if game.isShopping {
                ShopPanel(game: game)
                Text("Repartir")
                    .font(.headline.weight(.heavy))
                    .padding(.top, 4)
            }

            if game.isExploring {
                Button {
                    game.recall()
                } label: {
                    Label("Rappeler le héros au camp", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }

            PlaceRow(game: game, place: .camp, sprite: "campfire_1", title: "Feu de camp",
                     subtitle: "Les PV et l'énergie remontent avec le temps")
            PlaceRow(game: game, place: .shop, sprite: "icon_potion", title: "Boutique",
                     subtitle: "Équipement, potions et vente du butin")

            ForEach(Dungeon.all) { dungeon in
                DungeonRow(game: game, dungeon: dungeon)
            }
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
            .frame(minWidth: 76)
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(enabled ? Color.green : Color.white.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(enabled ? Color.black : Color.white.opacity(0.45))
        }
        .buttonStyle(.plain)
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
            PixelImage(name: sprite, size: 32)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DungeonRow: View {
    let game: GameState
    let dungeon: Dungeon

    var body: some View {
        let unlocked = game.isUnlocked(dungeon)
        let risk = game.risk(of: dungeon)
        let scale = game.timeScale

        HStack(spacing: 12) {
            PixelImage(name: dungeon.boss.sprite, size: 48)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(unlocked ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 3) {
                Text(dungeon.name)
                    .font(.subheadline.weight(.bold))
                if unlocked {
                    Text("Exploration \((dungeon.duration / scale).shortDuration) · \(dungeon.rooms) salles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(risk.label)
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(risk.color.opacity(0.22), in: Capsule())
                            .foregroundStyle(risk.color)
                        if game.clears[dungeon.id] > 0 {
                            Text("Terminé ×\(game.clears[dungeon.id])")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Label("Terminez \(Dungeon.all[dungeon.id - 1].name)", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if unlocked {
                GoButton(game: game, place: .dungeon(dungeon.id), blocker: game.entryBlocker(dungeon))
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// L'étal du marchand : provisions et équipement du moment.
private struct ShopPanel: View {
    let game: GameState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Provisions")
                .font(.headline.weight(.heavy))
            ForEach(Supply.allCases) { supply in
                HStack(spacing: 12) {
                    PixelImage(name: supply.sprite, size: 32)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    .accessibilityLabel("Acheter \(supply.name) pour \(game.price(of: supply).short) or")
                }
                .padding(10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    PixelImage(name: item.sprite, size: 32)
                        .frame(width: 48, height: 48)
                        .background(item.rarity.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(item.rarity.color, lineWidth: 1.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
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
                        game.buyGear(item)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    .accessibilityLabel("Acheter \(item.name) pour \(game.gearPrice(item).short) or")
                }
                .padding(10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}
