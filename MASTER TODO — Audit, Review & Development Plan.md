# MASTER TODO — AUDIT + REVIEW + DEVELOPMENT

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

- [ ] Lire l'arborescence complète du repository.
- [ ] Identifier frontend, backend, shared code, configuration et données.
- [ ] Identifier la stack exacte utilisée.
- [ ] Identifier tous les systèmes déjà implémentés.
- [ ] Identifier tous les systèmes partiellement implémentés.
- [ ] Identifier les prototypes temporaires.
- [ ] Identifier le code mort / doublonné.
- [ ] Identifier les valeurs économiques hardcodées.
- [ ] Identifier les points faisant confiance au client alors qu'ils devraient être serveur-authoritative.
- [ ] Identifier les risques évidents de duplication de rewards.
- [ ] Identifier les problèmes potentiels de concurrence / double-click / double-claim.
- [ ] Vérifier la persistance joueur.
- [ ] Vérifier le RNG.
- [ ] Vérifier la gestion des erreurs.
- [ ] Vérifier le responsive/mobile.
- [ ] Vérifier les performances évidentes.
- [ ] Vérifier les dépendances inutiles ou fragiles.

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

- [ ] Vérifier le système de spin actuel.
- [ ] Vérifier que le résultat est déterminé de manière fiable.
- [ ] Vérifier que le client ne peut pas choisir son résultat.
- [ ] Vérifier consommation correcte des spins.
- [ ] Empêcher double spin accidentel.
- [ ] Empêcher spam réseau.
- [ ] Empêcher double reward.
- [ ] Prévoir état loading / animation / result.
- [ ] Prévoir reprise correcte après perte réseau.
- [ ] Prévoir idempotency côté backend.
- [ ] Vérifier animation fluide sur mobile.
- [ ] Prévoir feedback haptique.
- [ ] Prévoir feedback audio.
- [ ] Prévoir différents niveaux de célébration selon la récompense.

Le gameplay doit rester rapide.

Ne pas créer une animation de 5 secondes obligatoire pour chaque spin.

---

# 2. SPIN MULTIPLIER / BET

Ajouter ou auditer :

- [ ] x1
- [ ] x2
- [ ] x3
- [ ] x5
- [ ] x10
- [ ] autres valeurs configurables plus tard

Le multiplicateur :

- consomme davantage de spins ;
- multiplie les rewards appropriées ;
- doit être correctement intégré aux events ;
- ne doit jamais produire de valeurs incohérentes.

Le multiplicateur doit être DATA-DRIVEN.

---

# 3. SPIN REGENERATION

- [ ] Recharge automatique basée sur le temps serveur.
- [ ] Maximum gratuit configurable.
- [ ] Temps de recharge configurable.
- [ ] Calcul offline fiable.
- [ ] Affichage timer client.
- [ ] Aucun timer critique basé uniquement sur l'heure du téléphone.
- [ ] Gestion du retour après plusieurs heures/jours.

---

# 4. VIRTUAL CURRENCY

Une monnaie interne sans valeur monétaire réelle.

- [ ] Vérifier earning.
- [ ] Vérifier spending.
- [ ] Vérifier persistence.
- [ ] Vérifier grosses valeurs numériques.
- [ ] Prévoir progression pouvant atteindre des montants très élevés.
- [ ] Utiliser un système numérique adapté pour éviter overflow / imprécision.
- [ ] Prévoir notation UI : K / M / B / T / etc.

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

- [ ] Village data model.
- [ ] Structure data model.
- [ ] Upgrade levels.
- [ ] Upgrade costs.
- [ ] Visual state selon niveau.
- [ ] Completion detection.
- [ ] Village completion reward.
- [ ] Transition vers village suivant.
- [ ] Sauvegarde.
- [ ] Reprise correcte.
- [ ] Protection contre double-completion reward.

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

- [ ] progression des coûts ;
- [ ] récompenses ;
- [ ] vitesse de progression ;
- [ ] difficulté ;
- [ ] inflation monétaire.

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

- [ ] Collection inventory.
- [ ] New card detection.
- [ ] Duplicate detection.
- [ ] Collection progress UI.
- [ ] Missing card display.
- [ ] Card detail.
- [ ] Persistence.
- [ ] Data-driven card definitions.

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

- [ ] détecter completion ;
- [ ] empêcher double claim ;
- [ ] afficher célébration ;
- [ ] attribuer grosse récompense ;
- [ ] enregistrer set completed.

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

- [ ] quantity per card.
- [ ] affichage duplicates.
- [ ] architecture compatible avec futur trading.
- [ ] architecture compatible avec futur système d'échange.

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

