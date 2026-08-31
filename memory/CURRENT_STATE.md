# MÉMOIRE — ÉTAT ACTUEL R30

> MAJ 31/08/2026. R26 = « volume de contenu + live-ops automatisée » —
> intégralement commitée dans `da142f8` (22 commits au total avant R27). R27
> ferme les dettes post-audit sans design final, wallet natif ni build Android.
> R28 rend le playthrough social HTTP reproductible et fail-closed.

## Lot R30 (validé après review)

- Deux P2 Bugbot corrigés dans `run_local_full_gate.ps1` : target Cargo relatif
  normalisé en absolu depuis `server/`, et restauration des deux variables DB de
  test modifiées par `validate_all.ps1`.
- Security Review : aucun constat.
- Gate réelle avec chemin relatif et sentinelles : `LOCAL_FULL_GATE_OK`,
  `ENV_RESTORE_OK`, 39/39 Rust, 12/12 PostgreSQL et aucun serveur résiduel.

## Lot R29 (validé)

- `tools/run_local_full_gate.ps1` rend la validation locale mono-commande : build
  serveur debug, deux instances/identités DEV éphémères, readiness, gate R28,
  arrêt garanti et restauration des variables.
- Ports occupés refusés ; logs temporaires supprimés sur succès et conservés sur
  échec. Test réel terminé par `LOCAL_FULL_GATE_OK`.
- Après sortie : zéro processus `cyberseeker-server`, zéro log de gate résiduel,
  aucun APK/AAB produit.

## Lot R28 (validé)

- `tools/social_contract_check.ps1` orchestre deux joueurs authentifiés par deux
  instances DEV partageant PostgreSQL/JWT, sans injection SQL.
- Couverture : amitié/ciblage, Firewall 0→3, trois Attack bloquées puis un dégât,
  revanche, réparation, Raid conservatif et Trade 1-pour-1 atomique ; retries
  byte-identiques sur les mutations critiques.
- `validate_all.ps1` exige la seconde instance lorsqu'une gate HTTP est demandée.
- Gate complète verte : 39/39 Rust, 12/12 PostgreSQL, 53 analytics, 18 smokes,
  `API_CONTRACT_CHECK_OK`, `SOCIAL_CONTRACT_CHECK_OK`, validation finale verte.

## Lot R27 (validé)

- **Rattrapage live-ops complet** : les occurrences distribuables ne sont plus
  limitées à quatre ; la profondeur dérive de `claimWindowHours` et de la
  cadence. Le test extrême couvre 180 occurrences encore réclamables
  (720 h / cadence 4 h). Le fallback `LIKE` des claims a aussi été supprimé.
- **Qualité Rust** : `cargo fmt --check` et
  `cargo clippy --all-targets -- -D warnings` passent avec Rust 1.97.1.
- **Récompenses client data-driven** : un formateur partagé couvre spins,
  crédits et coffres, y compris les récompenses credits-only/chest-only.
- **Refactor Spin** : mapping des symboles dans `SpinVisuals`, télémétrie dans
  `SpinTelemetry`; `SpinScreen.gd` passe de 1 067 à 989 lignes et la gate fixe
  désormais la limite à 1 000.
- **Validation R27** : `CYBERSEEKER_VALIDATION_OK`, 39/39 tests Rust,
  `DB_TESTS_PROVEN: 12/12`, 53/53 analytics, smoke 6 scènes × 3 ratios et
  `API_CONTRACT_CHECK_OK` sur une instance dédiée.

