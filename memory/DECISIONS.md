# MÉMOIRE — DÉCISIONS

> Décisions structurantes prises sur le projet. **Ne pas les rouvrir sans demande explicite de l'utilisateur.** Si une décision change, mettre à jour ce fichier + le fichier mémoire concerné.

## Validées par l'utilisateur
| # | Décision |
|---|---|
| D1 | Moteur : **Godot 4** (texte pur → buildable par IA, gratuit, export Android) |
| D2 | Backend : **Rust (Axum) + PostgreSQL** ; Redis seulement si la charge future justifie un cache distribué |
| D3 | **Login wallet obligatoire** (pas de guest) — c'est un téléphone lié à une crypto |
| D4 | **Pas de mode offline** — écran "no network" propre |
| D5 | Paiements SKR : **transfert SPL → trésorerie, vérifié on-chain serveur** |
| D6 | **0 budget** — outils gratuits, free-tier cloud, art original via imagegen intégré et SVG/code natif |
| D7 | **Qualité exigée haute** : bon jeu, juice/art/équilibrage soignés — pas un prototype moche |
| D8 | **Pas une copie de Coin Master** : noms, personnages, écrans, collections, brandings originaux |
| D9 | Pas de marketplace, cash-out ou NFT par carte. Le refus historique de tout trading est remplacé par D11/T29 pour autoriser uniquement le swap social non financier de doublons. |
| D10 | Carte blanche donnée aux agents IA pour builder ("carte blanche", "GO") |
| D11 | Exécuter tout le MASTER TODO avec une boucle fidèle aux sensations Coin Master mais contenu original ; design et wallet natif différés temporairement |

