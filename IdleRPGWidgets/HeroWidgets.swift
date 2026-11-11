import SwiftUI
import UIKit
import WidgetKit

// MARK: - Chronologie

struct HeroEntry: TimelineEntry {
    let date: Date
    /// Nil : aucun héros choisi, ou le jeu n'a encore rien écrit.
    let frame: HeroWidgetData.Frame?
    let upcoming: [HeroWidgetData.Upcoming]
}

/// Lit les images du héros écrites d'avance par le jeu et en fait une chronologie.
struct HeroProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeroEntry {
        HeroEntry(date: .now, frame: HeroWidgetData.sample.frames.first, upcoming: HeroWidgetData.sample.upcoming)
    }

    func getSnapshot(in context: Context, completion: @escaping (HeroEntry) -> Void) {
        if context.isPreview, HeroWidgetData.load()?.frames.isEmpty ?? true {
            completion(placeholder(in: context))
        } else {
            completion(entries(from: .now).first ?? placeholder(in: context))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeroEntry>) -> Void) {
        completion(Timeline(entries: entries(from: .now), policy: .atEnd))
    }

    private func entries(from now: Date) -> [HeroEntry] {
        guard let data = HeroWidgetData.load(), let current = data.frame(at: now) else {
            return [HeroEntry(date: now, frame: nil, upcoming: [])]
        }
        func upcoming(after date: Date) -> [HeroWidgetData.Upcoming] {
            data.upcoming.filter { $0.date > date }
        }
        var entries = [HeroEntry(date: now, frame: current, upcoming: upcoming(after: now))]
        for frame in data.frames where frame.date > now {
            entries.append(HeroEntry(date: frame.date, frame: frame, upcoming: upcoming(after: frame.date)))
        }
        return entries
    }
}

// MARK: - Widgets

/// Le héros sur l'écran d'accueil, en trois tailles, et sur l'écran verrouillé.
struct HeroWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HeroWidget", provider: HeroProvider()) { entry in
            HeroWidgetView(entry: entry)
        }
        .configurationDisplayName("Le héros")
        .description("Où il est, ce qu'il fait, et comment il va.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Pensé pour le mode StandBy : le lieu du héros en grand, comme une fenêtre sur son aventure.
struct VigilWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VigilWidget", provider: HeroProvider()) { entry in
            VigilView(entry: entry)
        }
        .configurationDisplayName("Veillée")
        .description("Le héros dans son décor, à poser en mode StandBy près du lit.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        // En StandBy, garder le décor au lieu d'un fond noir.
        .containerBackgroundRemovable(false)
    }
}

private let night = Color(red: 0.06, green: 0.07, blue: 0.11)

struct HeroWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeroEntry

    var body: some View {
        Group {
            if let frame = entry.frame {
                switch family {
                case .systemSmall: SmallView(frame: frame)
                case .systemMedium: MediumView(frame: frame)
                case .systemLarge: LargeView(frame: frame, upcoming: entry.upcoming)
                case .accessoryCircular: CircularView(frame: frame)
                case .accessoryRectangular: RectangularView(frame: frame)
                case .accessoryInline: InlineView(frame: frame)
                default: SmallView(frame: frame)
                }
            } else {
                EmptyHero(compact: family.isAccessory)
            }
        }
        .containerBackground(for: .widget) {
            if family.isAccessory {
                AccessoryWidgetBackground()
            } else {
                SceneBackground(name: entry.frame?.scene, dim: 0.55)
            }
        }
    }
}

// MARK: - Écran d'accueil

private struct SmallView: View {
    let frame: HeroWidgetData.Frame

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(frame.name)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.yellow)
                Text("Niv. \(frame.level)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .lineLimit(1)
            if frame.dead {
                Spacer(minLength: 0)
                Tomb(frame: frame, compact: true)
            } else {
                Text(frame.place)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let alert = frame.alert {
                    AlertTag(text: alert)
                } else {
                    Countdown(end: frame.end)
                        .font(.title3.weight(.heavy))
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 4) {
                    NeedBars(frame: frame, labels: false)
                    AnimatedHero(frame: frame, height: 44)
                        .padding(.trailing, -10)
                }
            }
        }
        .foregroundStyle(.white)
    }
}

private struct MediumView: View {
    let frame: HeroWidgetData.Frame

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                AnimatedHero(frame: frame, height: 66)
                Text(frame.name)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
                Text("Niv. \(frame.level) · \(Int(frame.gold)) or")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 104)

            VStack(alignment: .leading, spacing: 6) {
                if frame.dead {
                    Tomb(frame: frame, compact: false)
                } else {
                    Text(frame.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(frame.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        ProgressBar(frame: frame)
                        Countdown(end: frame.end)
                            .font(.subheadline.weight(.heavy))
                            .fixedSize()
                    }
                    if let alert = frame.alert { AlertTag(text: alert) }
                    Spacer(minLength: 0)
                    NeedBars(frame: frame, labels: false)
                }
            }
        }
        .foregroundStyle(.white)
    }
}

