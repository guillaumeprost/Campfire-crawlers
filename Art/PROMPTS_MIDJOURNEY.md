# Prompts Midjourney — version précise (1 sujet par image)

## Pourquoi la 1ʳᵉ version ratait
Les anciens prompts demandaient des **grilles / « sprite sheets »** avec plein d'éléments listés.
Midjourney ne sait pas faire ça proprement → épées et boucliers partout, images floues.
**La règle d'or : UN seul sujet par image, isolé, net.** On génère chaque asset séparément.

## Réglages à mettre une fois (⚙️ Settings, en haut à droite)
- **Version : 6.1**
- **Raw Mode : ON** (le modèle colle beaucoup plus au texte, moins de fioritures)
- **Stylization : bas** (le curseur vers la gauche, ~50)

---

## LE MODÈLE DE PROMPT (à réutiliser pour TOUT)

Remplace juste `[SUJET]` par ce que tu veux. Le reste ne bouge pas.

```
[SUJET], single subject, full body, centered, isolated on a plain flat white background, 2D fantasy game asset, 3/4 view, thick clean black outline, flat cel shading, sharp crisp edges, high detail, no shadow --style raw --no scenery, background objects, multiple characters, extra weapons, text, watermark, blur, bokeh, depth of field --ar 1:1
```

> Le `--no ...` est ce qui **enlève le bazar** (armes en trop, flou, fond). Garde-le tel quel.
> Pour un objet seul (arme, potion…) remplace `full body` par `single object`.

---

## SUJETS À GÉNÉRER (plug chacun dans `[SUJET]`)

### Héros (1 image nette par classe, pose neutre)
- `a stout human warrior knight in chainmail and red tabard, holding ONE sword and a round shield, standing idle`
- `an agile human archer ranger in a green hooded cloak, holding ONE longbow, standing idle`
- `a human mage in a blue robe and pointed hat, holding ONE wooden staff with a glowing crystal, standing idle`

> ⚠️ Les **animations image-par-image** (marche, attaque…), Midjourney n'est pas fait pour ça
> (chaque image serait un perso différent). Le plus simple : on génère **1 héros net par classe**
> et **on anime dans le code**. Si tu veux quand même des poses, génère-les **une par une** :
> remplace `standing idle` par `swinging the sword`, `drinking from a wooden ale mug`,
> `sitting exhausted and out of breath`, etc. — une image = une pose.

### PNJ
- `a friendly fat fantasy merchant with an apron and a coin pouch, standing`
- `a cheerful medieval bard playing a lute, feathered hat, standing`
- `a friendly tavern waitress with an apron and braided hair, carrying a tray of ale mugs`

### Monstres (une image chacun)
rat géant · chauve-souris · araignée · gelée verte · loup-garou · spectre · plante carnivore ·
gobelin · squelette · squelette archer · scorpion · araignée des sables · gargouille ·
golem de givre · gelée bleue de glace · diablotin · lutin de feu · orc · gelée rouge de lave
```
Exemples de [SUJET] :
a giant sewer rat, monster
a werewolf, fantasy monster
a green jelly slime with eyes, cute monster
a skeleton warrior holding a sword, fantasy monster
```

### Boss (une image chacun, « imposing, large »)
golem de pierre · liche · minotaure · kraken · dragon rouge · nécromancien · chevalier noir ·
démon · ogre · chimère · cerbère · dragon noir
```
Exemple de [SUJET] :
a massive stone golem boss, imposing, menacing
a red dragon boss, imposing, wings spread
```
(ajoute `imposing, large, menacing` au sujet.)

### Armes (objet seul — remplace `full body` par `single object`)
Pour chaque : génère la version **commune, rare, épique, légendaire** en changeant la fin.
- Guerrier : `a fantasy sword` / `a fantasy battle axe`
- Archer : `a fantasy longbow` / `a fantasy crossbow`
- Mage : `a fantasy magic staff` / `a fantasy wand`
```
Rareté → ajoute à la fin du [SUJET] :
commune    : , plain iron, simple
rare       : , fine steel with a soft blue glow
épique     : , ornate with a purple magical glow
légendaire : , golden legendary with a radiant aura and runes
```

### Bijoux & bottes (objet seul)
- `a fantasy amulet pendant` · `a fantasy talisman`
- `a fantasy ring` · `a magical gemstone`
- `a pair of leather boots`
(même échelle de raretés que les armes.)

### Consommables (objet seul)
- `a red healing potion bottle`
- `a rolled magic scroll`
- `a rolled bedroll sleeping bag`
- `a food ration, bread and cheese`

### Interface & effets (objet seul, `icon` plutôt que `full body`)
pièce d'or · cœur rouge · éclair d'énergie · icône carte · icône sac à dos · icône livre ·
boule de feu · entaille (slash) · étincelle de soin verte · explosion de montée de niveau dorée
```
Exemple de [SUJET] :
a shiny gold coin, game icon
a glowing fireball, game effect icon
```

### Props de décor (objet seul)
coffre fermé · coffre ouvert plein d'or · piège à pointes · autel lumineux · enseigne de boutique ·
feu de camp · tente · rondin · rochers · souche · panneau en bois · arbre stylisé · buisson ·
champignons · fougère · étal de marché · tonneaux · sacs · cristal lumineux · pilier de pierre ·
torche murale · stalactites de glace · chute de lave

---

## FONDS DE SCÈNE (prompt différent — paysage, bouclable)

Modèle à part (pas d'isolement ici, c'est une vraie scène) :
```
[LIEU], 2D side-scroller game background, side view, a clear flat empty walkable ground along the bottom, continuous horizon, empty center with no large object, soft painterly style, seamless left-right tiling, no characters, no text --style raw --no characters, people, creatures, text, watermark, blur --ar 16:9 --tile
```
Relance ensuite la même en **`--ar 9:16`** (portrait), en gardant `--tile`.

`[LIEU]` possibles :
- `a cozy forest camp clearing with a campfire and tents, warm safe mood`
- `a cozy medieval tavern interior, firelight, barrels, long tables, lanterns`
- `a lively medieval market street with colorful stalls and lanterns`
- `a sunny open field of golden wheat under a wide blue sky`
- `a dark damp cave with wet stone and moss`
- `a haunted forest with twisted purple trees, fog and fireflies`
- `a bone crypt with carved stone, skulls and flickering torches`
- `a blue ice cavern with frost and hanging icicles`
- `a volcano cavern with black rock and glowing red lava`
- `a wilderness dirt travel path with grass and distant hills`

---

## LOGO & ICÔNE
```
app icon for a fantasy RPG, a bold heroic emblem with a sword and shield, vibrant, simple, readable at small size, rounded square --style raw --no text, watermark --ar 1:1
```

---

### Récap des bons réflexes
1. **1 sujet = 1 image.** Jamais de liste de plusieurs trucs dans un prompt.
2. Garde le **`--no ...`** (c'est lui qui vire le flou et les armes en trop).
3. **Raw Mode ON** + stylize bas dans les réglages.
4. Une fois une image au bon style : récupère son **`--sref <url>`** et ajoute-le partout pour l'homogénéité.
5. Fond **blanc uni** pour les sprites → facile à détourer ensuite.
