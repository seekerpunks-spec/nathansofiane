# MÉMOIRE — TODO / PROCHAINES TÂCHES R25

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

## Prochain lot proposé

- [x] Git installé, `.git` réapproprié, travail R24 commité (15 commits).
- [ ] **Volume de contenu** : prouver les claims data-driven à l'échelle. On a
      2 districts, 8 cartes, 2 sets, 3 coffres alors que le MASTER TODO cible
      N districts (§6) et des catégories de coffres Basic→Elite (§12). Ajouter
      du contenu par config uniquement, sans toucher le moteur, et vérifier
      l'économie avec `economy_check`.
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
