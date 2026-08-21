import bpy
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in locals() else os.getcwd()
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    srgb_to_linear,
    clear_scene,
    setup_render_settings,
    create_sokpop_lighting,
    create_clay_mat,
    apply_uniform_clay_bevel,
    render_and_clean,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
os.makedirs(SPRITES_POWERUPS, exist_ok=True)

def build_diamond_gem():
    objs = []
    # Material palette: Brilliant Sky Cyan, Luminous Core, Pure White Gleam
    mat_gem = create_clay_mat("m_dia_body", (0.22, 0.75, 0.98, 1.0), roughness=0.25)
    mat_core = create_clay_mat("m_dia_core", (0.50, 0.90, 1.0, 1.0), emission=(0.50, 0.90, 1.0, 1.0), emission_str=3.0)
    mat_sparkle = create_clay_mat("m_dia_spark", (1.0, 1.0, 1.0, 1.0), emission=(1.0, 1.0, 1.0, 1.0), emission_str=4.0)

    # 1. Main Brilliant-cut Crystal Diamond Body
    # Top Crown
    bpy.ops.mesh.primitive_cylinder_add(radius=0.92, depth=0.42, vertices=8, location=(0, 0, 0.18))
    crown = bpy.context.active_object
    crown.data.materials.append(mat_gem)
    apply_uniform_clay_bevel(crown, width=0.06, segments=2)
    objs.append(crown)

    # Flat Table Top
    bpy.ops.mesh.primitive_cylinder_add(radius=0.62, depth=0.10, vertices=8, location=(0, 0, 0.42))
    table = bpy.context.active_object
    table.data.materials.append(mat_gem)
    apply_uniform_clay_bevel(table, width=0.03, segments=2)
    objs.append(table)

    # Bottom Pavilion Cone
    bpy.ops.mesh.primitive_cone_add(radius1=0.92, radius2=0.05, depth=0.88, vertices=8, location=(0, 0, -0.42))
    pavilion = bpy.context.active_object
    pavilion.rotation_euler = (math.radians(180), 0, 0)
    pavilion.data.materials.append(mat_gem)
    apply_uniform_clay_bevel(pavilion, width=0.05, segments=2)
    objs.append(pavilion)

    # 2. Glowing Inner Core Crystal
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.35, location=(0, 0, 0.05))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(core)

    # 3. Sparkling Star Gleams
    for (sx, sy, sz, s_scale) in [(0.52, -0.52, 0.35, 0.16), (-0.45, 0.45, 0.28, 0.12), (0.0, -0.65, -0.15, 0.10)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, sy, sz))
        spark = bpy.context.active_object
        spark.scale = (s_scale * 1.5, s_scale * 0.35, s_scale * 0.35)
        spark.rotation_euler = (0, 0, math.radians(45))
        spark.data.materials.append(mat_sparkle)
        apply_uniform_clay_bevel(spark, width=0.01, segments=1)
        objs.append(spark)

        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, sy, sz))
        spark2 = bpy.context.active_object
        spark2.scale = (s_scale * 0.35, s_scale * 1.5, s_scale * 0.35)
        spark2.rotation_euler = (0, 0, math.radians(45))
        spark2.data.materials.append(mat_sparkle)
        apply_uniform_clay_bevel(spark2, width=0.01, segments=1)
        objs.append(spark2)

    return objs

def main():
    print("==================================================")
    print(" Rendering Diamond Gem Collectible Sprite.. ")
    print("==================================================")

    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=2.60)
    dia_objs = build_diamond_gem()
    dia_out = os.path.join(SPRITES_POWERUPS, "diamond_gem.png")
    render_and_clean(dia_objs, dia_out)
    print(f"[OK] Diamond Gem rendered -> {dia_out}")

if __name__ == '__main__':
    main()
