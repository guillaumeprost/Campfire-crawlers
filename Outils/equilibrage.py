"""Simulateur d'équilibrage : reproduit les règles de GameState.swift, World.swift et Item.swift.

À tenir à jour avec le jeu. Lancer : python3 Outils/equilibrage.py [nombre de parties]
Il simule un joueur qui passe quatre fois par jour, de prudent à téméraire, jusqu'à la fin du jeu."""
import math, random, statistics, sys

P = dict(  # paramètres réglables
    rank_factor=1.35, item_factor=1.15, chest_item=0.3, chest_time=0.4, monster_item=0.05, max_rank=5,
    energy=[6, 15, 30, 55, 90], energy_regen=1.0,     # énergie par minute
    hp_regen=0.015,                                    # part des PV max par minute
    injury=0.5,                                        # régénération des PV pendant une blessure
    flee_gold_loss=0.5,
    fire_costs=[500, 2500, 10000, 40000, 160000], fire_step=0.25,
    forge_max=10, forge_step=0.1, forge_cost=3, forge_growth=1.5,
    unlock_rank=5, xp_growth=1.35,
    # Mécaniques Tamagotchi et roguelike (voir GameState.swift)
    happy=1.06, sad=0.85, hungry=0.8, brave=1.03,
    sharp=1.12, stone=0.88, fortune=1.3, second_wind=0.25,
    skill_victories=3,
    # Taverne : prix de base (× 3^(palier-1)), effets, montée du moral par heure, durée d'une soirée.
    ale=30, ale_mood=20, max_ales=3, stew=40, stew_food=45, bard=5, bard_mood=10,
    tavern_mood=12, tavern_rest=0.5, tavern_stay=1800, tavern_trigger=45,
    # Survie : soif, fuites qui peuvent échouer, mort définitive (voir GameState.escapeChance).
    thirsty=0.85, thirst_span=36000, hunger_span=57600,
    escape_base=0.75, escape_ko=0.35, escape_boss=0.10, escape_fatigue=0.25,
    escape_needy=0.15, escape_empty=0.25, escape_injured=0.10, legacy=0.25,
    ration=20, water=10, boots_div=400, ring_div=800,
    # Rythme réel : facteur appliqué aux durées des donjons, aux trajets et au repos ;
    # heures de passage du joueur « sessions » (il ne relance le héros qu'à ces moments-là).
    time_factor=8.5, sessions=(8, 12.5, 19, 22.5),
    mode='off',   # 'off' : règles d'avant ; 'idle' : joueur absent ; 'active' : joueur attentif ;
                  # 'tavern' : joueur absent qui emmène le héros à la taverne quand le moral flanche
)
DUNGEONS = [
    dict(travel=20, duration=120, rooms=6, hp=24, dmg=3, gold=5, xp=6),
    dict(travel=60, duration=600, rooms=10, hp=70, dmg=7, gold=15, xp=16),
    dict(travel=180, duration=1800, rooms=16, hp=200, dmg=14, gold=45, xp=45),
    dict(travel=360, duration=3600, rooms=24, hp=600, dmg=28, gold=140, xp=120),
    dict(travel=600, duration=7200, rooms=36, hp=1800, dmg=55, gold=420, xp=320),
]
CLASSES = {'warrior': (1.3, 1, 0, 0), 'archer': (1, 1, 0.25, 0.25), 'mage': (0.9, 1.25, 0, 0)}
BASE = {'weapon': [4, 10, 28, 80, 230], 'helmet': [2, 2, 3, 3, 4], 'armor': [2, 3, 4, 5, 6], 'amulet': [25, 60, 140, 320, 750], 'ring': [8, 12, 16, 20, 25], 'boots': [5, 8, 11, 14, 17]}
CAP = {'boots': 60, 'ring': 150, 'armor': 30, 'helmet': 15}
RARITY = [(1, 4), (1.5, 10), (2.2, 25), (3.5, 70)]

def scale(rank): return P['rank_factor'] ** (rank - 1)
def max_rank(i): return 999 if i == 4 else P['max_rank']

class Item:
    __slots__ = ('slot', 'bonus', 'value', 'forge')
    def __init__(s, slot, bonus, value): s.slot, s.bonus, s.value, s.forge = slot, bonus, value, 0
    def eff(s):
        b = s.bonus * (1 + P['forge_step'] * s.forge)
        return min(b, CAP[s.slot]) if s.slot in CAP else b
    def forge_cost(s): return round(s.value * P['forge_cost'] * P['forge_growth'] ** s.forge)

