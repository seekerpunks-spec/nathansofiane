# GAME DESIGN DOCUMENT — CYBERPUNK SEEKER SPIN GAME

> **Version 1.0 — 2026-08-20**
> Ce document est la source de vérité actuelle du projet. Toute décision structurante qui s'y ajoute doit y être documentée.

## 1. Objectif du projet

Je veux développer un **jeu mobile exclusivement pensé pour le Solana Seeker**, avec l'objectif de le distribuer à terme via le **Solana dApp Store**.

Le jeu doit être :

* mobile-first ;
* simple techniquement ;
* rapide à développer ;
* facile à comprendre ;
* très orienté rétention quotidienne ;
* fortement monétisable ;
* visuellement identifiable ;
* adapté aux habitudes des utilisateurs Seeker ;
* construit comme un live-service pouvant évoluer pendant longtemps.

L'inspiration principale pour la structure de gameplay et les boucles de rétention est **Coin Master**.

Il ne faut cependant PAS créer une copie de Coin Master.

Le jeu doit posséder :

* sa propre direction artistique ;
* ses propres noms ;
* ses propres personnages ;
* ses propres écrans ;
* ses propres événements ;
* ses propres collections ;
* sa propre progression.

L'objectif est uniquement de s'inspirer de la logique :

**SPINS → RÉCOMPENSES → PROGRESSION → COLLECTION → EVENTS → NOUVEAUX SPINS**

---

# 2. Direction artistique

L'univers est entièrement **cyberpunk / crypto / futuriste**.

## Ambiance générale

* ville futuriste ;
* nuit permanente ou majoritairement nocturne ;
* néons ;
* technologies holographiques ;
* terminaux ;
* serveurs ;
* cybercriminalité fictive ;
* hackers ;
* corporations ;
* quartiers futuristes ;
* infrastructure blockchain stylisée ;
* influences Solana / Seeker.

## Palette principale

Couleurs dominantes :

* noir ;
* bleu nuit ;
* violet ;
* magenta ;
* rose néon ;
* cyan ;
* bleu électrique.

Accents possibles :

* orange ;
* jaune ;
* vert électronique.

Le rendu doit être immédiatement identifiable sur un téléphone.

L'interface doit donner une sensation :

**crypto + cyberpunk + arcade + machine à récompenses.**

---

# 3. Plateforme

Le jeu est **MOBILE ONLY**.

Il n'y a pas de version desktop prévue pour le lancement.

La plateforme principale visée est :

**Solana Seeker / Android / Solana dApp Store**

Toutes les interfaces doivent donc être pensées pour :

* écran tactile ;
* navigation au pouce ;
* gros boutons ;
* sessions courtes ;
* animations rapides ;
* peu de texte ;
* transitions rapides ;
* temps de chargement réduit.

L'orientation portrait est recommandée pour la majorité du gameplay, sauf raison de design particulière.

---

# 4. Concept fondamental

Le joueur possède une réserve de **spins**.

Il utilise ces spins sur une machine / roue / interface cyberpunk.

Chaque spin produit un résultat.

Le résultat peut lui permettre de :

* gagner de la monnaie virtuelle ;
* progresser ;
* attaquer ou interagir avec un système futur ;
* obtenir des multiplicateurs ;
* avancer dans un événement ;
* gagner certains bonus.

La boucle centrale doit être extrêmement simple :

1. ouvrir le jeu ;
2. récupérer ses spins ;
3. utiliser les spins ;
4. gagner des ressources ;
5. améliorer son district ;
6. ouvrir des coffres ;
7. collectionner des cartes ;
8. compléter des collections ;
9. obtenir énormément de spins ;
10. recommencer.

---

# 5. Système de spins

Le **spin** est l'action principale du jeu.

Le joueur appuie sur un gros bouton.

Une animation courte se déclenche.

Le résultat est calculé côté serveur.

L'expérience doit être extrêmement satisfaisante.

Ajouter :

* sons courts ;
* feedback haptique ;
* animations ;
* anticipation avant gros résultat ;
* effets lumineux ;
* multiplicateurs ;
* confettis / glitches / explosions néon lors des grosses récompenses.

