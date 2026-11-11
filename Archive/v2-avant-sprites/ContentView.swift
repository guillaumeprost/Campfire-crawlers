import SpriteKit
import SwiftUI

struct ContentView: View {
    let game: GameState
    @State private var scene: WorldScene
    @State private var confirmReset = false
    @State private var tab: Tab = .map

    private enum Tab { case map, gear, journal }

    init(game: GameState) {
        self.game = game
        _scene = State(initialValue: WorldScene(game: game))
    }

    var body: some View {
        @Bindable var game = game

        VStack(spacing: 10) {
            header

            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            ActivityStrip(info: game.activityInfo)
            VitalsCard(game: game)
            tabSelector

            ScrollView {
                Group {
                    switch tab {
                    case .map: MapPanel(game: game)
                    case .gear: EquipmentPanel(game: game)
                    case .journal: JournalPanel(game: game)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Color(red: 0.06, green: 0.07, blue: 0.11).ignoresSafeArea())
        .onChange(of: tab) { _, newTab in
            if newTab == .gear { game.markLootSeen() }
        }
        .onChange(of: game.unseenLoot) { _, _ in
            if tab == .gear { game.markLootSeen() }
        }
        .sheet(item: $game.awayReport) { report in
            AwaySheet(report: report)
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                CoinIcon(size: 24)
                Text(game.gold.short)
                    .contentTransition(.numericText(value: game.gold))
                    .animation(.snappy(duration: 0.25), value: game.gold)
            }
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Or : \(game.gold.short)")

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Niveau \(game.level)")
                    .font(.subheadline.weight(.heavy))
                ProgressView(value: min(game.xp / game.xpNeeded, 1))
                    .tint(.cyan)
                    .frame(width: 90)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Niveau \(game.level), expérience \(Int(game.xp)) sur \(Int(game.xpNeeded))")

            Menu {
                Toggle("Mode test : temps ×\(Int(GameState.testTimeScale))", isOn: Binding(
                    get: { game.isTestSpeed },
                    set: { game.setTestSpeed($0) }
                ))
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
                Text("Votre or, votre niveau, vos donjons et votre équipement seront perdus.")
            }
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 6) {
            tabButton(.map, title: "Carte", icon: "map.fill", badge: 0)
            tabButton(.gear, title: "Équipement", icon: "shield.lefthalf.filled", badge: game.unseenLoot)
            tabButton(.journal, title: "Journal", icon: "book.fill", badge: 0)
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tabButton(_ target: Tab, title: String, icon: String, badge: Int) -> some View {
        let selected = tab == target
        return Button {
            tab = target
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
            .font(.footnote.weight(.bold))
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
}

/// Ce que fait le héros, avec l'avancement et le temps restant.
private struct ActivityStrip: View {
    let info: ActivityInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(info.title)
                    .font(.subheadline.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                if let eta = info.eta {
                    Text(eta.countdown)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.cyan)
                }
            }
            HStack(spacing: 8) {
                Text(info.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let progress = info.progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(.cyan)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Signes vitaux et caractéristiques du héros.
private struct VitalsCard: View {
    let game: GameState

    var body: some View {
        VStack(spacing: 6) {
            gauge(icon: "heart.fill", color: .red, label: "PV", value: game.shownHP, limit: game.maxHP)
            gauge(icon: "bolt.fill", color: .yellow, label: "Énergie", value: game.energy, limit: GameState.maxEnergy)
            HStack(spacing: 10) {
                stat("Attaque \(game.attack.short)")
                if game.speedBonus > 0 { stat("Vitesse +\(Int(game.speedBonus * 100))\u{00A0}%") }
                if game.luck > 0 { stat("Chance +\(Int(game.luck * 100))\u{00A0}%") }
                Spacer(minLength: 0)
                if game.scrollReady { PixelImage(name: "icon_scroll", size: 16) }
                if game.potions > 0 {
                    HStack(spacing: 2) {
                        PixelImage(name: "icon_potion", size: 16)
                        Text("×\(game.potions)")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(game.potions) potions")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stat(_ text: String) -> some View {
        Text(text).lineLimit(1).minimumScaleFactor(0.8)
    }

    private func gauge(icon: String, color: Color, label: String, value: Double, limit: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)
            ProgressView(value: min(max(value / limit, 0), 1))
                .tint(color)
            Text("\(Int(value)) / \(Int(limit))")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .frame(minWidth: 74, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) : \(Int(value)) sur \(Int(limit))")
    }
}

/// Journal de l'aventure, du plus récent au plus ancien.
private struct JournalPanel: View {
    let game: GameState

    var body: some View {
        VStack(spacing: 6) {
            ForEach(game.journal.reversed()) { entry in
                JournalRow(entry: entry)
            }
        }
    }
}

struct JournalRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.icon)
                .font(.footnote)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(entry.text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var color: Color {
        switch entry.tone {
        case .good: .green
        case .bad: .red
        case .neutral: .secondary
        }
    }
}

/// Résumé de ce qui s'est passé pendant l'absence du joueur.
private struct AwaySheet: View {
    let report: AwayReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
            Text("Pendant votre absence")
                .font(.title3.weight(.heavy))
            Text("Absence de \(report.seconds.shortDuration)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                if report.gold > 0 {
                    HStack(spacing: 5) { CoinIcon(size: 16); Text("+\(report.gold.short)") }
                }
                if report.items > 0 { Label("+" + GameState.count(report.items, "objet"), systemImage: "sparkles") }
                if report.levels > 0 { Label("+\(report.levels) niveau\(report.levels > 1 ? "x" : "")", systemImage: "star.fill") }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.yellow)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(report.lines.reversed()) { entry in
                        JournalRow(entry: entry)
                    }
                }
            }

            Button {
                dismiss()
            } label: {
                Text("Continuer")
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

/// Image en pixel art, agrandie sans lissage pour garder des pixels nets.
struct PixelImage: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Image(name)
            .interpolation(.none)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Bouton de prix : vert quand on peut payer, grisé sinon.
struct PriceButton: View {
    let price: Double
    let enabled: Bool
    var blocker: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let blocker {
                    Text(blocker)
                        .font(.caption.weight(.bold))
                } else {
                    HStack(spacing: 5) {
                        CoinIcon(size: 14)
                        Text(price.short)
                    }
                    .font(.subheadline.weight(.heavy))
                    .monospacedDigit()
                }
            }
            .frame(minWidth: 76)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(enabled ? Color.green : Color.white.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(enabled ? Color.black : Color.white.opacity(0.45))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
