# Pack d'images — inventaire complet & prompts Midjourney

Document de travail pour refaire **toutes** les images du jeu.
Source : code du jeu (`IdleRPG/World.swift`, `Item.swift`) + pipeline (`Art/import_sheets.py`, `Art/slicer.py`, `Art/heros/animations.json`).

Le pipeline découpe des **planches** (grilles de sprites sur une même image) puis les tranche
avec `slicer.py`. On garde donc la logique « 1 planche Midjourney = plusieurs sprites »,
sauf pour les héros et les décors de fond qui ont leur propre image.

---

## 0. Style commun (à coller à la fin de CHAQUE prompt de sprite)

> `fantasy mobile RPG art, clean bold black outline, cohesive warm palette, 16-bit inspired but hi-res, soft cel shading, no text, no watermark, items/creatures centered and well separated on a flat background --v 6.1`

- **Sprites (persos, monstres, items, props)** → fond **uni** (noir `#000000` ou magenta `#FF00FF`) pour un détourage propre. Le slicer vire le fond uni.
- **Fonds de scène** → image complète, **pas** de fond à détourer.
- Génère en haute résolution : le pipeline pixellise lui-même (`px` dans `import_sheets.py`).

---

## 1. Héros (planche `05_heroes` + feuilles d'animation)

3 classes : **Guerrier**, **Archer**, **Mage**. Chaque classe a besoin de :

| Anim | Frames | Note |
|------|--------|------|
| portrait | 1 | |
| idle | 4 | |
| walk (marche) | 4 | |
| attack | 4–5 | |
| hurt | 1 | |
| flee (fuite) | 3 | |
| rest (repos) | 4 | assis près du feu |
| **tired / épuisé** 🆕 | 4 | vraiment à bout : épaules tombantes, souffle court, titube |
| **drink / taverne** 🆕 | 4 | voir §2b (chope / potion / verre selon la classe) |
| **victory** 🆕 (option) | 3 | lève son arme après un boss |

→ **~30 poses par classe** maintenant, soit **~90 poses héros** + **3 portraits**.
Format feuille : lignes de 4 vignettes, une anim par ligne, perso centré, même échelle partout.

**Ajout au prompt héros** (à insérer dans la liste des rows) :
`…, exhausted/out-of-breath (slumped shoulders, panting, barely standing), drinking at a tavern, raising weapon in victory, …`

**Prompt Guerrier :**
```
character sprite sheet of a stout human WARRIOR knight, chainmail + red tabard, sword and round shield, side 3/4 view, rows showing: idle, walking, sword attack, hurt, fleeing, resting by fire — 4 frames per row, consistent size, flat magenta background, fantasy mobile RPG art, clean bold black outline, cohesive warm palette, 16-bit inspired but hi-res, soft cel shading, no text --v 6.1 --ar 4:5
```
**Prompt Archer :** remplace par `agile human ARCHER/ranger, green hood and cloak, longbow and quiver, nimble pose`.
**Prompt Mage :** remplace par `human MAGE, blue robe and pointed hat, wooden staff with glowing crystal, casting pose, magic sparks`.

> Astuce : génère chaque classe à part pour garder le costume cohérent entre toutes les frames.

---

## 2. Marchand / PNJ (planche `06_ui` cellule marchand)

```
single sprite of a friendly fantasy MERCHANT NPC, round belly, apron, coin pouch, standing behind a market stall, side 3/4 view, flat magenta background, [style commun]
```

---

## 2b. Taverne 🆕 (nouvelles animations + PNJ + décor)

Le code gère déjà la taverne (`World.swift` : `TavernOrder = ale / stew / bard`, max 3 chopes).
Il manque juste les visuels. À produire :

