# MÉMOIRE — ÉTAT ACTUEL R33

> MAJ 31/08/2026. R32 = UI joueur 100 % anglaise (D12). R33 = identité de
> boot + packaging Android (splash, icônes launcher, description EN).

## Lot R33 (identité de boot + packaging Android)

- **Boot splash** : fini le splash Godot par défaut — `boot_splash/bg_color`
  navy #0B1024 + `assets/boot_splash.png` (logo 512, 32 Ko). Description
  projet passée en anglais (dernier reliquat D12).
- **Icônes launcher Android** câblées dans le preset (elles retombaient sur
  l'icône robot Godot) : `main_192x192` + adaptive fg (logo 256 centré,
  circumradius 119 px < safe zone 132 px) + bg dégradé, 42 Ko en tout,
  générées par `client/tests/ExportIcon.gd` (Godot headless) puis
  `tools/android_icons/build_icons.py` (venv PIL). `export/*` exclu du pck.
- **Preset** : version 0.3.0-r33 (code 18). Gate mobile étendue : splash
  configuré, 3 icônes présentes, description sans accents ; test négatif
  vérifié (icône manquante → rouge).

## Lot R32 (UI anglaise, D12)

- **103 remplacements** : tout le copy français des `.gd` client (Main,
  les 6 écrans, composants Spin, `Ui.gd`, `Wallet.gd`) et les libellés joueur
  des configs (7 descriptions `achievements.json`, label GLITCH de
  `spin_table.json`) passés en anglais. `Ui.mmss_long` : `%dj` → `%dd`.
- **Périmètre vérifié** : le client n'affiche jamais le `message` brut du
  serveur (tout est mappé sur des libellés locaux) → les messages d'erreur
  API restent français (dev-facing), comme les commentaires code et les
  `note` de config.
- **Tripwire T37** dans `mobile_ux_check.ps1` : accents interdits dans les
  chaînes des `.gd` client (hors commentaires/tests) et dans les champs
  joueur des configs ; × (U+00D7) exclu. Test négatif regex vérifié.
- **Smoke ajusté** : attente `CLAIM` (ex-RÉCLAMER), fixture achievement en
  anglais. Inventaire rejouable : `tools/i18n_en/dump_ui_strings.py`.

## Validation R32

`run_local_full_gate.ps1` : voir sentinelle `LOCAL_FULL_GATE_OK` du lot.
Référence R31 (verte) : 39/39 Rust, `DB_TESTS_PROVEN: 12/12`, smoke 6 scènes
× 3 ratios, `API_CONTRACT_CHECK_OK`, `SOCIAL_CONTRACT_CHECK_OK`, Clippy strict.

## Historique condensé (R25→R31, tout commité)

- R25 : gate sécurité réparée (`String.Split` char[]) ; R24 commité.
- R26 : 5 districts data-driven, tests Postgres fail-closed prouvés,
  live-ops automatisée (migration 0020, commit `da142f8`).
- R27 : rattrapage live-ops (180 fenêtres), Clippy strict, SpinScreen 989 l.
- R28 : `social_contract_check.ps1` = playthrough deux joueurs/deux instances.
- R29 : `run_local_full_gate.ps1` mono-commande, arrêt garanti.
- R30 : target Cargo normalisé, variables DB de test restaurées.
- R31 : assets 47,65 → 3,65 Mo (WebP calibré, ~25 Mo morts supprimés),
  staging pipelines sous `art/`, gate budget/orphelins/WebP, hôte
  PowerShell 5.1 réparé (BOM + `-Encoding UTF8` + `Add-Type`).

## Périmètre livré (cumul R17→R32)

Slot autoritaire ×1→×100K, 5 districts, collection de lancement, rétention,
live-ops automatisée, social complet (Signal Jam/Ghost Vault/amis/crews/
trading), achievements, entitlements NFT fail-closed, reward pool SKR
désactivée, UI 100 % anglaise. 21 modules Rust, 20 migrations.
Détail : `docs/ROADMAP.md`.

## Environnement IA (R16/R25/R31)

- Shell Cursor : `required_permissions: ["all"]` obligatoire ; hôte réel =
  **Windows PowerShell 5.1** (pas de pwsh installé) → les .ps1 accentués
  DOIVENT garder leur BOM UTF-8 et tout `Get-Content` de gate son
  `-Encoding UTF8`.
- Git 2.55, `core.autocrlf=false` local, identité Sofiane Deroide
  <sofiane.deroide1@gmail.com>. `git fsck` propre (un seul dangling connu).
- Postgres 16 opérationnel ; venv pipeline (PIL) :
  `C:\Users\danbi\Documents\Codex\2026-08-22\ex\local-ai\venv`.
- Godot 4.7.2 : `%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\`.

## Ce qui dépend encore de l'extérieur

Wallet Adapter Seeker, RPC/indexeur/trésorerie SKR, providers pub/paiement,
HTTPS production, keystore éditeur, QA appareil, fiche dApp Store. Voir
`docs/RELEASE_CHECKLIST.md`. Aucun APK intermédiaire n'est un livrable.