private struct LargeView: View {
    let frame: HeroWidgetData.Frame
    let upcoming: [HeroWidgetData.Upcoming]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AnimatedHero(frame: frame, height: 76)
                VStack(alignment: .leading, spacing: 2) {
                    Text(frame.name)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.yellow)
                    Text("Niveau \(frame.level) · \(Int(frame.gold)) or")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    if let alert = frame.alert, !frame.dead { AlertTag(text: alert) }
                }
                Spacer(minLength: 0)
                if !frame.dead {
                    Sprite(name: frame.sprite, size: 44, fallback: "camp_fire_1")
                }
            }

            if frame.dead {
                Tomb(frame: frame, compact: false)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(frame.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(frame.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        ProgressBar(frame: frame)
                        Countdown(end: frame.end)
                            .font(.headline.weight(.heavy))
                            .fixedSize()
                    }
                }
                NeedBars(frame: frame, labels: true)

                if !upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("À venir")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white.opacity(0.6))
                        ForEach(upcoming.prefix(3), id: \.self) { next in
                            HStack(spacing: 8) {
                                Image(systemName: next.symbol)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.cyan)
                                    .frame(width: 18)
                                Text(next.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(next.date, style: .time)
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - StandBy

private struct VigilView: View {
    let entry: HeroEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let frame = entry.frame {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(frame.dead ? "Repose en paix" : frame.place)
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        if frame.dead {
                            Image(systemName: "heart.slash.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                        } else if let alert = frame.alert {
                            AlertTag(text: alert)
                        } else {
                            Countdown(end: frame.end)
                                .font(.title2.weight(.heavy))
                        }
                    }
                    Spacer(minLength: 4)
                    if !frame.dead { MiniHeart(value: frame.hp) }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                AnimatedHero(frame: frame, height: 84)
                    .padding(.leading, -6)
                    .padding(.bottom, 6)
            } else {
                EmptyHero(compact: false)
                    .padding(12)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            SceneBackground(name: entry.frame?.scene, dim: 0.25)
        }
    }
}

private struct MiniHeart: View {
    let value: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
                .foregroundStyle(value < 0.25 ? .red : .pink)
            Text("\(Int((value * 100).rounded())) %")
                .monospacedDigit()
        }
        .font(.caption2.weight(.heavy))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.45), in: Capsule())
    }
}

// MARK: - Écran verrouillé

private struct CircularView: View {
    let frame: HeroWidgetData.Frame

    var body: some View {
        if frame.dead {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "heart.slash.fill").font(.title3)
            }
        } else {
            // Le besoin le plus pressant, sinon les PV.
            let needs = NeedBars.needs(of: frame)
            let shown = needs.dropFirst().filter { $0.value < 0.25 }.min { $0.value < $1.value } ?? needs[0]
            Gauge(value: shown.value) {
                Image(systemName: shown.symbol)
            } currentValueLabel: {
                Image(systemName: shown.symbol)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
    }
}

private struct RectangularView: View {
    let frame: HeroWidgetData.Frame

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(frame.name)
                .font(.headline)
                .widgetAccentable()
            if frame.dead {
                Text(frame.title).font(.caption).lineLimit(2)
            } else {
                Text(frame.alert ?? frame.place)
                    .font(.caption)
                    .lineLimit(1)
                if let end = frame.end, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text("PV \(Int((frame.hp * 100).rounded())) %")
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineView: View {
    let frame: HeroWidgetData.Frame

    var body: some View {
        if frame.dead {
            Label("\(frame.name) est mort", systemImage: "heart.slash.fill")
        } else {
            Label("\(frame.name) · \(frame.alert ?? frame.place)", systemImage: "flame.fill")
        }
    }
}

// MARK: - Pièces

private struct EmptyHero: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: 6) {
            if !compact { Sprite(name: "camp_fire_1", size: 40) }
            Text(compact ? "Aucun héros" : "Le feu attend un héros")
                .font(compact ? .caption : .headline)
                .multilineTextAlignment(.center)
            if !compact {
                Text("Ouvrez le jeu pour en choisir un.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }
}

private struct Tomb: View {
    let frame: HeroWidgetData.Frame
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Mort", systemImage: "heart.slash.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(frame.title)
                .font(.caption)
                .lineLimit(compact ? 2 : 3)
            if !compact {
                Text("Ouvrez le jeu pour choisir son successeur.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

private struct AlertTag: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.heavy))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(text == "Carrefour" ? Color.cyan : Color.orange, in: Capsule())
            .lineLimit(1)
    }
}

/// PV, satiété, hydratation et moral en petites jauges. Avec libellés dans le grand widget.
private struct NeedBars: View {
    let frame: HeroWidgetData.Frame
    let labels: Bool

