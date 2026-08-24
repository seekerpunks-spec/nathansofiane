# MÉMOIRE — TODO / PROCHAINES TÂCHES

> MAJ R20 (22/08/2026). La roadmap détaillée est `docs/ROADMAP.md` et la
> checklist de publication est `docs/RELEASE_CHECKLIST.md`.

## Réalisé localement

- [x] M1 : auth dev, état autoritaire, spin, regen, idempotence et analytics.
- [x] M2 : District 1, cinq éléments, six états visuels par élément, upgrades et
      récompense de complétion.
- [x] M3 : coffres, cartes, doublons, sets et claim anti double-récompense.
- [x] M4 : daily, missions, événement, classement et paliers.
- [x] M5 : offres, publicité via adaptateur, achats vérifiés via provider et
      season pass data-driven.
- [x] M6 : refonte cyberpunk mobile, navigation cinq onglets, accessibilité,
      préférences, retry réseau et assets originaux.
- [x] M7 local : tests Rust, smoke des six scènes, intégration API, build serveur
      release et APK Android arm64 signé/debug vérifié.
- [x] M8 : Figma MCP installé, slot trois rouleaux conçu puis intégré avec atlas
      original, animations multi-phases, anticipation, jackpot, SFX et haptique.
- [x] M9a : Blender 5.2 LTS portable, scène maître 2.5D, rendu transparent et
      cabinet final intégré dans Godot.
- [x] M9b : dioramas Blender District/Collection/Missions/Store, mascotte BYTE,
      onboarding illustré, fond vivant, transitions et QA visuelle desktop.

## Reste externe avant publication

- [ ] Optionnel : authentifier Tripo localement pour remplacer certains volumes
      procéduraux ; ne jamais stocker la clé API dans le dépôt ou les logs.

- [ ] Brancher Solana Mobile Wallet Adapter sur un appareil Seeker réel.
- [ ] Choisir le RPC/indexeur, le mint SKR et l'adresse de trésorerie.
- [ ] Brancher les providers réels de publicité et de paiement avec leurs secrets.
- [ ] Configurer domaine/API HTTPS de production et observabilité hébergée.
- [ ] Créer et sauvegarder le keystore de publication appartenant à l'éditeur.
- [ ] Effectuer QA Seeker 30 minutes : haptique, reprise, réseau mobile, batterie,
      mémoire et température.
- [ ] Fournir comptes, textes légaux et fiche dApp Store pour la soumission.

Ces tâches demandent un appareil, des identifiants, des choix commerciaux ou une
infrastructure que le dépôt ne peut ni inventer ni certifier.

Le prochain APK/AAB n'est généré qu'une fois cette gate shippable fermée. Les
itérations intermédiaires utilisent uniquement Godot desktop, captures et tests.
