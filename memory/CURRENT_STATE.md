# MÉMOIRE — ÉTAT ACTUEL R39

> MAJ 01/09/2026. R39 = netteté / lisse (D7). Layout R38 inchangé.

## Lot R39

- Bâtiments : knockout BFS + spread RGB + alpha gaussien, WebP lossless.
  Stages natifs (plus d'upscale 1080). Chrome UI 8× (star/hammer/wrench).
- Godot 4.7 : Nunito ExtraBold MSDF, Linear+mipmaps (filter=2), pas de snap
  pixel, StyleBoxFlat AA. FXAA/MSAA 2D **non** (Compatibility, doc 4.7).
- UI : outline 2, plus de grille SignalBackdrop, étoiles/marteaux en sprites.

## Validation

`mobile_ux_check` + smoke 360/540/720. QA visuelle : `PLAY.bat` + F11.

## Périmètre

Gameplay MASTER TODO + villages R38. 21 modules Rust, 20 migs.

## Environnement IA

Shell Cursor `all` ; PS 5.1 ; Godot 4.7.2 ; venv PIL `...\ex\local-ai\venv`.

## Dépendances externes

Wallet Seeker, RPC/SKR, providers, HTTPS, keystore, QA appareil, fiche store.
