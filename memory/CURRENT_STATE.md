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
- Funnel analytics complet : 25 événements cœur + 22 sociaux, batches idempotents,
  props bornées/validées et progression événementielle incluse dans `/spin`.
- Tous les rangs 1–50 d'une cohorte reçoivent un palier ; le claim final est
  exposé dans l'écran Missions après expiration.
- Crews légers : création payée, recherche, join/leave, owner/transfert/kick,
  capacité et classement de Network Power data-driven.
- Échanges directs 1-pour-1 entre amis : doublons uniquement, conservation d'un
  exemplaire, raretés configurables, expiration, historique et résolution atomique.
- Les outcomes Carte/Coffre donnent désormais N exemplaires à ×N ; les quantités
  d'inventaire sont en `BIGINT` et les additions commerce sont vérifiées.
- Signal Cache quotidien : récompense pondérée serveur distincte du streak,
  claim atomique/idempotent, disponibilité issue du jour serveur et UI Missions.
- Catalogue commercial autoritaire : starter, spins vides, progression, événement
  et retour joueur sont filtrés puis revalidés sous verrou au moment de l'achat.
- Tous les grants de spins conservent désormais la regen gratuite non persistée ;
  achats et pubs relisent aussi l'idempotence sous verrou avant l'éligibilité.
- Crew Uplink coopératif réutilise les sources de points Neon Rush : score
  partagé atomique, contribution individuelle minimale, trois milestones
  data-driven et claim unique par joueur même après un changement d'équipe.
- Sept achievements permanents cumulent les actions autoritaires dans
  `player_action_totals`, accordent leurs rewards une fois et ajoutent 10 points
  Network Power configurables par achievement réclamé.
- Entitlements NFT centralisés et fail-closed : aucune route d'ownership client,
  activation + TTL + provider requis côté serveur, expiration automatique et
  bonus daily spins uniquement. La collection OG reste désactivée par défaut.
- Audit transversal : aucun Pets runtime ; claims événement/saison relus sous
  verrou ; safe areas, stretch portrait, Retour Android, modales dismissibles,
  inputs tactiles et redraw réduit sont couverts par deux nouvelles gates.

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
  `0015_entitlements.sql`.
- Idempotence par action, transactions, audit économique, horloge serveur,
  rate-limit et nettoyage périodique.
- Mode release protégé : refus de `DEV_AUTH`, secret JWT fort, CORS allowlist,
  corps 256 Kio et aucun crédit commercial sans provider.

## Validation exécutée

- `tools/economy_check.ps1` : OK, 277 605 CR équivalents/spin, 9,4 % vides,
  233,5 spins pour District 1 et 501,8 pour District 2.
- `cargo test --locked` : 18/18 ; `cargo clippy --locked -- -D warnings` : OK.
- `tools/analytics_check.ps1` : 52/52 événements présents.
- `tools/security_check.ps1` et `tools/mobile_ux_check.ps1` : OK ; six scènes
  validées à 360×800, 540×1170 et 720×1280.
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
- Network Power data-driven avec détail upgrades/districts/cartes/sets, profil
  modifiable, code ami, recherche, invitations, liste, classement et revanche.
- Intégration PostgreSQL à deux joueurs : invitation simultanée rejouée à
  l'identique, acceptation symétrique, score/rang exacts, cible amie consommée
  par Signal Jam et droit de revanche validé depuis le journal reçu.
- Intégration crews/trading à deux joueurs : join concurrent rejoué à l'identique,
  transfert d'owner aller-retour, leaderboard exact, Carte ×4 = quatre copies et
  acceptation concurrente d'un swap avec deltas stricts `-1/+1` des deux côtés.
- Intégration Signal Cache : deux claims concurrents renvoient la même réponse,
  un seul gain est appliqué et la disponibilité du jour devient fausse.
- Intégration offres : pack Emergency absent/refusé avec spins, visible à zéro,
  achat concurrent rejoué en deux HTTP 200 pour un seul crédit ; même gate pour
  pub récompensée. Test PostgreSQL dédié : 2 spins régénérés + reward 5 = 7.
- Intégration Crew Uplink : spin ×100 = 1 000 points équipe/contribution ; deux
  claims concurrents donnent une réponse identique et une seule récompense ; un
  membre à zéro contribution est refusé, devient éligible à 100 points, puis
  reste bloqué par `ALREADY_CLAIMED` après avoir changé d'équipe.
- Intégration achievements : spin ×10 progresse simultanément les contrats 10 et
  100 ; deux claims concurrents du premier accordent une seule fois +25 spins et
  +100 000 CR, le second est refusé avant son seuil et Network Power gagne 10.
- Intégration entitlements : état sans preuve = zéro perk ; une ownership active
  écrite via le point d'entrée provider obtient le bonus configuré, puis retombe
  automatiquement à zéro dès que son TTL PostgreSQL est expiré.
- Intégration idempotence season : deux claims simultanés du même palier donnent
  deux HTTP 200 identiques et une seule récompense (+25 spins, +100 000 CR).
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
