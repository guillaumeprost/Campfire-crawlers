import AVFoundation
import QuartzCore
import UIKit

/// Musique et bruitages. Les fichiers sont fabriqués par `Outils/sons.py` (IdleRPG/Sons) :
/// `music_<lieu>.caf` en boucle, `sfx_<nom>.wav` pour les bruitages.
///
/// Le son suit le bouton silencieux de l'iPhone et se mêle à ce que le joueur écoute déjà
/// (catégorie « ambiant ») : un jeu qu'on laisse tourner ne doit couper la musique de personne.
/// Mieux : tant qu'une autre app joue du son (musique, podcast), le jeu se tait entièrement,
/// musique et bruitages, et reprend quand elle s'arrête.
@MainActor
final class Audio {
    static let shared = Audio()

    private static let mutedKey = "audio.muted"
    private static let musicVolume: Float = 0.32

    /// Coupé par le joueur dans le menu. Retenu d'un lancement à l'autre.
    private(set) var muted = UserDefaults.standard.bool(forKey: Audio.mutedKey)

    /// Une autre app joue du son : le jeu lui laisse la place.
    private var yielding = false
    private var silent: Bool { muted || yielding }

    private var track: String?
    private var music: AVAudioPlayer?
    /// Quelques lecteurs par bruitage : deux coups rapprochés ne se coupent pas l'un l'autre.
    private var pools: [String: [AVAudioPlayer]] = [:]
    private var lastPlayed: [String: TimeInterval] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        yielding = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
        // iOS prévient quand une autre app commence ou cesse de jouer ; on revérifie aussi au retour
        // dans le jeu, l'avis n'arrivant que si le jeu est au premier plan.
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Audio.shared.checkOtherAudio() }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Audio.shared.checkOtherAudio() }
        }
    }

    private func checkOtherAudio() {
        let other = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
        guard other != yielding else { return }
        yielding = other
        applyVolume()
    }

    func setMuted(_ value: Bool) {
        muted = value
        UserDefaults.standard.set(value, forKey: Self.mutedKey)
        applyVolume()
    }

    private func applyVolume() {
        if silent {
            music?.setVolume(0, fadeDuration: 0.3)
        } else if let music {
            if !music.isPlaying { music.play() }
            music.setVolume(Self.musicVolume, fadeDuration: 0.6)
        }
    }

    /// Passe à la musique d'un lieu (`camp`, `road`, `dungeon`, `boss`, `tavern`, `shop`), en fondu.
    /// nil : silence. Demander la musique déjà en cours ne la relance pas.
    func play(music name: String?) {
        guard name != track else { return }
        track = name
        let old = music
        old?.setVolume(0, fadeDuration: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { old?.stop() }
        music = nil
        guard let name, let url = Bundle.main.url(forResource: "music_\(name)", withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = 0
        player.prepareToPlay()
        player.play()
        if !silent { player.setVolume(Self.musicVolume, fadeDuration: 1.2) }
        music = player
    }

    /// Joue un bruitage (`hit`, `coin`, `victory`…). Sans effet si le son est coupé, si une autre app joue ou si le fichier manque.
    func play(_ name: String, volume: Float = 0.7) {
        guard !silent else { return }
        // Le même son deux fois dans le même instant (rattrapage en accéléré) : une seule fois suffit.
        let now = CACurrentMediaTime()
        if let last = lastPlayed[name], now - last < 0.05 { return }
        lastPlayed[name] = now

        var pool = pools[name] ?? []
        var player = pool.first { !$0.isPlaying }
        if player == nil, pool.count < 3,
           let url = Bundle.main.url(forResource: "sfx_\(name)", withExtension: "wav"),
           let fresh = try? AVAudioPlayer(contentsOf: url) {
            fresh.prepareToPlay()
            pool.append(fresh)
            pools[name] = pool
            player = fresh
        }
        guard let player else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }
}
