"""Compose les icones launcher Android + le boot splash depuis icon_512.png.

Source : client/export/icons/icon_512.png (rasterise par
client/tests/ExportIcon.gd via Godot headless). Sorties :
- main_192x192.png : icone classique (Android < 8).
- adaptive_foreground_432x432.png : logo a 256 px centre sur fond transparent,
  circumradius ~119 px < 132 px (safe zone adaptive de 264 px de diametre).
- adaptive_background_432x432.png : degrade vertical #0B1024 -> #17103A,
  meme fond que l'icone SVG.
- client/assets/boot_splash.png : rendu 512 tel quel (centre sur bg_color).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ICONS = ROOT / "client" / "export" / "icons"
TOP = (11, 16, 36)
BOTTOM = (23, 16, 58)


def gradient(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size))
    for y in range(size):
        t = y / (size - 1)
        row = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
        img.paste(row, (0, y, size, y + 1))
    return img


def main() -> int:
    source = Image.open(ICONS / "icon_512.png").convert("RGBA")

    source.resize((192, 192), Image.LANCZOS).save(
        ICONS / "main_192x192.png", optimize=True
    )

    foreground = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    logo = source.resize((256, 256), Image.LANCZOS)
    foreground.paste(logo, ((432 - 256) // 2, (432 - 256) // 2), logo)
    foreground.save(ICONS / "adaptive_foreground_432x432.png", optimize=True)

    gradient(432).save(ICONS / "adaptive_background_432x432.png", optimize=True)

    source.save(ROOT / "client" / "assets" / "boot_splash.png", optimize=True)

    for name in (
        "main_192x192.png",
        "adaptive_foreground_432x432.png",
        "adaptive_background_432x432.png",
    ):
        path = ICONS / name
        print(f"{name}: {path.stat().st_size} octets")
    print("boot_splash.png:", (ROOT / "client" / "assets" / "boot_splash.png").stat().st_size, "octets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
