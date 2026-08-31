# CyberSeeker — usine locale d'assets

Cette chaîne utilise uniquement la RTX locale et des modèles téléchargeables.
Aucune clé API, aucun compte payant et aucun éditeur graphique ne sont requis.

`generate.ps1` démarre ComfyUI en arrière-plan, génère les variantes décrites
dans `asset_manifest.json`, sélectionne automatiquement la meilleure image,
détoure les éléments, construit l'atlas du slot et dépose les fichiers en
staging dans `art/local_ai/staging/`. Seules les promotions du manifest
touchent le runtime, et elles convertissent en WebP calibré (budget mobile
R31) : aucun PNG de staging n'entre dans `client/assets/`.

Les textes restent des contrôles Godot. Ils ne sont jamais aplatis dans les
images générées afin de préserver lisibilité, accessibilité et traduction.

## Commandes

Génération complète :

```powershell
.\tools\ai_assets\generate.ps1
```

Régénération forcée du cabinet et de BYTE :

```powershell
.\tools\ai_assets\generate.ps1 -Only slot_cabinet,byte_mascot -Force
```

Les candidats et le rapport sont conservés sous `art/local_ai/` pour assurer
la reproductibilité et permettre une sélection automatique plus stricte lors
des itérations suivantes.
