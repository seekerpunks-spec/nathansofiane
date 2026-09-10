# MASTER TODO — AUDIT + REVIEW + DEVELOPMENT

## Mise à jour R46 — Cohérence UI et MAP — 10/09/2026

Nouvelle place nocturne MAP, bâtiments agrandis et fenêtres de construction
harmonisées. Missions découpées en Daily/Events/Season/Settings, boutique et
fenêtres réseau/rencontres/résultats/classements/énergie reprises dans le thème.
Quatre nouveaux coffres assortis à Punk City ; illustrations R45 des cartes
conservées. Retour Android, défilement et actions tactiles couverts par le smoke.
Gate complète verte : 47 tests Rust, 16 PostgreSQL, contrats API/sociaux et
6 scènes sur 3 formats. Pas d'APK/AAB ni de modification économique.
Voir [livraison, inventaire et prompts R46](docs/R46_UI_COHERENCE.md).

## Correctif local — Quota réseau — 09/09/2026

À la demande du joueur, les requêtes d'authentification et de gameplay ne sont
plus limitées pour un serveur debug en DEV_AUTH depuis une adresse loopback.
Les connexions distantes, l'auth réelle et les builds release restent protégés.
Le JWT, la révocation de session, l'idempotence et les validations économiques
restent obligatoires. La gate utilise désormais le quota réel de 30/minute et
vérifie 61 lectures protégées consécutives sans refus en mode local.
Le message générique « NETWORK ERROR » du client reste une dette UX ; cette
modification supprime le quota local, pas toutes les causes possibles d'erreur.

## Mise à jour R45 — Collections crypto — 09/09/2026

COLLECTION remplace le raccourci RAID redondant dans la navigation. Cinq albums
de neuf cartes sont intégrés : Layer 1, Genesis Crew, DeFi District, Web3 Culture
et Class of 2017. Illustrations originales, logos crypto, raretés, doublons,
aperçu agrandi, coffres et récompenses de complétion.
Inventaire, identifiants, probabilités, prérequis et récompenses conservés.
Gate complète revérifiée : 46 tests Rust, dont 16 PostgreSQL, contrats API et
six scènes sur trois formats. Aucun APK/AAB, aucune intégration wallet.
Voir [livraison R45](docs/R45_CRYPTO_COLLECTIONS.md).

## Mise à jour R44 — Illustrations des bâtiments

Les 55 anciens sprites sont archivés et remplacés par 75 nouvelles illustrations
(25 bâtiments, trois évolutions), dans le thème de l'interface.
Imagegen puis détourage automatique explicitement autorisé. Économie inchangée,
gate complète verte : [livraison R44](docs/R44_BUILDING_ART.md).

## Mise à jour R43 — MAP

Refonte MAP dans le thème Punk City livrée et validée : sélection de bâtiments,
fiche d'amélioration, Build Bay, liste des districts et complétion.
Voir [livraison et tests MAP](docs/R43_MAP_DESIGN.md). Assets de bâtiments
existants réutilisés, aucune réécriture économique ni APK/AAB.

## Mise à jour R42 — 07/09/2026

La nouvelle demande explicite de refonte d'après l'image Punk City remplace le
gel du design et le brief skyline jour. L'accueil et le thème global sont en
R42, sans réécriture économique : voir [livraison et restant R42](docs/R42_REFERENCE_DESIGN.md).
Le remplacement de toutes les illustrations n'est **pas terminé** : la
génération des bâtiments a rencontré la limite d'images. Aucun APK/AAB ni
implémentation wallet dans ce lot. Ne pas rouvrir les fonctionnalités R41 déjà
validées simplement parce qu'elles figurent dans l'inventaire historique.

Tu travailles sur un jeu mobile live-service inspiré dans sa **structure de boucles** par Coin Master, mais avec une identité originale cyberpunk / crypto / Solana Seeker.

Le projet existe déjà et une partie du développement a été réalisée.

## RÈGLE ABSOLUE AVANT DE CODER

**NE SUPPOSE PAS qu'une fonctionnalité manque simplement parce qu'elle apparaît dans cette TODO.**

Pour CHAQUE système décrit ci-dessous :

1. inspecte le repository ;
2. détermine s'il existe déjà ;
3. si oui, fais une review complète ;
4. vérifie s'il correspond réellement aux spécifications ;
5. vérifie architecture, sécurité, UX et edge cases ;
6. conserve ce qui est bon ;
7. refactorise uniquement si nécessaire ;
8. complète seulement ce qui manque ;
9. ne réécris jamais gratuitement un système fonctionnel.

Le projet a déjà avancé dans cette direction.

L'objectif n'est donc PAS :

> "reconstruire tout le jeu"

mais :

> **comprendre → auditer → corriger → compléter → intégrer proprement.**

---

# PHASE 0 — AUDIT COMPLET DU PROJET

