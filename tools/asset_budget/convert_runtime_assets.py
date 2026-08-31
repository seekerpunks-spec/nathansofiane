"""Convertit les assets runtime du client au budget mobile R31.

PNG photographiques -> WebP avec perte calibree, atlas du slot -> WebP sans
perte (symboles nets), icones de coffre redimensionnees a leur taille d'usage
reelle (86 px a l'ecran, 256 px source pour les ecrans denses). Chaque
conversion reussie supprime le PNG source et son .import : le runtime ne doit
garder qu'une seule copie de chaque asset.

Reutilisable apres une regeneration d'art : il ne traite que les PNG listes et
il est sans effet si tout est deja converti.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parents[2]
GENERATED = PROJECT_ROOT / "client" / "assets" / "generated"

# (chemin relatif a assets/generated, qualite lossy ou None pour lossless,
#  taille cible carree ou None pour conserver les dimensions)
CONVERSIONS: list[tuple[str, int | None, int | None]] = [
    ("districts/neon_slums_bg.png", 90, None),
    ("districts/district_02_bg.png", 90, None),
    ("districts/district_03_bg.png", 90, None),
    ("districts/district_04_bg.png", 90, None),
    ("districts/district_05_bg.png", 90, None),
    ("api_gpt/spin_background.png", 90, None),
    ("api_gpt/slot_machine.png", 90, None),
    ("api_gpt/spin_button.png", 90, None),
    ("api_gpt/byte.png", 90, None),
    ("api_gpt/heroes/district_hero.png", 90, None),
    ("api_gpt/heroes/collection_hero.png", 90, None),
    ("api_gpt/heroes/missions_hero.png", 90, None),
    ("api_gpt/heroes/store_hero.png", 90, None),
    # Symboles du slot : lisibilite au pixel pres, compression sans perte.
    ("api_gpt/slot_symbols_atlas.png", None, None),
    # Coffres affiches a 86 px ; 256 px garde une marge x3 sans peser 1 Mo.
    ("chests/basic_cache.png", 92, 256),
    ("chests/neon_cache.png", 92, 256),
    ("chests/quantum_cache.png", 92, 256),
    ("chests/black_ice_vault.png", 92, 256),
]


def convert(relative: str, quality: int | None, target_size: int | None) -> str:
    source = GENERATED / relative
    target = source.with_suffix(".webp")
    if not source.exists():
        if target.exists():
            return f"[deja converti] {relative}"
        raise FileNotFoundError(f"source absente et cible absente: {source}")
    with Image.open(source) as image:
        image = image.convert("RGBA")
        if target_size is not None:
            image = image.resize((target_size, target_size), Image.LANCZOS)
        if quality is None:
            image.save(target, "WEBP", lossless=True, method=6)
        else:
            image.save(target, "WEBP", quality=quality, method=6)
    before = source.stat().st_size
    after = target.stat().st_size
    source.unlink()
    stale_import = source.with_name(source.name + ".import")
    if stale_import.exists():
        stale_import.unlink()
    return f"[converti] {relative}: {before // 1024} Ko -> {after // 1024} Ko"


def main() -> int:
    for relative, quality, target_size in CONVERSIONS:
        print(convert(relative, quality, target_size), flush=True)
    print("ASSET_CONVERSION_OK", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
