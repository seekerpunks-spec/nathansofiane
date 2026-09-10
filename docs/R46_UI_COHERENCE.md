# R46 — Cohérence visuelle des écrans et nouvelle MAP

## Livraison — 10 septembre 2026

Passe visuelle locale, sans APK/AAB ni changement des règles économiques.
Les modifications serveur/quota déjà présentes avant ce lot sont conservées.

### Écrans et fenêtres

- MAP : place nocturne dédiée, placement 2–1–2 des bâtiments, illustrations agrandies, plateformes de sélection, fiche d'amélioration compacte. Les 25 bâtiments et leurs évolutions R44 restent utilisés.
- MAP / Build Bay : aperçus agrandis, même cadre de fenêtre, actions toujours liées au devis serveur.
- MAP / Districts : aperçus composés avec les vrais bâtiments de chaque district et le nouveau décor, statuts de déblocage et récompenses conservés.
- MAP / Complétion : trophée, récompenses et transition conservés dans la fenêtre commune.
- Missions : pages Daily, Events, Season, Settings ; bonus et événements illustrés. Les accès du bas ouvrent effectivement la bonne page.
- Réglages : grandes commandes ON/OFF pour son, vibrations et mouvement réduit.
- Boutique : bannières énergie, offres et collection ; états vide et offre active contrôlés.
- Réseau : pages Profile, Friends, Crew, Trades, Rank ; champs et listes déroulantes thémés, actions de taille tactile, noms longs enveloppés.
- Attack / Raid : choix illustrés en grille, cases ouvertes différenciées, montant non encaissé lisible, résultat dédié après résolution.
- Classements événement/global : lignes de classement lisibles, noms et scores séparés.
- Énergie vide, connexion réseau et erreur hors-ligne : habillage commun et actions explicites.
- Collection : albums et illustrations R45 conservés ; détails de carte, ouverture de coffre et complétion utilisent le cadre commun. Quatre nouvelles illustrations de coffres remplacent l'ancien style.
- Accueil Spin et onboarding : conservés car déjà conformes au thème ; onboarding vérifié en capture.

### Robustesse UX

Fenêtres à contenu défilant avec fermeture fixe au-dessus de la navigation,
safe areas existantes préservées, groupe Retour Android commun. Le chargement
du réseau ne rouvre plus sa fenêtre si elle a été fermée avant la réponse.
Un résultat d'attaque remplace maintenant la grille au lieu d'être ajouté sous
celle-ci. Les callbacks d'erreur ne réutilisent plus une boîte déjà libérée.

Les tests de retour, pages, largeur des contenus et taille des actions sociales
sont ajoutés au smoke test. La gate statique compte les appels à la factory
commune plutôt que d'exiger sept copies du même code de fermeture.

## Validation

- Gate complète : LOCAL_FULL_GATE_OK, 47 tests Rust réussis (16 PostgreSQL),
  contrats API et sociaux réussis.
- Smoke : 6 scènes, formats 360×800, 540×1170, 720×1280.
- Captures locales dans captures/r46-*.png : MAP et ses trois fenêtres,
  quatre pages Missions, boutique vide/avec offre, cinq pages réseau,
  attaque/raid/résultat/énergie/chargement, classement événement,
  albums/coffres/détails/drops, onboarding/hors-ligne.
- Contrôles supplémentaires en petit format : MAP, Crew, Raid ; district 5
  avec bâtiments au niveau maximum.
- Pas de validation sur appareil Android physique ; ce lot ne constitue pas
  une validation de sortie en production.

## Assets

Générateur intégré imagegen (pas de CLI/API externe). Aucune version de modèle
n'est imposée par le code du jeu. Conversion PNG → WebP avec l'outil Godot
existant, mipmaps conservées. Les images ne sont pas des captures interactives :
les textes et boutons restent de vrais contrôles Godot.

- Source MAP : art/punk_city/map_plaza.png
- Runtime MAP : client/assets/generated/punk_city/map_plaza.webp
- Sources coffres : art/punk_city/{basic_cache,neon_cache,quantum_cache,black_ice_vault}-r46.png
- Runtime coffres : client/assets/generated/chests/{basic_cache,neon_cache,quantum_cache,black_ice_vault}.webp
- Anciennes illustrations de coffres conservées dans art/punk_city/legacy_chests_r45/
- Référence de style : art/punk_city/reference.png

### Prompt MAP

