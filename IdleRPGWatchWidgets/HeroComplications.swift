import SwiftUI
import WidgetKit

// MARK: - Chronologie

struct HeroEntry: TimelineEntry {
    let date: Date
    let frame: HeroWidgetData.Frame?
}

/// Lit les images du héros écrites par le jeu (reçues de l'iPhone) et en fait une chronologie.
struct HeroProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeroEntry {
        HeroEntry(date: .now, frame: HeroWidgetData.sample.frames.first)
    }

    func getSnapshot(in context: Context, completion: @escaping (HeroEntry) -> Void) {
        completion(entries(from: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeroEntry>) -> Void) {
        completion(Timeline(entries: entries(from: .now), policy: .atEnd))
    }

    private func entries(from now: Date) -> [HeroEntry] {
        guard let data = HeroWidgetData.load(), let current = data.frame(at: now) else {
            return [HeroEntry(date: now, frame: nil)]
        }
        var entries = [HeroEntry(date: now, frame: current)]
        for frame in data.frames where frame.date > now {
            entries.append(HeroEntry(date: frame.date, frame: frame))
        }
        return entries
    }
}

// MARK: - Complication

struct HeroComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HeroComplication", provider: HeroProvider()) { entry in
            HeroComplicationView(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("Le héros")
        .description("Où il est, et comment il va.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct HeroComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeroEntry

    var body: some View {
        if let frame = entry.frame {
            switch family {
            case .accessoryCircular: CircularView(frame: frame)
            case .accessoryCorner: CornerView(frame: frame)
            case .accessoryRectangular: RectangularView(frame: frame)
            case .accessoryInline: InlineView(frame: frame)
            default: CircularView(frame: frame)
            }
        } else {
            EmptyComplication(family: family)
        }
    }
}

// MARK: - Besoins

private struct Need {
    let symbol: String
    let value: Double
}

/// Le besoin le plus pressant (sous 25 %), sinon les PV.
private func pressingNeed(of frame: HeroWidgetData.Frame) -> Need {
    let hp = Need(symbol: "heart.fill", value: frame.hp)
    let others = [Need(symbol: "fork.knife", value: frame.hunger),
                  Need(symbol: "drop.fill", value: frame.thirst),
                  Need(symbol: "face.smiling", value: frame.mood),
                  Need(symbol: "bolt.fill", value: frame.energy)]
    return others.filter { $0.value < 0.25 }.min { $0.value < $1.value } ?? hp
}

// MARK: - Familles

private struct CircularView: View {
    let frame: HeroWidgetData.Frame

    var body: some View {
        if frame.dead {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "heart.slash.fill").font(.title3)
            }
        } else {
            let need = pressingNeed(of: frame)
            Gauge(value: need.value) {
                Image(systemName: need.symbol)
            } currentValueLabel: {
                Image(systemName: need.symbol)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
    }
}

private struct CornerView: View {
    let frame: HeroWidgetData.Frame

    var body: some View {
        if frame.dead {
            Image(systemName: "heart.slash.fill")
                .font(.title3)
                .widgetLabel("Mort")
        } else {
            let need = pressingNeed(of: frame)
            Image(systemName: need.symbol)
                .font(.title3)
                .widgetLabel {
                    if let end = frame.end, end > .now {
                        Text(timerInterval: Date.now...end, countsDown: true)
                    } else {
                        Text(frame.place)
                    }
                }
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
                .lineLimit(1)
            if frame.dead {
                Label("Mort", systemImage: "heart.slash.fill")
                    .font(.caption)
            } else {
                Text(frame.alert ?? frame.place)
                    .font(.caption)
                    .lineLimit(1)
                if let end = frame.end, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Label("\(Int((frame.hp * 100).rounded())) %", systemImage: "heart.fill")
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

private struct EmptyComplication: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Aucun héros", systemImage: "flame")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Idle RPG").font(.headline).widgetAccentable()
                Text("Ouvrez le jeu").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Image(systemName: "flame")
                .font(.title3)
        }
    }
}
