# CyberSeeker — Client Godot 4

Client **vue uniquement** (GDD §37-39) : il envoie des intentions au serveur
authoritative et anime l'état renvoyé. Il ne calcule jamais un résultat RNG,
un solde, une probabilité ou une récompense.

## Lancer

1. **Serveur** d'abord (voir [README racine](../README.md)) — Postgres +
   `DEV_AUTH=true` dans `server/.env`.
2. Ouvrir `project.godot` dans **Godot 4.x** (standard, pas mono).
3. **F5**.

Flow : Onboarding → `CONNECT WALLET` (build debug : joueur de test) → navigation
Spin / District / Cards / Missions / Store.

> Le mode dev est dérivé des features Godot `editor/debug`; aucun booléen de
> contournement n'existe dans un build release. `Wallet.gd` attend alors le
> bridge Mobile Wallet Adapter Seeker.

APK arm64 de validation généré : `build/android/CyberSeeker-debug.apk`
(min SDK 24, cible 36, signature debug v2/v3 vérifiée).

## Structure

```text
project.godot           Viewport 540×1170 portrait, GL Compatibility (mobile)
scenes/Main.gd|tscn     Shell + boot flow (config → session → écran)
scenes/screens/         Onboarding, Spin, District, Collection, Missions, Store
scripts/core/           Autoloads :
  Preferences.gd        Son, haptique, réduction des mouvements
  Net.gd                HTTP/JSON, JWT (refresh auto sur 401), request-id (idempotence)
  Wallet.gd             Adaptateur wallet debug / Seeker release
  Config.gd             Remote config versionnée (GET /config) — TOUS les nombres
  Store.gd              Cache état joueur + horloge compensée (serverTimeMs)
  Sfx.gd                Sons synthétisés (aucun asset requis en M1)
  Haptics.gd            Vibrations (no-op desktop)
  Events.gd             Analytics batché (flush @10 / 15 s / fermeture, cap 100)
  Ui.gd                 Palette néon + helpers d'affichage (statique)
```

## Règles du code

- **Aucune valeur économique en dur** → tout se lit via `Config.*` (remote
  config, GDD §40). Les fallbacks `get("…", défaut)` sont des garde-fous,
  pas de l'équilibrage.
- **Horloge** : tous les compteurs (regen, offers…) utilisent
  `Store.now_ms()` (horloge serveur compensée), jamais `Time` brut.
- **Idempotence** : chaque mutation envoie un `requestId` (header + body).
- Les UI sont construites en code dans `_build()` (fichiers `.tscn` = racine
  Control + script) — plus simple à maintenir, aucune dépendance à l'éditeur.
