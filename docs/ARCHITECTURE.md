# CYBERSEEKER — ARCHITECTURE TECHNIQUE R24

> État effectivement implémenté au 22/08/2026. Le code serveur constitue le
> contrat final ; les payloads détaillés sont dans `API_R17.md`.

## 1. Vue d'ensemble

CyberSeeker est un jeu mobile online-only. Godot rend l'interface et anime les
réponses ; le serveur Rust détient l'intégralité de l'économie.

```text
Godot 4.7.2
  └─ intentions HTTP + requestId
        └─ Axum 0.7
             ├─ config JSON validée et hashée
             ├─ transactions SQLx
             ├─ RNG système
             └─ PostgreSQL + audit économique
```

Règle fondamentale : le client ne décide jamais d'un résultat, d'un coût, d'une
récompense, d'une limite ou d'un timestamp. Toute valeur économique est relue
depuis la config serveur dans la transaction qui applique l'action.

## 2. Dépôt

```text
client/
  project.godot              autoloads et scène principale
  export_presets.cfg         preset Android arm64
  scenes/                    Main + six écrans
  scripts/core/              réseau, état, wallet, préférences, UI, audio
  assets/generated/          illustrations raster originales
  tests/                     smoke des scènes
server/
  src/                       Axum, auth, jeu, progression, live-ops, commerce
  migrations/                schéma initial, live-ops et invariants économiques
config/                      économie et contenu data-driven
docs/                        GDD, design, API, privacy, release et prompts
tools/                       validation complète et audit de l'économie
memory/                      contexte condensé de reprise
```

## 3. Client Godot

### Autoloads

- `Preferences.gd` : son, haptique, mouvement réduit et réglages locaux.
- `Net.gd` : file HTTP séquentielle, JSON, retry borné, refresh JWT et URL issue
  de `CYBERSEEKER_API_URL`.
- `Wallet.gd` : interface d'adaptation ; identité dev uniquement en mode dev.
- `Config.gd` : remote config typée avec dernier cache valide.
- `Store.gd` : cache d'affichage, mutations et horloge compensée serveur.
- `Sfx.gd`, `Haptics.gd`, `Events.gd` : feedbacks et analytics batchés.
- `Ui.gd` : design system cyberpunk partagé.

Les tokens restent en mémoire. Une persistance sécurisée ne sera activée qu'avec
le coffre-fort natif du bridge wallet. Le refresh est single-flight : les
requêtes 401 concurrentes réutilisent une rotation déjà terminée.

### Écrans

- `OnboardingScreen` : gateway visuelle, challenge et connexion.
- `SpinScreen` : orchestration du slot, multiplicateur data-driven, regen et résultats.
- `scripts/components/SpinVisuals.gd` : cabinet, reels, backdrop et particules sans réseau.
- `SpinNetworkView.gd`, `SpinNetworkActions.gd` : composition et mutations du
  Seeker Network isolées de la boucle de spin.
- `SpinEncounterView.gd` : overlays Attack/Raid sans calcul économique client.
- `DistrictScreen` : cinq éléments, six niveaux visuels chacun et upgrade.
- `CollectionScreen` : coffres, cartes, doublons, progression et claims de sets.
- `MissionsScreen` : daily, missions, événement, classement et saison.
- `StoreScreen` : offres, pub optionnelle et achats derrière adaptateurs.

`Main.gd` conserve la navigation cinq onglets. Le client peut réafficher son
cache, mais chaque retour d'action remplace les valeurs concernées par celles du
serveur.

## 4. Serveur Rust

- `auth.rs`, `db.rs` : challenge, nonce PostgreSQL single-use, signature,
  JWT access et refresh rotatif (`jti` hashé) avec bypass dev isolé.
- `spin.rs` : regen à reliquat conservé, multiplicateur, RNG et récompense idempotente.
- `district.rs` : coûts autoritaires, niveaux et complétion anti double-claim.
- `collection.rs` : achat/ouverture de coffres, loot pondéré, cartes et sets.
- `engagement.rs` : daily, missions, événements, leaderboard PostgreSQL et saison.
- `commerce.rs` : reçus de pub, catalogue d'offres éligibles, limites et preuve
  d'achat par provider.
- `social.rs` : Signal Jam, Ghost Vault, Firewalls, dégâts et réparations.
- `progression.rs`, `friends.rs` : Network Power, profils, amis, ciblage et revanche.
- `teams.rs` : roster, propriété, capacité et classement des crews.
- `trading.rs` : offres carte-contre-carte, réservations de doublons et transfert atomique.
- `reward_pool.rs` : ledger saisonnier futur, budget global verrouillé,
  allocations idempotentes et settlement interne sans route client.
- `game.rs` : helpers communs d'idempotence, récompense et tirage.
- `config.rs` : désérialisation typée, validation et distribution hashée.
- `state.rs` : agrégation de l'état complet du joueur.
- `rate_limit.rs` : fenêtre PostgreSQL atomique partagée entre instances.

Les classements, nonces et quotas API utilisent PostgreSQL. Redis n'est pas une
dépendance runtime actuelle ; il ne devient utile qu'en cas de charge nécessitant
un cache distribué spécialisé.

Les invariants relationnels interdisent également les rencontres auto-ciblées,
les statuts résolus sans timestamp, les fenêtres temporelles inversées et plus
d'un owner par équipe, même hors des handlers applicatifs.