**PNJ animés** (feuille d'anim comme les héros, 3–4 frames par anim) :
- **Barde** — joue du luth, tape du pied, salue. `a cheerful medieval BARD playing a lute, feather hat, tapping foot, 3-4 frame loop`
- **Serveuse** — porte un plateau de chopes, pose une assiette, s'essuie les mains. `a friendly tavern WAITRESS/barmaid carrying a tray of mugs, apron, braided hair, 3-4 frame loop`

**Animation « boire » par classe** (4 frames : lève → boit → soupir de contentement → repose) :
| Classe | Récipient |
|--------|-----------|
| Mage | boit une **potion** (fiole) |
| Guerrier | boit une **chope** de cervoise (grande chope en bois/étain) |
| Archer | boit dans un **verre en bois** (gobelet tourné) |

```
character animation sheet, a human WARRIOR sitting at a tavern table, drinking from a big wooden ale mug, 4 frames: raising the mug, gulping, satisfied sigh, setting it down, side 3/4 view, flat magenta background, fantasy mobile RPG art, clean bold black outline, cohesive warm palette, soft cel shading, no text --v 6.1 --ar 2:1
```
(décline : Mage → fiole de potion ; Archer → gobelet en bois tourné.)

**Décor de taverne** (fond de scène, cf. §9) : salle chaleureuse, cheminée, tonneaux, longues
tables, lanternes — sol dégagé au premier plan, **tileable** pour le scroll.
```
2D side-scroller background, cozy medieval TAVERN interior, warm firelight, wooden beams, barrels, long tables, hanging lanterns, a clear flat walkable floor along the bottom third, empty center, seamless left-right loop, no characters, no text --v 6.1 --ar 16:9 --tile
```

---

## 3. Monstres ordinaires (planches `08_monsters_a` + `02_monsters_b`)

Utilisés par les donjons (+ 1 en réserve). Un monstre = une vignette, bien séparés, même sol.

| Clé | Nom | Donjon |
|-----|-----|--------|
| m_rat | Rat géant | Cave |
| m_bat | Chauve-souris | Cave |
| m_spider | Araignée | Cave |
| m_slime_green | Gelée verte | Cave |
| m_werewolf | Loup-garou | Bois hanté |
| m_ghost | Spectre | Bois hanté / Glacier |
| m_plant | Plante carnivore | Bois hanté |
| m_goblin | Gobelin | Bois hanté |
| m_skeleton | Squelette | Crypte |
| m_skeleton_archer | Squelette archer | Crypte |
| m_scorpion | Scorpion | Crypte |
| m_spider_brown | Araignée des sables | Crypte |
| m_gargoyle | Gargouille | Glacier |
| m_golem_gray | Golem de givre | Glacier |
| m_slime_blue | Gelée glacée | Glacier |
| m_imp | Diablotin | Volcan |
| m_fire_imp | Lutin de feu | Volcan |
| m_orc | Orc | Volcan |
| m_slime_red | Gelée de lave | Volcan |
| m_beholder | (réserve) | — |

**Prompt planche monstres (ex. Cave + Bois) :**
```
sprite sheet of fantasy RPG monsters, a grid of separate creatures: giant rat, cave bat, spider, green slime, werewolf, ghost, carnivorous plant, goblin — each centered in its own cell, same scale, full body, menacing but cute, flat black background, fantasy mobile RPG art, clean bold black outline, cohesive palette, 16-bit inspired hi-res, soft cel shading, no text --v 6.1 --ar 1:1
```
Fais une 2ᵉ planche pour Crypte/Glacier/Volcan : `skeleton, skeleton archer, scorpion, sand spider, gargoyle, frost golem, blue ice slime, imp, fire imp, orc, red lava slime, beholder`.

---

## 4. Boss (grandes vignettes, mêmes planches)

**Utilisés (5) :** Golem de pierre (`b_golem`, Cave), Liche (`b_lich`, Bois), Minotaure (`b_minotaur`, Crypte), Kraken (`b_kraken`, Glacier), Dragon (`b_dragon`, Volcan).

**En réserve (12) pour futurs donjons :** nécromancien, chevalier noir, démon, beholder, élémentaire de feu, minotaure armuré, ogre, chimère, golem de lave, cerbère, kraken armuré, dragon noir.

**Prompt boss :**
```
sprite sheet of epic fantasy RPG BOSS monsters, large and imposing, a grid of: stone golem, lich, minotaur, kraken, red dragon, necromancer, dark knight, demon — each centered full-body in its cell, 2x bigger than normal enemies, dramatic silhouettes, flat black background, fantasy mobile RPG art, clean bold black outline, rich palette, 16-bit inspired hi-res, soft cel shading, no text --v 6.1 --ar 1:1
```

---

## 5. Items / équipement (planches `04_items_main` + `01_items_extra`)

4 slots × 4 raretés (Commun → Rare → Épique → Légendaire), couleur de contour montante.

- **Armes** 🆕 : **plus de variété**. Au lieu d'1 seul modèle par classe, on passe à **2 variantes
  par classe** (comme les bijoux : suffixe `_a` / `_b`), × 4 raretés.
  - Guerrier → **épée** _et_ **hache/marteau** ; Archer → **arc** _et_ **arbalète** ; Mage → **bâton** _et_ **baguette/grimoire**
  - 3 classes × 2 familles × 4 raretés = **24 armes** (au lieu de 12).
  - ⚙️ _Côté code_ : la clé actuelle est `w_{classe}_{rareté}`. Pour exploiter les variantes,
    il faudra ajouter un suffixe `_a/_b` dans `Item.swift` (`spriteName`, slot `.weapon`) — petit
    changement, à faire quand les images seront prêtes.
- **Amulettes** : 2 variantes × 4 raretés = **8**
- **Anneaux** : 2 variantes × 4 raretés = **8**
- **Bottes** : 4 raretés = **4**

**Prompt armes (2 familles/classe) :**
```
item icon sprite sheet, fantasy RPG weapons on a grid: knight SWORDS and battle AXES/HAMMERS, ranger BOWS and CROSSBOWS, mage STAVES and WANDS — each weapon type shown in 4 rarity tiers left to right (plain gray → blue glow → purple glow → golden legendary with aura), single object centered per cell, 3/4 view, consistent scale, flat magenta background, fantasy mobile RPG art, clean bold black outline, 16-bit inspired hi-res, soft cel shading, no text --v 6.1 --ar 1:1
```
**Prompt bijoux + bottes :**
```
item icon sprite sheet, fantasy RPG gear: amulets, rings, gemstones and leather boots, each in 4 rarity tiers (gray, blue, purple, golden legendary with glow), 2 design variants each, single object centered per cell, flat magenta background, [style commun] --v 6.1 --ar 1:1
```

---

## 6. Consommables & boutique (planches `01_items_extra`, `10_camp_shop`, `06_ui`)

Potion de soin, Parchemin, Sac de couchage, Ration de nourriture.
```
item icon sprite sheet: a red healing POTION, a magic SCROLL, a rolled BEDROLL, a food RATION (bread + cheese) — each centered in its cell, flat magenta background, [style commun] --v 6.1 --ar 2:1
```

---

## 7. Interface & effets (planche `06_ui`)

- **UI** : pièce d'or (coin), cœur (PV), éclair (énergie), onglet carte, onglet sac, onglet livre.
- **Effets** : boule de feu, entaille/slash, soin, montée de niveau.
```
game UI icon sheet, fantasy mobile RPG: gold coin, red heart, energy bolt, map tab icon, backpack tab icon, book tab icon, plus FX icons: fireball, slash swoosh, green heal sparkle, golden level-up burst — each icon centered, flat magenta background, clean bold outline, glossy, cohesive palette, no text --v 6.1 --ar 1:1
```

---

## 8. Rencontres & props de camp (planche `10_camp_shop` + `11_dungeon_tiles`)

Coffre fermé, coffre ouvert, piège à pointes, autel/sanctuaire, enseigne de boutique, feu de camp.
Props de scène (~40) : feu de camp (3 frames), tente, rondin, rochers, souche, sac de couchage, sac à dos, gros coffre, panneaux (donjon / boutique), arbres (violet/bleu/vert), buissons, pousses, champignons (violet/vert/bleu/sarcelle), fougères, étals (rouge/vert/violet), comptoir, sacs de marchandise, cristal, pilier, torche, cristaux de glace, stalactites, chute de lave, pilier de feu.
```
sprite sheet of fantasy RPG environment props: wooden chest closed, chest open with gold, floor spike trap, glowing shrine, shop sign, campfire (3 flame frames), tent, log bench, rocks, tree stump, bedroll, backpack, signposts, stylized trees, bushes, mushrooms, ferns, market stalls, barrels and sacks, glowing crystal, stone pillar, wall torch, ice crystals, icicles, lava fall — each prop separated on its own, flat magenta background, side view, [style commun] --v 6.1 --ar 1:1
```

---

## 9. Fonds de scène (dossier `Art/scenes/`) — **le plus important visuellement**

Chaque lieu en **2 formats** : paysage (16:9) **et** portrait (9:16).
Contraintes techniques :
- **le sol occupe le tiers bas** de l'image (le héros marche dessus), le centre reste **dégagé** ;
- 🆕 **scène « scrollable » / bouclable** : le **bord gauche et le bord droit doivent se raccorder
  sans couture**, pour qu'on puisse la faire défiler en boucle. → paramètre **`--tile`** de
  Midjourney (jointure sans raccord), et horizon/sol continus d'un bout à l'autre.
  > _Note code_ : aujourd'hui `TileStrip` (WorldScene.swift) masque la jointure en **inversant une
  > tuile sur deux** (effet miroir). Avec des fonds `--tile`, on pourra enlever ce miroir et avoir
  > un vrai défilement continu. Évite donc tout élément trop reconnaissable qui trahirait la répétition.

| Scène | Ambiance |
|-------|----------|
| Camp | clairière chaleureuse, feu de camp, tentes (lieu central, rassurant) |
| Taverne 🆕 | salle chaleureuse, cheminée, tonneaux, lanternes (cf. §2b) |
| Marché / Boutique | étals colorés, lanternes, village |
| Champs 🆕 | plaine ouverte, blés dorés, ciel large, quelques arbres au loin |
| Cave aux rats | grotte sombre humide, pierres, mousse |
| Bois hanté | forêt violette brumeuse, arbres tordus, lucioles |
| Crypte des os | cryptes de pierre, ossements, torches |
| Glacier du Kraken | caverne de glace bleue, stalactites |
| Volcan du dragon | caverne de lave, roche noire, coulées rouges |
| Trajet | chemin générique entre les lieux |

**Prompt (ex. Bois hanté, paysage, bouclable) :**
```
2D side-scroller background for a fantasy mobile RPG, HAUNTED FOREST, twisted purple trees, drifting fog, glowing fireflies, eerie moonlight, a clear flat walkable ground strip along the bottom third, continuous horizon, empty space in the center for a character to walk, soft painterly parallax, seamless left-right loop, cohesive palette, no characters, no text --v 6.1 --ar 16:9 --tile
```
**Prompt Champs 🆕 :**
```
2D side-scroller background for a fantasy mobile RPG, sunny open FIELDS, rolling golden wheat, scattered wildflowers, a few distant trees, wide blue sky with soft clouds, a clear flat walkable path along the bottom third, continuous horizon, empty center, seamless left-right loop, soft painterly parallax, no characters, no text --v 6.1 --ar 16:9 --tile
```
Refais chaque scène en `--ar 9:16` pour le portrait (garde `--tile`), et décline l'ambiance par lieu.

---

## 10. Logo & icône (planche `03_logo` + `Art/icone.png`)

- **Logo titre** : « Idle RPG » façon bannière fantasy.
- **Icône d'app** : personnage/symbole lisible en petit, carré.
```
app icon for a fantasy idle RPG, a bold heroic emblem (sword + shield or hero face), vibrant, readable at small size, rounded square, no text --v 6.1 --ar 1:1
```

---

## Récap quantités

| Catégorie | Qté approx. |
|-----------|-------------|
| Poses de héros (3 classes × anims, dont épuisé/boire/victoire 🆕) | ~90 + 3 portraits |
| PNJ animés : marchand, **barde** 🆕, **serveuse** 🆕 | 3 |
| Monstres ordinaires | 19 (+1 réserve) |
| Boss | 5 (+12 réserve) |
| Armes 🆕 (2 familles/classe × 4 raretés) | 24 |
| Bijoux + bottes | 20 |
| Consommables | 4 |
| UI + effets | 10 |
| Rencontres + props | ~46 |
| Fonds de scène `--tile` (×2 formats), + **taverne** 🆕 + **champs** 🆕 | ~20 |
| Logo + icône | 2 |

> Les clés exactes (`m_rat`, `w_mage_3`, `sc_torch`…) et leur emplacement sur les planches
> sont dans `Art/import_sheets.py` (dict `SPRITES`). Après génération, c'est ce fichier qui
> dit à quel numéro de cellule va chaque sprite.