Avant toute grosse implémentation :

- [x] Lire l'arborescence complète du repository.
- [x] Identifier frontend, backend, shared code, configuration et données.
- [x] Identifier la stack exacte utilisée.
- [x] Identifier tous les systèmes déjà implémentés.
- [x] Identifier tous les systèmes partiellement implémentés.
- [x] Identifier les prototypes temporaires.
- [x] Identifier le code mort / doublonné.
- [x] Identifier les valeurs économiques hardcodées.
- [x] Identifier les points faisant confiance au client alors qu'ils devraient être serveur-authoritative.
- [x] Identifier les risques évidents de duplication de rewards.
- [x] Identifier les problèmes potentiels de concurrence / double-click / double-claim.
- [x] Vérifier la persistance joueur.
- [x] Vérifier le RNG.
- [x] Vérifier la gestion des erreurs.
- [x] Vérifier le responsive/mobile.
- [x] Vérifier les performances évidentes.
- [x] Vérifier les dépendances inutiles ou fragiles.

Créer ensuite un état synthétique :

```text
DONE
PARTIAL
MISSING
NEEDS REVIEW
NEEDS REFACTOR
BLOCKED BY DESIGN DECISION
```

Pour chaque système.

Ne commence PAS par réécrire le projet.

---

# PHASE 1 — CORE GAME LOOP

Boucle fondamentale :

```text
SPINS
↓
REWARDS
↓
VIRTUAL CURRENCY
↓
VILLAGE UPGRADES
↓
CHESTS
↓
CARDS
↓
COLLECTION COMPLETION
↓
LARGE SPIN REWARD
↓
MORE PROGRESSION
```

Cette boucle doit être extrêmement solide avant d'empiler les Live Ops.

---

# 1. SPIN SYSTEM

Auditer d'abord ce qui existe.

- [x] Vérifier le système de spin actuel.
- [x] Vérifier que le résultat est déterminé de manière fiable.
- [x] Vérifier que le client ne peut pas choisir son résultat.
- [x] Vérifier consommation correcte des spins.
- [x] Empêcher double spin accidentel.
- [x] Empêcher spam réseau.
- [x] Empêcher double reward.
- [x] Prévoir état loading / animation / result.
- [x] Prévoir reprise correcte après perte réseau.
- [x] Prévoir idempotency côté backend.
- [x] Vérifier animation fluide sur mobile.
- [x] Prévoir feedback haptique.
- [x] Prévoir feedback audio.
- [x] Prévoir différents niveaux de célébration selon la récompense.

Le gameplay doit rester rapide.

Ne pas créer une animation de 5 secondes obligatoire pour chaque spin.

---

# 2. SPIN MULTIPLIER / BET

Ajouter ou auditer :

- [x] x1
- [x] x2
- [x] x3
- [x] x5
- [x] x10
- [x] autres valeurs configurables jusqu'à ×100K

Le multiplicateur :

- consomme davantage de spins ;
- multiplie les rewards appropriées ;
- doit être correctement intégré aux events ;
- ne doit jamais produire de valeurs incohérentes.

Le multiplicateur doit être DATA-DRIVEN.

---

# 3. SPIN REGENERATION

- [x] Recharge automatique basée sur le temps serveur.
- [x] Maximum gratuit configurable.
- [x] Temps de recharge configurable.
- [x] Calcul offline fiable.
- [x] Affichage timer client.
- [x] Aucun timer critique basé uniquement sur l'heure du téléphone.
- [x] Gestion du retour après plusieurs heures/jours.

---

# 4. VIRTUAL CURRENCY

Une monnaie interne sans valeur monétaire réelle.

- [x] Vérifier earning.
- [x] Vérifier spending.
- [x] Vérifier persistence.
- [x] Vérifier grosses valeurs numériques.
- [x] Prévoir progression pouvant atteindre des montants très élevés.
- [x] Utiliser un système numérique adapté pour éviter overflow / imprécision.
- [x] Prévoir notation UI : K / M / B / T / Qa / Qi.

La monnaie sert notamment à :

- village ;
- coffres ;
- progression.

---

# PHASE 2 — VILLAGE / LEVEL PROGRESSION

Le terme **Village** est utilisé comme terme technique de gameplay.

La DA finale pourra utiliser un autre nom.

Chaque Village représente un niveau/scène prédéfini.

PAS de construction libre.

---

# 5. VILLAGE SYSTEM

Chaque village possède plusieurs structures.

Base de référence :

```text
5 structures
×
5 upgrade levels
```

Mais rendre ces valeurs configurables.

- [x] Village data model.
- [x] Structure data model.
- [x] Upgrade levels.
- [x] Upgrade costs.
- [x] Visual state selon niveau.
- [x] Completion detection.
- [x] Village completion reward.
- [x] Transition vers village suivant.
- [x] Sauvegarde.
- [x] Reprise correcte.
- [x] Protection contre double-completion reward.

