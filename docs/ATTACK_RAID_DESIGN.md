# CYBERSEEKER — DESIGN REVIEW ATTACK / RAID R24

## Rôle dans la boucle

Le serveur ne possède actuellement ni Attack, ni Raid, ni défense. La paire doit
interrompre le slot pendant 3 à 10 secondes, créer une interaction sociale lisible,
redistribuer une part contrôlée de l'économie et alimenter revenge, événements et
classements. Le résultat du spin ouvre une action serveur pending : aucun montant,
plateau ou blocage n'est décidé par le client.

## Cinq concepts Attack

1. **Signal Jam — retenu.** Choisir un nœud construit du district rival ; un
   Firewall bloque automatiquement, sinon le nœud devient `jammed` et doit être
   réparé. 3–5 s, rival réel ou corporation fallback, reward instantané multiplié,
   risque nul pour l'attaquant. Fantaisie : impulsion réseau. Backend moyen.
   Rétention forte via journal/revenge. Différence : statut temporaire et réparation,
   pas de bâtiment écrasé ou de personnage copié.
2. **Drone Intercept.** Taper au bon moment pour détourner un drone cargo adverse.
   4 s, reward selon timing, échec possible. Fantaisie très lisible, backend faible,
   mais dépend davantage d'une validation de timing client difficile à sécuriser.
3. **Power Surge.** Router une surcharge dans l'un de trois circuits ; la défense
   peut déplacer la charge. 5–7 s, duel asynchrone, reward moyen. Backend moyen,
   bon mind-game mais moins immédiat pour un nouveau joueur.
4. **Bounty Trace.** Choisir un rival dans une courte liste et révéler sa prime.
   3 s, compétition/revenge forte, reward variable. Backend faible, mais la sensation
   offensive est trop abstraite et moins satisfaisante visuellement.
5. **Firewall Duel.** Trois paquets simultanés, choisir attaque gauche/centre/droite
   face à une règle de défense prédéfinie. 6–8 s, risque de blocage, backend moyen.
   Bonne profondeur, mais trop lent pour la fréquence d'un résultat de slot.

## Cinq concepts Raid

1. **Ghost Vault — retenu.** Six nœuds chiffrés, trois accès maximum. Les caches
   augmentent le butin non encaissé ; une trace le détruit. Le joueur peut cash-out
   après chaque accès sûr. 5–10 s, cible sociale ou corporation fallback, jackpot
   multiplié et risque explicite. Backend moyen/élevé. Différence : push-your-luck
   et cash-out, pas trois fouilles garanties.
2. **Packet Chase.** Suivre trois paquets parmi des routes qui se croisent. 6 s,
   reward par paquet suivi, risque faible. Backend faible, mais trop dépendant d'une
   animation de suivi et peu accessible en mouvement réduit.
3. **Ledger Dive.** Choisir une profondeur 1–3 dans un bloc ; plus profond vaut plus
   mais peut être vide. 3–5 s, jackpot pur, backend faible. Simple mais interaction
   sociale et agency trop faibles.
4. **Courier Hijack.** Choisir un des trois itinéraires d'un transport rival, avec
   information partielle. 5 s, gain ou échec total. Backend moyen, bonne tension,
   mais sensation proche d'un simple pile ou face.
5. **Black ICE Run.** Enchaîner des portes tant qu'aucune ICE n'est révélée, cash-out
   libre. 8–15 s, potentiel de jackpot très fort. Backend moyen, excellente tension,
   mais durée trop longue pour la boucle principale.

## Combinaison retenue

**Signal Jam + Ghost Vault + Firewall charges.** Signal Jam est direct, déterministe
et social ; Ghost Vault est exploratoire, optionnellement risqué et jackpot. Les
Firewalls protègent uniquement Signal Jam, sont gagnés au slot à raison de N
charges pour une mise ×N, ont une capacité
limitée et se consomment automatiquement. Les multiplicateurs scalent les crédits,
jamais la probabilité ni le nombre de choix. Les cibles sans rival disponible sont
des corporations serveur afin qu'aucun joueur ne soit bloqué au lancement.

Décision d'exécution : la directive utilisateur R24 demande d'avancer sans pause et
de prendre les décisions produit. La gate de validation du plan est donc satisfaite
par cette combinaison explicitement choisie avant l'implémentation.
