# MÉMOIRE — ÉTAT ACTUEL R31

> MAJ 31/08/2026. R26 = volume de contenu + live-ops (commit `da142f8`). R27 =
> robustesse post-audit. R28 = contrat social HTTP. R29 = gate mono-commande.
> R30 = correctifs de review. R31 = budget d'assets mobile + hôte PowerShell 5.1.

## Lot R31 (validé, gate complète verte)

- **Budget d'assets** : `client/assets` passe de **47,65 Mo à 3,65 Mo** sans
  perte visible (vérif visuelle décor + atlas). 18 textures runtime en WebP :
  décors/api_gpt q90, atlas du slot lossless, coffres redimensionnés
  1024→256 px (affichés 86 px). Conversion reproductible :
  `tools/asset_budget/convert_runtime_assets.py` (venv de la pipeline).
- **~25 Mo d'assets morts supprimés** : staging `local_ai/` (17,6 Mo qui
  partaient dans l'APK) + copies promues `slot/`, `rendered/`, `onboarding/`
  jamais référencées par l'UI actuelle (direction `api_gpt/`).
- **Pipelines re-cadrées** : staging ComfyUI → `art/local_ai/staging/`,
  rendus Blender → `art/render_2_5d/staging/` ; les promotions du manifest
  convertissent en WebP calibré (quality/size par entrée). Aucun PNG de
  staging ne peut revenir dans `client/assets/`.
- **Gate mobile étendue** (`mobile_ux_check.ps1`) : plafond 5 Mo total,
  1 024 Ko par fichier, WebP obligatoire sous `assets/generated`, zéro asset
  orphelin (référence res:// dans les .gd ou nom relatif dans la config),
  zéro `.import` sans source, staging interdit. Tests négatifs vérifiés
  (orphelin et PNG déclenchent bien le rouge).
- **Nettoyage config/serveur** : champ `image` mort retiré des 45 cartes et de
  `CardConfig` ; `chests.json` pointe vers les .webp ;
  `DistrictScreen._asset_texture` résout `.webp` puis `.png`.
- **Hôte PowerShell 5.1 réparé** (les gates R28-R30 tournaient sous un shell
  en codepage UTF-8) : BOM UTF-8 ajouté aux .ps1 accentués (sinon erreurs de
  parse), `-Encoding UTF8` forcé sur tous les `Get-Content` des gates (sinon
  les motifs accentués ne matchent plus les sources), et
  `Add-Type System.Net.Http` dans `api_contract_check.ps1`.

## Validation exécutée R31 (verte, arbre de travail)

`run_local_full_gate.ps1` exit 0 : 39/39 Rust, `DB_TESTS_PROVEN: 12/12`,
smoke 6 scènes × 3 ratios, `API_CONTRACT_CHECK_OK`, `SOCIAL_CONTRACT_CHECK_OK`,
`CYBERSEEKER_VALIDATION_OK`, `LOCAL_FULL_GATE_OK`, zéro processus résiduel.
Clippy strict `-D warnings` vert.

## Historique condensé (R25→R30, tout commité, HEAD avant R31 `cf1de5d`)

- R25 : gate sécurité réparée (`String.Split` char[]) ; travail R24 commité.
- R26 : 5 districts data-driven, loot tables centralisées, tests Postgres
  fail-closed prouvés, smoke non-zéro, live-ops automatisée (migration 0020).
- R27 : rattrapage live-ops dérivé de la config (180 fenêtres), Clippy strict,
  récompenses UI génériques, SpinScreen 989 lignes.
- R28 : `social_contract_check.ps1` = playthrough deux joueurs/deux instances.
- R29 : `run_local_full_gate.ps1` mono-commande, arrêt garanti.
- R30 : target Cargo normalisé, variables DB de test restaurées.

## Périmètre livré (cumul R17→R31)

Slot autoritaire ×1→×100K, 5 districts, collection de lancement, rétention,
live-ops automatisée, social complet (Signal Jam/Ghost Vault/amis/crews/
trading), achievements, entitlements NFT fail-closed, reward pool SKR
désactivée. 21 modules Rust, 20 migrations. Client 47,65→3,65 Mo d'assets.
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