    struct Need {
        let label: String
        let symbol: String
        let color: Color
        let value: Double
    }

    static func needs(of frame: HeroWidgetData.Frame) -> [Need] {
        [Need(label: "PV", symbol: "heart.fill", color: .red, value: frame.hp),
         Need(label: "Satiété", symbol: "fork.knife", color: .orange, value: frame.hunger),
         Need(label: "Soif", symbol: "drop.fill", color: .cyan, value: frame.thirst),
         Need(label: "Moral", symbol: "face.smiling", color: .pink, value: frame.mood)]
    }

    var body: some View {
        let needs = Self.needs(of: frame) + (labels ? [Need(label: "Énergie", symbol: "bolt.fill", color: .yellow, value: frame.energy)] : [])
        if labels {
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(needs, id: \.label) { need in
                    GridRow {
                        Image(systemName: need.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint(need))
                        Text(need.label)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .gridColumnAlignment(.leading)
                        Bar(value: need.value, color: tint(need))
                        Text("\(Int((need.value * 100).rounded()))")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
        } else {
            VStack(spacing: 4) {
                ForEach(needs, id: \.label) { need in
                    HStack(spacing: 5) {
                        Image(systemName: need.symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tint(need))
                            .frame(width: 12)
                        Bar(value: need.value, color: tint(need))
                    }
                }
            }
        }
    }

    private func tint(_ need: Need) -> Color { need.value < 0.25 ? .red : need.color }
}

private struct Bar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(color)
                    .frame(width: max(geometry.size.width * min(max(value, 0), 1), value > 0 ? 3 : 0))
            }
        }
        .frame(height: 5)
    }
}

/// Avancement de l'activité, qui se remplit seul entre deux dates.
private struct ProgressBar: View {
    let frame: HeroWidgetData.Frame

    var body: some View {
        if let start = frame.start, let end = frame.end, end > start {
            ProgressView(timerInterval: start...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.cyan)
        }
    }
}

/// Compte à rebours qui avance seul. Rien à attendre : une coche.
private struct Countdown: View {
    let end: Date?

    var body: some View {
        if let end, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
                .monospacedDigit()
                .foregroundStyle(.cyan)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

private struct SceneBackground: View {
    let name: String?
    let dim: Double

    var body: some View {
        ZStack {
            night
            if let name, UIImage(named: name) != nil {
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .overlay(LinearGradient(colors: [.black.opacity(dim * 0.6), .black.opacity(min(dim + 0.25, 0.9))],
                                            startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

/// Le héros en mouvement. Un widget ne joue pas d'animation, mais il fait avancer seul un chronomètre :
/// celui-ci est écrit dans une police dont chaque chiffre est une image de l'animation, et seul le dernier
/// chiffre, celui des secondes, reste visible. Le héros change ainsi d'image chaque seconde.
/// Sans pose (héros mort, anciennes données), son portrait immobile.
private struct AnimatedHero: View {
    let frame: HeroWidgetData.Frame
    /// Hauteur du héros. Les sprites sont 124 × 80.
    let height: CGFloat

    private var width: CGFloat { (height * 124 / 80).rounded() }

    var body: some View {
        if let font = frame.animationFont {
            // Moins d'une heure : le chronomètre s'écrit « m:ss », jamais plus large.
            Text(timerInterval: frame.date...frame.date.addingTimeInterval(3_599), countsDown: false)
                .font(.custom(font, fixedSize: height))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(width: width * 5, height: height, alignment: .trailing)
                .frame(width: width, height: height, alignment: .trailing)
                .clipped()
                .accessibilityHidden(true)
        } else {
            Sprite(name: frame.portrait, size: height)
                .saturation(frame.dead ? 0 : 1)
                .opacity(frame.dead ? 0.5 : 1)
                .frame(width: width, height: height)
        }
    }
}

/// Image en pixel art, agrandie sans lissage. Si elle manque à l'extension, une autre la remplace.
private struct Sprite: View {
    let name: String
    let size: CGFloat
    var fallback: String = "camp_fire_1"

    var body: some View {
        Image(UIImage(named: name) != nil ? name : fallback)
            .interpolation(.none)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }
}

#Preview("Petit", as: .systemSmall) {
    HeroWidget()
} timeline: {
    HeroEntry(date: .now, frame: HeroWidgetData.sample.frames[0], upcoming: HeroWidgetData.sample.upcoming)
}