class Game:
    def __init__(s, cls, seed):
        s.r = random.Random(seed)
        s.hpf, s.atkf, s.spd, s.lck = CLASSES[cls]
        s.level, s.xp, s.gold = 1, 0.0, 0.0
        s.gear = {}; s.potions = 0; s.bedroll = False; s.fire = 0; s.injured = False
        s.best = [0] * 5   # meilleur rang terminé par donjon
        s.hunger, s.mood, s.charge, s.boss_kills = 80.0, 70.0, 0.0, 0
        s.thirst, s.deaths = 80.0, 0
        s.hp = s.maxhp(); s.energy = 100.0; s.t = 0.0
        s.first = {}; s.st = dict(runs=0, fled=0, exhausted=0, rest=0.0, travel=0.0, explore=0.0, spent=0.0, lost_items=0, lost_gold=0.0, earned=0.0, tavern=0.0, deaths=0)
    def g(s, slot): return s.gear[slot].eff() if slot in s.gear else 0
    def maxhp(s): return round((100 + 20 * (s.level - 1) + s.g('amulet')) * s.hpf)
    def condition(s):
        if P['mode'] == 'off': return 1.0
        f = 1.0
        if s.hunger < 25: f *= P['hungry']
        if s.thirst < 25: f *= P['thirsty']
        if s.mood >= 70: f *= P['happy']
        elif s.mood < 25: f *= P['sad']
        if s.boss_kills >= 5: f *= P['brave']
        return f
    def cheer(s, x): s.mood = min(max(s.mood + x, 0), 100)
    def wear(s, seconds, dungeon=False, idle_camp=False):
        if P['mode'] == 'off': return
        s.hunger = max(s.hunger - seconds * 100 / P['hunger_span'] * (2 if dungeon else 1), 0)
        s.thirst = max(s.thirst - seconds * 100 / P['thirst_span'] * (2 if dungeon else 1), 0)
        s.mood = max(s.mood - seconds * (8 if idle_camp else 3) / 3600, 0)
        if P['mode'] == 'active':
            # Le joueur passe régulièrement : il nourrit et encourage le héros.
            while s.hunger < 50: s.hunger = min(s.hunger + 40, 100)
            while s.thirst < 50: s.thirst = min(s.thirst + 50, 100)
            s.cheer(15 * seconds / 1800)
    def attack(s): return round((10 + 3 * (s.level - 1) + s.g('weapon')) * s.atkf * s.condition())
    def speed(s): return s.g('boots') / 100 + s.spd
    def luck(s): return s.g('ring') / 100 + s.lck
    def xpneed(s): return round(30 * P['xp_growth'] ** (s.level - 1))
    def boost(s): return (1.5 if s.bedroll else 1) * (1 + P['fire_step'] * s.fire)
    def unlocked(s):
        out = []
        for i in range(5):
            if i and s.best[i - 1] < P['unlock_rank']: break
            for rank in range(1, min(s.best[i] + 1, max_rank(i)) + 1): out.append((i, rank))
        return out
    def item(s, tier, rank, floor=0, luck=0.0, r=None):
        r = r or s.r
        slot = r.choice(list(BASE))
        b = 1 + luck; w = [x for x in [(0, 60), (1, 28 * b), (2, 10 * b), (3, 2 * b)] if x[0] >= floor]
        p = r.uniform(0, sum(x[1] for x in w)); rar = floor
        for k, x in w:
            if p < x: rar = k; break
            p -= x
        bonus = BASE[slot][tier - 1] * RARITY[rar][0] * r.uniform(0.85, 1.15) * P['item_factor'] ** (rank - 1)
        if slot in CAP: bonus = min(bonus, CAP[slot])
        return Item(slot, max(round(bonus), 1), math.ceil(DUNGEONS[tier - 1]['gold'] * RARITY[rar][1] * P['item_factor'] ** (rank - 1)))
    def rest(s, seconds):
        b = s.boost()
        hreg = s.maxhp() * P['hp_regen'] / P['time_factor'] / 60 * b * (P['injury'] if s.injured else 1)
        s.hp = min(s.maxhp(), s.hp + hreg * seconds)
        if s.hp >= s.maxhp(): s.injured = False
        s.energy = min(100, s.energy + P['energy_regen'] / P['time_factor'] / 60 * b * seconds)
        s.wear(seconds, idle_camp=True)
        s.t += seconds; s.st['rest'] += seconds
    def time_to_rest(s):
        b = s.boost()
        hreg = s.maxhp() * P['hp_regen'] / P['time_factor'] / 60 * b * (P['injury'] if s.injured else 1)
        return max((s.maxhp() - s.hp) / hreg, (100 - s.energy) / (P['energy_regen'] / P['time_factor'] / 60 * b), 0)
    def gain(s, xp):
        s.xp += xp
        while s.xp >= s.xpneed():
            s.xp -= s.xpneed(); s.level += 1; s.hp += round(20 * s.hpf)
    def receive(s, it):
        cur = s.gear.get(it.slot)
        if cur is None or it.eff() > cur.eff():
            ratio = s.hp / s.maxhp()
            if cur: s.gold += cur.value; s.st['earned'] += cur.value
            s.gear[it.slot] = it
            if it.slot == 'amulet': s.hp = max(round(s.maxhp() * ratio), 1)
        else:
            s.gold += it.value; s.st['earned'] += it.value
    def expedition(s, i, rank, r, real):
        """Joue une sortie. Renvoie l'issue ; si real, applique les gains."""
        d = DUNGEONS[i]; k = scale(rank)
        hp, energy, potions, level, xp = s.hp, s.energy, s.potions, s.level, s.xp
        maxhp, atk = s.maxhp(), s.attack()
        cost = P['energy'][i]; ren = cost / d['rooms']
        gold, loot = 0.0, []
        heal = lambda: round(maxhp * 0.4)
        outcome = 'fled'
        new = P['mode'] != 'off'
        blessings, forced, charge = set(), None, s.charge
        # Temps passé dans le donjon, en salles : un coffre s'ouvre plus vite qu'un combat.
        spent = 0.0
        for room in range(d['rooms']):
            kind = 'boss' if room == d['rooms'] - 1 else 'monster' if room == 0 else None
            if kind is None:
                x = r.random(); kind = 'monster' if x < 0.55 else 'chest' if x < 0.75 else 'trap' if x < 0.85 else 'fountain'
                if forced: kind, forced = forced, None
            atk_now = atk * (P['sharp'] if 'sharp' in blessings else 1)
            taken = (P['stone'] if 'stone' in blessings else 1) * (1 - s.g('armor') / 100)
            gmul = P['fortune'] if 'fortune' in blessings else 1
            spread = r.uniform(0.8, 1.2)
            wounded = min(hp, max(round(maxhp * 0.05), 1)); ko = False; ko_boss = kind == 'boss'
            if kind in ('monster', 'boss'):
                boss = kind == 'boss'
                fhp = d['hp'] * k * (3 if boss else 1); fdm = d['dmg'] * k * (1.5 if boss else 1)
                dmg = round(fdm * max(math.ceil(fhp / atk_now) - 1, 0.25) * spread * taken)
                # Joueur attentif : coup spécial sur le boss, ou pour éviter une défaite.
                if new and real and P['mode'] == 'active' and charge >= 1 and (boss or dmg >= hp):
                    charge, dmg = 0, round(dmg * 0.2)
                if dmg >= hp and (potions == 0 or dmg >= hp + heal()): hp = wounded; ko = True
                else:
                    if dmg >= hp: potions -= 1; hp += heal()
                    hp = min(max(hp - dmg, 1), maxhp)
                    gold += round(d['gold'] * k * (10 if boss else 1) * spread * gmul)
                    charge = min(charge + 1 / P['skill_victories'], 1)
                    if real and new:
                        s.cheer(10 if boss else 1)
                        if boss: s.boss_kills += 1
                    if real:
                        if boss: loot.append(s.item(i + 1, rank, 1, s.luck(), r))
                        elif r.random() < P['monster_item'] * (1 + s.luck()): loot.append(s.item(i + 1, rank, 0, s.luck(), r))
                    xp += d['xp'] * k * (5 if boss else 1)
                    while xp >= round(30 * P['xp_growth'] ** (level - 1)):
                        xp -= round(30 * P['xp_growth'] ** (level - 1)); level += 1; hp += round(20 * s.hpf)
                        maxhp = round((100 + 20 * (level - 1) + s.g('amulet')) * s.hpf); atk = round((10 + 3 * (level - 1) + s.g('weapon')) * s.atkf)
            elif kind == 'chest':
                gold += round(d['gold'] * k * 4 * spread * gmul)
                spent -= 1 - P['chest_time']
                if real and r.random() < min(P['chest_item'] * (1 + s.luck()), 0.95): loot.append(s.item(i + 1, rank, 0, s.luck(), r))
            elif kind == 'trap':
                dmg = round(d['dmg'] * k * 1.5 * spread * taken)
                if dmg >= hp: hp = wounded; ko = True
                else: hp = max(hp - dmg, 1)
            else:
                hp = min(hp + round(maxhp * 0.15), maxhp)
            energy = max(energy - ren, 0)
            spent += 1
            if ko: break
            if room == d['rooms'] - 1: outcome = 'clear'; break
            if hp <= maxhp * 0.25:
                if potions: potions -= 1; hp = min(maxhp, hp + heal())
                else: break
            if energy < ren: outcome = 'exhausted'; break
            # Carrefour une salle sur quatre (salles 3, 7, 11...) : trois bénédictions au choix.
            if new and room % 4 == 2 and room < d['rooms'] - 3:
                offer = r.sample(['sharp', 'stone', 'fortune', 'second', 'treasure', 'sanctuary'], 3)
                if P['mode'] == 'active':
                    pref = ['sharp', 'stone', 'second'] if hp > maxhp * 0.5 else ['second', 'stone', 'sharp']
                else:
                    pref = ['sharp'] if s.boss_kills >= 5 else (['second'] if hp < maxhp * 0.5 else [])
                pick = next((b for b in pref if b in offer), offer[0])
                if pick == 'second': hp = min(hp + round(maxhp * P['second_wind']), maxhp)
                elif pick == 'treasure': forced = 'chest'
                elif pick == 'sanctuary': forced = 'fountain'
                else: blessings.add(pick)
        if not real and outcome == 'fled': s._last = (ko, ko and ko_boss, energy)
        if real:
            s.hp, s.energy, s.potions = hp, energy, potions
            s.xp = 0; s.level = level; s.xp = xp
            dur = ((d['travel'] * 2) / (1 + s.speed()) + d['duration'] / (1 + s.speed()) * spent / d['rooms']) * P['time_factor']
            if P['mode'] == 'session':
                # Le héros emporte des provisions : il mange et boit en route, le joueur les a payées.
                k = 3 ** (s.tier() - 1)
                pack = (dur * 100 / P['hunger_span'] / 40 * P['ration'] + dur * 100 / P['thirst_span'] / 50 * P['water']) * k
                s.gold = max(s.gold - pack, 0); s.st['spent'] += pack
                s.wear(dur)
            else:
                s.wear(dur, dungeon=True)
            s.charge = charge
            s.t += dur; s.st['explore'] += dur
            s.st['runs'] += 1
            if outcome == 'fled' and P['mode'] != 'off':
                # La fuite peut échouer : c'est la mort, et tout repart de zéro sauf le camp.
                if r.random() >= s.escape(ko, ko and ko_boss, energy):
                    s.st['runs'] += 0; s.die(); return 'dead'
            if outcome == 'fled':
                s.st['fled'] += 1; s.injured = True
                if new: s.cheer(-20)
                s.st['lost_items'] += len(loot); s.st['lost_gold'] += gold * P['flee_gold_loss']
                gold *= 1 - P['flee_gold_loss']; loot = []
            if outcome == 'exhausted': s.st['exhausted'] += 1
            s.gold += gold; s.st['earned'] += gold
            for it in loot: s.receive(it)
            if outcome == 'clear':
                if new: s.cheer(10)
                if rank > s.best[i]: s.best[i] = rank
                s.first.setdefault((i, rank), s.t)
        return outcome
    def chance(s, i, rank, n=40):
        return s.odds(i, rank, n)[0]
    def odds(s, i, rank, n=40):
        """Réussite et risque de mort, comme les affiche le jeu (GameState.odds)."""
        seed = hash((i, rank, s.level, round(s.hp), s.potions)) & 0xffffffff
        r = random.Random(seed)
        wins = deaths = 0.0
        for _ in range(n):
            s._last = None
            out = s.expedition(i, rank, r, False)
            if out == 'clear': wins += 1
            elif out == 'fled' and s._last: deaths += 1 - s.escape(*s._last)
        return wins / n, deaths / n
    def pick(s, threshold):
        opts = s.unlocked()
        opts.sort(key=lambda o: (o[0], o[1]), reverse=True)
        for o in opts:
            if threshold <= 0: return o
            win, death = s.odds(*o)
            # Le joueur lit aussi le risque de mort affiché avant de partir.
            if win >= threshold and death <= (1 - threshold) / 3: return o
        return opts[-1]
    def shopping(s):
        tier = max([i + 1 for i in range(5) if s.best[i]] or [1])
        price = 30 * 3 ** (tier - 1)
        reserve = price * 3
        want = (s.potions < 3 and s.gold >= price) or (not s.bedroll and s.gold >= 400)
        forge = sorted([it for it in s.gear.values()], key=lambda it: it.forge_cost())
        if forge and forge[0].forge < P['forge_max'] and s.gold >= forge[0].forge_cost() + reserve: want = True
        if not want: return
        s.t += 90; s.st['travel'] += 90
        if not s.bedroll and s.gold >= 400: s.gold -= 400; s.st['spent'] += 400; s.bedroll = True
        while s.potions < 3 and s.gold >= price: s.gold -= price; s.potions += 1; s.st['spent'] += price
        changed = True
        while changed:
            changed = False
            for it in sorted(s.gear.values(), key=lambda it: it.forge_cost()):
                if it.slot in ('weapon', 'amulet') and it.forge < P['forge_max'] and s.gold >= it.forge_cost() + reserve:
                    c = it.forge_cost(); s.gold -= c; s.st['spent'] += c; it.forge += 1; changed = True
    def escape(s, ko=False, boss=False, energy=None):
        c = P['escape_base'] - (P['escape_ko'] if ko else 0) - (P['escape_boss'] if boss else 0)
        c -= P['escape_fatigue'] * (1 - min(max((s.energy if energy is None else energy) / 100, 0), 1))
        for need in (s.hunger, s.thirst):
            c -= P['escape_empty'] if need <= 0 else P['escape_needy'] if need < 25 else 0
        if s.injured: c -= P['escape_injured']
        c += s.g('boots') / P['boots_div'] + s.g('ring') / P['ring_div'] + s.g('helmet') / 100
        return min(max(c, 0.05), 0.97)
    def die(s):
        s.deaths += 1; s.st['deaths'] += 1
        s.gold = round(s.gold * P['legacy'])
        s.level, s.xp, s.gear, s.potions, s.injured = 1, 0.0, {}, 0, False
        s.best = [0] * 5
        s.hunger, s.thirst, s.mood, s.charge, s.boss_kills = 80.0, 80.0, 50.0, 0.0, 0
        s.hp = s.maxhp(); s.energy = 100.0
    def care(s):
        """Joueur absent : il ne nourrit et n'abreuve le héros qu'au retour, quand il en a vraiment besoin."""
        if P['mode'] == 'off': return
        k = 3 ** (s.tier() - 1)
        if P['mode'] == 'session':
            s.cheer(15)
            while s.hunger < 60 and s.gold >= P['ration'] * k:
                s.gold -= P['ration'] * k; s.st['spent'] += P['ration'] * k; s.hunger = min(s.hunger + 40, 100)
            while s.thirst < 60 and s.gold >= P['water'] * k:
                s.gold -= P['water'] * k; s.st['spent'] += P['water'] * k; s.thirst = min(s.thirst + 50, 100)
            return
        while s.hunger < 25 and s.gold >= P['ration'] * k:
            s.gold -= P['ration'] * k; s.st['spent'] += P['ration'] * k; s.hunger = min(s.hunger + 40, 100)
        while s.thirst < 25 and s.gold >= P['water'] * k:
            s.gold -= P['water'] * k; s.st['spent'] += P['water'] * k; s.thirst = min(s.thirst + 50, 100)
    def tier(s): return max([i + 1 for i in range(5) if s.best[i]] or [1])
    def tavern(s):
        """Une soirée à la taverne : aller-retour, commandes, puis un moment près de l'âtre."""
        if s.mood >= P['tavern_trigger'] and s.hunger >= 40: return
        k = 3 ** (s.tier() - 1)
        walk = 100 / (1 + s.speed())
        s.wear(walk); s.t += walk; s.st['travel'] += walk
        def buy(price):
            if s.gold < price: return False
            s.gold -= price; s.st['spent'] += price; s.st['tavern'] += price; return True
        ales = 0
        while ales < P['max_ales'] and s.mood < 90 and buy(round(P['ale'] * k)): s.cheer(P['ale_mood']); ales += 1
        if s.mood < 95 and buy(round(P['bard'] * k)): s.cheer(P['bard_mood'])
        if s.hunger < 60 and buy(round(P['stew'] * k)): s.hunger = min(s.hunger + P['stew_food'], 100); s.cheer(5)
        stay = P['tavern_stay']
        b = s.boost() * P['tavern_rest']
        s.hp = min(s.maxhp(), s.hp + s.maxhp() * P['hp_regen'] / P['time_factor'] / 60 * b * (P['injury'] if s.injured else 1) * stay)
        s.energy = min(100, s.energy + P['energy_regen'] / P['time_factor'] / 60 * b * stay)
        s.hunger = max(s.hunger - stay * 100 / 57600, 0)
        s.cheer(P['tavern_mood'] * stay / 3600)
        s.t += stay; s.st['rest'] += stay
    def camp(s):
        if s.fire < len(P['fire_costs']) and s.gold >= P['fire_costs'][s.fire] * 1.5:
            c = P['fire_costs'][s.fire]; s.gold -= c; s.st['spent'] += c; s.fire += 1