---

# 6. DATA-DRIVEN VILLAGES

IMPORTANT.

Ajouter un nouveau village ne doit PAS nécessiter de modifier le moteur.

Chaque village doit pouvoir définir :

```text
id
name
background
structures
upgradeLevels
upgradeCosts
completionRewards
unlockRequirements
assets
```

Objectif :

pouvoir avoir à terme :

```text
Village 1
Village 20
Village 100
Village 500
Village 1000
```

sans architecture différente.

---

# 7. VILLAGE PROGRESSION CURVE

Créer une vraie couche de configuration permettant de contrôler :

- [x] progression des coûts ;
- [x] récompenses ;
- [x] vitesse de progression ;
- [x] difficulté ;
- [x] inflation monétaire.

NE PAS choisir arbitrairement la courbe finale.

Créer les outils/configs permettant de l'équilibrer plus tard.

---

# PHASE 3 — CARDS & COLLECTIONS

Deuxième grosse boucle du jeu.

---

# 8. CARD SYSTEM

Chaque carte doit avoir au minimum :

```text
cardId
setId
name
rarity
dropWeight
asset
ownedQuantity
```

Raretés configurables :

```text
Common
Uncommon
Rare
Epic
Legendary
```

- [x] Collection inventory.
- [x] New card detection.
- [x] Duplicate detection.
- [x] Collection progress UI.
- [x] Missing card display.
- [x] Card detail.
- [x] Persistence.
- [x] Data-driven card definitions.

---

# 9. CARD SETS

Chaque collection contient plusieurs cartes.

Référence possible :

```text
9 cards / set
```

Mais NE PAS hardcoder 9.

Chaque set définit :

```text
setId
cards[]
completionReward
unlockRequirement
visualTheme
```

---

# 10. COLLECTION COMPLETION

Quand toutes les cartes sont obtenues :

- [x] détecter completion ;
- [x] empêcher double claim ;
- [x] afficher célébration ;
- [x] attribuer grosse récompense ;
- [x] enregistrer set completed.

Les récompenses peuvent atteindre des valeurs importantes :

```text
1 000 spins
3 000 spins
10 000 spins
15 000 spins
etc.
```

Ce ne sont PAS des valeurs finales.

Le système doit accepter facilement ces ordres de grandeur.

---

# 11. DUPLICATE CARDS

Conserver les doublons.

- [x] quantity per card.
- [x] affichage duplicates.
- [x] architecture compatible avec trading.
- [x] système d'échange direct 1-pour-1 implémenté.

IMPORTANT :

**PAS DE MARKETPLACE FINANCIER ACTUELLEMENT.**

Ne pas développer de vente de cartes contre SKR.

---

# PHASE 4 — CHESTS

---

# 12. CHEST SYSTEM

Créer/auditer plusieurs catégories de coffres.

Exemple :

```text
Basic
Advanced
Rare
Elite
```

Chaque coffre :

```text
chestId
price
currency
numberOfCards
lootTable
unlockRequirement
```

- [x] Achat en monnaie virtuelle.
- [x] Loot serveur.
- [x] Animation opening.
- [x] Révélation cartes.
- [x] New/duplicate visual feedback.
- [x] Anti-double opening.
- [x] Persistence.
- [x] Configurable drop tables.

---

# 13. LOOT TABLES

Ne hardcoder aucune probabilité critique directement dans les composants UI.

Créer un système de configuration centralisé.

Pouvoir modifier :

- rareté ;
- poids ;
- niveau requis ;
- coffre ;
- événement ;
- éventuels modifiers.

---

# PHASE 5 — ATTACK & RAID

## ATTENTION : NE PAS COPIER COIN MASTER ICI.

Nous voulons conserver **DEUX grandes features séparées** occupant le rôle structurel de :

```text
ATTACK
et
RAID
```

Elles doivent rester importantes dans la boucle du spinner.

MAIS :

**nous ne voulons PAS simplement faire "Attack un village" et "Raid un joueur" comme Coin Master.**

Cette partie doit être repensée.

---

# 14. PREMIÈRE ÉTAPE : DESIGN REVIEW ATTACK / RAID

AVANT D'IMPLÉMENTER :

- [x] Étudier l'architecture actuelle.
- [x] Vérifier si Attack existe déjà.
- [x] Vérifier si Raid existe déjà.
- [x] Si oui, auditer mais NE PAS supprimer immédiatement.
- [x] Identifier leur rôle actuel dans la boucle.
- [x] Identifier ce qu'elles apportent psychologiquement :
  - interaction sociale ;
  - interruption de la boucle ;
  - jackpot ;
  - compétition ;
  - tension ;
  - revenge ;
  - surprise ;
  - redistribution de monnaie.