Les spins doivent pouvoir être exécutés rapidement.

Le joueur ne doit pas attendre plusieurs secondes inutilement entre deux spins.

---

# 6. Réserve de spins

Le joueur possède :

```text
currentSpins
maxFreeSpins
```

Les spins gratuits se rechargent progressivement.

Exemple conceptuel :

```text
1 spin toutes les X minutes
```

Les valeurs exactes seront déterminées par l'équilibrage.

IMPORTANT :

Toutes les valeurs doivent être configurables à distance.

Ne jamais hardcoder les valeurs économiques importantes.

---

# 7. Sources de spins

Le joueur peut recevoir des spins via :

* recharge temporelle ;
* daily rewards ;
* événements ;
* leaderboards ;
* progression ;
* collections complétées ;
* coffres spéciaux ;
* récompenses de district ;
* publicités récompensées ;
* cadeaux événementiels ;
* achats optionnels.

Les différentes sources doivent se nourrir entre elles.

---

# 8. Achat de spins

Lorsque le joueur manque de spins, il doit avoir plusieurs choix :

### Option 1

Attendre la recharge gratuite.

### Option 2

Obtenir une récompense disponible.

### Option 3

Regarder une publicité récompensée.

### Option 4

Acheter un pack de spins.

Les achats de spins constituent une **source majeure de revenus**.

Exemples de packs :

* Small Pack ;
* Medium Pack ;
* Large Pack ;
* Mega Pack ;
* Event Pack.

Ne pas fixer les noms définitivement dans le code.

Chaque offre doit pouvoir être configurée depuis des données externes.

---

# 9. Offres limitées

Le jeu doit pouvoir afficher des offres temporaires.

Exemple :

```text
NEON DEAL
2 HOURS LEFT

500 Spins
50M Credits
1 Rare Chest
```

Ces offres sont importantes pour la monétisation.

Elles peuvent apparaître après certains événements :

* plus de spins ;
* district terminé ;
* grosse récompense ;
* nouvelle collection ;
* nouveau joueur ;
* événement temporaire.

Mais elles ne doivent pas rendre l'interface insupportable.

---

# 10. Monnaie virtuelle interne

Le jeu possède une monnaie virtuelle.

Nom définitif à déterminer.

Exemples temporaires :

* Neon Credits ;
* Cyber Credits ;
* City Coins.

IMPORTANT :

Cette monnaie :

* n'est PAS une crypto ;
* n'est PAS du SKR ;
* n'est PAS échangeable contre du SKR ;
* n'a aucune valeur monétaire réelle ;
* ne peut pas sortir du jeu ;
* ne peut pas être convertie en argent.

Elle existe uniquement comme ressource de gameplay.

---

# 11. Utilité de la monnaie virtuelle

La monnaie virtuelle sert principalement à :

* améliorer les éléments d'un district ;
* débloquer certaines améliorations ;
* acheter des coffres ;
* progresser dans le jeu.

Le joueur doit toujours avoir quelque chose sur lequel dépenser ses crédits.

---

# 12. Progression par districts

Le joueur progresse à travers des **districts cyberpunk**.

Le système reprend la philosophie des villages de Coin Master.

Un district est une scène prédéfinie.

Ce n'est PAS un city-builder libre.

Le joueur ne déplace rien.

Chaque district possède plusieurs éléments améliorables.

Exemple :

## District 1 — Neon Slums

Éléments :

* appartement ;
* terminal ;
* station énergétique ;
* boutique ;
* antenne.

Chaque élément peut posséder plusieurs niveaux.

Exemple :

```text
Level 0
Level 1
Level 2
Level 3
Level 4
Level 5
```

Chaque amélioration change visuellement l'élément.

---

# 13. Exemple d'évolution visuelle

Exemple d'un bâtiment :

### Niveau 0

Ruine sombre.

### Niveau 1

Électricité installée.

### Niveau 2

Premiers néons.

### Niveau 3

Écrans holographiques.

### Niveau 4

Architecture avancée.

### Niveau 5

Version cyberpunk complète et spectaculaire.

Le joueur doit ressentir visuellement qu'il construit quelque chose.

---

# 14. Completion d'un district

