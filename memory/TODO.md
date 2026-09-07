# MÉMOIRE — TODO / PROCHAINES TÂCHES R41

> MAJ 07/09/2026. Roadmap détaillée : `docs/ROADMAP.md`. Checklist de
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
- [x] **Live-ops automatisée R26 — WIP vert commité** (commit `da142f8`,
      22 commits avant R27 ; migration 0020 vérifiée dans le commit, hash blob
      `15a8fc2d`) : distributions idempotentes, récompenses de rang figées avec
      fenêtre de claim, 5 tables d'archives, `distribute_rank_rewards` /
      `archive_expired_events`, `EventSchedule`/`EventWindow`, rotation des
      missions par jour, configs daily/events/seasons, MissionsScreen. Revue de
      diff GO, `validate_all.ps1` vert.
- [x] **Gate `api_contract_check.ps1` R27** : rejouée sur une instance `DEV_AUTH`
      dédiée ; concurrence ×4, rejeu, soldes, achat, pub et logout tous verts.
- [x] **Diagnostic Git** : `git fsck --full` passe, avec un seul commit dangling
      et aucune corruption active ; aucun nettoyage destructif lancé.
- [x] **R27 robustesse** : rattrapage live-ops data-driven (test 180 fenêtres),
      Clippy strict vert, libellés de récompense génériques et SpinScreen à
      989 lignes avec composant de télémétrie séparé.
- [x] **Finaliser R27** : revue du diff et lot atomique validé pour versionnage.
- [x] **R28 contrat social HTTP** : deux joueurs/deux instances, Attack,
      Firewall, revanche, réparation, Raid conservatif et Trade atomique ; gate
      complète fail-closed et verte sans APK/AAB.
- [x] **R29 gate mono-commande** : build debug, deux serveurs cachés, readiness,
      validation complète et arrêt/restauration garantis ; aucun processus/log
      résiduel et aucun APK/AAB.
- [x] **R30 corrections de review** : target Cargo relatif cohérent et variables
      PostgreSQL imbriquées restaurées ; gate complète et sentinelles vertes.
- [x] **R31 budget d'assets mobile** : client 47,65 → 3,65 Mo (WebP calibré,
      coffres 256 px, ~25 Mo d'assets morts supprimés), staging des pipelines
      hors de `client/assets`, gate budget/orphelins/WebP dans
      `mobile_ux_check.ps1`, hôte PowerShell 5.1 réparé (BOM + `-Encoding
      UTF8` + `Add-Type System.Net.Http`). `LOCAL_FULL_GATE_OK`.
- [x] **R32 UI 100 % anglaise (D12)** : 103 remplacements client + configs
      joueur, smoke ajusté (`CLAIM`), tripwire accents T37 dans
      `mobile_ux_check.ps1`, messages serveur/commentaires/`note` restent
      français (dev-facing).
- [x] **R33 identité de boot + packaging Android** : boot splash navy + logo
      (fini le splash Godot), 3 icônes launcher générées et câblées dans le
      preset (main 192 + adaptive fg/bg 432, safe zone respectée),
      description projet en anglais, version 0.3.0-r33, gate mobile étendue
      avec test négatif.
- [x] **R34 juice design/anim** : `Juice.gd` (offset_transform 4.7),
      `SpinJuice.gd` (stagger/overshoot/anticipation), HUD ticker, squash
      boutons, modales collection/district, reduced_motion, SpinScreen 935 l.
- [x] **R35 DA graphique district** : diorama village (plus de liste), 15
      silhouettes 2.5D Neon Slums (3 paliers), HUD ivoire, voile levé,
      glyphes D2–D5, budget WebP tenu.

- [x] **R36 DA village 5 districts** : HUD overlay, 5 stages, 55 bâtiments.
- [x] **R38 DA Coin Master (feel)** : marteau rond + 2 taps + étoiles +
      barre de build en haut + BUILD BAY. Nav SPIN central coral.
      Cards/Quests/Shop en overlay illustré, plus de hero dashboard.
- [x] **R39 netteté** : alpha lissé, mipmaps, Nunito MSDF, chrome supersamplé.
      Viewport 540 conservé (T2). Pas de FXAA Compatibility.
- [x] **R41 fermeture MASTER TODO** : responsive Collection/Store, auth
      challenge liée au domaine et stable, export/suppression de compte,
      rétentions SQL, cadeau ami, chat rapide crew, entraide spins et CI GitHub.
      Gate : 44/44 Rust dont 16/16 PostgreSQL, API/social et smoke 360/540/720.
- [x] **Review R41** : nonce validé avant consommation, sessions invalides après
      recréation, export sans wallets tiers, dons/regen/reliquat, demandes ouvertes,
      contrôle d'appartenance et rejeu concurrent après complétion.
- [ ] **CI distante R41** : confirmer les deux jobs après push.
- [ ] **DA skyline jour jouet** : frame 1 générée (monde vide 9:16,
      staging `art/api_gpt_image/skyline_jour_jouet_v1.png`). Attente oui/non.
      Si non : régénérer cette frame seule. Si oui : composite Godot
      (labels live, pas de soldes peints). Runtime visuel = R39 tant que non
      validé.

## Décisions produit fermées en R41

- [x] §19 : cadeau quotidien de 1 spin créé par le quota social, sans coût
      expéditeur et sans transfert de crédits/SKR.
- [x] Phase 9 : chat par phrases allowlist uniquement ; demandes/dons de spins
      bornés et conservatifs dans une crew.
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
