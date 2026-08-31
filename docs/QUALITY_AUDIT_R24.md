# Quality Audit R24 — Security, Mobile et exclusions

Audit local exécuté le 24/08/2026. Il ne remplace pas la QA sur appareil Seeker,
la revue du provider de paiement ou un test d'intrusion de l'API hébergée.

## Sécurité économique

- Les soldes, RNG, timers, loot, progression et ranks sont calculés serveur.
- Toutes les mutations exigent un request ID et stockent leur réponse dans la
  transaction économique ; les retries concurrents relisent sous verrou.
- Les claims événement/saison ont été corrigés pendant cette revue : leur scope
  inclut désormais la ressource et leur retry concurrent renvoie la même réponse.
- Les achats/pub ne créditent une preuve `dev:*` qu'en `DEV_AUTH`; un binaire
  release refuse de démarrer avec ce mode.
- L'adresse Solana conserve strictement sa casse Base58.
- Les nonces et quotas API ne dépendent plus de la mémoire d'une instance :
  PostgreSQL consomme un nonce une seule fois et incrémente le quota atomiquement.
- Les refresh tokens portent un `jti` aléatoire dont seul le hash est stocké ;
  chaque rotation consomme l'ancien token et un replay HTTP renvoie 401.
- Le client sérialise les refresh concurrents et détecte si une autre coroutine
  a déjà remplacé l'access token avant de faire tourner la session.
- La déconnexion révoque le refresh courant de façon idempotente et toute
  expiration de session purge aussi les deux jetons du client.
- Le RNG de spin et du bonus quotidien utilise `OsRng`.
- Les leaderboards sont dérivés de tables autoritaires et utilisent `DENSE_RANK`.
- Les leaderboards publics utilisent le friend code et le profil minimal ; les
  adresses wallet brutes ne sont plus exposées dans les cohortes événement.
- Les entitlements n'ont aucune route de self-claim, exigent un provider interne,
  une définition activée et une expiration future.
- Les contraintes SQL protègent soldes, inventaires, claims uniques et relations.
- Les rencontres/trades imposent cohérence statut-timestamp et ordre temporel ;
  l'auto-ciblage social et plusieurs owners dans une équipe sont interdits en DB.
- Les réponses de claim relisent le solde autoritaire après régénération ; les
  longues absences, streaks, niveaux et progressions de mission bornent leurs
  conversions/additions avant écriture PostgreSQL.
- Le reward pool futur est livré désactivé. Son budget est sérialisé par verrou
  PostgreSQL, ses sources sont configurées et son settlement n'a aucune route client.
- La liveness reste indépendante ; `/ready` vérifie PostgreSQL. Le secret JWT
  d'exemple est refusé en release et le serveur draine les requêtes à l'arrêt.

Gate : `tools/security_check.ps1`. Test HTTP à deux instances validé : challenge
sur A, verify sur B, replay rejeté sur A et `RATE_LIMITED` partagé.
Test de session validé : verify 200, refresh 200, replay de l'ancien refresh 401,
puis rotation du nouveau refresh 200. La révocation et son rejeu sont également
couvertes par le test PostgreSQL. Le test HTTP logout valide ensuite 200 avec
`revoked=true`, un rejeu idempotent 200 avec `revoked=false`, puis le refus 401
de toute nouvelle rotation à partir de cette session.

Gate HTTP reproductible : `tools/api_contract_check.ps1`. Elle lance deux spins
×4 concurrents avec la même clé, exige deux réponses 200 identiques, vérifie une
seule consommation et les soldes de `/state`. Elle couvre aussi le refus d'un
montant d'achat incorrect, le crédit/replay exact de l'offre starter DEV, le
crédit/replay d'une pub, son cooldown, puis la révocation de session.
`validate_all.ps1 -ApiBaseUrl ... -ApiDevAddress ...` l'intègre à la gate quand
une instance locale `DEV_AUTH` dédiée est disponible.
La gate a été rejouée après R27 le 31/08/2026 : `API_CONTRACT_CHECK_OK`.

