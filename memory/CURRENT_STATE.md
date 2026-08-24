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
- District 2 `Chrome Heights` ajouté avec prérequis ordonné ; le client sélectionne
  le district actif depuis `districtIndex` et la complétion reste unique.
- Événement Neon Rush : quatre milestones configurables (auto/manuels), claims
  transactionnels idempotents, cohortes de 50 et classement `DENSE_RANK` par cohorte.
- Validation liveops : 8 tests Rust, économie des deux districts (225,4 puis
  484,5 spins), 6 scènes Godot et intégration PostgreSQL auto-claim/claim manuel/
  replay/cohorte/verrouillage District 2, complétion unique de Neon Slums puis
  premier upgrade autorisé dans Chrome Heights.
- Funnel analytics complet : 25 événements cœur + 8 sociaux, batches idempotents,
  props bornées/validées et progression événementielle incluse dans `/spin`.
- Tous les rangs 1–50 d'une cohorte reçoivent un palier ; le claim final est
  exposé dans l'écran Missions après expiration.

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
- Deux districts séquentiels : Neon Slums et Chrome Heights, avec cinq éléments
  et trente niveaux chacun.
- Deux sets, huit cartes et trois coffres avec assets originaux.
- Daily streak, missions, événement Neon Rush, milestones auto/manuels,
  leaderboard par cohortes, claims et saison.
- Offres temporisées, rewarded ad et achats derrière adaptateurs sécurisés.
- Réglages son, haptique, mouvement réduit et lisibilité.

## Serveur livré

- Modules R17 : `game`, `district`, `collection`, `engagement`, `commerce`.
- Migrations additives `0002_progression_liveops.sql` à
  `0006_social_encounters.sql`.
- Idempotence par action, transactions, audit économique, horloge serveur,
  rate-limit et nettoyage périodique.
- Mode release protégé : refus de `DEV_AUTH`, secret JWT fort, CORS allowlist,
  corps 256 Kio et aucun crédit commercial sans provider.

## Validation exécutée

- `tools/economy_check.ps1` : OK, 277 605 CR équivalents/spin, 9,4 % vides,
  233,5 spins pour District 1 et 501,8 pour District 2.
- `cargo test --locked` : 11/11 ; `cargo clippy --locked -- -D warnings` : OK.
- `tools/analytics_check.ps1` : 33/33 événements présents.
- Intégration analytics PostgreSQL : batch 25 accepté, replay dédupliqué, props
  invalides refusées et progression de spin renvoyée avec cohorte.
- Slot social complet : outcomes Attack/Raid/Shield/Chest/Card, Signal Jam,
  dégâts réparables, Firewalls capés/consommés et Ghost Vault push-your-luck.
- Intégration PostgreSQL sociale : pending bloque un second spin, Attack et
  réparation idempotents, Firewall ×2 bloque sans dégât, plateau Raid non exposé,
  pick/cash-out idempotents et débit/crédit exact entre deux joueurs.
- Revue concurrence : deux résolutions Attack simultanées avec le même
  `requestId` renvoient deux HTTP 200 strictement identiques pour une mutation ;
  Firewall ×4 donne trois charges et convertit exactement une charge en surplus,
  et un Raid perdu progresse bien mission et événement une seule fois.
- Économie réauditée : 277 605 CR équivalents/spin, 9,4 % de spins vides,
  districts estimés à 233,5 puis 501,8 spins. `cargo clippy -D warnings` vert.
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
