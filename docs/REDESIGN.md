# CYBERSEEKER — REFONTE PRODUIT ET DESIGN

> Source de vérité de la refonte R23. Le GDD reste la référence gameplay ; ce
> document fixe l'exécution visuelle, l'UX et les critères qualité.

## Promesse

CyberSeeker est un jeu mobile de progression cyberpunk construit autour d'une
boucle immédiate : **spin → récompense → construction → collection → nouvelle
session**. La lisibilité et la gratification d'un jeu casual priment, avec une
identité originale qui ne reproduit aucun écran, asset ou marque de Coin Master.

## Piliers

1. **Un objectif toujours visible** — le prochain bâtiment, coffre, palier ou
   spin doit être compris en moins de trois secondes.
2. **Chaque action a du poids** — son, mouvement, lumière et haptique sont
   proportionnels à la rareté, sans ralentir les spins successifs.
3. **Le quartier se transforme** — toute dépense produit une évolution visuelle
   claire et permanente.
4. **Serveur souverain** — le client n'envoie que des intentions ; coûts,
   résultats, délais et récompenses sont calculés côté serveur.
5. **Mobile d'abord** — portrait 540×1170, zones tactiles ≥ 48 px, navigation à
   une main, contraste AA visé et animations compatibles appareils modestes.

## Identité visuelle

- Spin : ciel turquoise lumineux, nuages ivoire/lavande et cyber-ville cobalt en
  plein écran. Les écrans secondaires conservent leur profondeur cobalt.
- Surfaces de jeu : ivoire chaud `#FFF0C0`, contour bleu nuit et volumes cobalt.
- Accent primaire : cyan électrique `#2BE7FF`.
- Accent secondaire : magenta plasma `#FF45B5`.
- Récompense : or chaud `#FFD34E`; CTA Spin : corail `#FF4F46`; succès : vert
  menthe `#61ED91`.
- Texte principal : ivoire `#FFF8E8`; secondaire : bleu pâle `#B6C7EB`.
- Formes : volumes épais et arrondis, contours bleu nuit, anneaux et circuits
  simplifiés. L'interface doit évoquer un jouet arcade, jamais un dashboard.
- Mouvement : impulsion courte 120–220 ms, révélation 300–500 ms, aucun écran
  bloqué plus de 1,2 s hors célébration explicitement ignorable.

## Architecture UX

- **Spin** : scène casual plein écran, ressources flottantes, machine dominante à
  trois rouleaux ivoire, jauge intégrée, mascotte BYTE et gros CTA corail.
- **District** : cinq pads de construction, niveau/coût, progression globale.
- **Collection** : sets, cartes possédées, coffres et récompenses.
- **Missions** : bonus quotidien, missions et événement actif.
- **Store** : coffres en crédits, offres, publicité récompensée simulée en dev.

La barre inférieure conserve cinq destinations. Les overlays servent uniquement
aux résultats, confirmations et états bloquants ; la navigation reste disponible
après toute erreur récupérable.

## Tranche verticale de référence

Le standard qualité est atteint lorsque le joueur peut se connecter, effectuer
des spins, ouvrir le District 1, améliorer les cinq structures jusqu'au niveau 5,
recevoir une récompense de complétion une seule fois, ouvrir un coffre, compléter
une mission et réclamer son bonus quotidien sans valeur économique calculée par
le client.

## Critères d'acceptation transversaux

- Toutes les mutations utilisent `X-Request-Id` et une transaction atomique.
- Tous les montants, poids, limites et délais proviennent de `config/`.
- Les erreurs API utilisent le contrat `{error:{code,message,details?}}`.
- Aucun secret, JWT ou détail SQL n'est journalisé.
- Le mode dev est visible et impossible à activer dans un build release.
- Le client gère 401, 403, 409, 429, timeout et perte réseau.
- Les parcours critiques disposent de tests serveur automatisés.
- Les systèmes non raccordables localement (wallet Seeker, pub et paiement
  réels) possèdent une interface d'adaptation, un mode simulé et une checklist
  de validation sur appareil/service.

## Refonte slot R18

- La roue circulaire R17 est remplacée par une vraie machine à sous à trois
  rouleaux, avec une ligne de gain centrale immédiatement lisible.
- Quatre états ont été prototypés dans Figma : repos, rotation, anticipation et
  jackpot. Fichier source : `CyberSeeker — Slot Machine R18`, clé
  `btBFjxNk1ue6lWN1p0elWg`.
- La réponse du serveur reste souveraine. Le client traduit le tier en symbole
  visuel et ne calcule ni gain, ni coût, ni probabilité.
- Séquence : démarrage mécanique, défilement accélération/croisière/freinage,
  arrêts décalés, anticipation rare+, impact final, particules et quick stop.
- Le mode mouvement réduit raccourcit la séquence et supprime les secousses.

## Pipeline de rendu final R19

