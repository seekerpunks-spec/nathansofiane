# MÉMOIRE — ÉTAT ACTUEL R44 : nouveaux bâtiments Punk City

> R44 : les 55 anciennes illustrations de bâtiments sont retirées du runtime
> et archivées. 25 bâtiments redessinés × trois évolutions = 75 nouveaux sprites.
> Imagegen intégré + détourage automatique autorisé par l'utilisateur.
> Gate complète verte. Voir `docs/R44_BUILDING_ART.md`.

> R43 : refonte MAP livrée dans le thème R42. Fiche d'amélioration explicite,
> Build Bay illustré, districts défilants et complétion dorée. Économie préservée.
> Gate complète verte ; détails et limites : `docs/R43_MAP_DESIGN.md`.

> MAJ 07/09/2026. Gameplay R41 conservé. Nouvelle demande explicite utilisateur :
> refaire l'aspect à partir de l'image Punk City du 3 septembre. Le brief de jour
> ci-dessous est remplacé, sans effacer les anciens essais.

## Design

R42 : machine trois rouleaux argentés, bleu nuit/cyan/magenta, logo graffiti
CYBER SEEKER, bouton doré, rails illustrés, village et navigation six onglets.
Composition native séparée de SpinScreen dans `SpinHomeView.gd` / `NeonSkin.gd`.
Police Rajdhani Bold et thème des six scènes harmonisés. Résultats, mises et
soldes serveur préservés. Sources sous `art/punk_city`, ancien art archivé sous
`art/archive/r23-replaced`. Les essais skyline/R40 restent historiques.

**Pas de déclaration "design fini à 100 %"** : fonds de districts et illustrations
de coffres secondaires encore anciens. Le blocage imagegen R42 est levé et les
bâtiments sont tous remplacés en R44. Gemmes, piggy bank, Coin Fever,
Mega Chest et autospin ne sont pas simulés par de faux boutons/compteurs.
Lire `docs/R42_REFERENCE_DESIGN.md` pour le livré, les adaptations et le restant.
Ne pas remplacer ce brief par la précédente direction skyline jour.

## Gameplay et plateforme R41

MASTER TODO local fermé : cadeau ami quotidien, chat rapide crew et entraide
spins ajoutés. Challenge auth lié au domaine, confidentialité export/delete,
rétentions configurables et workflow CI GitHub validé sur Linux.
22 modules Rust, 23 migrations.

Revue du 07/09 : access JWT lié à sa session (invalide après recréation),
nonce consommé seulement après signature valide, effacement/recréation sérialisés,
exports sociaux sans wallets tiers, dons avec régénération et reliquat conservés,
retries concurrents après remplissage et contrôle des deux membres de crew.
Le test d'archivage contrôle sa propre occurrence, pas les résidus d'autres runs.

Suivi CI du 07/09 : premier run Linux a détecté un filtre de chemins Windows
dans le contrôle i18n (corrigé), et RustSec RUSTSEC-2023-0071 via RSA/SQLx 0.8.
SQLx migré en 0.9 (Rust >=1.94), RSA retirée du lockfile ; audit local sans
alerte ni exclusion, Clippy strict et 44 tests verts sur les migrations existantes.
Les requêtes SQL assemblées à partir de constantes deviennent des littéraux.
Checkout GitHub actualisé. Deux jobs distants verts sur `c057320` :
[full-gate et dependency-audit](https://github.com/seekerpunks-spec/nathansofiane/actions/runs/34076666433).

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