## Décisions techniques (agents)
| # | Décision | Raison |
|---|---|---|
| T1 | UI Godot **construite en code** dans `_build()` ; `.tscn` = racine Control + script | Le code GDScript reste lisible, testable et cohérent avec le design system partagé |
| T2 | Viewport 540×1170 (demi 1080×2340), `gl_compatibility`, portrait | Mobile-safe, léger |
| T3 | `Ui` = class_name statique, pas un autoload | Pas d'état, pas besoin de node |
| T4 | Slot = trois `SlotReel` dessinés en code avec atlas original 3×2 ; le résultat économique serveur est traduit en combinaison visuelle, quick stop au tap | Lecture immédiate type machine à sous sans déplacer l'autorité économique vers le client |
| T5 | SFX **synthétisés en code** (AudioStreamWAV int16 22050 Hz, sin/carré/scie), échelonnés par rareté | 0 asset pour le M1, déjà satisfaisant |
| T6 | Horloge compensée : `serverTimeMs` sur `/state` + `/spin` → `Store.clock_offset_ms` ; tous les compteurs via `Store.now_ms()` | Pas de drift client/serveur sur regen/countdowns |
| T7 | JSON via `JSON.new().parse()` + `get_data()` | Compatible tout Godot 4.x (évite l'API 4.3-only) |
| T8 | La roue reste crédits + glitch ; coffres/cartes passent par leurs routes dédiées | Boucles séparées, probabilités et audit plus faciles à comprendre |
| T9 | Configs de contenu JSON typées, fichiers plats par famille sauf districts | Petit catalogue R17, validation croisée au boot |
| T10 | Idempotence : `requestId` (header `x-request-id` + body) ; rejeu stocké DANS la tx du spin, re-lecture sous row lock | Pas de double-spend même en race |
| T11 | Rate-limit borné en mémoire et leaderboard dans PostgreSQL pour R17 | Une seule instance suffit au lancement ; Redis reste une optimisation de scale |
| T12 | Dev bypass `DEV_AUTH=true` + `DEV_ADDRESS=dev-player-0001` + signature `"dev"` | Dev desktop sans wallet ; à JAMAIS activer en prod |
| T13 | Analytics batchés côté client (10 / 15 s / fermeture, cap 100, horloge serveur) | GDD §41, léger |
| T14 | Fichiers mémoire condensés dans `memory/` (GDD, ARCHITECTURE, DECISIONS, CURRENT_STATE, TODO) | Reprise rapide après reset de contexte — **à maintenir à chaque changement significatif** |
| T15 | `Net.gd` réécrit contre l'API HTTPRequest **vérifiée dans la doc officielle Godot 4.7** (`request_raw(url, headers, method, PackedByteArray)` + `await _http.request_completed` → `[result, response_code, headers, body]`), file d'attente interne 1 requête à la fois, timeout 15 s, `DEBUG` gate | Les 3 drafts HTTPClient ont échoué chez l'utilisateur ; `request()` prend du `String` pas du `PackedByteArray` d'où le choix `request_raw` ; 1 nœud HTTPRequest = 1 requête max à la fois (doc) |
| T16 | Cinq onglets fixes : Spin, District, Cards, Missions, Store | Les boucles principales restent accessibles en un tap |
| T17 | Toute mutation R17 est idempotente et scopée par action | Évite rejouage croisé, double dépense et double claim |
| T18 | Commerce via adaptateurs ; simulation uniquement quand le serveur est explicitement en dev | Aucun crédit production sur une déclaration client |
| T19 | APK local via template officiel Godot précompilé, arm64, min 24 / cible 36 | Build reproductible sans embarquer un projet Gradle inutile |
| T20 | Figma sert de source de vérité visuelle R18 avec quatre états (idle/spinning/anticipation/jackpot), puis exécution native Godot | Séparer clairement rythme/hiérarchie visuelle et implémentation runtime |
| T21 | Rendu final R19 = Blender 5.2 LTS ; Tripo fournit seulement de la géométrie source, puis Blender impose caméra, lumière, matériaux et export PNG 2.5D | Coin Master repose sur une présentation 2D/2.5D ; une pipeline de rendu contrôlée donne cohérence et performance mobile sans imposer une scène 3D temps réel |
| T22 | Aucun APK/AAB pendant les itérations de design ; validation par Godot desktop, captures et smoke-tests, puis build unique à la gate shippable | Un export Android n'apporte aucune information utile tant que le contenu et l'UX ne sont pas verrouillés |
| T23 | Multiplicateurs `[1,2,3,4,5,10,20,50,100,250,500,1000,2500,5000,10000,25000,50000,100000]`; une seule animation, débit/progression de N, gain de base ×N, probabilités inchangées | Contrat utilisateur et intégrité économique serveur |
| T24 | Le district actif est le premier district non complété ; les prérequis forment une chaîne contiguë et la récompense de complétion est unique | Progression lisible et extensible, fidèle à une boucle de villages sans laisser le client choisir un district verrouillé |
| T25 | Classements événementiels en cohortes configurables, attribution sérialisée et rang `DENSE_RANK`; milestones configurables auto/manuels et idempotents | Évite un classement mondial illisible, traite correctement les égalités et sécurise chaque récompense |
| T26 | Les 25 événements funnel sont vérifiés statiquement ; les batches analytics ont un `batchId` stable et sont dédupliqués en PostgreSQL | Les retries réseau ne gonflent pas les métriques et les données sont bornées avant insertion |
| T27 | Paire sociale = Signal Jam (dégât réparable, Firewall auto) + Ghost Vault (six nœuds, trace, cash-out), cible rival ou NEON CORP fallback | Deux sensations distinctes, quelques secondes, scaling multiplicateur, interaction sociale et économie contrôlée sans copier les mini-jeux de Coin Master |
| T28 | Score global `Network Power` dérivé de quatre composantes configurables ; identité sociale par code ami, sans exposer l'adresse complète ; ciblage ami/revanche consommé au prochain Signal Jam | Évite la dérive d'un compteur client, fournit prestige/matchmaking, garde le social léger et empêche le ciblage arbitraire de joueurs |
| T29 | Crews limités à 50, sans chat/donation au premier lot ; échange direct 1-pour-1 réservé aux amis et aux doublons, un exemplaire toujours conservé, raretés data-driven avec légendaires verrouillées | Reproduit les leviers de coopération/collection attendus sans créer marketplace, transfert libre de richesse, modération lourde ou exposition SKR |

## Noms / brandings (à verrouiller — O1 GDD)
- Jeu : **CyberSeeker** (provisoire, utilisé partout pour l'instant).
- Monnaie interne : "credits" (CR) dans l'UI (provisoire — candidates : Neon Credits / Cyber Credits / City Coins).
- Wallet de trésorerie SKR : à définir (O6).
