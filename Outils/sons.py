#!/usr/bin/env python3
"""Fabrique les bruitages et les musiques du jeu, façon 8 bits, sans rien télécharger.

Tout est synthétisé ici (ondes carrées, triangles, bruit) : pas de fichier d'origine, pas de
licence à suivre. Pour remplacer un son par un vrai enregistrement, il suffit de déposer un
fichier du même nom dans IdleRPG/Sons/ et de retirer son entrée d'ici.

Sorties dans IdleRPG/Sons/ :
  sfx_<nom>.wav    bruitages courts (22 kHz mono)
  music_<lieu>.caf boucles de musique sans raccord audible (IMA4, converties par `afconvert`)

Usage : /usr/bin/python3 Outils/sons.py [noms…]   (sans argument : tout)
"""
import array, math, os, random, subprocess, sys, wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "IdleRPG", "Sons")
SR = 22_050

NOTES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def hz(name):
    """« A4 », « C#5 », « Bb3 » → fréquence."""
    letter, rest = name[0], name[1:]
    semi = NOTES[letter]
    while rest and rest[0] in "#b":
        semi += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 440.0 * 2 ** ((semi - 9) / 12 + int(rest) - 4)


class Track:
    """Tampon mono. `loop=True` : ce qui dépasse la fin revient au début, pour boucler sans raccord."""

    def __init__(self, seconds, loop=False):
        self.n = int(seconds * SR)
        self.buf = [0.0] * self.n
        self.loop = loop
        self.rng = random.Random(7)

    def tone(self, start, dur, freq, kind="square", vol=0.3, attack=0.004, release=0.04,
             to=None, duty=0.5, vibrato=0.0, decay=0.0):
        """Une note. `to` : fréquence d'arrivée (glissé). `decay` : part du volume perdue pendant la note."""
        i0, count = int(start * SR), int((dur + release) * SR)
        phase, held, hold_left = 0.0, 0.0, 0.0
        for k in range(count):
            t = k / SR
            f = freq if to is None else freq + (to - freq) * min(t / dur, 1)
            if vibrato:
                f *= 1 + vibrato * math.sin(2 * math.pi * 5.5 * t)
            phase += f / SR
            x = phase % 1.0
            if kind == "square":
                s = 1.0 if x < duty else -1.0
            elif kind == "tri":
                s = 4 * abs(x - 0.5) - 1
            elif kind == "saw":
                s = 2 * x - 1
            elif kind == "sine":
                s = math.sin(2 * math.pi * x)
            else:  # bruit : une valeur tenue, renouvelée à la fréquence demandée
                hold_left -= f / SR
                if hold_left <= 0:
                    held, hold_left = self.rng.uniform(-1, 1), 1.0
                s = held
            env = min(t / attack, 1.0) if attack else 1.0
            if t > dur:
                env *= max(1 - (t - dur) / release, 0)
            env *= 1 - decay * min(t / dur, 1)
            j = i0 + k
            if self.loop:
                j %= self.n
            elif j >= self.n:
                break
            self.buf[j] += s * vol * env

    def save(self, name, peak=0.85):
        top = max(max(self.buf), -min(self.buf), 1e-9)
        gain = peak / top
        data = array.array("h", (int(max(-1, min(1, s * gain)) * 32_000) for s in self.buf))
        os.makedirs(OUT, exist_ok=True)
        path = os.path.join(OUT, name + ".wav")
        with wave.open(path, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes(data.tobytes())
        return path


# MARK: Bruitages

def sfx_hit():
    t = Track(0.22)
    t.tone(0, 0.05, 900, "noise", 0.5, release=0.08, to=300)
    t.tone(0, 0.09, 190, "square", 0.45, to=70, release=0.05)
    return t

def sfx_slash():
    t = Track(0.24)
    t.tone(0, 0.11, 5000, "noise", 0.4, to=1200, release=0.08, attack=0.01)
    t.tone(0.02, 0.07, 700, "saw", 0.15, to=250)
    return t

def sfx_crit():
    t = Track(0.5)
    t.tone(0, 0.07, 1200, "noise", 0.55, to=250, release=0.1)
    t.tone(0, 0.12, 240, "square", 0.5, to=60, release=0.06)
    t.tone(0.05, 0.1, hz("E6"), "square", 0.25, duty=0.25, release=0.2)
    t.tone(0.11, 0.12, hz("B6"), "square", 0.22, duty=0.25, release=0.22)
    return t

def sfx_hurt():
    t = Track(0.3)
    t.tone(0, 0.16, 420, "square", 0.4, to=140, duty=0.3, release=0.06)
    t.tone(0, 0.05, 700, "noise", 0.3, release=0.05)
    return t

def sfx_ice():
    t = Track(0.45)
    t.tone(0, 0.04, 3000, "noise", 0.35, release=0.05)
    for i, n in enumerate(["E7", "B6", "G7", "D7"]):
        t.tone(0.02 + i * 0.045, 0.05, hz(n), "tri", 0.3, release=0.16)
    return t

def sfx_shadow():
    t = Track(0.5)
    t.tone(0, 0.3, 130, "saw", 0.35, to=55, release=0.12, vibrato=0.04)
    t.tone(0, 0.3, 137, "saw", 0.3, to=58, release=0.12)
    t.tone(0, 0.08, 500, "noise", 0.3, to=150, release=0.1)
    return t

def sfx_fire():
    t = Track(0.5)
    t.tone(0, 0.3, 1600, "noise", 0.5, to=180, release=0.15, attack=0.01)
    t.tone(0, 0.14, 150, "square", 0.35, to=50, release=0.08)
    return t

def sfx_coin():
    t = Track(0.4)
    t.tone(0, 0.06, hz("B5"), "square", 0.3, duty=0.25, release=0.03)
    t.tone(0.07, 0.1, hz("E6"), "square", 0.3, duty=0.25, release=0.2)
    return t

def sfx_chest():
    t = Track(0.7)
    t.tone(0, 0.12, 140, "saw", 0.3, to=260, release=0.04)
    for i, n in enumerate(["C5", "E5", "G5", "C6"]):
        t.tone(0.16 + i * 0.07, 0.07, hz(n), "square", 0.28, duty=0.25, release=0.14)
    return t

def sfx_heal():
    t = Track(0.7)
    for i, n in enumerate(["C5", "E5", "G5", "B5", "D6"]):
        t.tone(i * 0.08, 0.1, hz(n), "tri", 0.4, release=0.25, attack=0.02)
    return t

def sfx_levelup():
    t = Track(1.0)
    for i, n in enumerate(["C5", "E5", "G5", "C6", "E6", "G6"]):
        t.tone(i * 0.075, 0.08, hz(n), "square", 0.28, duty=0.25, release=0.1)
    t.tone(0.46, 0.3, hz("C7"), "square", 0.25, duty=0.25, release=0.22, vibrato=0.01)
    t.tone(0.46, 0.3, hz("E6"), "tri", 0.3, release=0.22)
    return t

def sfx_victory():
    t = Track(2.2)
    line = [("G4", 0.0, 0.14), ("C5", 0.16, 0.14), ("E5", 0.32, 0.14), ("G5", 0.48, 0.3),
            ("E5", 0.84, 0.14), ("G5", 1.0, 0.9)]
    for n, at, d in line:
        t.tone(at, d, hz(n), "square", 0.3, duty=0.25, release=0.12, vibrato=0.008 if d > 0.5 else 0)
        t.tone(at, d, hz(n) / 2, "tri", 0.3, release=0.12)
    for n in ["C4", "E4", "G4"]:
        t.tone(1.0, 0.9, hz(n), "square", 0.12, duty=0.5, release=0.2)
    for at in (0.0, 0.48, 1.0):
        t.tone(at, 0.05, 2500, "noise", 0.25, release=0.1)
    return t

def sfx_death():
    t = Track(0.6)
    t.tone(0, 0.35, 380, "square", 0.35, to=45, duty=0.4, release=0.1)
    t.tone(0.05, 0.3, 900, "noise", 0.3, to=120, release=0.15)
    return t

def sfx_flee():
    t = Track(0.6)
    for i, n in enumerate(["A5", "F5", "D5", "A4"]):
        t.tone(i * 0.09, 0.08, hz(n), "square", 0.3, duty=0.5, release=0.05)
    return t

def sfx_boss():
    t = Track(1.4)
    t.tone(0, 0.9, hz("D2"), "saw", 0.4, release=0.3, vibrato=0.02)
    t.tone(0, 0.9, hz("Ab2"), "saw", 0.3, release=0.3)
    t.tone(0, 0.25, 300, "noise", 0.4, to=60, release=0.25)
    t.tone(0.3, 0.6, hz("D4"), "square", 0.2, to=hz("C#4"), duty=0.3, release=0.3)
    return t

def sfx_elite():
    t = Track(0.8)
    t.tone(0, 0.35, hz("E3"), "saw", 0.35, release=0.2)
    t.tone(0.12, 0.35, hz("Bb3"), "square", 0.25, duty=0.3, release=0.25)
    t.tone(0, 0.1, 400, "noise", 0.3, to=100, release=0.1)
    return t

def sfx_trap():
    t = Track(0.35)
    t.tone(0, 0.03, 4000, "noise", 0.5, release=0.04)
    t.tone(0.03, 0.08, 1400, "square", 0.3, to=500, duty=0.2, release=0.1)
    return t

def sfx_buy():
    t = Track(0.5)
    t.tone(0, 0.04, 2000, "noise", 0.3, release=0.03)
    t.tone(0.05, 0.06, hz("E6"), "square", 0.28, duty=0.25, release=0.04)
    t.tone(0.12, 0.1, hz("A6"), "square", 0.28, duty=0.25, release=0.2)
    return t

def sfx_visitor():
    t = Track(1.0)
    t.tone(0, 0.2, hz("E6"), "sine", 0.4, release=0.5, decay=0.5)
    t.tone(0.22, 0.2, hz("C6"), "sine", 0.4, release=0.55, decay=0.5)
    return t

def sfx_fork():
    t = Track(0.9)
    for i, n in enumerate(["D5", "A5", "F#5", "D6"]):
        t.tone(i * 0.1, 0.12, hz(n), "tri", 0.4, release=0.3)
    return t

def sfx_bite():
    t = Track(0.25)
    t.tone(0, 0.03, 2500, "noise", 0.45, release=0.04)
    t.tone(0.05, 0.03, 1800, "noise", 0.45, release=0.05)
    t.tone(0, 0.1, 260, "square", 0.25, to=120, release=0.05)
    return t

def sfx_tap():
    t = Track(0.1)
    t.tone(0, 0.025, hz("A5"), "square", 0.2, duty=0.25, release=0.03)
    return t


# MARK: Musiques

def song(name, bpm, bars, chords, lead, steps=16, bass_kind="tri", drums="", lead_duty=0.25,
         lead_vol=0.2, arp=True, arp_every=2, swing=0.0, lead_vibrato=0.004):
    """Une boucle : accords (un par mesure), ligne de basse et arpège tirés des accords, mélodie écrite.

    `lead` : par mesure, une chaîne « NOTE:durée … » en pas (— pour un silence).
    `drums` : motif d'une mesure, une lettre par pas (k grosse caisse, s caisse claire, h charley).
    """
    step = 60 / bpm * 4 / steps
    t = Track(bars * steps * step, loop=True)

    def at(bar, s):
        return (bar * steps + s) * step + (swing * step if s % 2 else 0)

    for bar in range(bars):
        root, kind = chords[bar % len(chords)]
        third = 3 if kind == "m" else 4
        tones = [hz(root), hz(root) * 2 ** (third / 12), hz(root) * 2 ** (7 / 12)]
        # Basse : fondamentale sur les temps, quinte en relance.
        beat = steps // 4
        for b in range(4):
            f = tones[0] / 2 if b != 3 else tones[2] / 2
            t.tone(at(bar, b * beat), step * beat * 0.8, f, bass_kind, 0.34, release=0.05)
        # Arpège discret, une octave au-dessus.
        if arp:
            order = [0, 1, 2, 1]
            for i, s in enumerate(range(0, steps, arp_every)):
                t.tone(at(bar, s), step * arp_every * 0.7, tones[order[i % 4]] * 2, "square", 0.07, duty=0.5, release=0.03)
        # Mélodie.
        s = 0
        for token in lead[bar % len(lead)].split():
            n, length = token.split(":")
            length = int(length)
            if n != "-":
                t.tone(at(bar, s), step * length * 0.9, hz(n), "square", lead_vol, duty=lead_duty,
                       release=0.06, vibrato=lead_vibrato if length >= 4 else 0)
            s += length
        # Percussions.
        for s, c in enumerate(drums[: steps]):
            if c == "k":
                t.tone(at(bar, s), 0.07, 150, "square", 0.3, to=45, release=0.03)
            elif c == "s":
                t.tone(at(bar, s), 0.06, 2600, "noise", 0.2, release=0.06)
            elif c == "h":
                t.tone(at(bar, s), 0.02, 9000, "noise", 0.08, release=0.02)
    return t


def music_camp():
    # Feu de camp : lent, doux, sans percussions.
    return song("camp", 66, 8, [("A2", "m"), ("F2", "M"), ("C3", "M"), ("G2", "M")],
                ["E5:6 C5:2 A4:8", "A4:4 C5:4 F5:6 E5:2", "E5:6 G5:2 E5:8", "D5:4 B4:4 G4:8",
                 "A4:4 C5:4 E5:6 D5:2", "C5:6 A4:2 F4:8", "E5:4 G5:4 C6:6 B5:2", "B5:4 G5:4 D5:8"],
                lead_vol=0.14, lead_duty=0.5, arp_every=4)


def music_road():
    # Sur la route : pas décidé, mélodie claire.
    return song("road", 104, 8, [("C3", "M"), ("G2", "M"), ("A2", "m"), ("F2", "M")],
                ["E5:2 G5:2 C6:4 B5:2 G5:2 E5:4", "D5:2 G5:2 B5:4 A5:2 G5:2 D5:4",
                 "C5:2 E5:2 A5:4 G5:2 E5:2 C5:4", "F5:4 A5:4 G5:4 E5:2 D5:2",
                 "E5:2 G5:2 C6:4 D6:2 C6:2 G5:4", "B5:4 D6:4 B5:2 A5:2 G5:4",
                 "A5:2 C6:2 E6:4 D6:2 C6:2 A5:4", "A5:4 G5:4 F5:2 E5:2 D5:4"],
                drums="k--h--h-k--h--h-", lead_vol=0.17)


def music_dungeon():
    # Donjon : mineur, tendu, ligne qui rôde.
    return song("dungeon", 92, 8, [("D2", "m"), ("Bb2", "M"), ("G2", "m"), ("A2", "M")],
                ["D5:6 F5:2 E5:4 D5:4", "-:4 F5:4 D5:6 Bb4:2", "G4:4 Bb4:4 D5:6 C5:2", "C#5:8 E5:4 A4:4",
                 "D5:6 A5:2 G5:4 F5:4", "-:4 D5:4 F5:6 D5:2", "Bb4:4 D5:4 G5:6 F5:2", "E5:8 C#5:4 A4:4"],
                bass_kind="saw", drums="k-------k---h---", lead_vol=0.15, lead_duty=0.125,
                arp_every=4, lead_vibrato=0.012)


def music_boss():
    # Combat de boss : rapide, basse qui martèle.
    return song("boss", 148, 8, [("E2", "m"), ("C3", "M"), ("D3", "M"), ("B2", "M")],
                ["E5:2 E5:2 G5:2 B5:2 A5:2 G5:2 E5:4", "E5:2 G5:2 C6:4 B5:2 G5:2 E5:4",
                 "F#5:2 A5:2 D6:4 C6:2 A5:2 F#5:4", "B5:4 F#5:4 D#5:2 F#5:2 B5:4",
                 "E6:2 D6:2 B5:2 G5:2 A5:2 B5:2 E5:4", "G5:2 C6:2 E6:4 D6:2 C6:2 G5:4",
                 "A5:2 D6:2 F#6:4 E6:2 D6:2 A5:4", "B5:2 D#6:2 F#6:4 B5:8"],
                bass_kind="saw", drums="k-h-s-h-k-k-s-h-", lead_vol=0.18)


def music_tavern():
    # Taverne : une gigue à trois temps.
    return song("tavern", 120, 8, [("G2", "M"), ("C3", "M"), ("D3", "M"), ("G2", "M")],
                ["G5:2 B5:1 D6:2 B5:1 G5:2 B5:1 D6:3", "E5:2 G5:1 C6:2 G5:1 E5:2 G5:1 C6:3",
                 "D5:2 F#5:1 A5:2 F#5:1 D6:2 C6:1 A5:3", "B5:2 A5:1 G5:2 D5:1 G5:6",
                 "D6:2 B5:1 G5:2 B5:1 D6:2 E6:1 D6:3", "C6:2 G5:1 E5:2 G5:1 C6:2 D6:1 E6:3",
                 "F#6:2 D6:1 A5:2 D6:1 F#6:2 E6:1 D6:3", "D6:2 B5:1 A5:2 F#5:1 G5:6"],
                steps=12, drums="k--h--k--h--", lead_vol=0.17, arp_every=3)


def music_shop():
    # Boutique : léger, sautillant.
    return song("shop", 112, 8, [("F2", "M"), ("Bb2", "M"), ("C3", "M"), ("F2", "M")],
                ["F5:2 -:2 A5:2 -:2 C6:2 A5:2 F5:4", "D5:2 -:2 F5:2 -:2 Bb5:2 F5:2 D5:4",
                 "E5:2 -:2 G5:2 -:2 C6:2 Bb5:2 G5:4", "A5:2 C6:2 A5:2 F5:2 F5:8",
                 "C6:2 -:2 A5:2 -:2 F5:2 A5:2 C6:4", "D6:2 -:2 Bb5:2 -:2 F5:2 Bb5:2 D6:4",
                 "E6:2 -:2 C6:2 -:2 G5:2 Bb5:2 C6:4", "A5:2 G5:2 F5:2 A5:2 F5:8"],
                drums="k---h---k---h-h-", lead_vol=0.15, lead_duty=0.5, swing=0.18)


def main(wanted):
    made = []
    for name, build in sorted(globals().items()):
        if not callable(build) or not (name.startswith("sfx_") or name.startswith("music_")):
            continue
        if wanted and name not in wanted and name.split("_", 1)[1] not in wanted:
            continue
        music = name.startswith("music_")
        path = build().save(name, peak=0.6 if music else 0.85)
        if music:
            # IMA4 dans un CAF : quatre fois plus léger que le WAV, et bouclable sans silence ajouté.
            caf = path[:-4] + ".caf"
            subprocess.run(["afconvert", "-f", "caff", "-d", "ima4", path, caf], check=True)
            os.remove(path)
            path = caf
        made.append((os.path.basename(path), os.path.getsize(path) // 1024))
    for file, size in made:
        print(f"{file}  {size} Ko")


if __name__ == "__main__":
    main(set(sys.argv[1:]))
