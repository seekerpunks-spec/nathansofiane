# MÉMOIRE — ÉTAT ACTUEL R41 + reset DA

> MAJ 07/09/2026. R41 = hardening/fermeture MASTER TODO local. Le runtime visuel
> reste R39 ; le home/mockup R40 est **abandonné**.

## Design

Reset user : rien ne va. Plus de Punk City, plus de rails, plus de
`SpinHomeChrome`. Client visuel = commit `4bb98d3` (R34–R39).
Brief DA : **skyline jour jouet**. Frame 1 (monde vide, pas de HUD/slot)
en staging `art/api_gpt_image/skyline_jour_jouet_v1.png` — **pas encore
câblée**. Attente oui/non user.

## Gameplay et plateforme R41

MASTER TODO local fermé : cadeau ami quotidien, chat rapide crew et entraide
spins ajoutés. Challenge auth lié au domaine, confidentialité export/delete,
rétentions configurables et workflow CI GitHub (exécution distante à confirmer).
22 modules Rust, 23 migrations.

Revue du 07/09 : access JWT lié à sa session (invalide après recréation),
nonce consommé seulement après signature valide, effacement/recréation sérialisés,
exports sociaux sans wallets tiers, dons avec régénération et reliquat conservés,
retries concurrents après remplissage et contrôle des deux membres de crew.
Le test d'archivage contrôle sa propre occurrence, pas les résidus d'autres runs.

## Validation

`LOCAL_FULL_GATE_OK` du 07/09 : 44 tests Rust, dont 16 PostgreSQL réels,
API + social à deux instances et smoke des 6 scènes en 360/540/720.
Clippy strict vert. Gate rejouée hors sandbox sans erreur Godot.
Aucun APK/AAB R41.

## Environnement IA

PowerShell 7 (`pwsh`) disponible ; compatibilité scripts PS 5.1 conservée ;
Godot 4.7.2. Le sandbox peut bloquer les paramètres/certificats utilisateur Godot.

## Dépendances externes

Wallet Seeker, RPC/SKR, providers, HTTPS, keystore, QA appareil, fiche store.