Lorsque tous les éléments sont au niveau maximum :

```text
DISTRICT COMPLETE
```

Le joueur reçoit :

* récompense ;
* spins ;
* éventuellement coffre ;
* accès au district suivant.

Puis il passe à une nouvelle zone.

---

# 15. Progression extensible

Le système doit être **DATA-DRIVEN**.

Il doit être possible d'ajouter :

* District 10 ;
* District 20 ;
* District 100 ;
* District 500 ;

sans modifier la logique centrale du jeu.

Chaque district doit être défini par des données :

```text
id
name
background
elements
upgradeCosts
rewards
assets
```

---

# 16. Cartes à collectionner

Les cartes constituent une seconde boucle majeure.

Le joueur peut collectionner des cartes cyberpunk inspirées de l'univers crypto.

Exemple de collection :

## CRYPTO LEGENDS

* Bitcoin ;
* Solana ;
* SKR ;
* Genesis Block ;
* Validator ;
* Hash Power ;
* Cold Wallet ;
* etc.

IMPORTANT :

Créer des représentations graphiques originales.

Ne pas simplement reprendre des logos ou artworks existants sans vérifier les droits nécessaires.

---

# 17. Autres collections possibles

Exemples :

### Seeker Tech

* Seed Vault ;
* Mobile Node ;
* Neon Antenna ;
* Secure Chip.

### Hacker Tools

* Quantum Rig ;
* Ghost Terminal ;
* Data Spike ;
* Neural Key.

### Digital Relics

* Genesis Drive ;
* Broken Ledger ;
* Ancient Wallet ;
* Lost Block.

### Neon Districts

Cartes représentant différents lieux de l'univers.

---

# 18. Rareté des cartes

Structure potentielle :

```text
Common
Uncommon
Rare
Epic
Legendary
```

Le système doit être configurable.

Chaque carte possède :

```text
cardId
setId
rarity
image
dropWeight
ownedQuantity
```

---

# 19. Coffres

Les cartes sont principalement obtenues via des coffres.

Les coffres sont achetés avec la monnaie virtuelle interne.

PAS directement avec du SKR.

Exemples :

* Basic Chest ;
* Neon Chest ;
* Rare Chest ;
* Elite Chest.

Chaque coffre possède sa propre table de loot.

---

# 20. Loot tables

Les probabilités doivent être entièrement définies côté serveur.

Exemple :

```text
Basic Chest:
Common: 70%
Uncommon: 20%
Rare: 8%
Epic: 1.8%
Legendary: 0.2%
```

Ces chiffres sont uniquement des exemples.

Ne jamais utiliser ces valeurs comme équilibre définitif.

---

# 21. Compléter une collection

Lorsqu'un joueur possède toutes les cartes d'un set :

```text
COLLECTION COMPLETE
```

Cela doit être un des plus gros moments de récompense du jeu.

Le joueur reçoit énormément de spins.

Exemples envisagés selon difficulté :

```text
1 000 spins
3 000 spins
5 000 spins
10 000 spins
15 000 spins
```

Le montant dépend :

* difficulté du set ;
* rareté ;
* progression du joueur ;
* économie globale.

---

# 22. Boucle collection

La logique recherchée :

```text
Spin
↓
Gagner crédits
↓
Acheter coffre
↓
Recevoir cartes
↓
Collection presque complète
↓
Continuer à jouer
↓
Dernière carte obtenue
↓
Collection terminée
↓
Énorme récompense de spins
↓
Nouvelle grosse session
```

C'est une boucle essentielle.

---

# 23. Doublons

Les cartes peuvent tomber plusieurs fois.

Le joueur peut posséder des doublons.

Les doublons restent enregistrés.

Pour le MVP, ils peuvent éventuellement être :

* conservés ;
* utilisés dans certains événements ;
* échangés dans un système non financier futur.

Ne pas créer actuellement de marketplace financier.

---

# 24. Marketplace

DÉCISION ACTUELLE :

**AUCUN MARKETPLACE SKR DANS LE MVP.**

Les cartes :

* n'ont pas de prix réel ;
* ne peuvent pas être revendues ;
* ne peuvent pas être cash-out ;
* ne représentent pas un investissement ;
* n'ont pas de valeur financière promise.

