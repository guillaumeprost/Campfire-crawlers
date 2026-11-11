import ActivityKit
import SwiftUI
import WidgetKit

/// Activité en direct : où en est le héros, sur l'écran verrouillé et la Dynamic Island.
struct HeroLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HeroActivityAttributes.self) { context in
            let panel = Self.panel(context)
            LockScreenPanel(panel: panel, hero: context.state.hero)
                .padding(14)
                .background {
                    // Le lieu du héros, assombri pour garder le texte lisible.
                    if let scene = panel.scene {
                        Image(scene)
                            .resizable()
                            .scaledToFill()
                            .overlay(LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.8)],
                                                    startPoint: .top, endPoint: .bottom))
                    }
                }
                .activityBackgroundTint(Color(red: 0.06, green: 0.07, blue: 0.11))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let panel = Self.panel(context)
            let hero = context.state.hero
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Sprite(name: hero?.portrait ?? panel.sprite, size: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(end: panel.end)
                        .font(.title3.weight(.bold))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(panel.headline)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        Text(panel.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        StepBars(steps: panel.steps)
                        if let hero { Needs(hero: hero) }
                    }
                }
            } compactLeading: {
                Sprite(name: hero?.portrait ?? panel.sprite, size: 22)
            } compactTrailing: {
                Countdown(end: panel.end)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: 52)
            } minimal: {
                Sprite(name: panel.sprite, size: 20)
            }
        }
    }

    /// Le panneau courant, ou le suivant une fois la date de péremption passée.
    private static func panel(_ context: ActivityViewContext<HeroActivityAttributes>) -> HeroActivityAttributes.Panel {
        context.isStale ? (context.state.later ?? context.state.now) : context.state.now
    }
}

private struct LockScreenPanel: View {
    let panel: HeroActivityAttributes.Panel
    let hero: HeroActivityAttributes.Hero?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Sprite(name: hero?.portrait ?? panel.sprite, size: 52)
                    .padding(4)
                    .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    if let hero {
                        Text(hero.name)
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.yellow)
                    }
                    Text(panel.headline)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(panel.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                if let end = panel.end {
                    VStack(alignment: .trailing, spacing: 2) {
                        Countdown(end: end)
                            .font(.title3.weight(.heavy))
                        Text("\(panel.endLabel) \(end, style: .time)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            StepBars(steps: panel.steps)
            if let hero { Needs(hero: hero) }
        }
        .foregroundStyle(.white)
    }
}

/// PV, satiété et moral du héros, en petites jauges.
private struct Needs: View {
    let hero: HeroActivityAttributes.Hero

    var body: some View {
        HStack(spacing: 10) {
            gauge("heart.fill", .red, hero.hp)
            gauge("fork.knife", .orange, hero.hunger)
            if let thirst = hero.thirst { gauge("drop.fill", .cyan, thirst) }
            gauge("face.smiling", .pink, hero.mood)
        }
    }

    private func gauge(_ symbol: String, _ color: Color, _ value: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(value < 0.25 ? .red : color)
            ProgressView(value: min(max(value, 0), 1))
                .tint(value < 0.25 ? .red : color)
        }
    }
}

/// Compte à rebours qui avance seul. Une fois l'heure passée, une coche.
private struct Countdown: View {
    let end: Date?

    var body: some View {
        if let end, end > Date.now {
            Text(timerInterval: Date.now...end, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.cyan)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

/// Une barre par étape. Chacune se remplit seule entre ses deux dates.
private struct StepBars: View {
    let steps: [HeroActivityAttributes.Step]

    var body: some View {
        if !steps.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                ForEach(steps, id: \.self) { step in
                    VStack(spacing: 3) {
                        ProgressView(timerInterval: step.start...max(step.end, step.start), countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(.cyan)
                        Text(step.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
    }
}

/// Image en pixel art, agrandie sans lissage.
private struct Sprite: View {
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
