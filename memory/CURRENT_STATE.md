# MÉMOIRE — ÉTAT ACTUEL R26 (en cours)

> MAJ 25/08/2026. R26 = « volume de contenu + live-ops automatisée ». La partie
> contenu est commitée et la gate est verte ; la partie live-ops est en WIP
> non commité (gate verte dessus). Design final et wallet natif restent gelés ;
> aucun build Android avant la gate shippable.

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
 - **Live-ops automatisée (WIP non commité, gate verte)** : migration 0020
   (`event_reward_distributions`, `event_rank_rewards` — rang figé à la
   distribution, fenêtre de claim bornée, grand-livre conservé post-expiration,
   5 tables d'archives sans FK) ; `distribute_rank_rewards` +
   `archive_expired_events` idempotents multi-instance ; `EventSchedule` /
   `EventWindow` config (fenêtres actives/terminées, clés claimables) ;
   rotation des missions quotidiennes par jour (`daily_missions_for`) ;
   configs `daily.json` / `events.json` / `seasons.json` étendues ;
   `MissionsScreen.gd` adapté. ~1254 insertions / 158 suppressions, 10 fichiers.
   **À committer une fois la revue du diff terminée.**

## R25 (clos, pour mémoire)

 - Gate sécurité réparée : `String.Split("#[cfg(test)]")` résolu par PowerShell
   vers la surcharge `char[]` tronquait l'analyse à 6 caractères ; corrigé en
   `-split` regex + garde-fou de longueur. Aucune violation réelle masquée.
 - Versioning réparé : le travail R24 n'avait jamais été commité ; historique
   porté de 13 à 15 commits, arbre propre.

## Validation exécutée R26

 - `cargo fmt --all` : propre (le WIP contenait un diff de format, appliqué).
 - `tools/validate_all.ps1` : **CYBERSEEKER_VALIDATION_OK** sur l'arbre avec WIP.
 - `economy_check` : 277 605 CR équivalents/spin, 9,4 % de spins vides ;
   coûts cumulés attendus par district : 64,8 M (Neon Slums), 139,3 M (Chrome
   Heights), 298,5 M (Rust Harbor), 642,3 M (Spire Exchange), 1,38 Md
   (Nullzone Core).
 - `analytics_check` : 53/53 événements. `security_check` et `mobile_ux_check` : OK.
 - Intégrations PostgreSQL : `DB_TESTS_PROVEN: 12/12`.
 - Import Godot + smoke `SMOKE_SCENES_OK: 6` aux ratios 360×800, 540×1170 et
   720×1280.

## Périmètre livré (cumul R17→R26)

Slot autoritaire ×1→×100K, regen serveur, 5 districts de lancement séquentiels
data-driven (Neon Slums → Nullzone Core), collection de lancement centralisée,
daily streak + Signal Cache, missions à rotation par jour, moteur d'événements
(Neon Rush individuel + Crew Uplink coop),
milestones auto/manuels, leaderboards en cohortes `DENSE_RANK`, boucle sociale
Signal Jam / Ghost Vault / Firewalls, Network Power, amis + revanche, crews,
trading 1-pour-1 de doublons, achievements, offres/pub/season pass derrière
provider, entitlements NFT fail-closed, reward pool SKR livrée désactivée.
Serveur : 21 modules Rust, 19 migrations additives (20e en WIP : live-ops),
audit économique, rotation one-time-use des refresh tokens, nonces et
rate-limit atomiques en PostgreSQL. Détail : `docs/ROADMAP.md` et
`docs/QUALITY_AUDIT_R24.md`.

## Environnement IA (R16/R25)

- Le shell Cursor exige `required_permissions: ["all"]` sur cette machine
  (aucun backend sandbox Windows) ; sans ça toute commande échoue à se lancer.
- Git 2.55.0.3 installé (`C:\Program Files\Git`). Le `.git/` avait été créé par
  le compte sandbox `CodexSandboxOnline` : propriété réattribuée à `danbi` sur
  921 fichiers avec `icacls /setowner`, donc plus besoin d'exception
  `safe.directory`. Historique intact, `git fsck` propre.
- `core.autocrlf=false` en config locale : l'installateur Git for Windows force
  `true` au niveau système alors que l'historique est en LF.
- Identité git globale : Sofiane Deroide <sofiane.deroide1@gmail.com>.
- Postgres 16 opérationnel (les tests d'intégration passent).

## Ce qui dépend encore de l'extérieur

Wallet Adapter et signature réelle sur Seeker, RPC/indexeur et trésorerie SKR,
providers pub/paiement, API HTTPS, keystore de publication, QA appareil et compte
dApp Store. Voir `docs/RELEASE_CHECKLIST.md` ; aucune de ces dépendances n'est
simulée ou présentée comme prête. Aucun APK intermédiaire n'est un livrable.
