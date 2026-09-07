# MÉMOIRE — ARCHITECTURE (CONDENSÉ R17)

> Détail : `docs/ARCHITECTURE.md`. Contrats : `docs/API_R41.md`. Le code
> serveur reste l'autorité en cas de divergence documentaire.

## Stack et règle d'or

- Client : Godot 4.7.2, GDScript, portrait 540×1170, rendu Compatibility,
  Nunito ExtraBold MSDF, textures Linear+mipmaps.
- Serveur : Rust, Axum 0.7, SQLx 0.8 et PostgreSQL.
- Config : JSON validé au boot et distribué avec version + SHA-256.
- Le client envoie des intentions et anime la réponse. RNG, soldes, coûts,
  récompenses, limites et horloge restent exclusivement côté serveur.

## Client

- Autoloads : `Preferences`, `Net`, `Wallet`, `Config`, `Store`, `Sfx`,
  `Haptics`, `Events`.
- `Net` lit `CYBERSEEKER_API_URL`, sérialise les requêtes, rafraîchit le JWT et
  retente une fois les GET/mutations idempotentes.
- Navigation : Spin, District (diorama pads 2.5D), Cards, Missions et Store.
- Les six scènes représentatives sont fumées par `client/tests/SmokeScenes.gd`.
- Les tokens ne sont pas persistés avant raccordement d'un coffre-fort mobile.

## API autoritaire

- Auth : `/auth/challenge`, `/auth/verify`, `/auth/refresh`, `/auth/logout`.
- Lecture : `/health`, `/ready`, `/config`, `/state`, `/offers`, `/friends`,
  `/players/search`, `/teams`, `/teams/leaderboard`, `/trades`,
  `/progression/leaderboard`, `/events/:event_id/leaderboard`.
- Économie : `/spin`, `/district/upgrade`, `/chest/buy`, `/chest/open`,
  `/set/claim`, `/daily/claim`, `/daily/bonus/claim`, `/mission/claim`,
  `/district/repair`, `/attack/resolve`, `/raid/pick`, `/raid/cashout`,
  `/profile`, `/friends/*`, `/social/target`, `/teams/*`, `/trades/*`,
  `/events/:event_id/milestones/:milestone_index/claim`,
  `/events/:event_id/claim`, `/season/claim`, `/ad/reward`,
  `/purchase/verify`, `/analytics`.
- Aucune route client d'ownership NFT ni de payout reward pool (fail-closed).
- Chaque mutation économique reçoit un identifiant d'idempotence et relit la
  config côté serveur dans une transaction atomique.

## Données

- `0001_init.sql` : joueurs, état, progression, cartes, sets, événements,
  achats, idempotence, audit et analytics.
- `0002_progression_liveops.sql` : daily, missions, coffres, événements/saisons
  et champs de progression R17.
- `0003_core_integrity.sql` : soldes/quantités non négatifs et relations joueur.
- `0004_event_milestones_cohorts.sql` : cohortes de classement et claims de
  milestones événementiels.
- `0005_analytics_batches.sql` : déduplication atomique des batches analytics.
- `0006_social_encounters.sql` : Firewalls, dégâts de district et rencontres
  Attack/Raid pending avec plateau Raid secret.
- `0007_profiles_friends_progression.sql` : profils, codes amis, demandes,
  amitiés, cibles sociales et score global décomposé.
- `0008`→`0015` : crews/trading, inventaire `BIGINT`, Signal Cache, éligibilités
  d'offres, événements d'équipe, achievements et progression, entitlements.
- `0016_distributed_guards.sql` : `auth_nonces` et `api_rate_limits` atomiques,
  partagés entre instances.
- `0017_reward_pool_ledger.sql` : allocations et settlements SKR (désactivés).
- `0018_refresh_rotation.sql` : `refresh_sessions`, `jti` hashé, usage unique.
- `0019_relational_invariants.sql` : anti auto-ciblage, cohérence
  statut/timestamp des rencontres et trades, un seul owner par équipe.
- Configs typées : économie, roue, district, cartes, sets, coffres, daily,
  missions, événements, saisons et offres.

## Sécurité production

- JWT HS256 avec secret production d'au moins 32 caractères.
- `DEV_AUTH=true` refusé par le binaire release.
- CORS permissif uniquement en dev ; allowlist en production.
- Limite de corps 256 Kio, rate-limit, expiration des nonces et nettoyage de
  l'idempotence.
- Pub et paiement ne créditent rien hors dev sans preuve validée par provider.
- Les headers d'IP transférée non fiables ne servent pas d'identité sécurité.

## Livraison locale

- Serveur : `server/target/release/cyberseeker-server.exe`.
- Android : `client/build/android/CyberSeeker-debug.apk`, arm64, signé debug,
  signature v2/v3 vérifiée.
- Publication : keystore release, Wallet Adapter, providers, HTTPS et QA Seeker
  sont des dépendances externes listées dans `docs/RELEASE_CHECKLIST.md`.