Ensuite :

### PROPOSER 5 CONCEPTS ORIGINAUX POUR LE SLOT "ATTACK"

et

### PROPOSER 5 CONCEPTS ORIGINAUX POUR LE SLOT "RAID"

adaptés à un univers :

```text
Cyberpunk
Crypto
Solana
Seeker
Hacking
Corporations
Networks
Digital infrastructure
```

Chaque proposition doit expliquer :

```text
Gameplay
Duration
Player interaction
Reward
Risk
Visual fantasy
Backend complexity
Retention potential
Difference from Coin Master
```

---

# 15. CONTRAINTES ATTACK / RAID

Les deux mécaniques doivent être :

- immédiatement compréhensibles ;
- jouables en quelques secondes ;
- compatibles mobile ;
- satisfaisantes ;
- fortes visuellement ;
- adaptées à des multiplicateurs ;
- compatibles avec leaderboards/events ;
- relativement simples techniquement ;
- originales.

Elles doivent avoir **deux sensations différentes**.

Exemple abstrait :

```text
Feature A = offensive/direct/instant
Feature B = discovery/choice/jackpot
```

Mais NE PAS considérer cet exemple comme la solution finale.

---

# 16. IMPORTANT — DESIGN GATE

**NE PAS implémenter la nouvelle version de Attack/Raid avant validation utilisateur.**

Tu dois d'abord remettre :

```text
ATTACK PROPOSALS
RAID PROPOSALS
RECOMMENDED COMBINATION
WHY
```

Puis attendre validation.

Tu peux seulement corriger les bugs fondamentaux de l'ancienne implémentation si nécessaire.

Statut R24 : cinq concepts Attack et cinq concepts Raid sont documentés dans
`docs/ATTACK_RAID_DESIGN.md`. La directive utilisateur ultérieure demande de
prendre les décisions produit et de poursuivre sans pause ; la combinaison
Signal Jam + Ghost Vault + Firewalls a donc été validée avant implémentation.

---

# PHASE 6 — DEFENSIVE SYSTEM

Coin Master possède Shields.

Notre jeu peut conserver cette fonction structurelle mais avec une identité originale.

---

# 17. DEFENSE SYSTEM

Réfléchir à une version cyberpunk :

Exemples conceptuels uniquement :

```text
Firewall
Security Node
ICE Shield
Network Defense
Cyber Barrier
```

Fonction :

- protéger contre la feature offensive ;
- être gagnée via spins/rewards ;
- avoir capacité limitée ;
- être consommée automatiquement ou selon règles.

Avant implémentation finale :

- [x] vérifier relation avec future Attack feature.

---

# PHASE 7 — STARS / ACCOUNT PROGRESSION

---

# 18. GLOBAL PROGRESSION SCORE

Créer/auditer un score global de progression.

Peut agréger :

- villages ;
- upgrades ;
- collections ;
- achievements permanents.

Utilisations :

- classement ;
- unlock requirements ;
- prestige ;
- matchmaking événementiel éventuel.

Le nom final peut être différent de "Stars".

Statut R24 : `Network Power` agrège upgrades, districts complétés, cartes uniques
pondérées par rareté, sets et achievements réclamés. Les poids et la limite de
leaderboard sont data-driven ; le score est recalculé transactionnellement aux
mutations. Sept contrats permanents cumulent les actions serveur `spin`,
`upgrade`, `chest_open`, `attack` et `raid`, avec claim et reward idempotents.

---

# PHASE 8 — SOCIAL

---

# 19. FRIEND SYSTEM

Selon architecture actuelle :

- [x] profil joueur minimal ;
- [x] friend system si pertinent ;
- [x] inviter/retrouver joueur ;
- [x] voir progression ;
- [x] envoyer certaines ressources : cadeau quotidien gratuit et borné entre
      amis, sans transfert libre de crédits/SKR.

Statut R24 : code ami stable, recherche bornée, demandes idempotentes,
accept/refus/suppression, classement global, journal Signal Jam et sélection
ami/revanche pour le prochain Signal Jam. Aucun transfert de ressource libre.

Ne pas transformer le jeu en réseau social.

---

# 20. CARD TRADING — FUTURE READY

Statut R24 : **implémenté en version sociale non financière** après la directive
utilisateur d'exécuter le MASTER TODO.

Possibilité future :

```text
duplicate card
↔
duplicate card
```

PAS de SKR.

PAS de cash-out.

PAS de marketplace.

- [x] échange direct 1 carte contre 1 carte entre amis ;
- [x] uniquement des doublons, avec conservation obligatoire d'un exemplaire ;
- [x] raretés échangeables data-driven, légendaires verrouillées actuellement ;
- [x] offres expirables, réservations implicites et plafond de pending ;
- [x] acceptation/refus/annulation idempotents et transfert atomique ;
- [x] historique et UI fonctionnelle dans Seeker Network ;
- [x] tests PostgreSQL de concurrence et quantités exactes.