- Le rendu final 2.5D est produit dans Blender 5.2 LTS. Figma reste réservé à
  la composition UX et Tripo devient une source éventuelle de géométrie.
- Aucun GLB généré n'entre directement dans Godot : normalisation, matériaux,
  caméra orthographique, éclairage et export PNG passent par la scène maître.
- Le cabinet du slot est désormais un rendu Blender transparent superposé aux
  rouleaux Godot animés. Le rendu reste reproductible via
  `tools/render_2_5d/render.ps1`.
- Source : `art/blender/cyberseeker_slot_master.blend`.
- Staging : `art/render_2_5d/staging/slot_cabinet.png` (depuis R31, le runtime
  n'embarque que les assets WebP réellement référencés par le client).

## Extension visuelle R20

- Quatre dioramas Blender transparents habillent District, Collection, Missions
  et Store avec la même caméra, palette et lumière que le cabinet.
- BYTE, mascotte originale ronde et immédiatement lisible, devient le guide de
  l'onboarding. Sa scène source reste éditable dans Blender.
- Le shell partage une grille lumineuse animée, des halos très lents et des
  transitions d'onglets. Les héros respirent légèrement et les cartes entrent
  en cascade ; tous ces mouvements sont coupés par le réglage dédié.
- Pipeline reproductible : `tools/render_2_5d/render_screens.ps1`.
- Captures de contrôle : `captures/onboarding_runtime.png`,
  `captures/shell_runtime.png`, plus une capture par écran.

## Direction cyber-cartoon locale R21

- Le rendu final bascule vers une illustration 2D dessinée : contours bleu nuit
  épais, silhouettes massives, cel-shading limité, cobalt/cyan/magenta/or. Les
  anciens dioramas Blender restent des sources de secours, pas la cible runtime.
- L'usine `tools/ai_assets/generate.ps1` pilote FLUX.2 Klein 4B dans ComfyUI en
  local sur RTX, sans clé API ni service payant. Elle génère plusieurs candidats,
  sélectionne automatiquement, détoure, valide les dimensions et assemble
  l'atlas des six symboles.
- Dix-sept assets sont couverts : symboles, cabinet, BYTE, cinq héros/fonds,
  décor Neon Slums et trois caches. Une génération complète réussie promeut
  douze sorties atomiquement et sauvegarde les anciens fichiers runtime.
- Les textes, prix, compteurs et contrôles restent natifs Godot afin de préserver
  lisibilité, traduction et accessibilité. Aucun texte généré n'entre au runtime.
- Le vocabulaire visible privilégie l'action casual — SPIN, STOP NOW, ALMOST,
  YOU WIN, MEGA JACKPOT — plutôt que le jargon de terminal réseau.

## Rendu premium GPT Image R23

- La direction finale de l'écran Spin est une 3D stylisée cyber-cartoon de jeu
  mobile premium : volumes de jouet, contours cobalt, matières propres, lumière
  cyan/magenta/or et décor diurne immédiatement lisible.
- Le master et les composants de production sont générés séparément avec GPT
  Image intégré : fond, cabinet transparent, BYTE, bouton physique et six
  symboles transparents. Quatre héros dédiés étendent la direction aux écrans
  District, Cards, Quests et Shop. Le master sert de cible artistique, jamais
  de capture aplatie au runtime.
- Godot conserve les trois rouleaux vivants, les textes, compteurs, contrôles,
  états et animations. Les assets bitmap apportent la finition ; le moteur
  conserve l'interactivité, l'accessibilité et l'autorité du serveur.
- Le jeu reprend uniquement les principes génériques d'une boucle casual
  spin/construction/collection. Aucun personnage, logo, nom, écran ou asset de
  Coin Master n'est reproduit.
- Sources, rapport de dimensions et prompts : `art/api_gpt_image/`. Assets
  runtime : `client/assets/generated/api_gpt/`.

## Assets originaux actifs

- `client/assets/generated/api_gpt/spin_background.png`
- `client/assets/generated/api_gpt/slot_machine.png`
- `client/assets/generated/api_gpt/byte.png`
- `client/assets/generated/api_gpt/spin_button.png`
- `client/assets/generated/api_gpt/slot_symbols_atlas.png`
- `client/assets/generated/api_gpt/heroes/*.png`

## Assets historiques et secondaires

- `client/assets/generated/districts/neon_slums_bg.png`
- `client/assets/generated/onboarding/signal_gateway.png`
- `client/assets/generated/chests/basic_cache.png`
- `client/assets/generated/chests/neon_cache.png`
- `client/assets/generated/chests/black_ice_vault.png`
- `client/assets/generated/slot/slot_symbols_atlas.png`
- Généré et validé par l'usine locale décrite dans
  `tools/ai_assets/asset_manifest.json` ; les anciens fichiers `imagegen` sont
  conservés dans les sauvegardes de promotion et la documentation historique.
