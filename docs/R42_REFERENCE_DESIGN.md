# R42 — refonte d'après la référence utilisateur

> Mise à jour R44 : la limitation de génération citée ci-dessous est historique.
> Tous les bâtiments sont maintenant remplacés : [livraison R44](R44_BUILDING_ART.md).

07/09/2026. La demande « repars à zéro tout l'aspect du jeu et fais ce design »
remplace le brief skyline jour jouet et la mise de côté du design. Le produit
conserve le nom CyberSeeker et son serveur R41. **Cette livraison n'est pas une
reproduction complète de chaque illustration du mockup, ni une version shippable.**

## Intégré dans le jeu

- Ville nocturne cyan/magenta, nouvelle machine cobalt, logo graffiti original
  CYBER SEEKER et atlas de douze icônes générés avec l'outil d'image intégré.
- Trois vrais rouleaux argentés, affichage de neuf symboles, arrêt décalé,
  anticipation, rebond, effets de résultat et réglage de mouvement réduit conservés.
- Bouton Spin doré, levier cliquable, mise sur plaque noire, vrais soldes,
  régénération et progression du village. Une mise ×4 reste une requête et une
  animation, pour quatre spins consommés par le serveur.
- Cadres à angles coupés, doubles filets cyan/magenta, boutons plus verts,
  navigation Map / Missions / Raid / Spin / Events / Clan.
- Boutique, cartes, coffres, quotidien, récompenses, saison et classement reliés
  aux écrans fonctionnels. Les bâtiments du bandeau ouvrent les améliorations.
- Thème global des six scènes, en-têtes illustrés, police Rajdhani Bold sous OFL,
  palettes et contrôles de village harmonisés. Nouvelles images en WebP avec alpha.
- Animation légère du logo ; les animations existantes des rouleaux, résultats,
  transitions, boutons et retours haptiques restent actives.

## Adaptations honnêtes au gameplay existant

- Le mockup montre des gemmes : le jeu n'en possède pas. La troisième ressource
  est le score de progression réel, avec un trophée, sans faux solde de gemmes.
- Firewall est un nombre de charges, pas une protection chronométrée fictive.
- Les événements actifs et délais viennent de l'état serveur ; un événement
  expiré n'est plus promu comme actif. Les rails récompenses/saison ne simulent
  pas un événement Coin Fever ou une progression Mega Chest inexistants.
- Le classement ouvre le classement réel ; aucun faux adversaire ou rang n'est
  affiché dans le bandeau d'accueil.
- Le jeu affiche « TAP TO SPIN » : maintien/autospin non implémenté dans ce lot.
  Les accès Raid indiquent le déclenchement requis, sans créer de raid gratuit.

## Corrections trouvées pendant l'intégration

- Les anciens symboles donnaient trois Raid pour un jackpot de crédits. Le
  symbole suit désormais le type serveur : pièces / raid / attaque / bouclier /
  coffre / carte. Les probabilités et montants ne changent pas.
- Les marges de StyleBox gonflaient les petites barres de progression.
- Les libellés de récompenses longs imposaient la largeur de l'écran. Les
  boutons passent maintenant à la ligne et les tests couvrent ce débordement.
- Les grilles générées ont des gouttières irrégulières : leurs régions sont
  mesurées pour éviter de montrer un morceau de l'icône suivante.
- Le texte est rendu sans les anciens contours superposés qui dégradaient sa
  netteté sur les captures mobiles.

## Restant pour atteindre toute la référence

- **Bloqué par quota de génération d'images** : nouvelles illustrations des
  bâtiments/stades et des coffres secondaires. L'essai d'atlas village a été
  refusé avec `usage_limit_reached`, sans produire d'image. Leurs assets existants
  sont conservés ; ne pas déclarer l'ensemble de l'art remplacé.
- Icônes dédiées roue Spin, clan et missions plus proches de la référence ; les
  icônes cohérentes disponibles sont réutilisées en attendant.
- Illustration de lancement et icônes de packaging encore héritées du lot
  précédent ; aucun nouvel export Android effectué pour ce travail visuel.
- Piggy Bank, gemmes, Coin Fever et Mega Chest : ce sont des mécaniques absentes
  ou différentes, pas des éléments à maquiller avec de faux compteurs.
- Autospin au maintien, si le périmètre gameplay est étendu à cette interaction.
- QA appareil physique : petits compteurs, safe areas réelles, toucher,
  performances et lisibilité. Le rendu dense du mockup n'est pas validé Seeker.

## Fichiers et reprise

`client/scripts/components/SpinHomeView.gd` compose l'accueil, sans mutations
économiques. `NeonSkin.gd` contient chrome, typographie et régions d'atlas.
`SpinScreen.gd` conserve la logique de jeu et descend à 687 lignes.

Sources et référence : `art/punk_city/`. Prompts : `art/punk_city/PROMPTS.md`.
Runtime : `client/assets/generated/punk_city/`. Huit anciens visuels et leurs
imports sont **déplacés, récupérables** sous `art/archive/r23-replaced/`.
Les essais préexistants skyline et `CaptureSpin.gd` ont été préservés.

Police officielle : [Rajdhani / Google Fonts](https://github.com/google/fonts/tree/main/ofl/rajdhani),
licence livrée avec le fichier. Les retours à la ligne utilisent le
[Button Godot natif](https://docs.godotengine.org/en/stable/classes/class_button.html#class-button-property-autowrap-mode).

## Validation

- Premier passage complet : `LOCAL_FULL_GATE_OK`, 44 tests Rust dont 16 PostgreSQL,
  API concurrente/idempotence, social à deux instances, six scènes aux trois
  formats 360×800, 540×1170, 720×1280.
- Gate complète rejouée après les corrections finales, notamment les longs
  libellés et la navigation. Les scènes QA sont isolées du réseau ; le runtime
  normal continue de synchroniser ses données. Un avertissement intermittent de
  fermeture a été identifié comme AudioStreamWAV/AudioStreamPlaybackWAV du dernier
  clic : arrêt et libération du pool audio, puis drainage du mixeur dans le test.
  `git diff --check` réussi.
- Tests ajoutés : mapping des symboles, trois rouleaux, cinq bâtiments, cycle de
  mise et fallback, bounds des contrôles, événement expiré, navigation six tabs
  et débordements des écrans secondaires.
- Captures réelles Godot : `captures/r42-*-540.png`,
  `captures/r42-home-1024x1536.png`, `captures/r42-home-540x1170.png`,
  `captures/r42-home-360x800.png`. Données QA explicites ; aucun montage de mockup
  présenté comme runtime.
- Aucun APK/AAB, changement wallet ou migration SQL dans ce lot.
