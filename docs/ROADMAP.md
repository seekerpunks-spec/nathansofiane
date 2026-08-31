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
- [x] Signal Cache quotidien pondéré, distinct de la série de connexion.
- [x] Missions quotidiennes simples et progression événementielle.
- [x] Classement d'événement et paliers de récompense.
- [x] Écrans Missions/Événement et compteurs horloge serveur.

## P4 — Continuité et monétisation

- [x] Publicité récompensée via adaptateur, simulée seulement en dev.
- [x] Offres data-driven, limites par joueur et expiration serveur.
- [x] Catalogue serveur et éligibilités starter, spins vides, progression,
      événement et retour joueur, revalidées dans l'achat.
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
- [x] Funnel analytics complet, gate 50 événements et batches idempotents.
- [x] Signal Jam, Ghost Vault, Firewalls et réparations autoritaires.
- [x] Network Power, profils, amis, classement, ciblage ami et revanche.
- [x] Crews, classement d'équipe et trading social 1-pour-1 sans SKR.
- [x] Événement coopératif d'équipe, contribution minimale et claims personnels
      protégés contre les changements d'équipe.
- [x] Achievements permanents data-driven, progression cumulative, rewards
      idempotentes et contribution configurable à Network Power.
- [x] Entitlements NFT fail-closed, TTL serveur et bonus daily centralisé ;
      collection et provider restent désactivés jusqu'à configuration externe.
- [x] Audit Pets négatif, gate sécurité, safe areas, Retour Android, touch targets
      et smoke des six scènes sur trois ratios portrait.
- [x] Nonces single-use et rate limiting PostgreSQL atomiques, partagés entre
      plusieurs instances et validés par test HTTP croisé.
- [x] Architecture SKR future fail-closed : budget saisonnier global, allocations
      idempotentes, pending balance et settlement provider interne sans payout client.
- [x] Refactor Spin : composants de rendu, Network et rencontres extraits ;
      smoke interactif des overlays en plus des six scènes.
- [x] Inventaire reproductible des caches et dossiers racine corrompus ; aucun
      nettoyage destructif requis pour le runtime.
- [x] Rotation one-time-use des refresh tokens avec `jti` hashé, concurrence
      PostgreSQL, replay HTTP rejeté et logout avec révocation idempotente.
- [x] Gate sécurité réparée : l'extraction du runtime `auth.rs` utilisait
      `String.Split("#[cfg(test)]")`, résolu par PowerShell vers la surcharge
      `char[]`, ce qui tronquait l'analyse à six caractères et neutralisait les
      checks négatifs Base58/nonce. Remplacé par un `-split` regex avec
      garde-fou de longueur ; `validate_all.ps1` repasse vert.
- [ ] Autres systèmes restants du MASTER TODO.
- [ ] Design et Wallet Adapter différés explicitement pour ce lot.

## P9 — Robustesse post-audit R27

- [x] Rattrapage de toutes les occurrences live-ops encore claimables, profondeur
      dérivée de la cadence et de la fenêtre de claim (180 fenêtres testées).
- [x] Suppression du fallback `LIKE` fragile pour reconnaître les occurrences
      d'un même événement.
- [x] `cargo fmt --check` et Clippy strict `-D warnings` verts.
- [x] Résumé de récompense partagé spins/crédits/coffres sur Missions, Events,
      Crew, Season, Collection et complétion de district.
- [x] Extraction du mapping de symboles et de la télémétrie Spin ; contrôleur
      ramené à 989 lignes, gate anti-régression fixée à 1 000.
- [x] Gate complète et contrat HTTP rejoués sans APK/AAB.
- [ ] Transfert libre de ressources, chat et donations restent fermés par
      décision anti-abus/modération ; design et wallet restent hors lot.

## P10 — Contrat social HTTP R28

- [x] Gate reproductible à deux joueurs et deux instances DEV, sans injection
      SQL ni contournement de l'autorité serveur.