Ne pas développer cette fonctionnalité tant qu'elle n'est pas explicitement redemandée.

---

# 25. Leaderboards

Le jeu doit avoir des compétitions temporaires.

Exemple :

```text
NEON RUSH

03:41:28 remaining
```

Les joueurs accumulent des points pendant l'événement.

Leaderboard :

```text
1. PlayerX — 12 450
2. PlayerY — 11 900
3. PlayerZ — 10 820
...
```

---

# 26. Récompenses leaderboard

À la fin :

### Top 1

Très grosse récompense.

### Top 2

Récompense importante.

### Top 3

Récompense importante.

Puis différents tiers :

```text
4-10
11-25
26-50
etc.
```

Récompenses possibles :

* spins ;
* crédits ;
* coffres ;
* bonus événementiels.

---

# 27. Durée des leaderboards

Prévoir différentes durées :

* 4 heures ;
* 8 heures ;
* 12 heures ;
* 24 heures ;
* week-end.

Cela permet de renouveler constamment la compétition.

Le joueur doit régulièrement sentir :

```text
"Je suis proche du prochain palier."
```

---

# 28. Événements

Le moteur doit supporter des événements temporaires.

Chaque événement possède :

```text
eventId
startTime
endTime
rules
pointSources
rewardTiers
assets
```

Exemple :

### Neon Raid

Certains résultats de spin donnent des points.

### Blockchain Rush

Certaines combinaisons produisent des multiplicateurs.

### Seeker Weekend

Récompenses spéciales pendant 48 heures.

---

# 29. Daily rewards

Chaque jour :

```text
DAILY REWARD AVAILABLE
```

Le joueur reçoit une récompense.

Exemple :

### Jour 1

50 spins.

### Jour 2

75 spins.

### Jour 3

100 spins.

### Jour 4

Coffre.

### Jour 5

150 spins.

etc.

Toutes les valeurs restent configurables.

---

# 30. Daily missions

Objectifs simples :

```text
Use 50 Spins
Upgrade 3 Buildings
Open 2 Chests
Earn 1M Credits
```

Récompense :

* spins ;
* crédits ;
* coffres.

Les missions doivent être extrêmement simples à comprendre.

---

# 31. Rewarded Ads

Aucune publicité forcée.

Le joueur choisit volontairement.

Exemple :

```text
OUT OF SPINS

Wait 12:41
Watch Ad → +25 Spins
Get Spins
```

Le bouton de publicité doit être optionnel.

Limiter le nombre de pubs disponibles par jour.

Exemple configurable :

```text
maxRewardedAdsPerDay
rewardPerAd
cooldown
```

---

# 32. Sources de revenus

Le jeu est conçu pour générer du revenu.

## Source 1 — Packs de spins

Source principale potentielle.

---

## Source 2 — Starter Pack

Exemple :

```text
WELCOME PACK

500 Spins
5M Credits
2 Chests
```

---

## Source 3 — Offres temporaires

Exemple :

```text
90% BONUS
30 MINUTES LEFT
```

---

## Source 4 — Season Pass

Système saisonnier avec :

* progression gratuite ;
* progression premium.

---

## Source 5 — Rewarded Ads

Le joueur regarde une publicité volontairement.

Le développeur reçoit les revenus publicitaires.

---

## Source 6 — Event Bundles

Offres temporaires liées à un événement.

---

# 33. Philosophy de monétisation

Le joueur gratuit doit pouvoir jouer.

Le jeu ne doit PAS être bloqué derrière un paiement obligatoire.

La tension économique vient du fait que le joueur veut :

```text
CONTINUER MAINTENANT
```

Lorsque les spins sont vides, plusieurs possibilités :

```text
attendre
récompense
pub
achat
```

Les achats vendent principalement du **temps et de la continuité de session**, pas un accès exclusif au jeu.

---

# 34. Season Pass

Le jeu peut posséder des saisons.

Exemple :

```text
SEASON 01 — NEON GENESIS
```

Le joueur gagne des points grâce à son activité.

Deux tracks :

```text
FREE
PREMIUM
```

