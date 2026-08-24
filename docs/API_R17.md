# API R17 — CONTRATS CLIENT / SERVEUR

Toutes les routes de mutation exigent `Authorization: Bearer …`,
`Content-Type: application/json` et `X-Request-Id`. Une même clé rejoue la même
réponse sans répéter la mutation. Le serveur ignore tout prix ou récompense
calculé par le client.

## Lecture

- `GET /health` — liveness, version serveur/config.
- `GET /config` — configuration complète versionnée SHA-256.
- `GET /state` — soldes, district, inventaire, daily, missions, événements,
  saison et horloge serveur.
- `GET /events/:event_id/leaderboard` — top 50 et rang du joueur.

## Auth

- `POST /auth/challenge {address}`
- `POST /auth/verify {address,signature}`
- `POST /auth/refresh {refreshToken}`

## Mutations

- `POST /spin {requestId}`
- `POST /district/upgrade {districtId,elementId,requestId}`
- `POST /chest/buy {chestId,requestId}`
- `POST /chest/open {chestId,requestId}`
- `POST /set/claim {setId,requestId}`
- `POST /daily/claim {requestId}`
- `POST /mission/claim {missionId,requestId}`
- `POST /events/:event_id/claim {requestId}`
- `POST /season/claim {seasonId,tier,premium,requestId}`
- `POST /ad/reward {receipt,requestId}`
- `POST /purchase/verify {offerId,txSignature,tokenMint,amountU64,requestId}`
- `POST /analytics {events:[{name,props}]}`

## Erreurs

Format unique : `{ \"error\": { \"code\", \"message\", \"details\"? } }`.
Codes principaux : `BAD_REQUEST`, `UNAUTHORIZED`, `NOT_FOUND`,
`INSUFFICIENT_CREDITS`, `ALREADY_CLAIMED`, `UNAVAILABLE`, `NO_SPINS`,
`RATE_LIMITED`, `INTERNAL`.

Les routes publicité et achat n'acceptent les preuves `dev:*` qu'en compilation
debug avec `DEV_AUTH=true`. Hors de ce contexte, elles refusent de créditer tant
qu'un provider externe n'a pas été raccordé.

