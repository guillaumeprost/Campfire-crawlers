import SpriteKit
import SwiftUI

struct ContentView: View {
    let game: GameState
    @State private var scene: WorldScene
    @State private var confirmReset = false
    @State private var tab: Section = .map
    @State private var pickingHero = false
    @State private var showOptions = false
    @Namespace private var sectionSpace

    private enum Section { case map, gear, exploits, journal }

    init(game: GameState) {
        self.game = game
        _scene = State(initialValue: WorldScene(game: game))
    }

    /// Hauteur du panneau replié : activité, signes vitaux et onglets.
    private static let compactPanel: CGFloat = 250
    @State private var detent: PresentationDetent = .height(ContentView.compactPanel)

    /// Largeur du panneau latéral en paysage.
    private static let sidePanel: CGFloat = 370
    @State private var landscape = false
    /// En paysage, l'île dynamique est-elle du côté du panneau ? Sinon il peut se coller au bord.
    @State private var islandOnRight = false
    @State private var safeTrailing: CGFloat = 0

    /// Marge droite du panneau : l'île impose la zone sûre, un bord libre seulement l'arrondi de l'écran.
    private func panelMargin(_ trailing: CGFloat) -> CGFloat { islandOnRight ? trailing + 12 : 14 }

    /// L'île dynamique suit la caméra : à gauche quand l'interface est tournée vers la droite.
    private func readIsland() {
        let device = UIDevice.current.orientation
        if device == .landscapeLeft { islandOnRight = false; return }
        if device == .landscapeRight { islandOnRight = true; return }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        islandOnRight = scene?.effectiveGeometry.interfaceOrientation == .landscapeLeft
    }

