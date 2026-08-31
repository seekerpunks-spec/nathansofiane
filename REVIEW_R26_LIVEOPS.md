# REVIEW R26 — live-ops (revue finale historique)

> Revue finale du lot live-ops désormais versionné dans `da142f8`.
> Gate `validate_all.ps1` verte. **Verdict global : GO.**

## Verdict par thème

| Thème | Verdict |
|---|---|
| Idempotence | **GO** |
| Atomicité | **GO** |
| Fail-closed | **GO** |
| Config / schedules | **GO** |
| Client (MissionsScreen + /state) | **GO** |
| Migration 0020 | **GO** |

### Idempotence
- Distribution : verrou advisory `hashtextextended(key,1)` + ligne `event_reward_distributions`
  (PK `event_key`) + recheck sous verrou. Test Postgres prouve le pattern 1 → 0.
- Récompenses de rang : `INSERT ... ON CONFLICT DO NOTHING` sur PK `(event_key,address)`.
- Archivage : filtre `claim_until < now() AND archived_at IS NULL`, test prouve 1 → 0.
- Récurrence par pur calcul (ancre + cadence + durée) : déterministe multi-instance,
  clés `"{eventId}#{n}"`, `#` réservée par la validation config.

### Atomicité
- Tout dans une transaction ; claim sous `FOR UPDATE` ; grand-livre
  `event_rank_rewards` conservé après claim ET expiration.
- `claim_event` draine toutes les clés claimables du joueur dans une seule tx,
  audit économique final unique par request (pas d'audit en double par reward).
- `ProgressResult::merge` : la 2e action dans la même tx (spin/attack/raid +
  `credits_earned`) fusionne proprement events/achievements.

### Fail-closed
- Claim avant distribution → `Unavailable` (le rang n'est plus calculé à la volée,
  l'ancien comportement trichable est mort — test dédié).
- Fenêtre close → rejet (`claim_until > now()` dans la requête de claim).
- Mission non tirée aujourd'hui → `NotFound` au claim (même tirage déterministe
  SHA-256 pour accrual, claim et exposition `/state`).
- Saisons : `pointSources` autonomes (plus de dépendance à un événement actif),
  validation non-chevauchement.

### Migration 0020
- 7 tables : distributions, rank rewards, 5 archives sans FK.
- Contraintes cohérentes : `rewarded <= participants`, `claimed_at <= claim_until`,
  `archived_at >= distributed_at` ; FK `players` uniquement sur `event_rank_rewards`
  (CASCADE), archives sans FK → l'historique survit aux suppressions.
- Colonnes `event_key`/`event_id` en `TEXT` : les clés `#n` passent sans limite
  de longueur. Index partiel sur les claims en attente.

## Points mineurs (non bloquants, à noter)

1. **`ended_windows(now, 4)`** : borne de 4 occurrences par passe du worker. Si le
   serveur est down > 4 × cadence (cadence min 4 h → ~4 jours), des occurrences ne
   seront **jamais** distribuées. Acceptable en M1 ; à documenter dans la roadmap.
2. **MissionsScreen.gd** : le label `"RANG #%d — +%s SPINS"` suppose `spins` dans
   la reward de tier. Un tier à `credits`/`chest` seul affichera `+0 SPINS`
   (cosmétique).
3. **Fragilité clé** : le fallback `AlreadyClaimed` de `claim_event` utilise
   `event_key LIKE '{eventId}%'`. OK tant que `#` est réservée par la validation
   config — c'est le point le plus cassant si un jour le format de clé change.
4. Le mojibake `ΓÇó`/`├ë` dans `fulldiff.txt` est l'encodage du dump (UTF-16),
   PAS le source. Les `.gd` sont UTF-8 corrects (runs Godot propres). Ne pas
   "corriger" le source sur la foi du dump.

## Suivi R27

Les trois réserves fonctionnelles de cette revue sont fermées dans R27 :

- le rattrapage n'est plus borné à quatre occurrences et couvre toute la fenêtre
  encore réclamable dérivée de la configuration ;
- les libellés de récompense partagent un formateur spins/crédits/coffres ;
- la reconnaissance des clés récurrentes n'utilise plus de wildcard SQL.

La gate HTTP dédiée a également été rejouée avec succès le 31/08/2026. Les
fichiers temporaires et dossiers anormaux n'ont pas été supprimés : aucun
nettoyage destructif n'était requis pour ce lot.