Toujours aucun SKR, cash-out, NFT par carte ou marketplace.

---

# PHASE 9 — TEAMS / CLANS

Statut R24 : **socle léger implémenté** pour compléter la boucle sociale, sans
ajouter la complexité d'un réseau social complet :

- [x] création payée côté serveur, code et nom uniques ;
- [x] recherche, join/leave, capacité data-driven ;
- [x] owner, transfert et exclusion ;
- [x] score d'équipe dérivé de Network Power et leaderboard `DENSE_RANK` ;
- [x] UI mobile fonctionnelle et analytics ;
- [x] revue concurrence : join simultané rejoué sans membre dupliqué.
- [x] cooperative events — `Crew Uplink` réutilise les sources de points du
      moteur Neon Rush, avec score partagé, contribution personnelle minimale,
      milestones data-driven et claim unique par joueur même après changement
      d'équipe ;
- [x] chat limité — phrases remote-config uniquement, aucun texte libre ;
- [x] donations — demandes de spins en crew, plafonnées, atomiques et
      conservatrices ; aucun crédit, SKR ou cash-out.

---

# PHASE 10 — DAILY LOOP

TRÈS IMPORTANT.

---

# 21. DAILY LOGIN

- [x] Daily reward.
- [x] Streak.
- [x] Server timestamps.
- [x] No device-time exploit.
- [x] Reward config.
- [x] UI claim.
- [x] Duplicate protection.

---

# 22. DAILY BONUS

Possibilité :

- bonus wheel ;
- mystery reward ;
- free chest.

Choisir UNE première mécanique simple.

Ne pas créer trois systèmes identiques.

Statut R24 : **Signal Cache implémenté**. Un tirage quotidien distinct de la
série de connexion choisit côté serveur une récompense pondérée (spins, crédits
ou coffre). Config, horloge, RNG système, claim idempotent, audit, UI et analytics
sont couverts ; aucune roue graphique supplémentaire n'est créée.

---

# 23. DAILY MISSIONS

Exemples :

```text
Use X Spins
Upgrade X structures
Open X chests
Earn X currency
```

Toutes les missions data-driven.

Prévoir :

```text
missionType
target
reward
expiration
```

---

# PHASE 11 — EVENTS & LIVE OPS

C'est une des parties essentielles au potentiel économique du jeu.

---

# 24. GENERIC EVENT ENGINE

Ne pas coder chaque événement comme un système indépendant.

Créer un moteur générique capable de gérer :

```text
eventId
start
end
pointSources
multipliers
milestones
rewards
leaderboard
assets
```

Statut R24 : le même moteur alimente désormais les variantes individuelles,
classement et coopératives. `Crew Uplink` ne duplique aucune règle de scoring :
les actions configurées pour Neon Rush alimentent atomiquement le joueur, sa
saison et son équipe active.

---

# 25. EVENT MILESTONES

Exemple :

```text
100 points → spins
300 → currency
700 → chest
1500 → spins
...
```

- [x] progress bar ;
- [x] rewards tiers ;
- [x] claim ;
- [x] auto claim ou manual configurable ;
- [x] double claim protection.

---

# 26. TEMPORARY LEADERBOARDS

Durées potentielles :

```text
4h
8h
12h
24h
48h
```

- [x] grouping/cohorts.
- [x] score.
- [x] ranking.
- [x] reward tiers.
- [x] expiration.
- [x] distribution.
- [x] tie handling.
- [x] anti-cheat.

Ne pas mettre nécessairement tous les joueurs mondiaux dans le même leaderboard.

Prévoir cohortes configurables.

---

# PHASE 12 — MONETIZATION

---

# 27. PAID SPIN PACKS

Architecture permettant :

```text
offerId
price
currency
spinAmount
bonus
startDate
endDate
eligibility
```

Les achats doivent être vérifiés côté backend.

Ne jamais créditer seulement sur déclaration du client.

Statut R24 : packs de spins décrits par `contents`, prix, fenêtre, limite et
éligibilité. Le catalogue `GET /offers` est calculé côté serveur et l'achat
revalide les mêmes règles sous verrou. Le provider réel reste obligatoire hors dev.

---

# 28. STARTER OFFER

Prévoir architecture pour :

```text
one-time purchase
new player eligibility
expiration window
```

Statut R24 : `welcome_signal` est limité à un achat et aux sept premiers jours
du compte, indépendamment de l'horloge du client.

---

# 29. LIMITED OFFERS

Prévoir offres déclenchées par :

- spins empty ;
- village completion ;
- progression ;
- event ;
- retour joueur.

IMPORTANT :

Les offres doivent être pilotables par données.

Ne pas enfouir les règles commerciales dans les composants UI.