    var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let screen = CGSize(width: geometry.size.width + insets.leading + insets.trailing,
                                height: geometry.size.height + insets.top + insets.bottom)
            if landscape {
                // Paysage : la scène couvre tout l'écran ; le panneau de verre flotte à droite
                // et laisse voir le décor flouté à travers lui.
                let open = screen.width - Self.sidePanel - panelMargin(insets.trailing) - 12
                ZStack(alignment: .topLeading) {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60)
                        .frame(width: screen.width, height: screen.height)
                    header
                        .frame(width: open - insets.leading - 28)
                        .padding(.leading, insets.leading + 14)
                        .padding(.top, 10)
                    panel
                        .frame(width: Self.sidePanel)
                        .frame(maxHeight: .infinity)
                        .clipShape(.rect(cornerRadius: 34))
                        .glassEffect(.regular, in: .rect(cornerRadius: 34))
                        .padding(.vertical, 10)
                        .padding(.trailing, panelMargin(insets.trailing))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .ignoresSafeArea()
            } else {
                // Portrait : la scène couvre tout l'écran ; son sol reste juste au-dessus du panneau replié.
                sceneCard(top: insets.top, leading: 0, height: screen.height)
                    .ignoresSafeArea()
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            // Zone cachée à droite par le panneau en paysage, nulle en portrait.
            proxy.size.width > proxy.size.height ? Self.sidePanel + panelMargin(proxy.safeAreaInsets.trailing) + 12 : 0
        } action: { hidden in
            landscape = hidden > 0
            scene.trailingInset = hidden
            scene.bottomInset = hidden > 0 ? 0 : Self.compactPanel - 40
        }
        .background { PlaceBackdrop(image: placeImage) }
        .preferredColorScheme(.dark)
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            readIsland()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            withAnimation(.smooth) { readIsland() }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.trailing } action: { safeTrailing = $0 }
        // Un demi-tour d'un paysage à l'autre ne change pas la taille : on recale la scène à la main.
        .onChange(of: islandOnRight) {
            if landscape { scene.trailingInset = Self.sidePanel + panelMargin(safeTrailing) + 12 }
        }
        .sheet(isPresented: Binding(get: { !landscape }, set: { _ in })) {
            panel
                .presentationDetents([.height(Self.compactPanel), .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationContentInteraction(.scrolls)
                .interactiveDismissDisabled()
                .preferredColorScheme(.dark)
        }
    }

    /// Le panneau en verre : ce que fait le héros, puis la carte, l'équipement ou le journal.
    /// Les fenêtres du jeu partent de lui, puisqu'il est déjà présenté par-dessus la scène.
    private var panel: some View {
        @Bindable var game = game
        return VStack(spacing: 12) {
            VStack(spacing: 9) {
                ActivityStrip(info: game.activityInfo)
                Divider()
                VitalsCard(game: game)
            }
            .padding(.horizontal, 20)

            // Replié en portrait, le panneau ne montre que l'activité et les onglets.
            if landscape || detent != .height(Self.compactPanel) {
            ScrollView {
                Group {
                    switch tab {
                    case .map: MapPanel(game: game)
                    case .gear: EquipmentPanel(game: game)
                    case .exploits: ExploitsPanel(game: game)
                    case .journal: JournalPanel(game: game)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }

            // Les onglets tout en bas, comme une barre d'onglets ; leur contenu s'affiche au-dessus.
            sectionBar
                .padding(.horizontal, 20)
                .padding(.bottom, landscape ? 12 : 0)
        }
        .padding(.top, 22)
        // Replié, le panneau montre son haut : l'activité et les signes vitaux.
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: tab) { _, newTab in
            if newTab == .gear { game.markLootSeen() }
        }
        // Le héros part : on replie le panneau pour laisser voir la scène.
        .onChange(of: MapPanel.tab(for: game.activity).title) { _, place in
            if place == "Trajet" || place == "Balade" {
                withAnimation(.snappy) { detent = .height(Self.compactPanel) }
            }
        }
        .onChange(of: game.unseenLoot) { _, _ in
            if tab == .gear { game.markLootSeen() }
        }
        .confirmationDialog("Options", isPresented: $showOptions, titleVisibility: .hidden) {
            Button(game.isTestSpeed ? "Désactiver le mode test" : "Mode test : temps ×\(Int(GameState.testTimeScale))") {
                game.setTestSpeed(!game.isTestSpeed)
            }
            Button("Recommencer la partie", role: .destructive) {
                // La confirmation s'ouvre une fois ce menu refermé.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { confirmReset = true }
            }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog("Recommencer la partie ?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Tout effacer", role: .destructive) { game.reset() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Votre or, votre niveau, vos donjons et votre équipement seront perdus.")
        }
        .fullScreenCover(isPresented: Binding(
            get: { game.heroClass == nil || pickingHero },
            set: { pickingHero = $0 }
        )) {
            HeroPicker(game: game) { pickingHero = false }
        }
        .sheet(item: $game.awayReport) { report in
            AwaySheet(report: report)
                .presentationDetents([.medium])
        }
    }

    /// Scène du jeu bord à bord, sous la barre d'état, avec l'en-tête en verre posé dessus.
    private func sceneCard(top: CGFloat, leading: CGFloat, height: CGFloat) -> some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60)
            .frame(height: height)
            .overlay(alignment: .top) {
                header
                    .padding(.horizontal, 14)
                    .padding(.leading, leading)
                    .padding(.top, top + 2)
            }
            .overlay(alignment: .bottomLeading) {
                if game.isExploring {
                    // En combat, on peut prêter main-forte au héros.
                    CombatActions(game: game)
                        .padding(.leading, leading + 14)
                        .padding(.bottom, landscape ? 18 : Self.compactPanel + 44)
                }
            }
    }

    /// Barre d'onglets en verre, comme celle du système, posée sur le lieu flouté.
    private var sectionBar: some View {
        GlassEffectContainer {
            HStack(spacing: 2) {
                let place = MapPanel.tab(for: game.activity)
                sectionButton(.map, title: place.title, icon: place.icon, badge: 0)
                sectionButton(.gear, title: "Équipement", icon: "backpack.fill", badge: game.unseenLoot)
                sectionButton(.exploits, title: "Exploits", icon: "trophy.fill", badge: game.claimableCount)
                sectionButton(.journal, title: "Journal", icon: "book.closed.fill", badge: 0)
            }
            .padding(5)
            .glassEffect(.regular.interactive(), in: .capsule)
            // Seule la pastille glisse d'un onglet à l'autre ; le contenu change d'un coup.
            .animation(.bouncy(duration: 0.35), value: tab)
        }
    }

    private func sectionButton(_ target: Section, title: String, icon: String, badge: Int) -> some View {
        let selected = tab == target
        return Button {
            tab = target
            if detent == .height(Self.compactPanel) { detent = .medium }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.caption2.weight(.heavy))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.red, in: Capsule())
                                .offset(x: 12, y: -6)
                        }
                    }
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.6))
            .background {
                if selected {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .matchedGeometryEffect(id: "onglet", in: sectionSpace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge) nouveaux objets" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Image du lieu où se trouve le héros, reprise floutée en fond d'écran.
    private var placeImage: String {
        switch game.activity {
        case .resting: WorldScene.campImage
        case .shopping: "scene_marche"
        case .tavern: WorldScene.tavernImage
        case .traveling: "scene_trajet"
        case .roaming: UIImage(named: "scene_campagne") != nil ? "scene_campagne" : "scene_trajet"
        case .exploring(let run):
            switch Dungeon.all[run.dungeon].style {
            case .cave: "scene_cave"
            case .forest: "scene_bois_hante"
            case .crypt: "scene_crypte"
            case .ice: "scene_glacier"
            case .volcano: "scene_volcan"
            }
        }
    }

    private var header: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    CoinIcon(size: 20)
                    Text(game.gold.short)
                        .contentTransition(.numericText(value: game.gold))
                        .animation(.snappy(duration: 0.25), value: game.gold)
                }
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Or : \(game.gold.short)")

                Spacer()

                // Toucher la pastille du héros ouvre le choix du héros.
                Button {
                    pickingHero = true
                } label: {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(game.name) · Niv. \(game.level)")
                            .font(.footnote.weight(.heavy))
                        ProgressView(value: min(game.xp / game.xpNeeded, 1))
                            .tint(.cyan)
                            .frame(width: 84)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(game.name), \(game.heroLook.name), niveau \(game.level), expérience \(Int(game.xp)) sur \(Int(game.xpNeeded))")
                .accessibilityHint("Changer de héros")

                // Les options s'ouvrent depuis le panneau : en portrait, c'est lui qui est au premier plan.
                Button {
                    showOptions = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Options")
            }
        }
    }
}

