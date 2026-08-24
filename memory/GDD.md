# MÉMOIRE — GDD (condensé)

> Version condensée pour reprise rapide. Source de vérité complète : `docs/GDD.md` (51 sections). Ne pas résumer ici ce qui n'y est pas.

## Concept
Spin game cyberpunk/mobile (portrait) pour Solana Seeker / dApp Store. Structure de boucle inspirée de Coin Master, univers/noms/branding 100% originaux (pas une copie).

**Boucle centrale** : SPINS → récompenses → progression → collection → events → nouveaux spins.

## Spin
- Action principale : gros bouton → POST /spin → résultat calculé **côté serveur uniquement**.
- Réserve : `currentSpins` / `maxFreeSpins`, regen temporelle (1 spin / X min).
- Sources de spins : regen, dailies, events, collections complétées, coffres, missions, pubs récompensées, achats.
- Quand plus de spins : attendre / récompense / pub / achat (les 4 options toujours présentes).

## Monnaie (crédits)
- Monnaie virtuelle interne uniquement. **PAS une crypto, PAS du SKR, aucun cash-out, aucune valeur réelle, ne sort pas du jeu.**
- Utilité : upgrades de district, coffres, progression. Toujours quelque chose à acheter.

## Progression : districts
- Scènes prédéfinies (pas de city-builder libre), data-driven (`config/districts/*.json`).
- Chaque district : N éléments × 6 niveaux, changement visuel par niveau, coût en crédits.
- District complété → gros reward (spins + coffre) → district suivant. Extensible à l'infini sans toucher au moteur.
- District 01 : "Neon Slums" (5 éléments).

## Cartes & coffres
- Coffres achetés **en crédits** (jamais en SKR), chacun avec sa loot table serveur.
- Cartes avec rareté configurable (Common → Legendary). Sets/collections : Crypto Legends, Seeker Tech, Hacker Tools, Digital Relics, Neon Districts (représentations graphiques ORIGINALES, pas de logos existants).
- Collection complétée = un des plus gros moments du jeu → énorme reward de spins (1k–15k selon difficulté, configurable).
- Doublons : conservés (qty), pas de marketplace.

## Interdictions MVP (règles dures)
- **AUCUN** marketplace, trading, cash-out, promesse de valeur financière, NFT par carte.
- **AUCUN** MMO, monde ouvert, chat, temps réel, éditeur, avatars lourds.
- Monétisation = vente de **temps/continuité de session**, jamais d'accès exclusif au jeu. Joueur gratuit toujours jouable.

## Rétention
- Dailies (streak), missions simples, leaderboards temporaires (4h → week-end, paliers de récompense), événements temporaires (moteur data-driven), offres limitées temporisées (NEON DEAL style), Season Pass (M5+).

## Web3 (minimal)
- Login wallet obligatoire. Blockchain utilisée seulement pour : identité, achats SKR. **Un spin normal n'est PAS une transaction on-chain.** Un coffre n'est PAS un NFT.

## Monétisation (priorité)
1. Packs de spins (source principale) — Small/Medium/Large/Mega/Event, contenu configurable.
2. Starter pack. 3. Offres temporaires (bonus % + timer). 4. Rewarded ads (optionnel, quotidiennes, limitées). 5. Season Pass premium. 6. Event bundles.

## Économie
- **Aucune valeur économique hardcodée** — tout dans `config/` (remote config versionnée, modifiable sans release). Les valeurs actuelles sont PROVISIONAL.

## KPI
D1/D7/D30 retention, sessions/jour, spins/player, ARPDAU, conversion, ad engagement.