Le premium peut contenir :

* spins ;
* coffres ;
* crédits ;
* éléments de collection spéciaux ;
* bonuses événementiels.

---

# 35. Intégration Seeker

Le jeu doit être pensé pour le Solana Seeker dès le départ.

L'utilisation blockchain doit rester minimale.

La blockchain peut servir principalement pour :

* authentification wallet si nécessaire ;
* achats en SKR ;
* fonctionnalités explicitement Web3.

Elle ne doit PAS servir à enregistrer chaque action.

Un spin normal n'est PAS une transaction blockchain.

Une carte normale n'est PAS nécessairement un NFT.

Une amélioration n'est PAS une transaction blockchain.

---

# 36. Paiements

Les paiements liés au Web3 doivent être isolés du gameplay.

Exemple :

```text
Player chooses Pack
↓
App generates payment request
↓
Wallet confirmation
↓
Transaction submitted
↓
Backend verifies transaction
↓
Backend credits spins
```

IMPORTANT :

Ne jamais créditer un achat uniquement parce que le client affirme que la transaction existe.

Toujours vérifier côté serveur.

---

# 37. Architecture serveur

Le backend doit être **AUTHORITATIVE**.

Le client ne décide jamais :

* du résultat RNG ;
* du nombre de spins ;
* du solde ;
* des récompenses ;
* des cartes ;
* des coffres ;
* des points leaderboard.

---

# 38. Exemple de spin

Client :

```text
POST /spin
```

Serveur :

1. authentifie le joueur ;
2. vérifie le nombre de spins ;
3. applique éventuellement multiplicateur ;
4. retire le coût ;
5. génère résultat sécurisé ;
6. calcule récompense ;
7. modifie progression ;
8. sauvegarde ;
9. retourne résultat.

Puis seulement le client joue l'animation.

---

# 39. Anti-triche

Priorité importante car l'économie du jeu dépend des ressources.

Prévoir :

* backend authoritative ;
* validation serveur ;
* rate limiting ;
* timestamps serveur ;
* transaction IDs ;
* idempotency ;
* logs ;
* contrôle des rewards ;
* contrôle des purchases ;
* protection double claim ;
* leaderboard validation.

---

# 40. Remote Config

L'économie doit pouvoir être modifiée sans publier une nouvelle version de l'application.

Paramètres :

```text
spinRegen
maxSpins
chestPrices
upgradePrices
dropRates
eventRewards
dailyRewards
adRewards
offerPrices
offerContents
```

Cela est indispensable pour équilibrer le jeu après lancement.

---

# 41. Analytics

Le jeu doit être mesurable.

Événements importants :

```text
app_open
session_start
spin
spins_empty
currency_earned
upgrade
district_complete
chest_open
card_drop
collection_complete
daily_reward_claimed
event_join
leaderboard_reward
rewarded_ad_started
rewarded_ad_completed
purchase_screen_open
purchase_started
purchase_completed
```

---

# 42. KPI à suivre

Priorité :

### D1 Retention

Combien reviennent le lendemain.

### D7 Retention

Combien reviennent après 7 jours.

### D30 Retention

Combien restent après un mois.

### Sessions per day

### Spins per player

### ARPDAU

Average Revenue Per Daily Active User.

### Conversion rate

Pourcentage qui achètent.

### Ad engagement

### Purchase frequency

---

# 43. Live Ops

Le jeu doit pouvoir évoluer sans modification du moteur.

Live Ops permet de changer :

* événements ;
* offres ;
* bonus ;
* multiplicateurs ;
* rewards ;
* leaderboards ;
* nouvelles collections ;
* nouveaux districts.

Le moteur doit être conçu pour recevoir ce contenu.

---

# 44. Infrastructure scalable

Le jeu doit pouvoir commencer petit.

Ne PAS acheter une infrastructure énorme dès le début.

Prévoir une architecture cloud :

* scalable ;
* pay-as-you-go ;
* autoscaling ;
* base de données adaptée ;
* CDN pour assets ;
* backups.

Le système doit pouvoir monter progressivement avec le nombre de joueurs.

---

# 45. MVP recommandé

Première version :

## Core