/// Le lieu du héros en fond d'écran : flouté et assombri, il donne sa couleur au verre.
private struct PlaceBackdrop: View {
    let image: String

    var body: some View {
        ZStack {
            Color.black
            Image(image)
                .resizable()
                .scaledToFill()
                .blur(radius: 28)
                .overlay(Color.black.opacity(0.42))
                .id(image)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.8), value: image)
        .ignoresSafeArea()
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
        .accessibilityElement(children: .combine)
    }
}

/// Signes vitaux et caractéristiques du héros.
private struct VitalsCard: View {
    let game: GameState

    var body: some View {
        VStack(spacing: 6) {
            gauge(icon: "ui_heart", color: .red, label: "PV", value: game.shownHP, limit: game.maxHP)
            gauge(icon: "ui_bolt", color: .yellow, label: "Énergie", value: game.energy, limit: GameState.maxEnergy)
            HStack(spacing: 12) {
                need("fork.knife", color: .orange, label: "Satiété", value: game.hunger)
                need("drop.fill", color: .cyan, label: "Hydratation", value: game.thirst)
                need(moodSymbol, color: .pink, label: "Moral", value: game.mood)
            }
            HStack(spacing: 10) {
                stat("Attaque \(game.attack.short)")
                if game.speedBonus > 0 { stat("Vitesse +\(Int(game.speedBonus * 100))\u{00A0}%") }
                if game.luck > 0 { stat("Chance +\(Int(game.luck * 100))\u{00A0}%") }
                stat("Fuite \(Int((game.escapeChance() * 100).rounded()))\u{00A0}%")
                Spacer(minLength: 0)
                if game.scrollReady { PixelImage(name: "s_scroll", size: 16) }
                if game.potions > 0 {
                    HStack(spacing: 2) {
                        PixelImage(name: "s_potion", size: 16)
                        Text("×\(game.potions)")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(game.potions) potions")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }

    private func stat(_ text: String) -> some View {
        Text(text).lineLimit(1).minimumScaleFactor(0.8)
    }

    private var moodSymbol: String {
        game.mood >= 70 ? "face.smiling.inverse" : game.mood < 30 ? "cloud.rain.fill" : "face.smiling"
    }

    /// Besoin du héros : une petite jauge qui vire au rouge quand il est bas.
    private func need(_ symbol: String, color: Color, label: String, value: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(value < 25 ? .red : color)
                .frame(width: 16)
            ProgressView(value: min(max(value / 100, 0), 1))
                .tint(value < 25 ? .red : color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) : \(Int(value)) sur 100")
    }

    private func gauge(icon: String, color: Color, label: String, value: Double, limit: Double) -> some View {
        HStack(spacing: 8) {
            PixelImage(name: icon, size: 16)
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
        VStack(spacing: 0) {
            ForEach(Array(game.journal.reversed().enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().padding(.leading, 40) }
                JournalRow(entry: entry)
            }
        }
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
            .buttonStyle(.glassProminent)
            .tint(.green)
        }
        .padding(24)
    }
}

/// Choix du héros : au premier lancement, puis depuis le menu quand il est au camp.
private struct HeroPicker: View {
    let game: GameState
    let close: () -> Void
    @State private var abandonFor: HeroClass?

    var body: some View {
        VStack(spacing: 14) {
            Text("Choisissez votre héros")
                .font(.title2.weight(.heavy))
                .padding(.top, 24)
            Text(game.heroClass == nil
                 ? "La mort est définitive. Prenez soin de lui."
                 : "Choisir un autre héros abandonne \(game.name) à son sort. Il ne reviendra pas.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ForEach(HeroClass.allCases) { hero in
                let current = game.heroClass == hero
                Button {
                    if game.isAbandoning {
                        if !current { abandonFor = hero }
                    } else {
                        game.chooseHero(hero)
                        close()
                    }
                } label: {
                    HStack(spacing: 14) {
                        PixelImage(name: hero.portrait, size: 84)
                            .frame(width: 96, height: 96)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hero.name)
                                .font(.title3.weight(.heavy))
                            Text(hero.motto)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ForEach(hero.perks, id: \.self) { perk in
                                Text(perk)
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(perk.hasPrefix("-") ? Color.orange : Color.green)
                            }
                        }
                        Spacer(minLength: 0)
                        if current {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                                .accessibilityLabel("Héros actuel")
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(current ? .regular.tint(.green.opacity(0.35)) : .regular,
                                 in: .rect(cornerRadius: 24))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if game.heroClass != nil {
                Button("Fermer", action: close)
                    .font(.headline)
                    .buttonStyle(.glass)
                    .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PlaceBackdrop(image: "scene_camp") }
        .preferredColorScheme(.dark)
        .confirmationDialog("Abandonner \(game.name) ?", isPresented: Binding(
            get: { abandonFor != nil }, set: { if !$0 { abandonFor = nil } }
        ), titleVisibility: .visible, presenting: abandonFor) { hero in
            Button("Abandonner et partir avec \(hero.theName)", role: .destructive) {
                game.chooseHero(hero)
                abandonFor = nil
                close()
            }
            Button("Garder \(game.name)", role: .cancel) {}
        } message: { _ in
            Text("\(game.name) sera abandonné à son sort : c'est une mort définitive. Le nouveau héros repart du niveau 1 et hérite du camp et d'un quart de l'or.")
        }
    }
}

/// Pièce d'or, utilisée partout où l'on affiche un montant.
struct CoinIcon: View {
    let size: CGFloat

    var body: some View {
        PixelImage(name: "ui_coin", size: size)
    }
}

/// Image en pixel art, agrandie sans lissage pour garder des pixels nets.
struct PixelImage: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if UIImage(named: name) != nil {
                Image(name)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Lieu sans image dessinée (la taverne) : un symbole en attendant.
                Image(systemName: name)
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
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
            .frame(minWidth: 64)
            .padding(.vertical, 4)
        }
        .actionGlass(enabled)
        .disabled(!enabled)
    }
}

extension View {
    /// Bouton d'action en verre : vert et en relief quand il est utilisable, discret sinon.
    @ViewBuilder
    func actionGlass(_ enabled: Bool, tint: Color = .green) -> some View {
        if enabled {
            buttonStyle(.glassProminent).tint(tint)
        } else {
            buttonStyle(.glass)
        }
    }
}


/// Actions du joueur pendant un combat : le coup spécial, qui se charge en gagnant des combats,
/// et une potion à faire boire au héros.
private struct CombatActions: View {
    let game: GameState

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    game.useSkill()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 4)
                            .padding(3)
                        Circle()
                            .trim(from: 0, to: max(game.skillCharge, 0.001))
                            .stroke(Color.yellow, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(3)
                        Image(systemName: "bolt.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(game.canUseSkill ? Color.yellow : Color.white.opacity(0.5))
                    }
                    .frame(width: 58, height: 58)
                    .glassEffect(game.canUseSkill ? .regular.tint(.yellow.opacity(0.35)).interactive() : .regular,
                                 in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(!game.canUseSkill)
                .accessibilityLabel(game.skillCharge >= 1 ? "Coup spécial prêt" : "Coup spécial, chargé à \(Int(game.skillCharge * 100)) pour cent")

                Button {
                    game.drinkPotion()
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        PixelImage(name: "s_potion", size: 30)
                            .frame(width: 50, height: 50)
                            .opacity(game.canDrinkPotion ? 1 : 0.4)
                        Text("\(game.potions)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(4)
                    }
                    .glassEffect(game.canDrinkPotion ? .regular.interactive() : .regular, in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(!game.canDrinkPotion)
                .accessibilityLabel("Faire boire une potion, \(game.potions) restantes")
            }
        }
    }
}