- [x] Amitié bilatérale, ciblage ami/revanche, Firewall ×3, Attack bloquée et
      dommageable, réparation, Raid conservatif et trading de doublons prouvés.
- [x] Rejeux byte-identiques pour les mutations sociales critiques.
- [x] `validate_all.ps1` fail-closed quand une gate HTTP est demandée sans la
      seconde instance d'authentification.
- [x] Gate R28 complète verte sans APK/AAB.

## P11 — Orchestration mono-commande R29

- [x] Build automatique du serveur debug avec target Cargo configurable.
- [x] Refus des ports occupés, deux identités DEV et secret JWT éphémères.
- [x] Démarrage caché, readiness bornée et diagnostics conservés en cas d'échec.
- [x] Arrêt garanti des seuls PID créés et restauration de l'environnement.
- [x] Gate complète verte jusqu'à `LOCAL_FULL_GATE_OK`, sans processus/log
      résiduel et sans build Android.

## P12 — Correctifs de review R30

- [x] `CargoTargetDir` relatif résolu une seule fois depuis `server/`, puis
      réutilisé sous forme absolue pour le build et le lancement.
- [x] Sauvegarde/restauration de `CYBERSEEKER_TEST_DATABASE_URL` et
      `CYBERSEEKER_ALLOW_DB_TEST_SKIP` autour de la gate imbriquée.
- [x] Test réel avec target relatif et variables sentinelles :
      `LOCAL_FULL_GATE_OK`, `ENV_RESTORE_OK`, zéro processus résiduel.

## P13 — Budget d'assets mobile R31

- [x] Inventaire exhaustif des références runtime : ~25 Mo d'assets jamais
      chargés (staging `local_ai/` embarqué, copies promues `slot/`,
      `rendered/`, `onboarding/` orphelines) supprimés du client.
- [x] Conversion WebP calibrée des 18 textures runtime (décors q90, atlas
      lossless, coffres 1024→256 px) : `client/assets` passe de 47,65 à
      3,65 Mo, qualité vérifiée visuellement.
- [x] Pipelines re-cadrées : staging ComfyUI sous `art/local_ai/staging/`,
      rendus Blender sous `art/render_2_5d/staging/`, promotions du manifest
      avec conversion WebP intégrée (quality/size par entrée).
- [x] Gate budget dans `mobile_ux_check.ps1` : 5 Mo total, 1 024 Ko par
      fichier, WebP obligatoire, zéro asset orphelin, zéro `.import` sans
      source, staging interdit ; tests négatifs vérifiés.
- [x] Hôte Windows PowerShell 5.1 fiabilisé : BOM UTF-8 sur les .ps1
      accentués, `-Encoding UTF8` sur les `Get-Content` des gates,
      `Add-Type System.Net.Http` avant `HttpClient`.
- [x] Champ `image` mort retiré des cartes (config + `CardConfig`).
- [x] `run_local_full_gate.ps1` exit 0 : `LOCAL_FULL_GATE_OK`, 39/39 Rust,
      12/12 PostgreSQL, contrats API et social verts, zéro résidu.

## P14 — UI 100 % anglaise R32 (D12)

- [x] Inventaire outillé du copy joueur (`tools/i18n_en/dump_ui_strings.py`) :
      chaînes des `.gd` client hors commentaires/tests + champs joueur des
      configs ; le client n'affiche jamais le `message` brut du serveur.
- [x] 103 remplacements exacts (échec si chaîne source introuvable) : Main,
      les 6 écrans, composants Spin, `Ui.gd` (`REWARD`, `%dd`), `Wallet.gd`,
      7 descriptions d'achievements, label GLITCH de la spin table.
- [x] Smoke ajusté : attente `CLAIM`, fixture achievement anglaise.
- [x] Tripwire T37 dans `mobile_ux_check.ps1` : accents interdits dans les
      chaînes UI client et les champs joueur des configs (× U+00D7 exclu),
      test négatif regex vérifié.
- [x] Hors périmètre volontaire : commentaires code, `note` de config,
      messages d'erreur API et sorties de gate restent français (dev-facing).

