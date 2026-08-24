# API R24 — CONTRATS CLIENT / SERVEUR

Toutes les routes de mutation exigent `Authorization: Bearer …`,
`Content-Type: application/json` et `X-Request-Id`. Une même clé rejoue la même
réponse sans répéter la mutation. Le serveur ignore tout prix ou récompense
calculé par le client.

## Lecture

- `GET /health` — liveness, version serveur/config.
- `GET /config` — configuration complète versionnée SHA-256.
- `GET /state` — soldes, district, inventaire, daily, missions, événements,
  saison et horloge serveur.
- `GET /events/:event_id/leaderboard` — classement `DENSE_RANK` et rang du
  joueur dans sa cohorte configurable.

## Auth

- `POST /auth/challenge {address}`
- `POST /auth/verify {address,signature}`
- `POST /auth/refresh {refreshToken}`

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
- `POST /chest/buy {chestId,requestId}`
- `POST /chest/open {chestId,requestId}`
- `POST /set/claim {setId,requestId}`
- `POST /daily/claim {requestId}`
- `POST /mission/claim {missionId,requestId}`
- `POST /events/:event_id/milestones/:milestone_index/claim {requestId}`
- `POST /events/:event_id/claim {requestId}`
- `POST /season/claim {seasonId,tier,premium,requestId}`
- `POST /ad/reward {receipt,requestId}`
- `POST /purchase/verify {offerId,txSignature,tokenMint,amountU64,requestId}`
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
