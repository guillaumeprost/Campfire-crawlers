import SwiftUI
import UIKit

private let night = Color(red: 0.06, green: 0.07, blue: 0.11)

/// L'écran du héros sur la montre. Comme les widgets, il choisit dans la chronologie
/// reçue l'image de l'heure qu'il est, et laisse le chronomètre animer le personnage.
struct WatchContentView: View {
    @EnvironmentObject private var link: WatchLink

    /// Données d'exemple pour l'aperçu et les captures : lancer avec l'argument « -demo ».
    private var demo: Bool { CommandLine.arguments.contains("-demo") }

    var body: some View {
        ZStack {
            night.ignoresSafeArea()
            if let data = demo ? HeroWidgetData.sample : link.data, !data.frames.isEmpty {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if let frame = data.frame(at: context.date) {
                        HeroPage(frame: frame, upcoming: data.upcoming.filter { $0.date > context.date })
                    } else {
                        EmptyHero()
                    }
                }
            } else {
                EmptyHero()
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Page du héros

private struct HeroPage: View {
    let frame: HeroWidgetData.Frame
    let upcoming: [HeroWidgetData.Upcoming]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                header
                if frame.dead {
                    Tomb(frame: frame)
                } else {
                    AnimatedHero(frame: frame, height: 72)
                    if let alert = frame.alert {
                        AlertTag(text: alert)
                    } else {
                        Countdown(end: frame.end)
                            .font(.title3.weight(.heavy))
                    }
                    NeedBars(frame: frame)
                    if !upcoming.isEmpty { Upcoming(items: upcoming) }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
    }

    private var header: some View {
        VStack(spacing: 1) {
            Text(frame.name)
                .font(.headline.weight(.heavy))
                .foregroundStyle(.yellow)
                .lineLimit(1)
            Text(frame.dead ? "Tombé au combat" : frame.place)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Niv. \(frame.level) · \(Int(frame.gold)) or")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
    }
}

private struct Upcoming: View {
    let items: [HeroWidgetData.Upcoming]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("À venir")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white.opacity(0.6))
            ForEach(items.prefix(3), id: \.self) { next in
                HStack(spacing: 6) {
                    Image(systemName: next.symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                        .frame(width: 16)
                    Text(next.title)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(next.date, style: .time)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}

// MARK: - Pièces partagées

private struct NeedBars: View {
    let frame: HeroWidgetData.Frame

    struct Need {
        let label: String
        let symbol: String
        let color: Color
        let value: Double
    }

    var needs: [Need] {
        [Need(label: "PV", symbol: "heart.fill", color: .red, value: frame.hp),
         Need(label: "Satiété", symbol: "fork.knife", color: .orange, value: frame.hunger),
         Need(label: "Soif", symbol: "drop.fill", color: .cyan, value: frame.thirst),
         Need(label: "Moral", symbol: "face.smiling", color: .pink, value: frame.mood),
         Need(label: "Énergie", symbol: "bolt.fill", color: .yellow, value: frame.energy)]
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(needs, id: \.label) { need in
                HStack(spacing: 6) {
                    Image(systemName: need.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint(need))
                        .frame(width: 14)
                    Bar(value: need.value, color: tint(need))
                    Text("\(Int((need.value * 100).rounded()))")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 22, alignment: .trailing)
                }
            }
        }
        .padding(.top, 2)
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
        .frame(height: 6)
    }
}

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

private struct AlertTag: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(text == "Carrefour" ? Color.cyan : Color.orange, in: Capsule())
            .lineLimit(1)
    }
}

private struct Tomb: View {
    let frame: HeroWidgetData.Frame

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text(frame.title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text("Ouvrez le jeu pour choisir son successeur.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }
}

private struct EmptyHero: View {
    var body: some View {
        VStack(spacing: 8) {
            Sprite(name: "camp_fire_1", size: 44)
            Text("Le feu attend un héros")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Ouvrez le jeu sur l'iPhone.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

/// Le héros en mouvement. La montre ne joue pas d'animation en continu, mais un chronomètre
/// avance seul : il est écrit dans une police dont chaque chiffre est une image de l'animation,
/// et seul le dernier chiffre (les secondes) reste visible. Le héros change d'image chaque seconde.
private struct AnimatedHero: View {
    let frame: HeroWidgetData.Frame
    /// Hauteur du héros. Les sprites font 124 × 80.
    let height: CGFloat

    private var width: CGFloat { (height * 124 / 80).rounded() }

    var body: some View {
        if let font = frame.animationFont {
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

/// Image en pixel art, agrandie sans lissage. Si elle manque au bundle, une autre la remplace.
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
