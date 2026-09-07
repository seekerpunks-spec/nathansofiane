# R44 — Bâtiments entièrement redessinés

07/09/2026. Demande utilisateur : retirer les anciennes illustrations et
repartir de zéro dans le style de l'interface Punk City.

## Livraison

- 25 architectures originales, couvrant les cinq districts.
- Trois évolutions illustrées par bâtiment : 75 sprites WebP RGBA de 320×360.
- Palette cobalt/violet, lumières cyan/magenta, volumes cartoon 2.5D et
  fondations compactes. Aucun ancien sprite réutilisé ou simplement recoloré.
- Niveaux 0–1 : première silhouette ; 2–3 : intermédiaire ; 4–5 : finale.
- Illustrations consommées dans MAP, sa fiche et Build Bay, ainsi que dans le
  village de l'accueil. Même code de sélection, de réparation et de paiement.
- Fonds des districts conservés : la demande portait sur les bâtiments.

Génération : outil imagegen intégré, cinq atlas et une tentative de correction
alpha rejetée. Le générateur a dessiné un fond opaque ; après accord explicite
de l'utilisateur, détourage/découpage par tools/prepare_building_atlas.py.
Le script conserve les emblèmes blancs, détoure les ouvertures des ponts et
réacteurs, détecte les silhouettes réelles et normalise les socles.

Sources et prompts complets : art/punk_city/buildings/source/ et
art/punk_city/buildings/PROMPTS.md. Sprites livrés :
client/assets/generated/districts/buildings/. Planches de contrôle sur fond
sombre et coordonnées de découpe : art/punk_city/buildings/prepared/.

## Retrait récupérable

55 anciennes images + leurs 55 fichiers .import déplacés dans
art/archive/r43-replaced-buildings/. Aucun effacement irréversible.
Vérification SHA-256 : les 55 remplacements diffèrent des anciennes images.
Les vingt nouveaux sprites intermédiaires des districts 2 à 5 sont référencés
dans la configuration ; aucun coût, reward ou prérequis n'a changé.

## Vérification

- LOCAL_FULL_GATE_OK : 44 tests Rust, dont 16 exécutés avec PostgreSQL.
- Contrats API/concurrence/idempotence et contrats sociaux validés.
- Six scènes Godot à 360×800, 540×1170, 720×1280.
- Tests nouveaux : 75 textures, trois images distinctes par bâtiment,
  dimensions normalisées, alpha présent et quatre coins transparents.
- Comparaison sémantique des quatre configs modifiées : seuls les champs
  asset changent. Aucun changement d'économie.
- Captures des cinq MAP inspectées ; accueil et MAP contrôlés à 360×800.
- captures/r44-d1.png à r44-d5.png : aperçu des villages au niveau 4.
- captures/r44-district-360.png et r44-spin-360.png : aperçu niveau 2.
- Aucun APK/AAB, aucune implémentation wallet ni push GitHub dans ce lot.
