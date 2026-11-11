import SpriteKit
import SwiftUI

struct ContentView: View {
    let game: GameState
    @State private var scene: BattleScene
    @State private var confirmReset = false
    @State private var tab: Tab = .upgrades

    private enum Tab { case upgrades, equipment }

    init(game: GameState) {
        self.game = game
        _scene = State(initialValue: BattleScene(game: game))
    }

    var body: some View {
        @Bindable var game = game

        VStack(spacing: 12) {
            header

            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .bottom) {
                    Text("Touchez la scène pour frapper")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.35), in: Capsule())
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                }

            stageProgress
            tabSelector

            ScrollView {
                Group {
                    switch tab {
                    case .upgrades:
                        VStack(spacing: 10) {
                            ForEach(UpgradeKind.allCases) { kind in
                                UpgradeRow(game: game, kind: kind)
                            }
                        }
                    case .equipment:
                        EquipmentPanel(game: game)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .onChange(of: tab) { _, newTab in
            if newTab == .equipment { game.markLootSeen() }
        }
        .onChange(of: game.unseenLoot) { _, _ in
            if tab == .equipment { game.markLootSeen() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Color(red: 0.06, green: 0.07, blue: 0.11).ignoresSafeArea())
        .sheet(item: $game.offlineReport) { report in
            OfflineSheet(report: report)
                .presentationDetents([.height(360)])
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    CoinIcon(size: 28)
                    Text(game.gold.short)
                        .contentTransition(.numericText(value: game.gold))
                        .animation(.snappy(duration: 0.25), value: game.gold)
                }
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Or : \(game.gold.short)")

                Text("\(game.dps.shortRate) dégâts/s · \(game.goldPerSecond.shortRate) or/s")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Text("Monstres vaincus : \(game.totalKills)")
                Button("Recommencer la partie", systemImage: "arrow.counterclockwise", role: .destructive) {
                    confirmReset = true
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Menu")
            .confirmationDialog("Recommencer la partie ?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Tout effacer", role: .destructive) { game.reset() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Votre or, votre zone, vos améliorations et votre équipement seront perdus.")
            }
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 6) {
            tabButton(.upgrades, title: "Améliorations", icon: "arrow.up.circle.fill", badge: 0)
            tabButton(.equipment, title: "Équipement", icon: "shield.lefthalf.filled", badge: game.unseenLoot)
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tabButton(_ target: Tab, title: String, icon: String, badge: Int) -> some View {
        let selected = tab == target
        return Button {
            tab = target
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
            }
            .font(.subheadline.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(selected ? Color.white.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge) nouveaux objets" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var stageProgress: some View {
        HStack(spacing: 10) {
            Text("Zone \(game.stage)")
                .font(.headline.weight(.heavy))
            HStack(spacing: 4) {
                ForEach(0..<GameState.monstersPerStage, id: \.self) { index in
                    let isBossSlot = index == GameState.monstersPerStage - 1
                    Capsule()
                        .fill(index < game.killsInStage
                              ? Color.green
                              : (isBossSlot ? Color.purple.opacity(0.7) : Color.white.opacity(0.15)))
                        .frame(height: 8)
                }
            }
            Text(game.isBossFight ? "BOSS" : "\(game.killsInStage + 1)/\(GameState.monstersPerStage)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(game.isBossFight ? Color.purple : Color.secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}

private struct UpgradeRow: View {
    let game: GameState
    let kind: UpgradeKind

    var body: some View {
        let maxed = game.isMaxed(kind)
        let affordable = game.canBuy(kind)
        let effect = game.effect(of: kind)

        HStack(spacing: 12) {
            Image(systemName: kind.icon)
                .font(.title2)
                .foregroundStyle(.yellow)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(kind.name)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Niv. \(game.level(kind))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(maxed ? effect.current : "\(effect.current) → \(effect.next)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            Button {
                if game.buy(kind) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } label: {
                HStack(spacing: 5) {
                    if !maxed { CoinIcon(size: 14) }
                    Text(maxed ? "MAX" : game.cost(of: kind).short)
                }
                    .font(.subheadline.weight(.heavy))
                    .monospacedDigit()
                    .frame(minWidth: 76)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                    .background(affordable ? Color.green : Color.white.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(affordable ? Color.black : Color.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .disabled(!affordable)
            .accessibilityLabel(maxed ? "\(kind.name), niveau maximum" : "Améliorer \(kind.name) pour \(game.cost(of: kind).short) or")
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct OfflineSheet: View {
    let report: OfflineReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            Text("Bon retour !")
                .font(.title2.weight(.heavy))
            Text("Votre héros a combattu pendant \(report.seconds.readableDuration) en votre absence.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                CoinIcon(size: 28)
                Text("+\(report.gold.short)")
            }
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.yellow)
            Button {
                dismiss()
            } label: {
                Text("Récupérer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(24)
    }
}

/// Petite pièce d'or dessinée, utilisée partout où l'on affiche un montant.
struct CoinIcon: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(red: 1.0, green: 0.80, blue: 0.20))
            .overlay(Circle().strokeBorder(Color(red: 0.75, green: 0.50, blue: 0.05), lineWidth: max(size * 0.12, 1.5)))
            .overlay(Circle().fill(Color.white.opacity(0.45)).frame(width: size * 0.22).offset(x: -size * 0.16, y: -size * 0.16))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
