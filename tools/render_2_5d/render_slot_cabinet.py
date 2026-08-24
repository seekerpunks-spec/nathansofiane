"""Rend le cabinet 2.5D de référence CyberSeeker avec Blender.

Ce script est volontairement autonome : les futurs modèles GLB de Tripo
pourront remplacer la géométrie procédurale sans changer caméra, lumière,
colorimétrie ou convention d'export.
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
    parser.add_argument("--output", required=True)
    parser.add_argument("--blend", required=True)
    parser.add_argument("--samples", type=int, default=64)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])


def clean_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def material(
    name: str,
    base: tuple[float, float, float, float],
    *,
    metallic: float = 0.0,
    roughness: float = 0.35,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength

    if name.startswith("Graphite"):
        noise = mat.node_tree.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 7.0
        noise.inputs["Detail"].default_value = 4.0
        noise.inputs["Roughness"].default_value = 0.72
        bump = mat.node_tree.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.13
        bump.inputs["Distance"].default_value = 0.08
        mat.node_tree.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        mat.node_tree.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat: bpy.types.Material,
    bevel: float = 0.12,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modifier = obj.modifiers.new("Toy bevel", "BEVEL")
    modifier.width = bevel
    modifier.segments = 6
    modifier.limit_method = "ANGLE"
    obj.data.materials.append(mat)
    return obj


def cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    vertices: int = 48,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=(math.pi / 2.0, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bevel = obj.modifiers.new("Edge bevel", "BEVEL")
    bevel.width = min(0.06, depth * 0.3)
    bevel.segments = 4
    return obj


def torus(
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=64,
        minor_segments=16,
        location=location,
        rotation=(math.pi / 2.0, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def wedge_logo(mat: bpy.types.Material) -> bpy.types.Object:
    verts = [
        (-0.10, -0.83, 8.08),
        (0.32, -0.83, 8.08),
        (0.05, -0.83, 7.61),
        (0.28, -0.83, 7.61),
        (-0.27, -0.83, 6.98),
        (-0.05, -0.83, 7.50),
        (-0.30, -0.83, 7.50),
    ]
    front = list(range(7))
    back = [(x, y + 0.14, z) for x, y, z in verts]
    vertices = verts + back
    faces = [front, list(reversed(range(7, 14)))]
    for index in range(7):
        next_index = (index + 1) % 7
        faces.append((index, next_index, next_index + 7, index + 7))
    mesh = bpy.data.meshes.new("SignalBoltMesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("SignalBolt", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bevel = obj.modifiers.new("Bolt bevel", "BEVEL")
    bevel.width = 0.045
    bevel.segments = 3
    return obj


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_area(
    name: str,
    location: tuple[float, float, float],
    color: tuple[float, float, float],
    energy: float,
    size: float,
    target: tuple[float, float, float],
) -> None:
    data = bpy.data.lights.new(name, "AREA")
    data.color = color
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    look_at(obj, target)


def add_point(
    name: str,
    location: tuple[float, float, float],
    color: tuple[float, float, float],
    energy: float,
    radius: float,
) -> None:
    data = bpy.data.lights.new(name, "POINT")
    data.color = color
    data.energy = energy
    data.shadow_soft_size = radius
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = location


def build_cabinet() -> None:
    graphite = material(
        "GraphiteShell", (0.018, 0.055, 0.135, 1.0), metallic=0.42, roughness=0.28
    )
    graphite_2 = material(
        "GraphiteInset", (0.040, 0.125, 0.285, 1.0), metallic=0.28, roughness=0.30
    )
    glass = material(
        "SmokedGlass", (0.018, 0.070, 0.170, 1.0), metallic=0.12, roughness=0.16
    )
    cyan = material(
        "SignalCyan",
        (0.020, 0.65, 0.78, 1.0),
        metallic=0.25,
        roughness=0.18,
        emission=(0.02, 0.88, 1.0, 1.0),
        emission_strength=3.2,
    )
    cyan_soft = material(
        "SignalCyanSoft",
        (0.020, 0.32, 0.42, 1.0),
        metallic=0.45,
        roughness=0.22,
        emission=(0.02, 0.62, 0.78, 1.0),
        emission_strength=1.25,
    )
    magenta = material(
        "PlasmaMagenta",
        (0.65, 0.015, 0.40, 1.0),
        metallic=0.3,
        roughness=0.2,
        emission=(1.0, 0.015, 0.55, 1.0),
        emission_strength=2.8,
    )
    gold = material(
        "RewardGold", (0.90, 0.43, 0.035, 1.0), metallic=0.92, roughness=0.16
    )
    white = material(
        "CoreWhite",
        (0.65, 0.90, 1.0, 1.0),
        metallic=0.2,
        roughness=0.18,
        emission=(0.4, 0.9, 1.0, 1.0),
        emission_strength=1.0,
    )

    # Silhouette principale : un jouet premium, épais et immédiatement lisible.
    box("LowerPedestal", (0.0, 0.05, 0.82), (6.32, 1.62, 1.55), graphite, 0.30)
    box("MachineBody", (0.0, 0.03, 4.08), (6.52, 1.35, 5.66), graphite, 0.34)
    box("TopCrown", (0.0, 0.02, 7.36), (6.08, 1.48, 1.32), graphite, 0.34)
    box("CrownInset", (0.0, -0.73, 7.38), (5.22, 0.16, 0.78), graphite_2, 0.23)

    # Écran profond et trois fenêtres de rouleaux.
    box("ReelBay", (0.0, -0.70, 4.32), (6.02, 0.20, 3.62), glass, 0.28)
    box("ReelBayShadow", (0.0, -0.57, 4.32), (5.74, 0.18, 3.34), graphite_2, 0.22)
    for index, x in enumerate((-1.96, 0.0, 1.96), start=1):
        box(f"ReelWindow{index}", (x, -0.82, 4.32), (1.76, 0.13, 3.08), glass, 0.18)
        box(f"ReelGlow{index}", (x, -0.90, 4.32), (1.62, 0.045, 0.86), cyan_soft, 0.12)
    for x in (-3.00, 3.00):
        box("ScreenRail", (x, -0.86, 4.32), (0.10, 0.11, 3.42), cyan, 0.045)
    for z in (2.58, 6.06):
        box("ScreenRail", (0.0, -0.86, z), (6.04, 0.11, 0.10), cyan, 0.045)
    for x in (-0.98, 0.98):
        box("ReelDivider", (x, -0.89, 4.32), (0.055, 0.08, 3.10), gold, 0.022)
    box("WinLine", (0.0, -0.98, 4.32), (5.82, 0.045, 0.055), magenta, 0.018)

    # Épaules, rails et boulons visibles renforcent le volume.
    for x in (-3.12, 3.12):
        box("SideShoulder", (x, -0.08, 4.06), (0.35, 1.60, 4.92), graphite_2, 0.16)
        box("SideNeon", (x * 1.015, -0.88, 4.12), (0.095, 0.10, 4.44), cyan, 0.04)
        for z in (2.02, 6.18):
            cylinder("GoldFastener", (x, -0.92, z), 0.16, 0.12, gold)
            cylinder("FastenerCore", (x, -1.00, z), 0.070, 0.05, graphite)

    # Filets dorés : ils apportent la chaleur casual qui manque à une palette
    # cyberpunk uniquement cyan/magenta.
    for x in (-2.92, 2.92):
        box("BodyGoldTrim", (x, -0.83, 4.12), (0.055, 0.055, 4.72), gold, 0.018)
    for z in (6.67, 8.03):
        box("CrownGoldTrim", (0.0, -0.79, z), (5.35, 0.055, 0.055), gold, 0.018)
    box("PedestalGoldTrim", (0.0, -0.79, 1.93), (5.62, 0.055, 0.060), gold, 0.020)

    # Console et bouton physique sous le bouton tactile Godot.
    box("ConsoleDeck", (0.0, -0.56, 1.35), (5.52, 0.48, 0.58), graphite_2, 0.22)
    box("ButtonRecess", (0.0, -0.86, 1.26), (3.28, 0.12, 0.36), glass, 0.18)
    box("ButtonEnergy", (0.0, -0.94, 1.26), (2.88, 0.06, 0.18), cyan, 0.085)
    for x in (-2.05, -1.78, 1.78, 2.05):
        box("Vent", (x, -0.87, 0.64), (0.13, 0.07, 0.42), graphite_2, 0.05)

    # Halo arrière : lisible même sur un décor complexe.
    torus("RearHalo", (0.0, 0.62, 4.50), 3.57, 0.055, cyan_soft)
    torus("RearHaloInner", (0.0, 0.64, 4.50), 3.30, 0.025, magenta)

    # Micro-détails asymétriques pour éviter l'aspect de simple panneau UI.
    for index, (x, z, mat) in enumerate(
        [(-2.72, 7.72, cyan), (2.72, 7.72, magenta), (-2.72, 1.12, gold), (2.72, 1.12, cyan)]
    ):
        cylinder(f"StatusLamp{index}", (x, -0.91, z), 0.10, 0.09, mat)
    box("SignalBadge", (-2.12, -0.89, 7.38), (0.58, 0.08, 0.12), cyan, 0.04)
    box("AlertBadge", (2.12, -0.89, 7.38), (0.58, 0.08, 0.12), magenta, 0.04)
    cylinder("CoreLens", (0.0, -0.93, 0.62), 0.24, 0.12, gold)


def configure_scene(args: argparse.Namespace) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 1350
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.film_transparent = True
    scene.render.filepath = str(Path(args.output).resolve())
    scene.render.image_settings.compression = 25
    scene.render.resolution_percentage = 100
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.use_file_extension = True
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.look = "AgX - Medium High Contrast"

    world = bpy.data.worlds.new("CyberVoid") if bpy.data.worlds.get("CyberVoid") is None else bpy.data.worlds["CyberVoid"]
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.025, 0.060, 0.140, 1.0)
    background.inputs["Strength"].default_value = 0.38

    camera_data = bpy.data.cameras.new("SpriteCamera")
    camera = bpy.data.objects.new("SpriteCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0.0, -15.5, 4.65)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 9.55
    camera_data.lens = 58
    look_at(camera, (0.0, 0.0, 4.05))
    scene.camera = camera

    add_area("KeyWarm", (-4.4, -6.5, 9.2), (1.0, 0.54, 0.24), 1450.0, 5.0, (0.0, 0.0, 4.1))
    add_area("FillCyan", (4.6, -4.6, 6.6), (0.06, 0.72, 1.0), 1650.0, 4.0, (0.0, 0.0, 4.0))
    add_area("TopSoft", (0.0, 0.8, 11.0), (0.62, 0.72, 1.0), 1950.0, 4.5, (0.0, 0.0, 3.8))
    add_area("FrontSoft", (0.0, -8.0, 3.8), (0.38, 0.66, 1.0), 900.0, 5.5, (0.0, 0.0, 3.8))
    add_point("ReelCyan", (-2.2, -2.2, 4.8), (0.02, 0.68, 1.0), 310.0, 1.4)
    add_point("ReelMagenta", (2.2, -2.1, 4.1), (1.0, 0.02, 0.48), 270.0, 1.2)

    # Les matériaux émissifs restent nets dans le master transparent. Le halo
    # final est appliqué dans Godot afin de conserver un contrôle mobile précis.


def main() -> None:
    args = arguments()
    output = Path(args.output).resolve()
    blend = Path(args.blend).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    blend.parent.mkdir(parents=True, exist_ok=True)
    clean_scene()
    build_cabinet()
    configure_scene(args)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.ops.render.render(write_still=True)
    print(f"CYBERSEEKER_RENDER_OK output={output} blend={blend}")


if __name__ == "__main__":
    main()