## 5. API

### Publique

- `GET /health`
- `GET /ready`
- `GET /config`
- `POST /auth/challenge`
- `POST /auth/verify`
- `POST /auth/refresh`
- `POST /auth/logout`

### Authentifiée

- `GET /state`
- `POST /spin`
- `POST /district/upgrade`
- `POST /chest/buy`
- `POST /chest/open`
- `POST /set/claim`
- `POST /daily/claim`
- `POST /mission/claim`
- `GET /events/:event_id/leaderboard`
- `POST /events/:event_id/claim`
- `POST /season/claim`
- `POST /ad/reward`
- `POST /purchase/verify`
- `GET /offers`
- `POST /analytics`
- `GET|POST /profile`, `GET /players/search`, `GET /friends`
- `POST /friends/request|accept|decline|remove`, `POST /social/target`
- `GET /progression/leaderboard`
- `GET /teams`, `POST /teams/create|join|leave|kick|transfer`,
  `GET /teams/leaderboard`
- `GET /trades`, `POST /trades/create|accept|decline|cancel`

Chaque mutation économique porte un `requestId`. La clé d'idempotence est aussi
scopée par action afin qu'un même identifiant ne puisse pas rejouer une réponse
d'un autre endpoint.

## 6. Base de données

`0001_init.sql` installe joueurs, état, districts, cartes, sets, événements,
achats, idempotence, audit et analytics. `0002_progression_liveops.sql` ajoute les
tables de rétention. `0003_core_integrity.sql` impose les soldes/quantités
positifs et les références joueur sur les tables économiques historiques.
Les migrations `0006` à `0011` ajoutent les rencontres sociales, profils,
Network Power, amis, équipes, échanges de cartes et inventaires `BIGINT` adaptés
au multiplicateur maximal ×100K, le Signal Cache et la session précédente utile
aux offres de retour.

Toutes les mutations d'économie sont atomiques : verrou joueur, validation,
écriture d'état, audit et mémorisation de la réponse idempotente partagent la
même transaction.

## 7. Remote config

- `economy.json` : regen, plafonds, ladder de multiplicateurs, nouveaux joueurs
  et limites publicitaires.
- `spin_table.json` : outcomes et poids.
- `districts/district_01.json` : éléments, niveaux, coûts et récompense finale.
- `cards.json`, `sets.json`, `chests.json` : collection et loot.
- `daily.json` : cycle, Signal Cache pondéré et missions quotidiennes.
- `events.json`, `seasons.json`, `offers.json` : live-ops et commerce.
- `progression.json`, `social.json` : score global, Attack/Raid/Firewalls,
  équipes et règles d'échange.

Le serveur refuse le démarrage si les identifiants, poids, références, dates,
coûts, récompenses ou fenêtres de contenu sont incohérents.

## 8. Sécurité et résilience

- JWT production d'au moins 32 caractères ; `DEV_AUTH=true` interdit en release.
- Le secret d'exemple est également refusé en release ; `/ready` contrôle
  PostgreSQL et SIGTERM/Ctrl-C déclenchent un arrêt avec drainage Axum.
- CORS allowlist en production, permissif uniquement en dev.
- Corps HTTP limité à 256 Kio.
- Nonces PostgreSQL à usage unique, consommation atomique inter-instance,
  expiration et nettoyage périodique.
- Refresh tokens à usage unique, rotation PostgreSQL inter-instance et rejet du replay.
- Rate-limit PostgreSQL partagé et borné, sans confiance dans
  `X-Forwarded-For` non authentifié.
- Retry client limité aux GET et mutations idempotentes.
- Publicité et paiement refusés hors dev sans preuve provider valide.
- Reward pool et settlements désactivés par défaut ; aucune route client ne peut
  déclarer une allocation ou un payout.
- Aucun détail SQL n'est renvoyé au client.

## 9. Android

- Godot 4.7.2 stable et templates officiels vérifiés par SHA-512.
- JDK Temurin 17.
- Android Platform/Build Tools 36.
- APK arm64, min SDK 24, cible 36, permissions Internet et vibration.
- Artefact local : `client/build/android/CyberSeeker-debug.apk`.
- Signature debug RSA 2048 vérifiée par schémas APK v2 et v3.

Le keystore release, le Wallet Adapter, les providers, l'API HTTPS et le test sur
Seeker relèvent de la publication externe ; voir `RELEASE_CHECKLIST.md`.

## 10. Validation

`tools/validate_all.ps1` enchaîne audit économique, format/test Rust, import
Godot et smoke des scènes. Avec `-ApiBaseUrl` et
`-ApiSecondaryAuthBaseUrl`, il exerce aussi les contrats généraux puis un
playthrough social complet à deux joueurs sur deux instances DEV partageant la
base et le secret JWT. Ce mode HTTP est fail-closed si la seconde instance
manque. Le binaire serveur release et l'APK sont construits séparément afin que
leur production échoue explicitement si la configuration est impropre.

`tools/run_local_full_gate.ps1` est l'entrée mono-commande : build serveur debug,
deux ports contrôlés, deux processus cachés, readiness, `validate_all`, puis arrêt
garanti dans `finally`. Les identités et le secret JWT sont éphémères ; les logs
temporaires sont supprimés uniquement en cas de succès et conservés pour
diagnostic en cas d'échec. Aucun artefact Android n'est produit par cette gate.
