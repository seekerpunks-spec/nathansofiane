# CYBERSEEKER — Cyberpunk Spin Game pour Solana Seeker

Jeu mobile cyberpunk (spin → progression → collection → événements) ciblé Solana Seeker / dApp Store.

- **GDD** (source de vérité) : [docs/GDD.md](docs/GDD.md)
- **Architecture technique** : [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Structure

```text
client/    Godot 4 — jeu (vue uniquement, aucune logique économique)
server/    Rust/Axum — backend authoritative (RNG, économie, anti-triche)
config/    Remote config JSON versionnée (TOUS les nombres du jeu)
docs/      GDD + architecture (sources de vérité complètes)
memory/    Fichiers condensés de reprise rapide (GDD, ARCHITECTURE, DECISIONS,
           CURRENT_STATE, TODO) — À MAINTENIR à chaque changement significatif
tools/     Setup Windows, audit d'économie et validation complète

GO.bat         Lanceur tout-en-un Windows : Postgres → serveur Rust → Godot
run_client.bat Lanceur client seul (Godot sur client/, après vérif du health)
```

> 📌 Les agents : lire `memory/` en premier à la reprise ; règles de maintenance
> dans [memory/README.md](memory/README.md).

## Démarrer en local

### Mode Windows one-click (recommandé)

1. Double-clic **`GO.bat`** — il vérifie Postgres (port 5432, sinon Docker, sinon
   instructions), lance le serveur Rust (avec l'environnement MSVC chargé via
   `server/run_server.bat`), attend le healthcheck, puis ouvre Godot sur `client/`.
2. Dans Godot : **F5** → Onboarding → **CONNECT WALLET** → Spin.

Prérequis une fois (scripts dans `tools/`) : `install_deps.bat` (Postgres 16 +
Rust, mot de passe Postgres = `postgres`), `install_linker.bat` (VS Build Tools
C++ pour `link.exe`), `fix_linker.bat` (diagnostic/réparation du composant C++).

### 1. Serveur (manuel, tout OS)

```bash
createdb cyberseeker          # ou : psql -c 'CREATE DATABASE cyberseeker;'
cd server
cp .env.example .env          # ajuster si besoin
cargo run                     # les migrations SQL s'appliquent au démarrage
```

Le serveur écoute sur `http://localhost:8080`.

### 2. Client

- Installer [Godot 4.x](https://godotengine.org/download) (standard, pas besoin du mono).
- Ouvrir `client/project.godot` dans Godot, puis **F5**.
- Flow : Onboarding → **CONNECT WALLET** → navigation complète. Dans l'éditeur
  ou un build debug, le connect peut utiliser le joueur de test local.
- Détails : [client/README.md](client/README.md).

### 3. Tester un spin (sans le client)

```bash
# challenge
NONCE=$(curl -s -X POST localhost:8080/auth/challenge \
  -H 'content-type: application/json' \
  -d '{"address":"dev-player-0001"}' | sed -E 's/.*"nonce":"([^"]+)".*/\1/')

# verify (mode dev : signature "dev" acceptée)
TOKEN=$(curl -s -X POST localhost:8080/auth/verify \
  -H 'content-type: application/json' \
  -d "{\"address\":\"dev-player-0001\",\"signature\":\"dev\"}" | sed -E 's/.*"token":"([^"]+)".*/\1/')

# spin
curl -s -X POST localhost:8080/spin \
  -H "authorization: Bearer $TOKEN" \
  -H 'x-request-id: 11111111-1111-4111-8111-111111111111' \
  -H 'content-type: application/json' \
  -d '{}'
```

## Mode dev (à NE JAMAIS activer en production)

- `DEV_AUTH=true` + `DEV_ADDRESS=dev-player-0001` : le `/auth/verify` accepte la signature littérale `"dev"` pour cette adresse (aucune vérification Ed25519).
- Le client Godot expose l'adaptateur dev uniquement dans les features
  éditeur/debug (aucun wallet installé).
- En production : `DEV_AUTH=false` → seul un vrai pair (adresse base58 + signature Ed25519 du nonce) est accepté.

## État du projet

- ✅ **M1** — auth, spin, regen, idempotence, remote config et audit.
- ✅ **M2** — District 1, upgrades atomiques et récompense de complétion.
- ✅ **M3** — coffres, cartes, doublons, collections et récompenses de sets.
- ✅ **M4 local** — daily, missions, leaderboard, événement et saison data-driven.
- ✅ **M5 adaptateurs** — ads/offres simulables en debug et refusées sans preuve en release.
- ✅ **M6 local** — polish, accessibilité, analytics, tests et design cyberpunk.
- ✅ **M7 historique** — un APK Android arm64 debug R33 a été vérifié ; il est
  désormais obsolète et ne constitue pas un artefact R41 publiable.
- ✅ **M8 R41** — MASTER TODO local fermé, confidentialité/auth durcies,
  entraide sociale et CI complète sans build Android.
- ⬜ **Publication externe** — Wallet Adapter, providers, API HTTPS, QA Seeker et
  compte dApp Store (voir la checklist release).

Le runtime R41 possède une navigation mobile complète, six écrans validés par
smoke test, un design system et des assets cyberpunk originaux. Voir
`docs/REDESIGN.md`, `docs/ROADMAP.md` et `docs/RELEASE_CHECKLIST.md`.

Validation complète locale :

```powershell
powershell -ExecutionPolicy Bypass -File tools\run_local_full_gate.ps1
```

Cette commande exige PostgreSQL local, construit uniquement le serveur debug,
lance deux instances `DEV_AUTH` cachées avec identités éphémères, exécute les
gates statiques/Rust/Godot/API/sociales, puis arrête les deux processus. Elle ne
construit aucun APK/AAB. `tools\validate_all.ps1` reste disponible pour les
passes sans orchestration de serveurs.

Ancien APK de validation R33 (obsolète, ne pas distribuer) :

```text
client/build/android/CyberSeeker-debug.apk
```

## Notes

- Les valeurs économiques sont data-driven et contrôlées par
  `tools/economy_check.ps1`; un live tuning ultérieur ne requiert pas de modifier
  le client.
- Les configs restent un fichier typé par famille tant que le catalogue actuel tient
  dans ce format ; le serveur valide toutes les références au boot.
