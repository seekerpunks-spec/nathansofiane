# MÉMOIRE — TODO / PROCHAINES TÂCHES R26

> MAJ 25/08/2026. Roadmap détaillée : `docs/ROADMAP.md`. Checklist de
> publication : `docs/RELEASE_CHECKLIST.md`. Spec produit : `MASTER TODO`.

## Fait (cumul)

- [x] M1→M9 : auth, spin, districts, collection, rétention, monétisation,
      refonte cyberpunk, slot trois rouleaux, direction 2.5D Blender.
- [x] Expansion gameplay R24 : multiplicateurs ×1→×100K, 2 districts, liveops,
      analytics 53 événements, social Signal Jam / Ghost Vault / Firewalls,
      Network Power, amis, crews, trading de doublons, Crew Uplink,
      achievements, entitlements NFT fail-closed, reward pool SKR désactivée,
      garde-fous distribués, rotation des refresh tokens, invariants SQL.
- [x] R25 : root cause de la gate sécurité rouge corrigée
      (`String.Split` char[] en PowerShell) et `validate_all.ps1` revert.
- [x] R26 : volume de contenu commité (5 districts de lancement data-driven,
      écran district piloté par config, loot tables centralisées) et qualité de
      gate renforcée (tests Postgres fail-closed prouvés, smoke non-zéro).

## Prochain lot proposé

- [x] Git installé, `.git` réapproprié, travail R24 commité (15 commits).
- [x] **Volume de contenu** : 5 districts de lancement (Neon Slums → Nullzone
      Core) ajoutés par config uniquement, économie vérifiée par `economy_check`
      (coûts cumulés 64,8 M → 1,38 Md). Reste éventuel : catégories de coffres
      Basic→Elite (§12).
- [ ] **Live-ops automatisée R26 — commit du WIP vert** : migration 0020
      (distributions idempotentes, récompenses de rang figées avec fenêtre de
      claim, 5 tables d'archives), `distribute_rank_rewards` /
      `archive_expired_events`, `EventSchedule`/`EventWindow`, rotation des
      missions par jour, configs daily/events/seasons, MissionsScreen. Gate
      `validate_all.ps1` verte sur le WIP ; revuer le diff puis committer.
- [ ] **Gate `api_contract_check.ps1`** : jamais rejouée dans cette session,
      elle exige une instance locale `DEV_AUTH` dédiée. À lancer via
      `validate_all.ps1 -ApiBaseUrl ... -ApiDevAddress ...`.

## Décisions produit encore ouvertes (ne pas inventer)

- [ ] §19 MASTER TODO : envoi de ressources entre amis. Actuellement fermé par
      D9/T29 (aucun transfert libre de richesse). À confirmer ou rouvrir.
- [ ] Phase 9 : chat d'équipe limité (différé, demande de la modération) et
      donations (écartées au profit du swap 1-pour-1).
- [ ] Design final et Wallet Adapter natif : différés explicitement.

## Reste externe avant publication

- [ ] Solana Mobile Wallet Adapter sur un appareil Seeker réel.
- [ ] RPC/indexeur, mint SKR et adresse de trésorerie.
- [ ] Providers réels de publicité et de paiement avec leurs secrets.
- [ ] Domaine/API HTTPS de production et observabilité hébergée.
- [ ] Keystore de publication appartenant à l'éditeur.
- [ ] QA Seeker 30 min : haptique, reprise, réseau mobile, batterie, thermique.
- [ ] Comptes, textes légaux et fiche dApp Store.
- [ ] Optionnel : authentifier Tripo localement (jamais de clé dans le dépôt).

Le prochain APK/AAB n'est généré qu'une fois cette gate shippable fermée. Les
itérations intermédiaires utilisent uniquement Godot desktop, captures et tests.
