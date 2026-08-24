from pathlib import Path
from PIL import Image
import json


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "heroes_sources"
OUTPUT = ROOT / "heroes_processed"
TARGET = (896, 640)
MARGIN = 28


report = {"provider": "built-in GPT Image", "target": TARGET, "heroes": {}}
OUTPUT.mkdir(parents=True, exist_ok=True)

for source_path in sorted(SOURCE.glob("*_hero.png")):
    image = Image.open(source_path).convert("RGBA")
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise RuntimeError(f"Asset entièrement transparent: {source_path.name}")

    cropped = image.crop(bounds)
    cropped.thumbnail(
        (TARGET[0] - MARGIN * 2, TARGET[1] - MARGIN * 2),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", TARGET, (0, 0, 0, 0))
    position = (
        (TARGET[0] - cropped.width) // 2,
        (TARGET[1] - cropped.height) // 2,
    )
    canvas.alpha_composite(cropped, position)
    output_path = OUTPUT / source_path.name
    canvas.save(output_path, optimize=True)

    report["heroes"][source_path.stem] = {
        "sourceSize": image.size,
        "visibleBounds": bounds,
        "normalizedSize": canvas.size,
        "alphaExtrema": canvas.getchannel("A").getextrema(),
    }

(OUTPUT / "hero_asset_report.json").write_text(
    json.dumps(report, indent=2), encoding="utf-8"
)
print(json.dumps(report, indent=2))
