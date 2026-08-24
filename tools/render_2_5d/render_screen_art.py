"""Génère les quatre dioramas 2.5D utilisés par les écrans secondaires.

Les modèles Tripo pourront remplacer les volumes procéduraux sans modifier la
caméra, la lumière, la palette ou le contrat d'export PNG transparent.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--blend-dir", required=True)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])


def clean_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for block in list(blocks):
            if block.users == 0:
                blocks.remove(block)


def mat(
    name: str,
    color: tuple[float, float, float, float],
    metallic: float = 0.25,
    roughness: float = 0.28,
    emission: tuple[float, float, float, float] | None = None,
    strength: float = 0.0,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if emission:
        shader.inputs["Emission Color"].default_value = emission
        shader.inputs["Emission Strength"].default_value = strength
    return material


def palette() -> dict[str, bpy.types.Material]:
    return {
        "navy": mat("ToyNavy", (0.018, 0.065, 0.18, 1), 0.42, 0.24),
        "blue": mat("ToyBlue", (0.035, 0.20, 0.46, 1), 0.34, 0.24),
        "glass": mat("DeepGlass", (0.012, 0.045, 0.12, 1), 0.18, 0.14),
        "cyan": mat(
            "SignalCyan", (0.015, 0.62, 0.78, 1), 0.22, 0.18,
            (0.02, 0.92, 1.0, 1), 2.2,
        ),
        "magenta": mat(
            "PlasmaMagenta", (0.68, 0.018, 0.38, 1), 0.24, 0.19,
            (1.0, 0.03, 0.56, 1), 2.0,
        ),
        "gold": mat("RewardGold", (0.92, 0.43, 0.035, 1), 0.92, 0.14),
        "white": mat(
            "CoreWhite", (0.62, 0.88, 1.0, 1), 0.18, 0.18,
            (0.3, 0.82, 1.0, 1), 0.75,
        ),
    }


def box(name: str, xyz: tuple[float, float, float], dims: tuple[float, float, float], material: bpy.types.Material, bevel: float = 0.12) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=xyz)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modifier = obj.modifiers.new("Premium bevel", "BEVEL")
    modifier.width = bevel
    modifier.segments = 5
    modifier.limit_method = "ANGLE"
    obj.data.materials.append(material)
    return obj


def cylinder(name: str, xyz: tuple[float, float, float], radius: float, depth: float, material: bpy.types.Material, rotation: tuple[float, float, float] = (0, 0, 0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=radius, depth=depth, location=xyz, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    bevel = obj.modifiers.new("Soft edge", "BEVEL")
    bevel.width = min(0.07, depth * 0.18)
    bevel.segments = 4
    return obj


def torus(name: str, xyz: tuple[float, float, float], major: float, minor: float, material: bpy.types.Material, rotation: tuple[float, float, float] = (0, 0, 0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=64, minor_segments=16, location=xyz, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    return obj


def sphere(name: str, xyz: tuple[float, float, float], radius: float, material: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=radius, location=xyz)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    return obj


def plinth(p: dict[str, bpy.types.Material], accent: str = "cyan") -> None:
    cylinder("DioramaBase", (0, 0.25, 0.15), 3.8, 0.35, p["navy"])
    torus("BaseTrim", (0, 0.25, 0.32), 3.28, 0.055, p[accent])
    cylinder("GoldCore", (0, 0.25, 0.34), 0.38, 0.13, p["gold"])


def district(p: dict[str, bpy.types.Material]) -> None:
    plinth(p, "cyan")
    specs = [(-2.45, 1.75, 1.1), (-1.25, 2.55, 1.25), (0, 3.65, 1.42), (1.35, 2.25, 1.2), (2.5, 1.55, 1.05)]
    for i, (x, height, width) in enumerate(specs):
        shell = p["blue"] if i % 2 else p["navy"]
        box(f"Tower{i}", (x, 0.2 + abs(x) * 0.10, 0.48 + height / 2), (width, 1.15, height), shell, 0.15)
        box(f"TowerGlow{i}", (x, -0.40 + abs(x) * 0.10, 0.9 + height * 0.42), (width * 0.68, 0.055, 0.12), p["cyan"] if i < 3 else p["magenta"], 0.035)
        for level in range(2):
            box(f"Window{i}_{level}", (x, -0.42 + abs(x) * 0.10, 0.82 + level * 0.52), (width * 0.42, 0.045, 0.17), p["white"], 0.035)
    torus("SignalRing", (0, 0.32, 3.62), 0.52, 0.065, p["gold"], (math.pi / 2, 0, 0))
    cylinder("SignalMast", (0, 0.32, 4.12), 0.09, 1.0, p["cyan"])
    sphere("SignalBeacon", (0, 0.32, 4.68), 0.18, p["magenta"])


def collection(p: dict[str, bpy.types.Material]) -> None:
    plinth(p, "magenta")
    box("VaultBody", (0.9, 0.30, 1.78), (3.5, 1.7, 3.0), p["navy"], 0.32)
    cylinder("VaultDoor", (0.9, -0.62, 1.78), 1.05, 0.25, p["blue"], (math.pi / 2, 0, 0))
    torus("VaultGold", (0.9, -0.78, 1.78), 0.79, 0.08, p["gold"], (math.pi / 2, 0, 0))
    cylinder("VaultCore", (0.9, -0.90, 1.78), 0.25, 0.16, p["cyan"], (math.pi / 2, 0, 0))
    for angle in (0, math.pi / 2, math.pi, math.pi * 1.5):
        x = 0.9 + math.cos(angle) * 0.55
        z = 1.78 + math.sin(angle) * 0.55
        dims = (0.12, 0.09, 0.48) if abs(math.cos(angle)) < 0.1 else (0.48, 0.09, 0.12)
        box("VaultSpoke", (x, -0.91, z), dims, p["gold"], 0.04)
    box("CacheBase", (-2.0, -0.15, 0.83), (2.0, 1.35, 1.05), p["blue"], 0.24)
    lid = box("CacheLid", (-2.0, 0.08, 1.58), (2.0, 0.95, 0.34), p["gold"], 0.15)
    lid.rotation_euler.x = math.radians(-18)
    box("CacheLight", (-2.0, -0.86, 1.05), (1.38, 0.05, 0.22), p["magenta"], 0.05)
    for i, color in enumerate(("cyan", "gold", "magenta")):
        card = box(f"DataCard{i}", (-2.45 + i * 0.47, -0.22 - i * 0.05, 2.05 + i * 0.18), (0.72, 0.10, 1.02), p[color], 0.10)
        card.rotation_euler.y = math.radians(-10 + i * 11)


def missions(p: dict[str, bpy.types.Material]) -> None:
    plinth(p, "cyan")
    cylinder("MissionPedestal", (0, 0.25, 1.12), 1.08, 1.65, p["blue"])
    torus("RadarOuter", (0, 0.04, 2.68), 1.46, 0.11, p["cyan"], (math.pi / 2, 0, 0))
    torus("RadarInner", (0, 0.01, 2.68), 0.88, 0.055, p["magenta"], (math.pi / 2, 0, 0))
    cylinder("RadarCore", (0, -0.12, 2.68), 0.26, 0.18, p["gold"], (math.pi / 2, 0, 0))
    for angle in (0, math.pi / 2, math.pi, math.pi * 1.5):
        x = math.cos(angle) * 1.12
        z = 2.68 + math.sin(angle) * 1.12
        sphere("SignalNode", (x, -0.08, z), 0.12, p["white"])
    for i, x in enumerate((-2.55, 2.55)):
        box(f"ObjectivePylon{i}", (x, 0.35, 1.28), (1.12, 1.1, 2.05), p["navy"], 0.22)
        box(f"ObjectiveScreen{i}", (x, -0.23, 1.42), (0.72, 0.05, 0.83), p["cyan"] if i == 0 else p["magenta"], 0.12)
        for step in range(3):
            box(f"Progress{i}_{step}", (x - 0.25 + step * 0.25, -0.29, 0.68), (0.14, 0.04, 0.12 + step * 0.16), p["gold"], 0.035)
    sphere("OrbitReward", (1.72, -0.1, 3.82), 0.27, p["gold"])


def store(p: dict[str, bpy.types.Material]) -> None:
    plinth(p, "magenta")
    box("StoreKiosk", (0, 0.30, 1.70), (4.35, 1.65, 2.9), p["navy"], 0.30)
    box("StoreFace", (0, -0.58, 1.78), (3.82, 0.13, 2.35), p["blue"], 0.22)
    box("StoreCanopy", (0, -0.25, 3.38), (5.05, 2.0, 0.48), p["gold"], 0.18)
    for i, color in enumerate(("cyan", "magenta", "cyan")):
        x = -1.18 + i * 1.18
        box(f"ProductBay{i}", (x, -0.70, 1.82), (0.92, 0.12, 1.35), p["glass"], 0.14)
        sphere(f"Product{i}", (x, -0.84, 1.86), 0.28 + i * 0.04, p[color])
        box(f"PriceRail{i}", (x, -0.83, 1.12), (0.64, 0.05, 0.14), p["gold"], 0.04)
    box("StoreSign", (0, -0.72, 3.43), (2.45, 0.10, 0.28), p["magenta"], 0.09)
    for i, x in enumerate((-2.5, 2.5)):
        cylinder(f"CoinStack{i}", (x, -0.05, 0.64), 0.46, 0.24 + i * 0.14, p["gold"])
        torus(f"CoinTrim{i}", (x, -0.05, 0.82 + i * 0.07), 0.30, 0.055, p["cyan"])


def mascot(p: dict[str, bpy.types.Material]) -> None:
    """BYTE, guide original de CyberSeeker : silhouette ronde et lisible."""
    cylinder("MascotBase", (0, 0.35, 0.18), 2.65, 0.34, p["navy"])
    torus("MascotBaseGlow", (0, 0.35, 0.36), 2.20, 0.055, p["magenta"])
    cylinder("Body", (0, 0.25, 1.42), 0.96, 1.62, p["blue"])
    torus("BodyCore", (0, -0.62, 1.48), 0.48, 0.09, p["gold"], (math.pi / 2, 0, 0))
    sphere("Head", (0, 0.05, 3.05), 1.34, p["navy"])
    box("FaceVisor", (0, -1.04, 3.02), (1.90, 0.17, 0.75), p["glass"], 0.25)
    for i, x in enumerate((-0.46, 0.46)):
        box(f"Eye{i}", (x, -1.15, 3.05), (0.34, 0.07, 0.20), p["cyan"] if i == 0 else p["magenta"], 0.08)
        torus(f"EarTrim{i}", (x * 2.85, 0.05, 3.05), 0.36, 0.08, p["gold"], (math.pi / 2, 0, 0))
    cylinder("Antenna", (0, 0.05, 4.62), 0.08, 0.72, p["gold"])
    sphere("AntennaBeacon", (0, 0.05, 5.02), 0.18, p["cyan"])
    for i, x in enumerate((-1.36, 1.36)):
        cylinder(f"Arm{i}", (x, 0.20, 1.72), 0.22, 0.82, p["blue"], (0, math.pi / 2, 0))
        sphere(f"Hand{i}", (x * 1.25, 0.20, 1.72), 0.30, p["gold"])
    for i, x in enumerate((-0.48, 0.48)):
        box(f"Foot{i}", (x, -0.02, 0.54), (0.68, 1.05, 0.42), p["navy"], 0.18)
    torus("HeadHalo", (0, 0.82, 3.12), 1.67, 0.045, p["cyan"], (math.pi / 2, 0, 0))


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def light(name: str, xyz: tuple[float, float, float], color: tuple[float, float, float], energy: float, size: float) -> None:
    data = bpy.data.lights.new(name, "AREA")
    data.color = color
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = xyz
    look_at(obj, (0, 0, 1.7))


def configure(output: Path, square: bool = False) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 850 if square else 1000
    scene.render.resolution_y = 850 if square else 470
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.compression = 25
    scene.render.film_transparent = True
    scene.render.filepath = str(output)
    scene.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("CyberVoid") if not bpy.data.worlds.get("CyberVoid") else bpy.data.worlds["CyberVoid"]
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.025, 0.06, 0.15, 1)
    background.inputs["Strength"].default_value = 0.30
    camera_data = bpy.data.cameras.new("HeroCamera")
    camera = bpy.data.objects.new("HeroCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (6.2, -13.8, 6.6) if square else (7.6, -13.8, 7.2)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 6.6 if square else 7.3
    look_at(camera, (0, 0.15, 2.35 if square else 1.9))
    scene.camera = camera
    light("WarmKey", (-5, -6, 8), (1.0, 0.48, 0.19), 1300, 4.5)
    light("CyanFill", (5, -5, 6), (0.04, 0.70, 1.0), 1550, 4.0)
    light("TopSoft", (0, 2, 10), (0.48, 0.62, 1.0), 1800, 5.0)


def render_one(name: str, builder, output_dir: Path, blend_dir: Path) -> None:
    clean_scene()
    builder(palette())
    output = output_dir / f"{name}_hero.png"
    blend = blend_dir / f"cyberseeker_{name}_hero.blend"
    configure(output, name == "mascot")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.ops.render.render(write_still=True)
    print(f"CYBERSEEKER_HERO_OK name={name} output={output}")


def main() -> None:
    args = arguments()
    output_dir = Path(args.output_dir).resolve()
    blend_dir = Path(args.blend_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    blend_dir.mkdir(parents=True, exist_ok=True)
    for name, builder in (
        ("district", district),
        ("collection", collection),
        ("missions", missions),
        ("store", store),
		("mascot", mascot),
    ):
        render_one(name, builder, output_dir, blend_dir)
    print("CYBERSEEKER_SCREEN_ART_OK count=5")


if __name__ == "__main__":
    main()
