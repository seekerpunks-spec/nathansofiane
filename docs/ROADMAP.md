# CYBERSEEKER — ROADMAP D'EXÉCUTION

## P0 — Fondations

- [x] Audit statique client/serveur/config.
- [x] Direction artistique et architecture UX R17.
- [x] Décor original Neon Slums.
- [x] Design system Godot et shell de navigation.
- [x] Contrats API typés et migration de schéma additive.
- [x] Tests unitaires de config, RNG borné, regen et idempotence.

## P1 — Boucle principale

- [x] Remplacement de la roue par un slot trois rouleaux autoritaire.
- [x] États repos/rotation/anticipation/jackpot conçus dans Figma.
- [x] Symboles originaux, quick stop, SFX mécaniques, haptique, particules,
      secousse et mode mouvement réduit.
- [x] `POST /district/upgrade` autoritaire.
- [x] Progression district dans `GET /state`.
- [x] Écran District interactif et célébration de complétion.
- [x] Analytics `upgrade` et `district_complete`.

## P2 — Collection

- [x] Config typée cartes, sets et coffres.
- [x] Achat/ouverture de coffre avec loot serveur.
- [x] Inventaire, doublons et récompense de set anti double-claim.
- [x] Écrans Collection et Coffres.

## P3 — Rétention

- [x] Bonus quotidien autoritaire.
- [x] Missions quotidiennes simples et progression événementielle.
- [x] Classement d'événement et paliers de récompense.
- [x] Écrans Missions/Événement et compteurs horloge serveur.

## P4 — Continuité et monétisation

- [x] Publicité récompensée via adaptateur, simulée seulement en dev.
- [x] Offres data-driven, limites par joueur et expiration serveur.
- [x] Vérification de paiement verrouillée par provider ; aucun crédit sur
      déclaration du client.
- [x] Season pass data-driven minimal.

## P5 — Qualité production

- [x] Tokens non persistés tant qu'un coffre-fort mobile natif n'est pas raccordé.
- [x] CORS allowlist, limites de corps, nettoyage idempotence/nonce/rate-limit.
- [x] Accessibilité, réglages son/haptique et reprise réseau.
- [x] Profil release sans `DEV_MODE` et serveur refusant `DEV_AUTH`.
- [x] Export Android arm64 de validation, signé avec le keystore debug local et
      vérifié par `apksigner` (API min 24 / cible 36 du template Godot 4.7.2).
- [ ] Signature release/AAB de publication avec le keystore propriétaire du
      compte éditeur (dépendance externe, voir `docs/RELEASE_CHECKLIST.md`).
- [x] Documentation et mémoire synchronisées.

## P6 — Direction artistique 2.5D R20

- [x] Installer et vérifier Blender 5.2 LTS portable par SHA-256 officiel.
- [x] Créer une scène maître de rendu orthographique transparent.
- [x] Produire et intégrer le premier cabinet 2.5D dans le slot Godot.
- [x] Conserver les rouleaux, résultats et animations autoritaires existants.
- [x] Étendre le rendu 2.5D aux écrans District, Collection, Missions et Store.
- [x] Créer BYTE, mascotte 2.5D originale, et refondre l'onboarding autour de lui.
- [x] Ajouter fond vivant, héros animés, cartes révélées en cascade et transitions
      entre onglets avec respect du mode mouvement réduit.
- [ ] Optionnel : remplacer certains volumes procéduraux par des modèles Tripo
      après authentification locale, sans modifier le contrat de rendu Blender.

## P7 — Gate shippable

- [x] Captures desktop déterministes du slot, des cinq écrans et du shell réel.
- [x] Smoke test des six scènes et tests serveur.
- [ ] Fermer les dépendances appareil/services listées dans la checklist release.
- [ ] Refaire un passage UX sur appareil physique et corriger les écarts trouvés.
- [ ] Construire l'APK/AAB uniquement lorsque ces gates sont fermées ; aucun build
      Android pendant les itérations de design.

## P8 — Expansion gameplay R24

- [x] Multiplicateurs de spin data-driven ×1 à ×100K, économie autoritaire et
      animation unique.
- [x] Deux districts séquentiels, prérequis de déblocage et transition client.
- [x] Milestones événementiels auto/manuels, claims idempotents et cohortes de
      leaderboard avec égalités `DENSE_RANK`.
- [x] Funnel analytics complet, gate 47 événements et batches idempotents.
- [x] Signal Jam, Ghost Vault, Firewalls et réparations autoritaires.
- [x] Network Power, profils, amis, classement, ciblage ami et revanche.
- [x] Crews, classement d'équipe et trading social 1-pour-1 sans SKR.
- [ ] Achievements, daily bonus simple, événement coopératif et autres systèmes
      restants du MASTER TODO.
- [ ] Design et Wallet Adapter différés explicitement pour ce lot.