## P15 — Identité de boot + packaging Android R33

- [x] Boot splash : `boot_splash/bg_color` navy #0B1024 +
      `assets/boot_splash.png` (logo 512 px, 32 Ko) — plus de splash Godot
      par défaut au lancement.
- [x] Icônes launcher Android générées et câblées dans le preset :
      `main_192x192`, adaptive foreground (logo 256 px centré, circumradius
      119 px dans la safe zone de 132 px), adaptive background dégradé ;
      pipeline `client/tests/ExportIcon.gd` (Godot headless, rasterise
      l'icône SVG) + `tools/android_icons/build_icons.py` (PIL).
- [x] Preset Android : `exclude_filter` étendu à `export/*` (icônes hors du
      pck), version `0.3.0-r33` (code 18).
- [x] `config/description` en anglais (dernier reliquat D12 : "cartes").
- [x] Gate `mobile_ux_check.ps1` étendue : splash configuré, fichier splash
      présent, 3 icônes câblées et présentes, description sans accents ;
      test négatif vérifié (icône manquante → gate rouge).

## P16 — Juice design/anim R34 (T38)

- [x] `Juice.gd` : animations UI via `offset_transform_*` Godot 4.7
      (squash, pop, shake, pulse, modal, count-up), `reduced_motion` fail-safe,
      armé sur `Ui.button` / nav / SPIN. Héros et scanline backdrop migrés.
- [x] `SpinJuice.gd` : accélération, croisière, overshoot, stagger ~320 ms,
      anticipation rare+, impact/shake. SpinScreen 989→935 lignes.
- [x] Payline scan + burst/anneau legendary, HUD ticker crédits/spins,
      respiration BYTE, SFX `coin`/`upgrade`.
- [x] Modales collection/district + pop carte d'upgrade.
- [x] Smoke : `offset_transform_enabled`, pop no-op en reduced_motion.
      Gate mobile : Juice.gd + SpinJuice.gd requis.

## P17 — DA graphique district R35 (T39)

- [x] Quinze silhouettes 2.5D jouet pour Neon Slums (5 bâtiments × 3 paliers),
      converties WebP 384 px, câblées dans `district_01.json` (lv 0–1 / 2–3 /
      4–5 → t0 / t1 / t2). Identité originale, pas un calque Coin Master.
- [x] `DistrictScreen` : diorama village (pads positionnés, HUD ivoire, fond
      lisible, voile 0.12). Overflow >5 en grille pour le smoke.
- [x] Glyphes procéduraux conservés pour D2–D5 et assets absents.
- [x] Gate : 15 WebP, zéro orphelin, tripwire anti-voile, smoke art D1.

## P18 — Villages 5 districts R36 + tap R37 (T40)

- [x] Cinq stages portrait + HUD overlay type spin, voile retiré.
- [x] 55 bâtiments 2.5D (D1 trois paliers, D2–D5 ruine/landmark).
- [x] T40 : D6 = 0 € outils, pas un cap Mo. Arts 1024 px (~12,4 Mo).
      District = tap sur le bâtiment + bulle de coût (plus de bandeau).
      Gate : hygiène WebP/orphelins, plafond santé 2048 Mo / 8192 Ko.

## P19 — DA casual Coin Master R38 (feel, D8)

- [x] Village : croix 2+1+2, marteau rond, 5 etoiles, 2 taps (cout puis
      build), barre de build en haut, BUILD BAY (shop).
- [x] Nav : SPIN coral au centre, BASE/CARDS/QUESTS/SHOP autour.
- [x] Cards/Quests/Shop : fond illustre + HUD overlay, plus de hero 172 px.

## P20 — Netteté runtime R39

- [x] Alpha feather + WebP lossless bâtiments, stages natifs, chrome 8×.
- [x] Nunito ExtraBold MSDF, mipmaps, snap pixels off, StyleBoxFlat AA.
- [x] Pas de FXAA/MSAA 2D (non supportés en Compatibility 4.7).

