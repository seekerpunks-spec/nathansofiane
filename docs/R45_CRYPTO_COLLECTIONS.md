# R45 — Collections crypto

Livraison et vérification finale : 09/09/2026.

## Périmètre livré

- Bouton COLLECTION à la place de RAID dans la navigation inférieure. Les encounters Raid restent déclenchés par les résultats de spin.
- Cinq collections de neuf cartes : Layer 1, Genesis Crew, DeFi District, Web3 Culture, Class of 2017.
- 45 scènes illustrées originales dans cinq atlas WebP, avec noms et logos crypto rendus séparément pour garder les symboles lisibles.
- Albums accessibles directement ; section CHESTS distincte pour acheter et ouvrir les coffres avec les crédits du jeu.
- Progression par album, rareté, quantité, doublons, aperçu agrandi, cartes manquantes consultables et prérequis visibles.
- Ouverture de coffre illustrée avec distinction NEW CARD / DUPLICATE et animation respectant les préférences de mouvement.
- Récompenses existantes conservées : spins seuls, spins et crédits, puis spins/crédits/coffre. Claim serveur unique, état déjà réclamé visible et panneau de confirmation.

## Compatibilité et fiabilité

Pas de migration SQL ni de remise à zéro. Tous les cardId, setId, rattachements,
raretés, dropWeight, récompenses et conditions de déblocage existants sont
conservés. Les anciennes cartes changent d'apparence et de nom ; elles ne sont
pas ajoutées une seconde fois. Les doublons, échanges et claims historiques
restent rattachés aux mêmes identifiants.

Les métadonnées symbol/image/imageIndex/logo traversent la configuration Rust
typée et GET /config. Les anciennes configurations sans illustration restent
désérialisables. Les chemins externes/traversants et indices d'atlas invalides
sont refusés.

Correction supplémentaire : une réponse chest/open contient les cartes tirées
avec leurs quantités absolues, et non l'inventaire entier. Le client fusionne
désormais ces lignes au lieu de masquer les cartes non tirées si GET /state
échoue ensuite. Le stock de coffres et les claims confirmés sont mis à jour
localement ; le rejeu n'ajoute pas une seconde quantité. Le serveur reste
l'autorité et un échec de resynchronisation est signalé à l'écran.

## Validation

Commande : tools/run_local_full_gate.ps1, sans option BuildAndroid.

- LOCAL_FULL_GATE_OK, CYBERSEEKER_VALIDATION_OK.
- 46 tests Rust réussis ; 16/16 tests PostgreSQL réellement exécutés.
- Contrats API et sociaux réussis, dont échanges et idempotence.
- CRYPTO_CONFIG_CONTRACT_OK : 45 cartes et cinq albums réellement servis par GET /config.
- Six scènes Godot testées à 360×800, 540×1170 et 720×1280.
- Tests client ajoutés : navigation COLLECTION, assets des 45 cartes, sélection des cinq albums, vue coffres, indices invalides, fusion de l'inventaire sans resynchronisation et rejeu des résultats.
- Sept captures finales contrôlées : les cinq albums, carte agrandie, ouverture de coffre ; aucun stderr Godot. Les images de QA utilisent un état fictif et ne modifient pas le compte du joueur.
- Budget total d'assets constaté : 14,45 Mo ; cinq atlas runtime totalisant environ 3,91 Mio.
- git diff --check sans erreur.

Journaux et captures locaux (ignorés par Git) : captures/r45-resume-gate.log,
captures/r45-layer1.png, r45-genesis.png, r45-defi.png, r45-culture.png,
r45-nostalgia.png, r45-detail.png, r45-drops.png.

## Assets et limites

[Catalogue complet, mapping des IDs, sources et prompts](../art/crypto_cards/README.md).
Génération via l'outil image intégré, sans fallback API/CLI payant.
Sources PNG : art/crypto_cards/source/. Runtime : client/assets/generated/crypto_cards/.
Logos et licence amont : client/assets/crypto_logos/.

Ces cartes sont des objets de jeu, pas des actifs crypto. Les noms historiques
ne prétendent pas décrire le statut actuel des projets. Aucune affiliation aux
marques représentées. Pas de wallet, transaction on-chain, APK/AAB ni validation
sur appareil physique dans ce lot.
