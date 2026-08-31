"""Netteté runtime : alpha lissé, WebP lossless, chrome UI supersamplé, mipmaps."""
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

WORKSPACE = Path(__file__).resolve().parents[2]
SRC = Path(
    r"C:\Users\danbi\.cursor\projects"
    r"\c-Users-danbi-lmstudio-apps-bionic-projects-b0598732-8bf2-45a2-a462-4f61d6bcead0-workspace"
    r"\assets"
)
BUILDINGS = WORKSPACE / "client/assets/generated/districts/buildings"
STAGES = WORKSPACE / "client/assets/generated/districts/stages"
UI = WORKSPACE / "client/assets/generated/ui"
GENERATED = WORKSPACE / "client/assets/generated"

IMPORT_PARAMS = """[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def knockout_hard(im: Image.Image, thresh: int = 20) -> Image.Image:
    arr = np.array(im.convert("RGBA"))
    dark = (arr[:, :, 3] < 8) | (
        (arr[:, :, 0] < thresh) & (arr[:, :, 1] < thresh) & (arr[:, :, 2] < thresh)
    )
    h, w = dark.shape
    vis = np.zeros((h, w), dtype=np.uint8)
    q = deque()
    border = np.zeros((h, w), dtype=bool)
    border[0, :] = True
    border[-1, :] = True
    border[:, 0] = True
    border[:, -1] = True
    for y, x in np.argwhere(dark & border):
        vis[y, x] = 1
        q.append((int(y), int(x)))
    while q:
        y, x = q.popleft()
        arr[y, x, 3] = 0
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and not vis[ny, nx] and dark[ny, nx]:
                vis[ny, nx] = 1
                q.append((ny, nx))
    return Image.fromarray(arr, "RGBA")


def spread_rgb(arr: np.ndarray, steps: int = 10) -> np.ndarray:
    rgb = arr[:, :, :3].copy()
    am = arr[:, :, 3] > 8
    for _ in range(steps):
        acc = np.zeros_like(rgb, dtype=np.int32)
        cnt = np.zeros(am.shape, dtype=np.int32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            r = np.roll(rgb, (dy, dx), (0, 1))
            m = np.roll(am, (dy, dx), (0, 1))
            acc += r.astype(np.int32) * m[:, :, None]
            cnt += m
        grow = (~am) & (cnt > 0)
        if not np.any(grow):
            break
        rgb[grow] = (acc[grow] / cnt[grow, None]).astype(np.uint8)
        am[grow] = True
    arr[:, :, :3] = rgb
    return arr


def feather_alpha(im: Image.Image, radius: float = 2.2) -> Image.Image:
    arr = spread_rgb(np.array(im), steps=10)
    hard = Image.fromarray(arr, "RGBA")
    r, g, b, a = hard.split()
    mask = a.point(lambda p: 255 if p > 8 else 0)
    soft = mask.filter(ImageFilter.GaussianBlur(radius=radius))
    return Image.merge("RGBA", (r, g, b, soft))


def punch_rgb(im: Image.Image) -> Image.Image:
    r, g, b, a = im.split()
    rgb = Image.merge("RGB", (r, g, b))
    rgb = ImageEnhance.Color(rgb).enhance(1.06)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.05)
    rgb = ImageEnhance.Sharpness(rgb).enhance(1.16)
    r, g, b = rgb.split()
    return Image.merge("RGBA", (r, g, b, a))


def write_import(webp: Path) -> None:
    rel = "res://assets/generated/" + "/".join(webp.relative_to(GENERATED).parts)
    text = (
        "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n"
        f"source_file=\"{rel}\"\n\n{IMPORT_PARAMS}"
    )
    dest = Path(str(webp) + ".import")
    if dest.exists():
        old = dest.read_text(encoding="utf-8")
        if "mipmaps/generate=false" in old:
            dest.write_text(old.replace("mipmaps/generate=false", "mipmaps/generate=true"), encoding="utf-8")
        return
    dest.write_text(text, encoding="utf-8")


def pack_sprite(src: Path, dest: Path, box: int = 1024) -> None:
    print("PACK", src.name, flush=True)
    raw = Image.open(src)
    print(" SIZE", raw.size, flush=True)
    im = punch_rgb(feather_alpha(knockout_hard(raw)))
    im = punch_rgb(feather_alpha(knockout_hard(Image.open(src))))
    bbox = im.getbbox()
    if bbox:
        l, t, r, btm = bbox
        pad = 20
        im = im.crop((max(0, l - pad), max(0, t - pad), min(im.width, r + pad), min(im.height, btm + pad)))
    im.thumbnail((box, box), Image.LANCZOS)
    canvas = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    canvas.paste(im, ((box - im.width) // 2, box - im.height), im)
    canvas.save(dest, "WEBP", lossless=True, quality=100, method=4)
    write_import(dest)
    print(dest.name, dest.stat().st_size, flush=True)


def _star_poly(cx: float, cy: float, r_out: float, r_in: float) -> list[tuple[float, float]]:
    pts = []
    for i in range(10):
        ang = -np.pi / 2 + i * np.pi / 5
        rad = r_out if i % 2 == 0 else r_in
        pts.append((cx + rad * np.cos(ang), cy + rad * np.sin(ang)))
    return pts


def _with_shadow(im: Image.Image, pad: int = 28) -> Image.Image:
    canvas = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
    alpha = im.getchannel("A")
    shadow = Image.new("RGBA", im.size, (24, 35, 86, 0))
    sh_a = alpha.filter(ImageFilter.GaussianBlur(10)).point(lambda p: int(p * 0.42))
    shadow.putalpha(sh_a)
    canvas.paste(shadow, (pad, pad + 8), shadow)
    canvas.paste(im, (pad, pad), im)
    return canvas


def make_chrome() -> None:
    UI.mkdir(parents=True, exist_ok=True)
    ss = 8
    s = 128 * ss
    star = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(star)
    ink = _star_poly(s / 2, s / 2 + ss, s * 0.46, s * 0.20)
    gold = _star_poly(s / 2, s / 2, s * 0.42, s * 0.18)
    d.polygon(ink, fill=(17, 34, 90, 255))
    d.polygon(gold, fill=(255, 211, 78, 255))
    star = _with_shadow(star.resize((128, 128), Image.LANCZOS))
    star.save(UI / "star.webp", "WEBP", lossless=True, method=6)

    def round_tool(fill: tuple[int, int, int], dest: Path, repair: bool) -> None:
        s = 256 * ss
        im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        m = ss * 10
        d.ellipse((m + ss * 4, m + ss * 8, s - m + ss * 4, s - m + ss * 8), fill=(17, 34, 90, 90))
        d.ellipse((m, m, s - m, s - m), fill=fill + (255,))
        d.ellipse((m + ss * 6, m + ss * 6, s - m - ss * 6, s - m - ss * 6), outline=(255, 255, 255, 255), width=ss * 8)
        ink = (17, 34, 90, 255)
        cx, cy = s / 2, s / 2
        if repair:
            d.rounded_rectangle((cx - ss * 30, cy - ss * 9, cx + ss * 38, cy + ss * 9), radius=ss * 8, fill=ink)
            d.arc((cx + ss * 14, cy - ss * 26, cx + ss * 56, cy + ss * 16), 200, 40, fill=ink, width=ss * 10)
        else:
            d.line((cx - ss * 24, cy + ss * 20, cx + ss * 26, cy - ss * 28), fill=ink, width=ss * 16)
            d.polygon(
                [
                    (cx + ss * 12, cy - ss * 38),
                    (cx + ss * 40, cy - ss * 20),
                    (cx + ss * 24, cy - ss * 4),
                    (cx + ss * 2, cy - ss * 22),
                ],
                fill=(255, 248, 210, 255),
            )
            d.ellipse((cx - ss * 34, cy + ss * 8, cx - ss * 6, cy + ss * 36), fill=ink)
        im = _with_shadow(im.resize((256, 256), Image.LANCZOS))
        im.save(dest, "WEBP", lossless=True, method=6)

    round_tool((255, 211, 78), UI / "hammer.webp", False)
    round_tool((255, 138, 58), UI / "wrench.webp", True)
    for name in ("star.webp", "hammer.webp", "wrench.webp"):
        path = UI / name
        write_import(path)
        print(name, path.stat().st_size)


def patch_imports() -> None:
    for path in GENERATED.rglob("*.import"):
        text = path.read_text(encoding="utf-8")
        if "mipmaps/generate=false" in text:
            path.write_text(text.replace("mipmaps/generate=false", "mipmaps/generate=true"), encoding="utf-8")


def pack_districts() -> None:
    BUILDINGS.mkdir(parents=True, exist_ok=True)
    STAGES.mkdir(parents=True, exist_ok=True)
    d1 = ["apartment", "terminal", "energy", "bodega", "antenna"]
    for name in d1:
        for tier in ("t0", "t1", "t2"):
            hi = SRC / f"{name}_{tier}_hi.png"
            src = hi if hi.exists() else SRC / f"{name}_{tier}.png"
            pack_sprite(src, BUILDINGS / f"{name}_{tier}.webp")
    for src in SRC.glob("d[2-5]_*.png"):
        pack_sprite(src, BUILDINGS / (src.stem + ".webp"))
    stages = {
        "neon_slums_stage.png": "neon_slums.webp",
        "chrome_heights_stage.png": "chrome_heights.webp",
        "rust_harbor_stage.png": "rust_harbor.webp",
        "spire_exchange_stage.png": "spire_exchange.webp",
        "nullzone_core_stage.png": "nullzone_core.webp",
    }
    for src_name, dest_name in stages.items():
        im = Image.open(SRC / src_name).convert("RGB")
        im = ImageEnhance.Color(im).enhance(1.05)
        im = ImageEnhance.Sharpness(im).enhance(1.12)
        dest = STAGES / dest_name
        im.save(dest, "WEBP", quality=95, method=6)
        write_import(dest)
        print(dest.name, dest.stat().st_size)


def main() -> None:
    pack_districts()
    make_chrome()
    patch_imports()
    total = sum(p.stat().st_size for p in (WORKSPACE / "client/assets").rglob("*") if p.is_file())
    print("TOTAL_MB", round(total / 1048576, 2))


if __name__ == "__main__":
    main()