Statut R24 : règles génériques supportées pour âge du compte, spins maximum,
district minimum/maximum, événement actif et durée d'inactivité. Les offres
Emergency Uplink, Chrome Accelerator, Neon Rush Bundle et Return Signal exercent
ces déclencheurs ; l'UI ne lit plus directement la liste brute de config.

---

# 30. REWARDED ADS

PAS DE PUB FORCÉE.

Uniquement :

```text
Watch ad
→
receive reward
```

- [x] Daily cap.
- [x] Cooldown.
- [x] Server reward validation where possible.
- [x] Failure handling.
- [x] No reward before successful completion.

---

# 31. SEASON PASS

Pas nécessaire pour le premier prototype.

Mais architecture compatible avec :

```text
Free Track
Premium Track
XP / points
seasonStart
seasonEnd
tiers
rewards
```

Statut R24 : tracks free/premium, points, fenêtres, tiers et claims idempotents
sont data-driven. L'achat premium reste derrière le même provider vérifié.

---

# PHASE 13 — NFT HOLDER PERKS

Le projet peut reconnaître certains NFT existants détenus par le joueur.

IMPORTANT :

Le NFT ne représente PAS :

- un investissement promis ;
- un rendement financier ;
- du cash-out.

Il donne uniquement des **avantages in-game**.

Exemples potentiels :

- bonus daily spins ;
- +X% virtual rewards ;
- bonus de coffres ;
- badge holder ;
- interface spéciale ;
- rewards supplémentaires ;
- autres perks permanents tant que le NFT est détenu.

---

# 32. NFT OWNERSHIP CHECK

Architecture :

```text
Wallet
↓
Ownership verification
↓
Entitlement
↓
Perks
```

Le serveur doit conserver un système d'ENTITLEMENTS plutôt que disperser :

```text
if ownsNFT
```

partout dans le code.

Exemple :

```text
entitlements:
  ogHolder: true
  rewardMultiplier: 1.10
  dailySpinBonus: ...
```

Les valeurs doivent être configurables.

Statut R24 : **architecture locale implémentée, provider externe volontairement
non branché**. Les définitions et perks sont remote-config ; la table serveur
exige vérificateur, référence d'ownership, dates de vérification et expiration.
Aucune route client ne peut déclarer un NFT. Seules les lignes actives, non
expirées et correspondant à une définition activée produisent un entitlement.
La définition OG livrée est désactivée jusqu'au choix d'une collection vérifiée.

---

# 33. OWNERSHIP CHANGES

Si le NFT quitte le wallet :

les perks correspondants doivent disparaître après la prochaine vérification appropriée.

Si le NFT arrive :

les perks deviennent actifs.

Ne pas avoir besoin de redéployer l'application.

Le point d'entrée interne du futur provider fait un upsert `owned=true/false`
avec TTL dérivé de la config. Un transfert retire donc le perk au prochain check,
et toute panne prolongée du provider expire automatiquement le droit (fail-closed).
Le seul perk câblé à ce stade est un bonus de spins sur le daily login ; aucun
rendement, cash-out ou bénéfice financier n'est créé.

---

# PHASE 14 — OPTIONAL SKR REWARD POOL

NE PAS implémenter immédiatement sans validation explicite.

Concept étudié :

certaines grosses étapes de progression peuvent éventuellement contribuer à une récompense SKR réelle.

Mais le modèle doit être :

- limité ;
- budgété ;
- saisonnier ;
- configurable ;
- financé par une reward pool définie.

Ne jamais hardcoder une promesse :

```text
Village = guaranteed permanent X SKR forever
```

Préférer architecture future de type :

```text
Season Reward Pool
↓
Configured progression rewards
↓
Internal pending claim balance
↓
Minimum claim threshold
↓
Blockchain claim
```

IMPORTANT :

La taille de la pool peut évoluer avec la santé économique du jeu.

Plus le jeu génère de revenus, plus les saisons futures peuvent éventuellement avoir une reward pool importante.

Ne pas promettre que la reward augmentera automatiquement avec le nombre de joueurs.

Cette feature est **GATED / FUTURE**.

Statut R24 : l'architecture locale est prête mais livrée avec `enabled=false` et
`settlementEnabled=false`. Les allocations de district/achievement sont
data-driven, idempotentes et bornées par un budget global verrouillé dans
PostgreSQL. Le pending balance et le point d'entrée interne de settlement sont
couverts par tests, y compris en concurrence. Aucune route client, transaction
blockchain ou promesse de payout n'est exposée avant validation du provider.

---

# PHASE 15 — REMOVE PET SYSTEM

## IMPORTANT

**NO PET SYSTEM.**

Nous supprimons volontairement cette mécanique.

