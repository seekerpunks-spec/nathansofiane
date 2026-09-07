# R43 — MAP dans le thème Punk City

Livraison du 07/09/2026, à la demande de l'utilisateur après validation de R42.

## Livré

- Village encadré cyan, fond de district réel assombri, chrome et police de R42.
- Solde crédits, progression et récompense de complétion issus de Store/Config.
- Cinq bâtiments sélectionnables avec nom, niveau et état réparation/MAX.
- Fiche persistante avec aperçu du niveau suivant, coût et achat explicite.
- Sélection et Build Bay sans achat implicite ; seul UPGRADE/REPAIR envoie la mutation.
- Solde insuffisant, requête en cours et niveau maximum bloquent le bouton.
- Build Bay illustré et défilant ; vue des cinq districts avec état et récompense.
- Fenêtre de complétion dorée ; accès au prochain village sans retour forcé à SPIN.
- Retour Android sur les modales, safe areas, feedback réseau, animations Juice.

La présentation est isolée dans DistrictMapView.gd. DistrictScreen.gd conserve
les mutations serveur, leur requestId, les analytics et le rendu de secours.
Aucun changement de coût, de récompense ou de règle économique côté serveur.
Les sprites de bâtiments et fonds de district existants sont réutilisés :
ce lot ne prétend pas livrer de nouvelles illustrations générées.

## Validation

- LOCAL_FULL_GATE_OK : 44 tests Rust, dont 16 PostgreSQL exécutés.
- API_CONTRACT_CHECK_OK et SOCIAL_CONTRACT_CHECK_OK.
- Smoke des six scènes à 360×800, 540×1170 et 720×1280.
- Assertions MAP : sélection sans débit, coût exact, manque de crédits,
  MAX, réparation au MAX, blocage pendant requête, limites de viewport,
  modales défilantes et groupe Retour Android.
- Captures réelles inspectées : captures/r43-map-540.png, r43-map-360.png,
  r43-bay.png, r43-route.png et r43-complete.png.
- Aucun APK/AAB, aucune modification wallet, aucun push dans ce lot.

La vérification visuelle est desktop/Godot ; pas de nouveau test appareil Seeker.