Gate sociale R28 reproductible : `tools/social_contract_check.ps1` crée deux
joueurs par deux instances DEV partageant PostgreSQL et `JWT_SECRET`, mais liées
à deux `DEV_ADDRESS` distinctes. Elle valide amitié/ciblage, Firewall 0→3, trois
Signal Jam bloqués, un dégât réel, revanche, réparation, Ghost Vault sans fuite
du plateau avec transfert conservatif et échange atomique de doublons. Les
rejeux Attack, Raid et Trade doivent être byte-identiques. Le test PostgreSQL
rejette aussi l'auto-ciblage et deux owners.

`validate_all.ps1 -ApiBaseUrl ... -ApiSecondaryAuthBaseUrl ...
-ApiDevAddress ... -ApiSecondaryDevAddress ...` enchaîne désormais les contrats
généraux et sociaux et échoue si la seconde instance manque. Les deux processus
de gate utilisent un quota local élevé ; cette configuration reste interdite en
production. Validation R28 : `API_CONTRACT_CHECK_OK`,
`SOCIAL_CONTRACT_CHECK_OK`, puis `CYBERSEEKER_VALIDATION_OK`.

Orchestration R29 : `tools/run_local_full_gate.ps1` rend cette passe
mono-commande. Il refuse les ports occupés, construit le serveur debug, génère
deux identités et un secret local, attend les deux `/ready`, lance toutes les
gates puis arrête ses deux PID dans un `finally`. Exécution de validation :
`LOCAL_FULL_GATE_OK`, puis contrôle externe `SERVER_PROCESSES=0` et
`GATE_LOGS=0`. Aucun APK/AAB construit.

## UX mobile locale

- Portrait, stretch `canvas_items/expand` et safe insets système.
- Navigation basse et contenus compensés par la safe area.
- Cibles principales de 64 px ; champs, menus et toggles au moins 52 px.
- Retour Android ferme d'abord la modale, revient ensuite au Spin, puis quitte.
- États chargement, hors-ligne, retry réseau et expiration de session présents.
- Aucun solde n'est fabriqué si le snapshot initial échoue ; un token mort est
  purgé au boot et le buffer analytics est isolé entre deux sessions joueur.
- Mouvement réduit coupe les redraw décoratifs continus inutiles.
- Six scènes instanciées sans erreur à 360×800, 540×1170 et 720×1280 ; le
  smoke ouvre aussi les overlays Network, Attack, Raid et résultat social.

Gate : `tools/mobile_ux_check.ps1` puis `tools/validate_all.ps1`.

## Durcissement R27

- La distribution live-ops parcourt toutes les occurrences encore claimables
  au lieu d'une constante de quatre. Un test couvre 180 fenêtres simultanément
  ouvertes pour la borne config 720 h / cadence 4 h.
- Les claims reconnaissent un événement fixe ou ses clés `eventId#n` sans
  wildcard SQL.
- `Ui.reward_text` rend les récompenses spins, crédits et coffres sans inventer
  `+0 SPINS`; le smoke couvre les formes credits-only, chest-only et mixte.
- `SpinScreen.gd` compte 989 lignes ; mapping visuel et télémétrie sont extraits,
  et `mobile_ux_check.ps1` bloque toute régression au-dessus de 1 000 lignes.
- Rust 1.97.1 : formatage et Clippy strict `--all-targets -D warnings` verts.
- Gate complète : 39 tests Rust, 12 tests PostgreSQL prouvés, 53 analytics et
  six scènes sur trois ratios portrait, sans APK/AAB.

## Pets

Aucun système, prototype, config, schéma ou dépendance Pets n'existe dans le
runtime. Rien n'a été créé ou remplacé. La gate mobile échoue si un identifiant
Pets est ajouté dans `client`, `server/src`, `server/migrations` ou `config`.

## Restes externes

- Wallet Adapter et coffre-fort de session natif.
- Provider Solana/indexeur NFT et vraie collection activée.
- Providers pub/paiement, HTTPS et observabilité hébergée.
- QA tactile, thermique, mémoire, réseau mobile et safe areas sur Seeker réel.
- Keystore release et soumission dApp Store.

Aucun de ces points n'est simulé comme prêt en production et aucun APK/AAB n'a
été généré pendant cette revue.