- [x] Vérifier si un système Pets existe déjà : aucun runtime, config ou schéma.
- [x] Si aucun : ne rien créer.
- [x] Si prototype incomplet : N/A, aucun prototype détecté.
- [x] Si dépendances existent : N/A, aucune dépendance détectée.
- [x] Nettoyer données/config/assets inutilisés : aucun artefact Pets détecté.
- [x] Ne pas remplacer automatiquement Pets par une mécanique équivalente.

Nous voulons éviter une feature supplémentaire sans nécessité.

---

# PHASE 16 — ANALYTICS

Ajouter/inventorier événements :

```text
session_start
spin_started
spin_completed
spins_empty
multiplier_changed
currency_earned
currency_spent
upgrade_started
upgrade_completed
village_completed
chest_opened
card_received
new_card
duplicate_card
set_completed
daily_claim
event_progress
milestone_claim
leaderboard_join
leaderboard_finish
rewarded_ad_offer
rewarded_ad_complete
purchase_offer_view
purchase_started
purchase_complete
```

Statut R24 : les 25 événements ci-dessus, 27 événements rétention/social et
`reward_pool_progress`, soit 53 événements, sont instrumentés et couverts
par la gate `tools/analytics_check.ps1`. Les batches sont bornés, validés et
dédupliqués côté serveur par `batchId` lors des retries réseau.

Pour Attack/Raid :

Les analytics sociaux ont été figés après validation de Signal Jam et Ghost Vault.

---

# PHASE 17 — REMOTE CONFIG / ECONOMY CONFIG

Toutes les valeurs importantes doivent être centralisées.

Notamment :

```text
spin regeneration
max spins
multipliers
reward weights
upgrade costs
chest prices
card drop weights
collection rewards
daily rewards
event rewards
leaderboard rewards
NFT perks
ad rewards
offers
```

L'objectif est de pouvoir équilibrer le jeu sans toucher à sa logique.

---

# PHASE 18 — SECURITY / ANTI-CHEAT

Faire audit explicite de :

- [x] client-authoritative resources.
- [x] manipulated timers.
- [x] duplicate API calls.
- [x] replay attacks.
- [x] duplicate purchase credits.
- [x] duplicate claims.
- [x] leaderboard manipulation.
- [x] invalid ownership claims.
- [x] RNG predictability where relevant.
- [x] race conditions.

Gate reproductible : `tools/security_check.ps1`. La revue R24 a notamment
corrigé la relecture idempotente sous verrou des claims finaux événement/saison ;
le retry concurrent season renvoie désormais deux réponses 200 identiques pour
un seul crédit de reward. Les nonces et le rate limiting sont stockés dans
PostgreSQL et mis à jour atomiquement : un test HTTP croisé entre deux processus
valide le challenge A / verify B, le rejet du replay et le quota commun.
Les refresh JWT utilisent aussi une rotation one-time-use avec `jti` hashé :
le test HTTP verify → refresh → replay confirme 200 → 200 → 401, puis le nouveau
refresh tourne à nouveau en 200. `POST /auth/logout` révoque la session courante
de façon idempotente et le client purge toujours access et refresh localement.
Le test HTTP confirme logout `200/true`, replay `200/false`, puis refresh `401`.
La passe overflow relit désormais le solde serveur après claim de set, borne la
régénération même au-delà de `i32` intervalles et protège streak, niveau et
progression de mission avant les additions PostgreSQL.
R28 automatise le playthrough HTTP à deux joueurs dans
`tools/social_contract_check.ps1` : amitié et ciblage, Firewall 0→3, trois Attack
bloquées puis un dégât, revanche, réparation, Raid sans fuite du plateau avec
débit/crédit conservatif, et échange atomique de deux doublons distincts. Les
rejeux des mutations critiques doivent être byte-identiques. La gate complète
exige deux instances DEV partageant PostgreSQL/JWT mais chacune liée à sa propre
`DEV_ADDRESS`. Les invariants DB refusent aussi auto-ciblage, statuts incohérents
et double owner.

R29 supprime toute orchestration manuelle : `tools/run_local_full_gate.ps1`
construit le serveur debug, vérifie que ses deux ports sont libres, démarre les
deux instances cachées avec identités/secrets éphémères, attend leur readiness,
enchaîne toute la gate R28 et arrête exactement les PID créés dans un `finally`.
Le chemin succès est vérifié sans processus ni journal temporaire résiduel. Ce
script ne demande et ne produit jamais d'APK/AAB.

Ne pas over-engineer.

Sécuriser surtout ce qui peut créer ou détruire de la valeur de jeu.

---

# PHASE 19 — MOBILE UX

Tout le jeu est pensé mobile.

Review :

- [x] touch targets.
- [x] responsive layout.
- [x] portrait screens.
- [x] animation performance locale et mode mouvement réduit.
- [x] low-latency interactions.
- [x] loading states.
- [x] offline/error states.
- [x] back button behavior.
- [x] safe areas.
- [x] different screen ratios (360×800, 540×1170, 720×1280).

