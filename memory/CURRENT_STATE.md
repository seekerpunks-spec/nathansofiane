# MÉMOIRE — ÉTAT ACTUEL R24

> MAJ 24/08/2026 : R24 ouvre l'expansion gameplay du MASTER TODO. Design et
> wallet natif sont gelés ; aucun build Android avant la gate shippable.

## Lot R24 validé

- Baseline Git locale `main` créée avant changements fonctionnels.
- Auth Solana corrigée : la casse Base58 est préservée.
- Ladder data-driven ×1 à ×100K ; un spin dépense N, joue une animation et
  multiplie le gain de base sans modifier les probabilités.
- Missions/événements/saison progressent de N ; idempotence et audit conservés.
- Arithmétique vérifiée, bornes de config, contraintes SQL et notation
  K/M/B/T/Qa/Qi ajoutées.
- Regen corrigée pour conserver le reliquat d'intervalle.
- Validation : 7 tests Rust, économie OK, 6 scènes Godot, intégration PostgreSQL
  ×4/invalid/insufficient/replay exacte.

## Produit livré

- Direction cyberpunk originale inspirée de la boucle de collection/construction
  d'un jeu social mobile, sans reprendre les marques ou assets de Coin Master.
- Écran principal transformé en machine à sous à trois rouleaux : symboles
  originaux, ligne de gain, quick stop, anticipation rare+, jackpot, particules,
  secousse, SFX procéduraux, haptique et mouvement réduit.
- Ciel/cyber-ville lumineux plein écran, cabinet 3D stylisé dominant, grille 3×3
  ivoire animée par Godot, ressources flottantes, jauge intégrée, BYTE et gros
  CTA SPIN physique ; six symboles GPT Image cohérents assemblés en atlas RGBA.
- Figma installé/connecté ; fichier `CyberSeeker — Slot Machine R18`, clé
  `btBFjxNk1ue6lWN1p0elWg`, avec quatre états de référence.
- Blender 5.2 LTS portable vérifié par SHA-256 officiel ; scène maître, script
  automatisé et PNG transparent reproductible disponibles dans le dépôt.
- Héros illustrés pour District, Collection, Missions et Store ; mascotte BYTE,
  onboarding illustré, fond de portail propre et transitions compatibles
  mouvement réduit.
- Navigation mobile : Spin, District, Cards, Missions, Store.
- District 1 : cinq éléments et trente états visuels programmés.
- Deux sets, huit cartes et trois coffres avec assets originaux.
- Daily streak, missions, événement Neon Rush, leaderboard, claims et saison.
- Offres temporisées, rewarded ad et achats derrière adaptateurs sécurisés.
- Réglages son, haptique, mouvement réduit et lisibilité.

## Serveur livré

- Modules R17 : `game`, `district`, `collection`, `engagement`, `commerce`.
- Migration additive `0002_progression_liveops.sql`.
- Idempotence par action, transactions, audit économique, horloge serveur,
  rate-limit et nettoyage périodique.
- Mode release protégé : refus de `DEV_AUTH`, secret JWT fort, CORS allowlist,
  corps 256 Kio et aucun crédit commercial sans provider.

## Validation exécutée

- `tools/economy_check.ps1` : OK, 225,4 spins attendus pour District 1.
- `cargo test` : 4/4.
- `cargo build --release` : OK.
- Garde release `DEV_AUTH=true` : refus confirmé.
- Intégration API live : auth, spin idempotent, upgrade, daily, coffre, pub dev,
  missions, événement, achat idempotent et claims de saison : OK.
- Smoke Godot : `SMOKE_SCENES_OK: 6`.
- Import Godot et capture runtime du slot premium final :
  `captures/slot_runtime.png`.
- Captures desktop de l'onboarding, du shell réel et des quatre écrans : OK ;
  portail sans texte ni personnage parasite, scrollbars affinées.
- API locale PostgreSQL/Rust : santé OK et flux challenge → signature dev →
  bearer → état joueur validé.

## Artefacts

- Serveur : `server/target/release/cyberseeker-server.exe`, SHA-256
  `4B9ABB78E0C638C2A6927B44B9381E915EA83A01C70AF3ACABD92591BE1BC7BC`.
- Scène Blender maître historique : `art/blender/cyberseeker_slot_master.blend`.
- Pack GPT Image intégré : `client/assets/generated/api_gpt/`.
- Héros GPT Image cohérents pour District, Cards, Quests et Shop :
  `client/assets/generated/api_gpt/heroes/`.
- Master, prompts et rapport d'assets : `art/api_gpt_image/`.
- Ancienne borne cartoon locale, conservée comme fallback historique :
  `client/assets/generated/rendered/slot_cabinet.png`.
- Héros et mascotte : `client/assets/generated/rendered/*_hero.png`.
- Pack local complet et candidats historiques : `art/local_ai/`.
- Pipeline reproductible : `tools/ai_assets/generate.ps1` et
  `tools/ai_assets/asset_manifest.json`.
- Stack locale : ComfyUI 0.33, FLUX.2 Klein 4B, Qwen 3 4B FP4, VAE FLUX.2 et
  rembg/U2Net ; scripts sous `local-ai/` dans le workspace Codex.
- Prompts et règles de direction : `docs/ASSET_PROMPTS.md`.

## Ce qui dépend encore de l'extérieur

Wallet Adapter et signature réelle sur Seeker, RPC/indexeur et trésorerie SKR,
providers pub/paiement, API HTTPS, keystore de publication, QA appareil et compte
dApp Store. Voir `docs/RELEASE_CHECKLIST.md` ; aucune de ces dépendances n'est
simulée ou présentée comme prête en production.

Aucun APK intermédiaire n'est considéré comme livrable. Le prochain build
Android sera déclenché seulement lorsque la version sera réellement shippable.