Use case: stylized-concept. Asset type: production mobile game MAP background, portrait 1024x1536. Style reference: Punk City screenshot provided, only use its cartoon cyberpunk materials and cyan purple lighting, NOT its UI. Create an empty elevated cyberpunk city plaza at night, three-quarter isometric view. Dark navy metallic tiled ground with polished blue reflections, neon cyan and magenta trim, chunky clean cartoon outlines, premium mobile-game painted 3D look. Distant tightly packed futuristic skyline only along the upper 15% and outermost sides. The center is an open uncluttered construction plaza where the game will overlay five building sprites. NO buildings on the foreground plaza, NO circular construction pads, NO numbers, NO text, NO buttons, NO UI, NO trees, NO grass, NO daylight, NO fog covering ground. Ground spans nearly the entire image with perspective connecting walkway seams, subtle outer railings, a few small futuristic lamps only at the edges. Clear center suitable for placing buildings in a 2-1-2 arrangement. Avoid huge bloom, microdetail or photorealism.

### Prompts coffres

#### basic

Use case: stylized-concept. Asset type: one square production game loot-chest illustration, 1024x1024. Image 1 is a STYLE REFERENCE ONLY: match the chunky polished cartoon 3D look of the Punk City chest, cyan purple materials and strong readable silhouettes. Subject: BASIC CACHE: a simple compact steel-blue treasure chest, angular bevels, two cyan light strips, small square digital lock, modest rarity. Composition: ONE CLOSED chest centered, three-quarter front view, entirely visible, occupying 80% of width and 65% of height. Plain uniform dark navy background #061224, no floor or horizon. Thick clean outlines, crisp bevel highlights, restrained soft neon glow, glossy premium mobile game rendering. No UI, no text, no letters, no characters, no coins, no checkerboard, no watermarks, no labels. Keep details bold enough for 140-pixel presentation.

#### neon

Use case: stylized-concept. Asset type: one square production game loot-chest illustration, 1024x1024. Image 1 is a STYLE REFERENCE ONLY: match the chunky polished cartoon 3D look of the Punk City chest, cyan purple materials and strong readable silhouettes. Subject: NEON CACHE: a premium rounded purple and cobalt treasure chest, heavy polished ribs, vivid cyan light strips and magenta accents, circular cyan digital lock. Composition: ONE CLOSED chest centered, three-quarter front view, entirely visible, occupying 80% of width and 65% of height. Plain uniform dark navy background #061224, no floor or horizon. Thick clean outlines, crisp bevel highlights, restrained soft neon glow, glossy premium mobile game rendering. No UI, no text, no letters, no characters, no coins, no checkerboard, no watermarks, no labels. Keep details bold enough for 140-pixel presentation.

#### quantum

Use case: stylized-concept. Asset type: one square production game loot-chest illustration, 1024x1024. Image 1 is a STYLE REFERENCE ONLY: match the chunky polished cartoon 3D look of the Punk City chest, cyan purple materials and strong readable silhouettes. Subject: QUANTUM CACHE: a rare angular violet futuristic treasure chest, faceted crystal inset in the lid, luminous turquoise circuit seams, bright geometric quantum lock. Composition: ONE CLOSED chest centered, three-quarter front view, entirely visible, occupying 80% of width and 65% of height. Plain uniform dark navy background #061224, no floor or horizon. Thick clean outlines, crisp bevel highlights, restrained soft neon glow, glossy premium mobile game rendering. No UI, no text, no letters, no characters, no coins, no checkerboard, no watermarks, no labels. Keep details bold enough for 140-pixel presentation.

#### elite

Use case: stylized-concept. Asset type: one square production game loot-chest illustration, 1024x1024. Image 1 is a STYLE REFERENCE ONLY: match the chunky polished cartoon 3D look of the Punk City chest, cyan purple materials and strong readable silhouettes. Subject: BLACK ICE VAULT: legendary massive obsidian and black-purple treasure chest, chunky gold corner armor, magenta illuminated seams, a golden crowned digital padlock. Composition: ONE CLOSED chest centered, three-quarter front view, entirely visible, occupying 80% of width and 65% of height. Plain uniform dark navy background #061224, no floor or horizon. Thick clean outlines, crisp bevel highlights, restrained soft neon glow, glossy premium mobile game rendering. No UI, no text, no letters, no characters, no coins, no checkerboard, no watermarks, no labels. Keep details bold enough for 140-pixel presentation.
