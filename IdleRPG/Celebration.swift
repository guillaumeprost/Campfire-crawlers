import SwiftUI

/// Une récompense à fêter : succès débloqué ou quête du jour accomplie.
struct Celebration: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    /// « Succès débloqué », « Quête accomplie ».
    let headline: String
    let title: String
    let gold: Double
}

/// La fête : une médaille dorée jaillit entre des rayons qui tournent, sous une pluie de confettis,
/// puis la récompense s'affiche. Elle s'efface seule, ou d'un toucher.
struct CelebrationView: View {
    let celebration: Celebration
    let dismiss: () -> Void

    @State private var shown = false
    @State private var textShown = false

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.55 : 0)
                .ignoresSafeArea()

            Confetti()
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                ZStack {
                    Rays()
                        .frame(width: 230, height: 230)
                        .opacity(shown ? 1 : 0)
                    Medal(symbol: celebration.symbol)
                        .scaleEffect(shown ? 1 : 0.2)
                        .rotationEffect(.degrees(shown ? 0 : -40))
                }
                VStack(spacing: 6) {
                    Text(celebration.headline.uppercased())
                        .font(.caption.weight(.heavy))
                        .tracking(2)
                        .foregroundStyle(.yellow)
                    Text(celebration.title)
                        .font(.title2.weight(.heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        CoinIcon(size: 22)
                        Text("+\(celebration.gold.short)")
                            .font(.title.weight(.black))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: textShown ? celebration.gold : 0))
                    }
                    .foregroundStyle(.yellow)
                    .shadow(color: .orange.opacity(0.8), radius: 10)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .opacity(textShown ? 1 : 0)
                .offset(y: textShown ? 0 : 16)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .task {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { shown = true }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { textShown = true }
            try? await Task.sleep(for: .milliseconds(2_300))
            // Remplacée entre-temps par une autre récompense : c'est la nouvelle qui décidera.
            guard !Task.isCancelled else { return }
            dismiss()
        }
        .transition(.opacity.combined(with: .scale(scale: 1.05)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(celebration.headline) : \(celebration.title), plus \(celebration.gold.short) or")
        .accessibilityAddTraits(.isButton)
    }
}

/// Médaille dorée, avec le symbole de l'exploit gravé au centre.
private struct Medal: View {
    let symbol: String
    @State private var shine = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.93, blue: 0.55), Color(red: 0.95, green: 0.65, blue: 0.1),
                                              Color(red: 0.7, green: 0.4, blue: 0.05)],
                                     center: .topLeading, startRadius: 4, endRadius: 110))
            Circle()
                .strokeBorder(Color(red: 1, green: 0.95, blue: 0.7), lineWidth: 4)
            Circle()
                .strokeBorder(Color(red: 0.6, green: 0.35, blue: 0.05).opacity(0.6), lineWidth: 2)
                .padding(10)
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .black))
                .foregroundStyle(Color(red: 0.45, green: 0.25, blue: 0.02))
                .shadow(color: .white.opacity(0.5), radius: 0, x: 0, y: 1.5)
            // Un reflet passe sur la médaille.
            LinearGradient(colors: [.clear, .white.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 40)
                .rotationEffect(.degrees(20))
                .offset(x: shine ? 90 : -90)
                .blendMode(.plusLighter)
                .clipShape(Circle())
        }
        .frame(width: 120, height: 120)
        .shadow(color: .yellow.opacity(0.7), radius: 24)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).delay(0.4)) { shine = true }
        }
    }
}

/// Rayons de lumière qui tournent lentement derrière la médaille.
private struct Rays: View {
    var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) / 12 * 360
            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    Capsule()
                        .fill(LinearGradient(colors: [Color.yellow.opacity(0.55), .clear], startPoint: .bottom, endPoint: .top))
                        .frame(width: 14, height: 115)
                        .offset(y: -58)
                        .rotationEffect(.degrees(Double(index) * 30))
                }
            }
            .rotationEffect(.degrees(angle))
            .blur(radius: 1.5)
        }
    }
}

/// Pluie de confettis tirée depuis le centre, retombant sous l'effet de la gravité.
private struct Confetti: View {
    private struct Piece {
        let velocity: CGVector
        let spin: Double
        let color: Color
        let size: CGSize
    }

    @State private var start = Date()
    private let pieces: [Piece] = (0..<70).map { _ in
        let angle = Double.random(in: -.pi * 0.95 ... -.pi * 0.05)
        let speed = Double.random(in: 260...620)
        return Piece(velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                     spin: .random(in: -9...9),
                     color: [.yellow, .orange, .pink, .cyan, .green, .white, .purple].randomElement()!,
                     size: CGSize(width: .random(in: 5...9), height: .random(in: 8...14)))
    }

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let t = context.date.timeIntervalSince(start)
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.42)
                let gravity = 900.0
                for piece in pieces {
                    let x = origin.x + piece.velocity.dx * t
                    let y = origin.y + piece.velocity.dy * t + 0.5 * gravity * t * t
                    let fade = max(0, min(1, 2.6 - t))
                    guard fade > 0, y < size.height + 20 else { continue }
                    var copy = canvas
                    copy.opacity = fade
                    copy.translateBy(x: x, y: y)
                    copy.rotate(by: .radians(piece.spin * t))
                    // Le confetti tourne sur lui-même : il s'aplatit et s'élargit tour à tour.
                    let flip = abs(cos(piece.spin * t * 0.7))
                    let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height * flip / 2,
                                      width: piece.size.width, height: max(piece.size.height * flip, 1.5))
                    copy.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(piece.color))
                }
            }
        }
    }
}