Gate reproductible : `tools/mobile_ux_check.ps1` + smoke des six scènes aux
trois ratios. La validation appareil Seeker physique reste une dépendance externe.

L'expérience doit pouvoir être comprise avec très peu de texte.

---

# PHASE 20 — CODE QUALITY

Statut R27 : le monolithe `SpinScreen.gd` a été ramené de 1 798 à 989 lignes.
Le rendu du cabinet/reels/particules et le mapping des symboles, la composition
Seeker Network, ses actions asynchrones, les overlays Attack/Raid et la
télémétrie vivent maintenant dans cinq composants sans logique économique
cliente. Le smoke ouvre réellement Network, Attack, Raid et le résultat social,
et vérifie aussi les récompenses spins/crédits/coffres et les symboles du slot.
L'inventaire `tools/workspace_inventory.ps1` confirme aussi que les quatre
dossiers racine aux noms anormaux ne contiennent aucun fichier ; `server/target`
est le seul volume majeur et reste ignoré, sans nettoyage nécessaire au runtime.

Après chaque système significatif :

- [x] tests pertinents ;
- [x] lint/typecheck ;
- [x] build serveur/debug desktop sans APK intermédiaire ;
- [x] inspect diff ;
- [x] tester flow complet ;
- [x] vérifier régressions.

Quand tu corriges un bug :

**NE MODIFIE PAS 12 fichiers si un patch propre de 2 fichiers suffit.**

Cherche la root cause.

---

# PRIORITY ORDER

## P0 — IMMÉDIAT

1. Audit repository.
2. Stabiliser spin actuel.
3. Currency.
4. Village.
5. Upgrade progression.
6. Persistence.
7. Chest.
8. Cards.
9. Collections.
10. Collection rewards.
11. Spin regeneration.

---

## P1 — CORE RETENTION

12. Spin multiplier.
13. Daily reward.
14. Daily missions.
15. Event engine.
16. Milestones.
17. Temporary leaderboards.
18. Defensive system.

---

## P1.5 — DESIGN

19. Audit Attack/Raid existants.
20. Proposer 5 nouveaux concepts Attack.
21. Proposer 5 nouveaux concepts Raid.
22. Recommander la meilleure paire.
23. ATTENDRE validation.
24. Puis implémenter.

---

## P2 — MONETIZATION

25. Rewarded ads.
26. Spin packs.
27. Starter pack.
28. Limited offers.
29. Purchase verification.
30. Analytics funnel.

---

## P3 — ECOSYSTEM

31. Wallet integration.
32. NFT entitlement verification.
33. NFT holder perks.
34. Seeker integration.
35. Season pass.

---

## FUTURE / GATED

36. Teams.
37. Card trading.
38. SKR seasonal reward pool.
39. Advanced social features.
40. More complex Live Ops.

---

# FEATURES EXPRESSÉMENT EXCLUES

Pour éviter les mauvaises interprétations :

```text
❌ Pets
❌ Financial card marketplace
❌ Card cash-out
❌ NFT financial yield
❌ Real-time MMO
❌ Open world
❌ Character movement system
❌ Unnecessary social complexity
```

---

# PREMIER LIVRABLE QUE JE VEUX DE TOI

NE COMMENCE PAS PAR AJOUTER 30 FEATURES.

Commence par me rendre :

## 1. REPOSITORY AUDIT

Architecture actuelle.

## 2. FEATURE MATRIX

Pour chaque feature :

```text
DONE
PARTIAL
MISSING
BROKEN
NEEDS REVIEW
```

## 3. MAJOR RISKS

Maximum 10.

## 4. TECHNICAL DEBT

Uniquement dette réellement importante.

## 5. RECOMMENDED NEXT 5 TASKS

Dans l'ordre.

## 6. ATTACK / RAID STATUS

Ce qui existe actuellement et ce qu'il faudrait conserver/repenser.

Ensuite seulement, commence l'exécution des tâches validées.

---

# MODE DE TRAVAIL

Tu es le **senior engineer / technical lead** de ce projet.

Ne te comporte pas comme un générateur de code aveugle.

Avant une modification importante :

1. inspecte ;
2. comprends ;
3. détermine la root cause ;
4. modifie le minimum nécessaire ;
5. teste ;
6. review ton propre diff.

Si une feature existe déjà et fonctionne correctement :

**NE LA RÉÉCRIS PAS.**

Si elle existe mais diverge légèrement de cette spec :

**adapte-la progressivement.**

Si une décision produit manque :

**ne l'invente pas lorsque son impact est important.**

Signale-la et demande validation.

La priorité absolue est :

> **un core loop extrêmement solide, extensible et monétisable avant d'ajouter de la complexité.**
