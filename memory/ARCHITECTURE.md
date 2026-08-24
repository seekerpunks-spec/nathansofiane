# MÉMOIRE — ARCHITECTURE (CONDENSÉ R17)

> Détail : `docs/ARCHITECTURE.md`. Contrats : `docs/API_R17.md`. Le code
> serveur reste l'autorité en cas de divergence documentaire.

## Stack et règle d'or

- Client : Godot 4.7.2, GDScript, portrait 540×1170, rendu Compatibility.
- Serveur : Rust, Axum 0.7, SQLx 0.8 et PostgreSQL.
- Config : JSON validé au boot et distribué avec version + SHA-256.
- Le client envoie des intentions et anime la réponse. RNG, soldes, coûts,
  récompenses, limites et horloge restent exclusivement côté serveur.

## Client

- Autoloads : `Preferences`, `Net`, `Wallet`, `Config`, `Store`, `Sfx`,
  `Haptics`, `Events`.
- `Net` lit `CYBERSEEKER_API_URL`, sérialise les requêtes, rafraîchit le JWT et
  retente une fois les GET/mutations idempotentes.
- Navigation : Spin, District, Cards, Missions et Store.
- Les six scènes représentatives sont fumées par `client/tests/SmokeScenes.gd`.
- Les tokens ne sont pas persistés avant raccordement d'un coffre-fort mobile.

## API autoritaire

- Auth : `/auth/challenge`, `/auth/verify`, `/auth/refresh`.
- Lecture : `/health`, `/config`, `/state`, `/events/:event_id/leaderboard`.
- Économie : `/spin`, `/district/upgrade`, `/chest/buy`, `/chest/open`,
  `/set/claim`, `/daily/claim`, `/mission/claim`,
  `/events/:event_id/milestones/:milestone_index/claim`,
  `/events/:event_id/claim`, `/season/claim`, `/ad/reward`,
  `/purchase/verify`, `/analytics`.
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