## Lot R26

 - **Volume de contenu livré (commité)** : 5 districts de lancement au lieu de 2
   (Neon Slums, Chrome Heights, Rust Harbor, Spire Exchange, Nullzone Core),
   progression data-driven par enveloppe de config, écran district piloté par
   config, loot tables centralisées (« launch collection »). Commits `a766697`,
   `ed13de4`, `1133fd1`.
 - **Qualité de gate (commité)** : tests PostgreSQL fail-closed avec preuve
   d'exécution dans la gate (`DB_TESTS_PROVEN: 12/12`) ; smoke Godot signale
   chaque échec et sort non-zéro au lieu de reposer sur `assert` (commits
   `2afea86`, `f50e63b`).
 - **Live-ops automatisée (commitée, commit `da142f8`)** : migration 0020
   (`event_reward_distributions`, `event_rank_rewards` — rang figé à la
   distribution, fenêtre de claim bornée, grand-livre conservé post-expiration,
   5 tables d'archives sans FK) ; `distribute_rank_rewards` +
   `archive_expired_events` idempotents multi-instance ; `EventSchedule` /
   `EventWindow` config (fenêtres actives/terminées, clés claimables) ;
   rotation des missions quotidiennes par jour (`daily_missions_for`) ;
   configs `daily.json` / `events.json` / `seasons.json` étendues ;
   `MissionsScreen.gd` adapté. ~1254 insertions / 158 suppressions, 10 fichiers.
   Revue de diff GO (rapport `REVIEW_R26_LIVEOPS.md`) ; migration 0020 vérifiée
   présente dans le commit (hash blob `15a8fc2d` = working tree = index).

## R25 (clos, pour mémoire)

 - Gate sécurité réparée : `String.Split("#[cfg(test)]")` résolu par PowerShell
   vers la surcharge `char[]` tronquait l'analyse à 6 caractères ; corrigé en
   `-split` regex + garde-fou de longueur. Aucune violation réelle masquée.
 - Versioning réparé : le travail R24 n'avait jamais été commité ; historique
   porté de 13 à 15 commits, arbre propre.

## Validation exécutée R26 (verte sur l'arbre commité)

 - `tools/validate_all.ps1` : **CYBERSEEKER_VALIDATION_OK** ; `cargo fmt` propre.
 - `economy_check` : 277 605 CR équivalents/spin, 9,4 % de spins vides ; coûts
   cumulés attendus par district : 64,8 M → 1,38 Md (Neon Slums → Nullzone Core).
 - `analytics_check` 53/53 ; `security_check` + `mobile_ux_check` OK ;
   Postgres `DB_TESTS_PROVEN: 12/12` ; smoke Godot `SMOKE_SCENES_OK: 6` aux
   ratios 360×800, 540×1170, 720×1280.

## Périmètre livré (cumul R17→R26)

Slot autoritaire ×1→×100K, regen serveur, 5 districts de lancement séquentiels
data-driven (Neon Slums → Nullzone Core), collection de lancement centralisée,
daily streak + Signal Cache, missions à rotation par jour, moteur d'événements
(Neon Rush + Crew Uplink), milestones auto/manuels, leaderboards cohortes
`DENSE_RANK`, social Signal Jam / Ghost Vault / Firewalls, Network Power,
amis + revanche, crews, trading 1-pour-1 de doublons, achievements,
offres/pub/season pass derrière provider, entitlements NFT fail-closed,
reward pool SKR livrée désactivée. Serveur : 21 modules Rust, 20 migrations
additives, audit économique, rotation one-time-use des refresh tokens, nonces
et rate-limit atomiques en PostgreSQL. Détail : `docs/ROADMAP.md` +
`docs/QUALITY_AUDIT_R24.md`.

## Environnement IA (R16/R25)

- Le shell Cursor exige `required_permissions: ["all"]` sur cette machine
  (aucun backend sandbox Windows) ; sans ça toute commande échoue à se lancer.
- Git 2.55.0.3 installé (`C:\Program Files\Git`). Le `.git/` avait été créé par
  le compte sandbox `CodexSandboxOnline` : propriété réattribuée à `danbi` sur
  921 fichiers avec `icacls /setowner`, donc plus besoin d'exception
  `safe.directory`. Historique intact, `git fsck` propre.
- 31/08/2026 : `git fsck --full` passe ; seul le commit orphelin
  `86157799592d6aafee81972bb0a3c0ad204eabf3` est signalé. Aucune corruption
  active de l'object store et aucun `git gc` forcé nécessaire pour ce lot.
- `core.autocrlf=false` en config locale : l'installateur Git for Windows force
  `true` au niveau système alors que l'historique est en LF.
- Identité git globale : Sofiane Deroide <sofiane.deroide1@gmail.com>.
- Postgres 16 opérationnel (les tests d'intégration passent).

## Ce qui dépend encore de l'extérieur

Wallet Adapter et signature réelle sur Seeker, RPC/indexeur et trésorerie SKR,
providers pub/paiement, API HTTPS, keystore de publication, QA appareil et compte
dApp Store. Voir `docs/RELEASE_CHECKLIST.md` ; aucune de ces dépendances n'est
simulée ou présentée comme prête. Aucun APK intermédiaire n'est un livrable.
