# API R24 — CONTRATS CLIENT / SERVEUR

Toutes les routes de mutation de gameplay exigent `Authorization: Bearer …`,
`Content-Type: application/json` et `X-Request-Id`. Une même clé rejoue la même
réponse sans répéter la mutation. Le serveur ignore tout prix ou récompense
calculé par le client.

## Lecture

- `GET /health` — liveness, version serveur/config.
- `GET /ready` — readiness PostgreSQL et version de config.
- `GET /config` — configuration complète versionnée SHA-256.
- `GET /state` — soldes, district, inventaire, daily, missions, événements,
  saison, état fail-closed du reward pool et horloge serveur.
- `GET /offers` — uniquement les offres actuellement éligibles pour le joueur,
  avec type, fenêtre et nombre d'achats restants.
- `GET /events/:event_id/leaderboard` — classement `DENSE_RANK` et rang du
  joueur dans sa cohorte configurable. Les leaders exposent uniquement
  `{playerId,displayName,avatarId,points,rank}`, jamais l'adresse wallet.

## Auth

- `POST /auth/challenge {address}`
- `POST /auth/verify {address,signature}`
- `POST /auth/refresh {refreshToken}` — rotation one-time-use : le token présenté
  est consommé atomiquement et son replay renvoie `UNAUTHORIZED`.
- `POST /auth/logout {refreshToken}` — révocation idempotente de la session
  courante ; le client purge ses jetons même si le réseau est indisponible.

## Mutations

- `POST /spin {requestId,multiplier}` — multiplicateur présent dans
  `economy.spinMultipliers`; défaut rétrocompatible `1`.
  Réponse : `{outcome,multiplier,spinsSpent,baseCreditsGained,creditsGained,
  spins,credits,progress,nextSpinAtMs,serverTimeMs}`. `progress.events` contient
  les points ajoutés/totaux, la cohorte et les milestones auto-claimés.
  En DEV_AUTH uniquement, `debugOutcomeId` et `debugTargetAddress` permettent
  des tests déterministes ; ces champs sont refusés en production.
- `POST /district/upgrade {districtId,elementId,requestId}`
- `POST /district/repair {districtId,elementId,requestId}`
- `POST /attack/resolve {encounterId,elementId,requestId}`
- `POST /raid/pick {encounterId,nodeIndex,requestId}`
- `POST /raid/cashout {encounterId,requestId}`
- `GET|POST /profile` — profil public minimal / mise à jour du nom.
- `GET /players/search?q=...`, `GET /friends`
- `POST /friends/request|accept|decline|remove {friendCode,requestId}`
- `POST /social/target {friendCode,source,requestId}` — `friend` ou `revenge`,
  consommé par le prochain Signal Jam.
- `GET /progression/leaderboard`
- `GET /teams?q=...`, `GET /teams/leaderboard`
- `POST /teams/create {name,requestId}`
- `POST /teams/join {teamCode,requestId}`
- `POST /teams/leave {requestId}`
- `POST /teams/kick|transfer {friendCode,requestId}`
- `GET /trades` — incoming/outgoing, noms de cartes et règles actives.
- `POST /trades/create {recipientFriendCode,offeredCardId,requestedCardId,requestId}`
- `POST /trades/accept|decline|cancel {tradeId,requestId}` — échange direct
  atomique entre amis ; chaque joueur conserve au moins un exemplaire.
- `POST /chest/buy {chestId,requestId}`
- `POST /chest/open {chestId,requestId}`
- `POST /set/claim {setId,requestId}`
- `POST /daily/claim {requestId}`
- `POST /daily/bonus/claim {requestId}` — Signal Cache pondéré, une fois par
  jour serveur ; résultat et récompense mémorisés atomiquement.
- `POST /mission/claim {missionId,requestId}`
- `POST /events/:event_id/milestones/:milestone_index/claim {requestId}`
- `POST /events/:event_id/claim {requestId}`
- `POST /season/claim {seasonId,tier,premium,requestId}`
- `POST /ad/reward {receipt,requestId}`
- `POST /purchase/verify {offerId,txSignature,tokenMint,amountU64,requestId}`
  — revalide fenêtre, prix, limite et éligibilité sous verrou avant tout crédit.
- `POST /analytics {batchId,events:[{name,props}]}` — batch ≤ 100, props objet
  ≤ 8 Kio par événement, déduplication atomique par `(address,batchId)`.

## Erreurs

Format unique : `{ \"error\": { \"code\", \"message\", \"details\"? } }`.
Codes principaux : `BAD_REQUEST`, `UNAUTHORIZED`, `NOT_FOUND`,
`INSUFFICIENT_CREDITS`, `INSUFFICIENT_SPINS`, `ALREADY_CLAIMED`, `UNAVAILABLE`,
`RATE_LIMITED`, `INTERNAL`.

`INSUFFICIENT_SPINS` expose `requiredSpins`, `availableSpins` et
`nextSpinAtMs`. Le serveur ne remplace jamais silencieusement le multiplicateur.

Les routes publicité et achat n'acceptent les preuves `dev:*` qu'en compilation
debug avec `DEV_AUTH=true`. Hors de ce contexte, elles refusent de créditer tant
qu'un provider externe n'a pas été raccordé.
