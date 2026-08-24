#!/usr/bin/env python3
"""CyberSeeker local asset factory.

Runs the local ComfyUI server, generates every item from the JSON manifest,
post-processes it, selects the strongest variant using deterministic image
metrics, assembles atlases, and writes assets straight into the Godot project.
No external generation API or interactive editor is used.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageFilter, ImageOps, ImageStat


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_AI_HOME = Path(r"C:\Users\danbi\Documents\Codex\2026-08-22\ex\local-ai")
AI_HOME = Path(os.environ.get("CYBERSEEKER_AI_HOME", DEFAULT_AI_HOME)).resolve()
COMFY_ROOT = AI_HOME / "ComfyUI"
PYTHON = AI_HOME / "venv" / "Scripts" / "python.exe"
SERVER = "http://127.0.0.1:8188"
REPORT_PATH = PROJECT_ROOT / "art" / "local_ai" / "generation_report.json"
os.environ.setdefault("U2NET_HOME", str(AI_HOME / "models" / "rembg"))
_REMBG_SESSION: Any = None


@dataclass
class Candidate:
    path: Path
    score: float
    seed: int


def request_json(url: str, payload: dict[str, Any] | None = None) -> Any:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=data)
    if data is not None:
        request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def server_ready() -> bool:
    try:
        request_json(f"{SERVER}/system_stats")
        return True
    except Exception:
        return False


def ensure_server() -> subprocess.Popen[str] | None:
    if server_ready():
        return None
    if not PYTHON.exists() or not (COMFY_ROOT / "main.py").exists():
        raise RuntimeError(f"ComfyUI local introuvable dans {AI_HOME}")
    log_dir = AI_HOME / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    stdout = (log_dir / "comfy.stdout.log").open("a", encoding="utf-8")
    stderr = (log_dir / "comfy.stderr.log").open("a", encoding="utf-8")
    process = subprocess.Popen(
        [
            str(PYTHON),
            str(COMFY_ROOT / "main.py"),
            "--listen", "127.0.0.1",
            "--port", "8188",
            "--preview-method", "none",
            "--disable-auto-launch",
        ],
        cwd=COMFY_ROOT,
        stdout=stdout,
        stderr=stderr,
        text=True,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    deadline = time.time() + 180
    while time.time() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"ComfyUI s'est arrêté avec le code {process.returncode}")
        if server_ready():
            return process
        time.sleep(1)
    process.terminate()
    raise TimeoutError("ComfyUI n'a pas démarré dans le délai imparti")


def first_existing(directory: Path, candidates: list[str], minimum_bytes: int = 1) -> str:
    for name in candidates:
        path = directory / name
        if path.exists() and path.stat().st_size >= minimum_bytes:
            return name
    raise FileNotFoundError(
        f"Modèle absent ou téléchargement incomplet dans {directory}: {', '.join(candidates)}"
    )


def flux_workflow(prompt: str, width: int, height: int, seed: int, prefix: str) -> dict[str, Any]:
    diffusion = first_existing(
        COMFY_ROOT / "models" / "diffusion_models",
        ["flux-2-klein-4b-fp8.safetensors", "flux-2-klein-4b.safetensors"],
        4_000_000_000,
    )
    clip = first_existing(
        COMFY_ROOT / "models" / "text_encoders",
        ["qwen_3_4b_fp4_flux2.safetensors", "qwen_3_4b.safetensors"],
        3_000_000_000,
    )
    vae = first_existing(COMFY_ROOT / "models" / "vae", ["flux2-vae.safetensors"], 300_000_000)
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": diffusion, "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": clip, "type": "flux2", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": vae}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["2", 0]}},
        "5": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["4", 0]}},
        "6": {"class_type": "EmptyFlux2LatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
        "7": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "8": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "9": {"class_type": "Flux2Scheduler", "inputs": {"steps": 4, "width": width, "height": height}},
        "10": {"class_type": "CFGGuider", "inputs": {"model": ["1", 0], "positive": ["4", 0], "negative": ["5", 0], "cfg": 1.0}},
        "11": {"class_type": "SamplerCustomAdvanced", "inputs": {"noise": ["7", 0], "guider": ["10", 0], "sampler": ["8", 0], "sigmas": ["9", 0], "latent_image": ["6", 0]}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": prefix}},
    }


def run_workflow(workflow: dict[str, Any], timeout: int = 900) -> Path:
    response = request_json(f"{SERVER}/prompt", {"prompt": workflow})
    if response.get("node_errors"):
        raise RuntimeError(json.dumps(response["node_errors"], indent=2, ensure_ascii=False))
    prompt_id = response["prompt_id"]
    deadline = time.time() + timeout
    while time.time() < deadline:
        history = request_json(f"{SERVER}/history/{prompt_id}")
        if prompt_id in history:
            entry = history[prompt_id]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise RuntimeError(json.dumps(status, indent=2, ensure_ascii=False))
            for output in entry.get("outputs", {}).values():
                images = output.get("images", [])
                if images:
                    image = images[0]
                    query = urllib.parse.urlencode({
                        "filename": image["filename"],
                        "subfolder": image.get("subfolder", ""),
                        "type": image.get("type", "output"),
                    })
                    cache = AI_HOME / "generated-cache" / f"{prompt_id}.png"
                    cache.parent.mkdir(parents=True, exist_ok=True)
                    urllib.request.urlretrieve(f"{SERVER}/view?{query}", cache)
                    return cache
        time.sleep(1)
    raise TimeoutError(f"Génération expirée: {prompt_id}")


def remove_green_background(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = list(rgba.getdata())
    converted: list[tuple[int, int, int, int]] = []
    for red, green, blue, _alpha in pixels:
        dominance = green - max(red, blue)
        alpha = 255 - max(0, min(255, int((dominance - 12) * 5.2)))
        if green > 105 and dominance > 18:
            spill = max(0, dominance)
            green = max(max(red, blue), green - spill)
        converted.append((red, green, blue, alpha))
    rgba.putdata(converted)
    alpha_channel = rgba.getchannel("A").filter(ImageFilter.GaussianBlur(0.65))
    rgba.putalpha(alpha_channel)
    bbox = alpha_channel.getbbox()
    return rgba.crop(bbox) if bbox else rgba


def remove_background(image: Image.Image) -> Image.Image:
    global _REMBG_SESSION
    try:
        from rembg import new_session, remove

        if _REMBG_SESSION is None:
            _REMBG_SESSION = new_session("u2net")
        cutout = remove(image.convert("RGB"), session=_REMBG_SESSION, alpha_matting=True)
        rgba = cutout.convert("RGBA")
        bbox = rgba.getchannel("A").getbbox()
        return rgba.crop(bbox) if bbox else rgba
    except Exception as error:
        print(f"[warn] rembg indisponible, détourage chroma utilisé: {error}", flush=True)
        return remove_green_background(image)


def fit_asset(image: Image.Image, width: int, height: int, transparent: bool) -> Image.Image:
    if transparent and image.mode == "RGBA" and image.getchannel("A").getextrema()[0] < 250:
        source = image.copy()
        bbox = source.getchannel("A").getbbox()
        source = source.crop(bbox) if bbox else source
    else:
        source = remove_background(image) if transparent else image.convert("RGB")
    if transparent:
        canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        scale = min((width * 0.88) / source.width, (height * 0.88) / source.height)
        target = source.resize((max(1, int(source.width * scale)), max(1, int(source.height * scale))), Image.Resampling.LANCZOS)
        canvas.alpha_composite(target, ((width - target.width) // 2, (height - target.height) // 2))
        return canvas
    return ImageOps.fit(source, (width, height), Image.Resampling.LANCZOS, centering=(0.5, 0.5))


def image_score(image: Image.Image, transparent: bool) -> float:
    rgba = image.convert("RGBA")
    stat = ImageStat.Stat(rgba.convert("RGB"))
    contrast = sum(stat.stddev) / 3.0
    score = contrast
    if transparent:
        alpha = rgba.getchannel("A")
        histogram = alpha.histogram()
        visible = 1.0 - histogram[0] / max(1, rgba.width * rgba.height)
        score -= abs(visible - 0.42) * 90.0
        border = Image.new("L", alpha.size, 0)
        border.paste(255, (0, 0, alpha.width, 8))
        border.paste(255, (0, alpha.height - 8, alpha.width, alpha.height))
        border.paste(255, (0, 0, 8, alpha.height))
        border.paste(255, (alpha.width - 8, 0, alpha.width, alpha.height))
        edge_alpha = ImageStat.Stat(ImageChops.multiply(alpha, border)).mean[0]
        score -= edge_alpha * 0.45
    return round(score, 3)


def generate_asset(asset: dict[str, Any], defaults: dict[str, Any], style: str, negative: str, force: bool) -> Candidate:
    settings = defaults | asset
    output = PROJECT_ROOT / settings["output"]
    if output.exists() and not force:
        with Image.open(output) as existing:
            return Candidate(output, image_score(existing, bool(settings["transparent"])), 0)
    output.parent.mkdir(parents=True, exist_ok=True)
    candidate_dir = PROJECT_ROOT / "art" / "local_ai" / "candidates" / settings["id"]
    candidate_dir.mkdir(parents=True, exist_ok=True)
    prompt = f"{settings['prompt']}. {style}. Avoid: {negative}."
    candidates: list[Candidate] = []
    for variant in range(int(settings["variants"])):
        seed = random.SystemRandom().randrange(1, 2**63 - 1)
        raw = run_workflow(
            flux_workflow(prompt, int(settings["width"]), int(settings["height"]), seed, f"cyberseeker/{settings['id']}/{variant}"),
        )
        with Image.open(raw) as generated:
            processed = fit_asset(generated, int(settings["width"]), int(settings["height"]), bool(settings["transparent"]))
            path = candidate_dir / f"{variant:02d}_{seed}.png"
            processed.save(path, optimize=True)
            candidates.append(Candidate(path, image_score(processed, bool(settings["transparent"])), seed))
    winner = max(candidates, key=lambda item: item.score)
    shutil.copy2(winner.path, output)
    return Candidate(output, winner.score, winner.seed)


def build_atlas(atlas: dict[str, Any], generated: dict[str, Candidate]) -> Path:
    cell = int(atlas["cell"])
    columns = int(atlas["columns"])
    rows = int(atlas["rows"])
    canvas = Image.new("RGBA", (columns * cell, rows * cell), (0, 0, 0, 0))
    for index, source_id in enumerate(atlas["sources"]):
        with Image.open(generated[source_id].path) as image:
            fitted = fit_asset(image, cell, cell, True)
            canvas.alpha_composite(fitted, ((index % columns) * cell, (index // columns) * cell))
    output = PROJECT_ROOT / atlas["output"]
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, optimize=True)
    return output


def validate_image(path: Path, width: int, height: int, transparent: bool) -> None:
    with Image.open(path) as image:
        if image.size != (width, height):
            raise ValueError(f"Dimensions invalides pour {path}: {image.size} != {(width, height)}")
        if transparent:
            if image.mode != "RGBA" or image.getchannel("A").getextrema()[0] >= 250:
                raise ValueError(f"Transparence absente pour {path}")


def promote_assets(promotions: list[dict[str, str]]) -> dict[str, str]:
    promoted: dict[str, str] = {}
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup_root = PROJECT_ROOT / "art" / "local_ai" / "previous_runtime" / stamp
    for item in promotions:
        source = PROJECT_ROOT / item["source"]
        target = PROJECT_ROOT / item["target"]
        if not source.exists():
            raise FileNotFoundError(f"Asset validé absent avant promotion: {source}")
        if target.exists():
            backup = backup_root / target.relative_to(PROJECT_ROOT)
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, backup)
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_suffix(target.suffix + ".next")
        shutil.copy2(source, temporary)
        os.replace(temporary, target)
        promoted[item["target"]] = item["source"]
        print(f"[promote] {source} -> {target}", flush=True)
    return promoted


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=SCRIPT_DIR / "asset_manifest.json")
    parser.add_argument("--only", nargs="*", default=[])
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--keep-server", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    selected = set(args.only)
    process = ensure_server()
    report: dict[str, Any] = {"generatedAt": int(time.time()), "engine": "FLUX.2 Klein 4B local", "assets": {}}
    generated: dict[str, Candidate] = {}
    try:
        for asset in manifest["assets"]:
            if selected and asset["id"] not in selected:
                continue
            print(f"[generate] {asset['id']}", flush=True)
            winner = generate_asset(asset, manifest["defaults"], manifest["style"], manifest["negative"], args.force)
            generated[asset["id"]] = winner
            settings = manifest["defaults"] | asset
            validate_image(winner.path, int(settings["width"]), int(settings["height"]), bool(settings["transparent"]))
            report["assets"][asset["id"]] = {"path": str(winner.path), "score": winner.score, "seed": winner.seed}
            print(f"[selected] {winner.path} score={winner.score}", flush=True)
        for atlas in manifest.get("atlases", []):
            if selected and not all(source in generated for source in atlas["sources"]):
                continue
            path = build_atlas(atlas, generated)
            report.setdefault("atlases", {})[atlas["id"]] = str(path)
            print(f"[atlas] {path}", flush=True)
        if not selected:
            report["promoted"] = promote_assets(manifest.get("promotions", []))
    finally:
        REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
        REPORT_PATH.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
        if process is not None and not args.keep_server:
            process.terminate()
    print(f"[report] {REPORT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
