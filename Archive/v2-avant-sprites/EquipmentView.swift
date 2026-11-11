import SwiftUI

/// Onglet Équipement : les quatre emplacements du héros, puis le sac.
struct EquipmentPanel: View {
    let game: GameState
    @State private var selected: Item?
    @State private var confirmSellBag = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(ItemSlot.allCases) { slot in
                    SlotTile(slot: slot, item: game.equipped[slot]) {
                        selected = game.equipped[slot]
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Sac")
                    .font(.headline.weight(.heavy))
                Text("\(game.bag.count)/\(GameState.bagCapacity)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                if game.isShopping, !game.bag.isEmpty {
                    Button {
                        confirmSellBag = true
                    } label: {
                        HStack(spacing: 5) {
                            Text("Tout vendre")
                            CoinIcon(size: 13)
                            Text(game.bagSellValue.short)
                        }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Vendre tout le sac ?", isPresented: $confirmSellBag, titleVisibility: .visible) {
                        Button("Vendre \(game.bag.count) objets", role: .destructive) { game.sellBag() }
                        Button("Annuler", role: .cancel) {}
                    } message: {
                        Text("Les objets équipés sont conservés.")
                    }
                }
            }

            if game.bag.isEmpty {
                Text("Le sac est vide. Les monstres et les coffres donnent parfois un objet, les boss toujours.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                if !game.isShopping {
                    Text("Le butin se vend à la boutique.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(game.bag) { item in
                        Button {
                            selected = item
                        } label: {
                            ItemTile(item: item, isUpgrade: game.isUpgrade(item))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.name), \(item.rarity.name), \(item.bonusText)")
                    }
                }
            }
        }
        .sheet(item: $selected) { item in
            ItemDetailSheet(game: game, item: item)
                .presentationDetents([.height(420)])
        }
    }
}

/// Un emplacement d'équipement du héros.
private struct SlotTile: View {
    let slot: ItemSlot
    let item: Item?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill((item?.rarity.color ?? Color.white).opacity(item == nil ? 0.04 : 0.18))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(item?.rarity.color ?? Color.white.opacity(0.18),
                                      style: StrokeStyle(lineWidth: 1.5, dash: item == nil ? [5, 4] : []))
                    if let item {
                        PixelImage(name: item.sprite, size: 48)
                    } else {
                        Image(systemName: slot.placeholderIcon)
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
                .frame(height: 62)

                Text(slot.name)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(item?.shortBonus ?? "vide")
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(item == nil ? Color.white.opacity(0.3) : Color.white)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(item == nil)
        .accessibilityLabel(item.map { "\(slot.name) : \($0.name), \($0.bonusText)" } ?? "\(slot.name) : vide")
    }
}

/// Une case du sac.
private struct ItemTile: View {
    let item: Item
    let isUpgrade: Bool

    var body: some View {
        VStack(spacing: 2) {
            PixelImage(name: item.sprite, size: 32)
            Text(item.shortBonus)
                .font(.caption2.weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(item.rarity.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(item.rarity.color, lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
            if isUpgrade {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.black, .green)
                    .offset(x: 4, y: -4)
            }
        }
    }
}

/// Fiche d'un objet, avec comparaison et actions.
private struct ItemDetailSheet: View {
    let game: GameState
    let item: Item
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let current = game.equipped[item.slot]
        let isEquipped = current?.id == item.id

        VStack(spacing: 10) {
            PixelImage(name: item.sprite, size: 64)
                .frame(width: 92, height: 92)
                .background(item.rarity.color.opacity(0.2), in: Circle())
                .overlay(Circle().strokeBorder(item.rarity.color, lineWidth: 2))

            Text(item.name)
                .font(.title3.weight(.heavy))
                .multilineTextAlignment(.center)
            Text("\(item.rarity.name) · \(item.slot.name) · Palier \(item.tier)")
                .font(.caption.weight(.bold))
                .foregroundStyle(item.rarity.color)

            Text(item.bonusText)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .padding(.top, 2)

            comparison(current: current, isEquipped: isEquipped)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if !isEquipped, !game.isShopping {
                Text("Vente possible à la boutique")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !isEquipped {
                HStack(spacing: 10) {
                    Button {
                        game.sell(item)
                        dismiss()
                    } label: {
                        HStack(spacing: 5) {
                            Text("Vendre")
                            CoinIcon(size: 14)
                            Text(item.sellValue.short)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(!game.isShopping)

                    Button {
                        game.equip(item)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    } label: {
                        Text("Équiper")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func comparison(current: Item?, isEquipped: Bool) -> some View {
        if isEquipped {
            Label("Objet équipé", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        } else if let current {
            let delta = Int(item.bonus - current.bonus)
            let unit = item.slot.isPercent ? "\u{00A0}%" : ""
            VStack(spacing: 4) {
                Text("Équipé : \(current.name), \(current.shortBonus)")
                    .foregroundStyle(.secondary)
                if delta > 0 {
                    Label("\(delta)\(unit) de mieux", systemImage: "arrow.up")
                        .foregroundStyle(.green)
                } else if delta < 0 {
                    Label("\(-delta)\(unit) de moins", systemImage: "arrow.down")
                        .foregroundStyle(.red)
                } else {
                    Text("Bonus identique")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Emplacement vide")
                .foregroundStyle(.secondary)
        }
    }
}