- [ ] Achat en monnaie virtuelle.
- [ ] Loot serveur.
- [ ] Animation opening.
- [ ] Révélation cartes.
- [ ] New/duplicate visual feedback.
- [ ] Anti-double opening.
- [ ] Persistence.
- [ ] Configurable drop tables.

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
- achievements futurs.

Utilisations :

- classement ;
- unlock requirements ;
- prestige ;
- matchmaking événementiel éventuel.

Le nom final peut être différent de "Stars".

---

# PHASE 8 — SOCIAL

---

# 19. FRIEND SYSTEM

Selon architecture actuelle :

- [ ] profil joueur minimal ;
- [ ] friend system si pertinent ;
- [ ] inviter/retrouver joueur ;
- [ ] voir progression ;
- [ ] envoyer certaines ressources si design validé.

Ne pas transformer le jeu en réseau social.

---

# 20. CARD TRADING — FUTURE READY

Architecture uniquement pour l'instant.

Possibilité future :

```text
duplicate card
↔
duplicate card
```

PAS de SKR.

PAS de cash-out.

PAS de marketplace.

Ne pas implémenter avant validation produit.

---

# PHASE 9 — TEAMS / CLANS

PAS priorité MVP.

Mais prévoir architecture compatible plus tard avec :

- teams ;
- team leaderboard ;
- cooperative events ;
- chat limité ;
- donations.

Ne pas construire maintenant sauf si déjà largement avancé.

Si déjà implémenté :

faire review.

---

# PHASE 10 — DAILY LOOP

TRÈS IMPORTANT.

---

# 21. DAILY LOGIN

- [ ] Daily reward.
- [ ] Streak.
- [ ] Server timestamps.
- [ ] No device-time exploit.
- [ ] Reward config.
- [ ] UI claim.
- [ ] Duplicate protection.

---

# 22. DAILY BONUS

Possibilité :

- bonus wheel ;
- mystery reward ;
- free chest.

Choisir UNE première mécanique simple.

Ne pas créer trois systèmes identiques.

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

---

# 28. STARTER OFFER

Prévoir architecture pour :

```text
one-time purchase
new player eligibility
expiration window
```

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

---

# 30. REWARDED ADS

PAS DE PUB FORCÉE.

Uniquement :

```text
Watch ad
→
receive reward
```

- [ ] Daily cap.
- [ ] Cooldown.
- [ ] Server reward validation where possible.
- [ ] Failure handling.
- [ ] No reward before successful completion.

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

---

# 33. OWNERSHIP CHANGES

Si le NFT quitte le wallet :

les perks correspondants doivent disparaître après la prochaine vérification appropriée.

Si le NFT arrive :

les perks deviennent actifs.

Ne pas avoir besoin de redéployer l'application.

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

---

# PHASE 15 — REMOVE PET SYSTEM

## IMPORTANT

**NO PET SYSTEM.**

Nous supprimons volontairement cette mécanique.

- [ ] Vérifier si un système Pets existe déjà.
- [ ] Si aucun : ne rien créer.
- [ ] Si prototype incomplet : retirer proprement.
- [ ] Si dépendances existent : supprimer sans casser les autres systèmes.
- [ ] Nettoyer données/config/assets inutilisés.
- [ ] Ne pas remplacer automatiquement Pets par une mécanique équivalente.

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

Statut R24 : les 25 événements ci-dessus et les 8 événements sociaux validés
(Attack, Raid et réparation), soit 33 événements, sont instrumentés et couverts
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

- [ ] client-authoritative resources.
- [ ] manipulated timers.
- [ ] duplicate API calls.
- [ ] replay attacks.
- [ ] duplicate purchase credits.
- [ ] duplicate claims.
- [ ] leaderboard manipulation.
- [ ] invalid ownership claims.
- [ ] RNG predictability where relevant.
- [ ] race conditions.

Ne pas over-engineer.

Sécuriser surtout ce qui peut créer ou détruire de la valeur de jeu.

---

# PHASE 19 — MOBILE UX

Tout le jeu est pensé mobile.

Review :

- [ ] touch targets.
- [ ] responsive layout.
- [ ] portrait screens.
- [ ] animation performance.
- [ ] low-latency interactions.
- [ ] loading states.
- [ ] offline/error states.
- [ ] back button behavior.
- [ ] safe areas.
- [ ] different screen ratios.

L'expérience doit pouvoir être comprise avec très peu de texte.

---

# PHASE 20 — CODE QUALITY

Après chaque système significatif :

- [ ] tests pertinents ;
- [ ] lint/typecheck ;
- [ ] build ;
- [ ] inspect diff ;
- [ ] tester flow complet ;
- [ ] vérifier régressions.

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
