# ASSETS R21 — PROMPTS DE PRODUCTION

## Source active : usine locale cyber-cartoon

La source de vérité exécutable est `tools/ai_assets/asset_manifest.json`. Le
runner `tools/ai_assets/generate.ps1` utilise FLUX.2 Klein 4B dans ComfyUI local,
génère deux variantes par asset, applique le détourage U²-Net, vérifie les
dimensions et la transparence, puis promeut le pack uniquement si la génération
complète est valide. Aucune API de génération ni manipulation dans un éditeur
graphique n'est requise.

Direction commune : illustration 2D mobile dessinée, contours bleu nuit épais,
formes massives, deux à quatre tons de cel-shading, cobalt/cyan/magenta/or,
silhouettes lisibles à petite taille, sans photoréalisme, brillant 3D générique,
texte, logo, marque, watermark, Viking, cochon, marteau ou couronne.

Les sections ci-dessous documentent les générations R18–R20 remplacées. Elles
restent utiles comme historique et référence de composition, mais ne pilotent
plus les assets runtime.

Mode utilisé : outil intégré `imagegen` (aucune clé API). Tous les assets sont
originaux, sans marque, texte, watermark ni reprise d'asset de Coin Master.

## Neon Slums

Décor mobile 9:16 d'un district cyberpunk « Neon Slums », mégalopole verticale
sous la pluie, cinq zones constructibles clairement séparées, marges HUD/navigation,
illustration 3D casual premium, palette cyan/magenta/ambre, sans personnage ni UI.

Sortie : `client/assets/generated/districts/neon_slums_bg.png`.

## Signal Gateway

Fond onboarding mobile 9:16, portail holographique abstrait au-dessus d'une
mégalopole néon, lower-third sombre et dégagé, style 3D mobile premium, ambiance
mystérieuse mais accueillante, sans personnage, texte, logo ni contrôle UI.

Sortie : `client/assets/generated/onboarding/signal_gateway.png`.

## Basic Cache

Icône carrée sur fond réellement transparent : coffre cyberpunk basique compact,
métal graphite usé, verrou circuit cyan, vue trois-quarts, silhouette lisible,
sans pièce, personnage, arme, texte, logo ni watermark.

Sortie : `client/assets/generated/chests/basic_cache.png`.

## Neon Cache

Icône carrée sur fond réellement transparent : coffre cyberpunk intermédiaire,
couvercle verre fumé facetté, coutures plasma magenta, verrou cyan et coins dorés,
vue trois-quarts, rendu 3D casual premium, sans texte, logo ni watermark.

Sortie : `client/assets/generated/chests/neon_cache.png`.

## Black ICE Vault

Icône carrée sur fond réellement transparent : coffre légendaire en alliage
obsidienne autour d'un cœur énergétique doré suspendu, glyphes cyan et halo
magenta, vue trois-quarts, silhouette monumentale, sans texte, logo ni watermark.

Sortie : `client/assets/generated/chests/black_ice_vault.png`.

## Atlas de symboles du slot

Mode : outil intégré `imagegen`, asset `stylized-concept`.

Prompt final :

> Use case: stylized-concept. Asset type: mobile game slot-machine symbol atlas.
> Primary request: create one polished sprite atlas containing exactly six
> original cyberpunk slot symbols arranged in a strict 3-column by 2-row grid.
> Scene/backdrop: genuinely transparent background. Subjects, in reading order:
> top-left a stack of glowing cyan credit chips; top-center a cyan hexagonal
> firewall shield; top-right a magenta hacker skull mask with circuit traces;
> bottom-left a premium black-and-gold high-security cyber vault; bottom-center
> an electric blue energy bolt in a compact power cell; bottom-right a fractured
> violet glitch crystal. Style/medium: high-end casual mobile game UI icons,
> glossy stylized 3D illustration, chunky readable silhouettes, beveled metal,
> neon edge lights, tactile toy-like finish, coherent CyberSeeker art direction.
> Composition/framing: square atlas, six equal invisible cells, one centered icon
> per cell, generous identical padding, consistent scale, no overlap, no cropping.
> Lighting/mood: dramatic studio rim light, luminous cyan/magenta/gold accents,
> deep material contrast. Constraints: exactly six icons; transparent background;
> no words, letters, numbers, logos, borders, grid lines, watermarks, characters,
> coins, slot cabinet or scenery. Each icon must remain readable at 96 px.

Sortie : `client/assets/generated/slot/slot_symbols_atlas.png`.

## Concept directeur GPT Image — écran principal v1

Mode : outil intégré `imagegen`, génération guidée par une capture Coin Master
utilisée uniquement comme référence de hiérarchie macro. Ce concept n'est pas un
asset runtime et ne reprend ni marque, personnage, icône ou forme propriétaire.

Prompt final condensé :

> Use case: ui-mockup. Asset type: shippable high-fidelity portrait mobile game
> home / slot screen concept. Imagine CYBERSEEKER as an original premium
> cyberpunk social slot-and-city-building mobile game. A large toy-like
> blue-and-gold cyber slot cabinet dominates the center; three tall readable
> reels show original energy cell, data vault, credit chip, shield drone and
> glitch portal symbols. BYTE, an original friendly round robot guide, reacts
> enthusiastically. Use polished casual mobile-game UI rendered in premium
> stylized 3D/2.5D, glossy rounded forms, warm gold rewards, bright cyan/magenta
> accents, cheerful rather than grim. Compose a 9:16 portrait screen with compact
> resources at top, clean timed-event badges, concise reward banner, central
> reels, energy meter, huge thumb-friendly SPIN button and five-icon bottom nav.
> Exact text: CYBERSEEKER, 8.5M CR, 47, NEON RUSH, +250K CR, SPIN. Original IP;
> no logos, trademarks, watermarks, copyrighted characters, pigs, foxes,
> hammers, crowns, Viking imagery, roulette wheel or desktop UI.

Sortie : `art/concepts/cyberseeker_gpt_image_direction_v1.png`.

### Variante v2 — cartoon dessiné

> Recomposer le même écran CyberSeeker en illustration 2D mobile dessinée à la
> main : contours bleu nuit épais et francs, volumes très lisibles, formes
> expressives, aplats et cel-shading limité à deux à quatre tons, petites
> irrégularités d'illustrateur, sans rendu 3D brillant ni surfaces lissées.
> Conserver machine centrale, BYTE, ressources, événements, jauge, gros bouton
> SPIN et navigation. Palette cobalt/cyan/magenta/or, cyberpunk lumineux.

Sortie : `art/concepts/cyberseeker_cartoon_direction_v2.png`.

### Variante v3 — pixel art natif

> Reconstruire tout l'écran CyberSeeker en vrai pixel art placé à la main sur
> une grille logique 360×640 puis agrandi par facteur entier : pixels carrés,
> aucun antialiasing, contours d'un à trois pixels, palette cohérente de trente-
> deux couleurs, dithering sélectif et silhouettes de sprites très nettes.
> Redessiner chaque élément ; ne pas appliquer un simple filtre de pixellisation.
> Conserver machine, BYTE, ressources, événements, jauge, SPIN et navigation.

Sortie : `art/concepts/cyberseeker_pixel_direction_v3.png`.
