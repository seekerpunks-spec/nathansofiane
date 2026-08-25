# MÉMOIRE — ÉTAT ACTUEL R25

> MAJ 25/08/2026. R25 reprend le lot R24 laissé inachevé (limite quotidienne de
> l'agent précédent). Design final et wallet natif restent gelés ; aucun build
> Android avant la gate shippable.

## Lot R25

- **Gate sécurité réparée (root cause)** : `tools/security_check.ps1` faisait
  `$auth.Split("#[cfg(test)]")` — PowerShell résout la surcharge `char[]`, donc
  le runtime analysé était tronqué à `"//! Au"` (6 caractères sur 10 802).
  Conséquences : le check de rotation de refresh échouait toujours (le code
  était correct) et les deux checks négatifs (interdiction `to_lowercase` sur
  Base58, interdiction de nonce en mémoire) étaient des no-ops silencieux.
  Corrigé en `-split '#\[cfg\(test\)\]'` + garde-fou de longueur. Aucune
  violation réelle n'était masquée (vérifié après correction).
- `tools/validate_all.ps1` repasse **CYBERSEEKER_VALIDATION_OK**.

## Validation exécutée R25

- `cargo check --locked --all-targets` : OK.
- `cargo fmt --check` : OK ; `cargo test` : **28/28** (dont intégrations
  PostgreSQL : nonce single-use, rate limit partagé, rotation refresh
  concurrente, auto-ciblage/double owner refusés, budget reward pool,
  entitlements expirés, regen non persistée).
- `economy_check` : 277 605 CR équivalents/spin, 9,4 % de spins vides,
  233,5 spins pour District 1 et 501,8 pour District 2.
- `analytics_check` : 53/53 événements. `security_check` et `mobile_ux_check` : OK.
- Import Godot + smoke `SMOKE_SCENES_OK: 6` aux ratios 360×800, 540×1170 et
  720×1280.

## Périmètre livré (cumul R17→R25)

Slot autoritaire ×1→×100K, regen serveur, 2 districts séquentiels (5 éléments ×
30 niveaux), collection 8 cartes / 2 sets / 3 coffres, daily streak + Signal
Cache, missions, moteur d'événements (Neon Rush individuel + Crew Uplink coop),
milestones auto/manuels, leaderboards en cohortes `DENSE_RANK`, boucle sociale
Signal Jam / Ghost Vault / Firewalls, Network Power, amis + revanche, crews,
trading 1-pour-1 de doublons, achievements, offres/pub/season pass derrière
provider, entitlements NFT fail-closed, reward pool SKR livrée désactivée.
Serveur : 21 modules Rust, 19 migrations additives, idempotence par action,
audit économique, rotation one-time-use des refresh tokens, nonces et
rate-limit atomiques en PostgreSQL. Détail : `docs/ROADMAP.md` et
`docs/QUALITY_AUDIT_R24.md`.

## Environnement IA (R16/R25)

- Le shell Cursor exige `required_permissions: ["all"]` sur cette machine
  (aucun backend sandbox Windows) ; sans ça toute commande échoue à se lancer.
- **`git` n'est pas installé** (absent du PATH et de `Program Files`) alors que
  `.git/` existe. Aucun versioning n'est donc possible pour l'instant : à
  installer avant le prochain gros lot.
- Postgres 16 opérationnel (les tests d'intégration passent).

## Ce qui dépend encore de l'extérieur

Wallet Adapter et signature réelle sur Seeker, RPC/indexeur et trésorerie SKR,
providers pub/paiement, API HTTPS, keystore de publication, QA appareil et compte
dApp Store. Voir `docs/RELEASE_CHECKLIST.md` ; aucune de ces dépendances n'est
simulée ou présentée comme prête. Aucun APK intermédiaire n'est un livrable.
