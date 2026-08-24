from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "sources"
OUTPUT = ROOT / "processed"
CELL = 512
ICON_MAX = 426

ICONS = ["credits", "shield", "hack", "vault", "energy", "glitch"]


def crop_alpha(image: Image.Image, padding: int) -> Image.Image:
    rgba = image.convert("RGBA")
    bbox = rgba.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("transparent image has no visible pixels")
    cropped = rgba.crop(bbox)
    canvas = Image.new(
        "RGBA",
        (cropped.width + padding * 2, cropped.height + padding * 2),
        (0, 0, 0, 0),
    )
    canvas.alpha_composite(cropped, (padding, padding))
    return canvas


def contain(image: Image.Image, width: int, height: int) -> Image.Image:
    result = image.copy()
    result.thumbnail((width, height), Image.Resampling.LANCZOS)
    return result


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)

    background = Image.open(SOURCE / "spin_background.png").convert("RGB")
    background.save(OUTPUT / "spin_background.png", optimize=True)

    master = Image.open(SOURCE / "master.png").convert("RGB")
    master.save(OUTPUT / "master.png", optimize=True)

    machine = crop_alpha(Image.open(SOURCE / "slot_machine.png"), 28)
    machine.save(OUTPUT / "slot_machine.png", optimize=True)

    mascot = crop_alpha(Image.open(SOURCE / "byte.png"), 28)
    mascot.save(OUTPUT / "byte.png", optimize=True)

    spin_button = crop_alpha(Image.open(SOURCE / "spin_button.png"), 24)
    spin_button.save(OUTPUT / "spin_button.png", optimize=True)

    atlas = Image.new("RGBA", (CELL * 3, CELL * 2), (0, 0, 0, 0))
    report: dict[str, object] = {
        "provider": "built-in GPT Image",
        "master": {"size": list(master.size)},
        "background": {"size": list(background.size)},
        "machine": {"size": list(machine.size)},
        "mascot": {"size": list(mascot.size)},
        "spinButton": {"size": list(spin_button.size)},
        "icons": {},
    }

    for index, name in enumerate(ICONS):
        icon = crop_alpha(Image.open(SOURCE / f"{name}.png"), 18)
        icon = contain(icon, ICON_MAX, ICON_MAX)
        normalized = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        x = (CELL - icon.width) // 2
        y = (CELL - icon.height) // 2
        normalized.alpha_composite(icon, (x, y))
        normalized.save(OUTPUT / f"{name}.png", optimize=True)
        atlas.alpha_composite(normalized, ((index % 3) * CELL, (index // 3) * CELL))
        report["icons"][name] = {
            "sourceSize": list(Image.open(SOURCE / f"{name}.png").size),
            "normalizedSize": [CELL, CELL],
            "visibleBounds": list(normalized.getchannel("A").getbbox() or ()),
        }

    atlas.save(OUTPUT / "slot_symbols_atlas.png", optimize=True)
    report["atlas"] = {
        "size": list(atlas.size),
        "mode": atlas.mode,
        "alphaExtrema": list(atlas.getchannel("A").getextrema()),
    }
    (OUTPUT / "asset_report.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