def next_session(t):
    day = int(t // 86400)
    for h in P['sessions']:
        at = day * 86400 + h * 3600
        if at >= t: return at
    return (day + 1) * 86400 + P['sessions'][0] * 3600

def play(cls, seed, threshold, limit=40 * 86400, goal=(4, 1)):
    g = Game(cls, seed)
    while g.t < limit and goal not in g.first:
        if P['mode'] == 'session':
            # Le héros rentre, se repose, puis attend que le joueur repasse.
            g.rest(g.time_to_rest())
            g.rest(next_session(g.t) - g.t)
            g.care(); g.camp(); g.shopping()
            o = g.pick(threshold)
            g.expedition(*o, g.r, True)
            continue
        g.camp()
        g.care()
        if P['mode'] == 'tavern': g.tavern()
        g.rest(g.time_to_rest())
        g.shopping()
        o = g.pick(threshold)
        g.expedition(*o, g.r, True)
    return g

def fmt(t):
    if t is None: return '  -   '
    h = t / 3600
    return f'{h:5.1f}h' if h < 48 else f'{h/24:5.1f}j'

def report(label, games):
    line = f'{label:30}'
    for key in ((1, 1), (2, 1), (3, 1), (4, 1)):
        ts = [g.first.get(key) for g in games]
        ts = [t for t in ts if t]
        line += f' {"BCGV"[key[0]-1]}{fmt(statistics.median(ts)) if len(ts) > len(games) / 2 else "  >40j"}'
    runs = sum(g.st['runs'] for g in games)
    tot = sum(g.st['rest'] + g.st['explore'] + g.st['travel'] for g in games)
    earned = sum(g.st['earned'] for g in games)
    line += f'  fuites {sum(g.st["fled"] for g in games)/runs:4.0%}  repos {sum(g.st["rest"] for g in games)/tot:4.0%}  or dépensé {sum(g.st["spent"] for g in games)/max(earned,1):4.0%}  niv {statistics.median(g.level for g in games)}'
    if P['mode'] == 'tavern': line += f'  taverne {sum(g.st["tavern"] for g in games)/max(earned,1):4.0%} de l\'or'
    line += f'  morts {statistics.mean(g.deaths for g in games):3.1f}'
    print(line, flush=True)

def report_days(label, games, goal=(4, 5)):
    days = lambda key: statistics.median([g.first.get(key, 400 * 86400) for g in games]) / 86400
    print(f'{label:22} Bois {days((1, 1)):5.1f} j  Crypte {days((2, 1)):5.1f} j  Glacier {days((3, 1)):5.1f} j'
          f'  Volcan {days((4, 1)):5.1f} j  fin (Volcan rang 5) {days(goal):5.1f} j'
          f'  morts {statistics.mean(g.deaths for g in games):.1f}', flush=True)

if __name__ == '__main__':
    # Objectif : un joueur régulier, qui passe quatre fois par jour, finit le jeu en deux mois environ.
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    P['mode'] = 'session'
    print('== joueur qui passe à', ', '.join(f'{h:g} h' for h in P['sessions']))
    for th, label in ((0.95, 'prudent (>=95 %)'), (0.75, 'raisonnable (>=75 %)'), (0.45, 'audacieux (>=45 %)')):
        report_days(label, [play('warrior', s, th, limit=400 * 86400, goal=(4, 5)) for s in range(N)])
