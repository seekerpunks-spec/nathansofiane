# Pipeline de rendu final 2.5D

Blender est la source de vérité du rendu. Tripo fournit éventuellement les
modèles de départ ; aucun fichier Tripo brut n'entre directement dans Godot.

Le pipeline fixe :

- caméra orthographique portrait ;
- matériaux graphite, cyan, magenta et or ;
- éclairage studio trois points ;
- rendu transparent PNG ;
- fichier `.blend` maître conservé dans `art/blender/` ;
- sortie runtime dans `client/assets/generated/rendered/`.

Exécution :

```powershell
& .\tools\render_2_5d\render.ps1
```

Les quatre dioramas d'écrans et leurs scènes Blender éditables sont produits
avec :

```powershell
& .\tools\render_2_5d\render_screens.ps1
```

Sorties : `district_hero.png`, `collection_hero.png`, `missions_hero.png`,
`store_hero.png` et la mascotte `mascot_hero.png` dans
`client/assets/generated/rendered/`, avec leurs fichiers `.blend` dans
`art/blender/`.

Les futurs GLB doivent être retopologisés avant import, conserver une silhouette
lisible à 128 px et recevoir leurs matériaux dans la scène maître avant rendu.
