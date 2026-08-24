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
- Le RNG de spin et du bonus quotidien utilise `OsRng`.
- Les leaderboards sont dérivés de tables autoritaires et utilisent `DENSE_RANK`.
- Les entitlements n'ont aucune route de self-claim, exigent un provider interne,
  une définition activée et une expiration future.
- Les contraintes SQL protègent soldes, inventaires, claims uniques et relations.

Gate : `tools/security_check.ps1`.

## UX mobile locale

- Portrait, stretch `canvas_items/expand` et safe insets système.
- Navigation basse et contenus compensés par la safe area.
- Cibles principales de 64 px ; champs, menus et toggles au moins 52 px.
- Retour Android ferme d'abord la modale, revient ensuite au Spin, puis quitte.
- États chargement, hors-ligne, retry réseau et expiration de session présents.
- Mouvement réduit coupe les redraw décoratifs continus inutiles.
- Six scènes instanciées sans erreur à 360×800, 540×1170 et 720×1280.

Gate : `tools/mobile_ux_check.ps1` puis `tools/validate_all.ps1`.

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