* login ;
* écran principal ;
* spins ;
* RNG backend ;
* monnaie virtuelle ;
* premier district ;
* upgrades ;
* progression ;
* coffres ;
* cartes ;
* collections.

## Rétention

* spin regeneration ;
* daily reward ;
* leaderboard simple ;
* un événement.

## Monétisation

* rewarded ads ;
* starter pack ;
* packs de spins.

## Backend

* comptes ;
* sauvegarde ;
* anti-triche minimum ;
* analytics ;
* remote config.

---

# 46. À NE PAS développer dans le premier MVP

Ne pas perdre de temps avec :

* monde ouvert ;
* déplacement personnage ;
* multijoueur temps réel ;
* chat ;
* marketplace ;
* trading financier ;
* NFT pour chaque carte ;
* économie cash-out ;
* éditeur complexe ;
* avatars très personnalisables.

Le produit repose sur ses boucles, pas sur sa complexité technique.

---

# 47. Priorité de développement

Ordre :

1. Spin prototype.
2. RNG serveur.
3. Rewards.
4. Monnaie.
5. District.
6. Upgrade.
7. Sauvegarde.
8. Coffres.
9. Cartes.
10. Collections.
11. Récompenses de collections.
12. Recharge des spins.
13. Daily rewards.
14. Leaderboard.
15. Event system.
16. Rewarded ads.
17. Achats.
18. Analytics.
19. Remote config.
20. Polish.
21. Seeker integration.
22. Release.

---

# 48. Philosophie technique

Le jeu doit être :

```text
simple à maintenir
simple à équilibrer
simple à étendre
```

Ne pas créer une architecture prématurément complexe.

Quand une nouvelle fonctionnalité est ajoutée :

1. expliquer brièvement où elle s'insère ;
2. vérifier ses dépendances ;
3. implémenter de façon modulaire ;
4. ne pas casser les systèmes existants ;
5. ajouter analytics appropriés.

---

# 49. Philosophie produit

La force du jeu doit venir de **plusieurs boucles imbriquées**.

Le joueur ne doit jamais avoir seulement :

```text
"Je n'ai plus de spins, je ferme."
```

Il doit éventuellement penser :

```text
Je peux récupérer mon daily.
Je peux finir cet event.
Je suis proche du top 10.
Il me manque une carte.
Mon district est presque terminé.
Un coffre est disponible.
Une pub peut me donner quelques spins.
```

Puis ces actions lui rendent des spins.

Cette mécanique doit provoquer une boucle naturelle.

---

# 50. Objectif final

Créer un jeu mobile cyberpunk accessible sur Solana Seeker reposant sur :

**SPINS**

*

**PROGRESSION**

*

**DISTRICTS**

*

**CARDS**

*

**COLLECTIONS**

*

**EVENTS**

*

**LEADERBOARDS**

*

**DAILY LOOP**

*

**REWARDED ADS**

*

**PURCHASES**

Le projet doit être relativement simple techniquement mais extrêmement travaillé en termes :

* d'équilibrage ;
* de rétention ;
* de progression ;
* d'économie ;
* de live operations.

Le moteur doit pouvoir supporter une évolution continue si le jeu rencontre du succès.

---

# 51. Instructions spécifiques

Considère ce document comme **la source de vérité actuelle du projet**.

Ne suppose aucune information extérieure à ce document.

Si une information importante manque, demande-la avant de prendre une décision structurante.

Ne crée pas spontanément :

* marketplace ;
* système cash-out ;
* trading SKR ;
* MMO ;
* monde social ;
* mechanics non demandées.

Lorsque tu proposes du code :

* privilégie la simplicité ;
* code modulaire ;
* séparation claire client/backend ;
* backend authoritative ;
* économie configurable ;
* sécurité des ressources ;
* mobile-first ;
* live-service ready.

Lorsqu'une valeur économique est inconnue, utilise une constante/configuration temporaire clairement signalée au lieu de présenter une valeur arbitraire comme définitive.

L'objectif n'est pas de reproduire Coin Master.

L'objectif est de créer **un jeu cyberpunk original pour Seeker utilisant une architecture de boucles de rétention comparable dans son efficacité**.
