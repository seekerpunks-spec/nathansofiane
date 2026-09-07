"""Prepare imagegen building atlases; automatic cutout explicitly approved by user.
Keeps original PNGs intact. Only writes to the supplied staging output folder.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter, ImageDraw
from collections import deque

NAMES = {
    1: ["apartment", "terminal", "energy", "bodega", "antenna"],
    2: ["d2_habitats", "d2_foundry", "d2_bazaar", "d2_clinic", "d2_beacon"],
    3: ["d3_cradle", "d3_rig", "d3_salvage", "d3_spine", "d3_lantern"],
    4: ["d4_vault", "d4_atrium", "d4_bridge", "d4_suite", "d4_crown"],
    5: ["d5_lattice", "d5_reactor", "d5_cipher", "d5_spine", "d5_beacon"],
}

def gap(profile: np.ndarray, ideal: float, radius: int) -> int:
    profile = np.convolve(profile, np.ones(7), mode="same")
    lo, hi = max(1, int(ideal) - radius), min(len(profile) - 1, int(ideal) + radius)
    candidates = np.arange(lo, hi)
    # Favor a genuine empty gutter and then the nearest point to the ideal grid.
    scores = profile[lo:hi] * 1000 + np.abs(candidates - ideal)
    return int(candidates[np.argmin(scores)])

def prepare(source: Path, district: int, output: Path) -> dict:
    image = Image.open(source).convert("RGBA")
    pixels = np.asarray(image).copy()
    rgb = pixels[:, :, :3].astype(np.float32)
    minimum, maximum = rgb.min(axis=2), rgb.max(axis=2)
    # These generated atlases have near-neutral white/gray backgrounds; retain
    # saturated cyan lights, colored windows and all dark structural outlines.
    neutral = (minimum > 205) & ((maximum - minimum) < 32)
    mask = Image.fromarray((neutral * 255).astype("uint8"))
    ImageDraw.floodfill(mask, (0, 0), 128)
    labels = np.asarray(mask).copy()
    background = labels == 128
    # Preserve white painted highlights and emblems inside the buildings.
    # Only large enclosed neutral holes (e.g. inside a beacon ring) are cut out.
    height, width = labels.shape
    remaining = labels == 255
    for sy, sx in zip(*np.where(remaining)):
        if not remaining[sy, sx]:
            continue
        todo = deque([(int(sy), int(sx))])
        remaining[sy, sx] = False
        component = []
        while todo:
            cy, cx = todo.popleft()
            component.append((cy, cx))
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < height and 0 <= nx < width and remaining[ny, nx]:
                    remaining[ny, nx] = False
                    todo.append((ny, nx))
        center_x = sum(point[1] for point in component) / len(component)
        # Semantic holes in the generated suspended bridge and reactor arms.
        # Keep the reactor's white energy core in the middle of its column.
        bridge_gap = district == 4 and 730 < center_x < 830 and len(component) >= 35
        reactor_gap = district == 5 and 350 < center_x < 620 and abs(center_x - 490) > 32 and len(component) >= 35
        if len(component) >= 1500 or bridge_gap or reactor_gap:
            ys, xs = zip(*component)
            background[ys, xs] = True
    alpha = pixels[:, :, 3].astype(np.float32) / 255
    alpha[background] = 0
    adjacent = np.asarray(Image.fromarray((background * 255).astype("uint8")).filter(ImageFilter.MaxFilter(3))) > 0
    edge = adjacent & ~background & (minimum > 65) & (alpha > 0)
    coverage = np.clip((255 - minimum) / 205, 0.05, 1)
    alpha[edge] *= coverage[edge]
    alpha[alpha < 0.1] = 0
    # Remove white matte contamination only from anti-aliased edge pixels.
    rgb[edge] = np.clip((rgb[edge] - 255 * (1 - coverage[edge, None])) / coverage[edge, None], 0, 255)
    pixels[:, :, :3] = rgb.astype("uint8")
    pixels[:, :, 3] = np.round(alpha * 255).astype("uint8")
    pixels[alpha == 0, :3] = 0
    cutout = Image.fromarray(pixels)
    occupied = alpha > 0
    h, w = occupied.shape
    # Generated rows do not have mathematically equal baselines. Locate the
    # fifteen actual structures instead of cutting through tall antennae.
    remaining = occupied.copy()
    objects = []
    for sy, sx in zip(*np.where(remaining)):
        if not remaining[sy, sx]:
            continue
        todo = deque([(int(sy), int(sx))])
        remaining[sy, sx] = False
        x0 = x1 = int(sx)
        y0 = y1 = int(sy)
        area = 0
        while todo:
            cy, cx = todo.popleft()
            area += 1
            x0, x1 = min(x0, cx), max(x1, cx)
            y0, y1 = min(y0, cy), max(y1, cy)
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < h and 0 <= nx < w and remaining[ny, nx]:
                    remaining[ny, nx] = False
                    todo.append((ny, nx))
        if area >= 1000:
            objects.append((area, (x0, y0, x1 + 1, y1 + 1)))
    objects.sort(reverse=True)
    if len(objects) < 15:
        raise ValueError(f"Expected fifteen isolated structures, found {len(objects)}")
    bounds = [item[1] for item in objects[:15]]
    bounds.sort(key=lambda b: (b[1] + b[3]) / 2)
    rows = [[*sorted(bounds[i:i + 5], key=lambda b: b[0])] for i in (0, 5, 10)]
    output.mkdir(parents=True, exist_ok=True)
    preview = Image.new("RGBA", (1600, 1140), "#061224")
    manifest = {"district": district, "source": source.name, "sprites": []}
    for tier in range(3):
        for column, stem in enumerate(NAMES[district]):
            left, top, right, bottom = rows[tier][column]
            sprite = cutout.crop((left, top, right, bottom))
            bbox = sprite.getbbox()
            if bbox is None:
                raise ValueError(f"Empty sprite {district}/{column}/{tier}")
            sprite = sprite.crop(bbox)
            scale = [0.76, 0.88, 1.0][tier]
            sprite.thumbnail((int(304 * scale), int(332 * scale)), Image.Resampling.LANCZOS)
            canvas = Image.new("RGBA", (320, 360))
            canvas.alpha_composite(sprite, ((320 - sprite.width) // 2, 346 - sprite.height))
            name = f"{stem}_t{tier}.webp"
            canvas.save(output / name, "WEBP", lossless=True, exact=True)
            preview.alpha_composite(canvas, (column * 320, tier * 380))
            transparent_fraction = float((np.asarray(canvas)[:, :, 3] == 0).mean())
            if not 0.2 < transparent_fraction < 0.96:
                raise ValueError(f"Unexpected alpha coverage {name}: {transparent_fraction}")
            manifest["sprites"].append({"name": name, "bounds": [left + bbox[0], top + bbox[1], left + bbox[2], top + bbox[3]], "transparent_fraction": round(transparent_fraction, 4)})
    preview.convert("RGB").save(output / f"district_{district:02d}_preview.jpg", quality=95)
    (output / f"district_{district:02d}_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("district", type=int, choices=NAMES)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    manifest = prepare(args.source, args.district, args.output)
    print(f"BUILDING_ATLAS_OK: district={args.district} sprites={len(manifest['sprites'])}")
