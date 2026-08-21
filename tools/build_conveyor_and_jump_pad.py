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
    ORTHO_SCALE_DEFAULT,
    TILE_FULL_BLEED,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TILES = os.path.join(PROJECT_DIR, "assets", "sprites", "tiles")
os.makedirs(SPRITES_TILES, exist_ok=True)

# ==================== 1. CONVEYOR BELT TILE ====================
def build_conveyor_tile():
    objs = []
    # Full-bleed tile dimensions
    tw = TILE_FULL_BLEED  # 2.0
    th = TILE_FULL_BLEED

    mat_track = create_clay_mat("m_conv_track", (0.18, 0.20, 0.24, 1.0), roughness=0.70)
    mat_rail = create_clay_mat("m_conv_rail", (0.35, 0.38, 0.44, 1.0), roughness=0.50)
    mat_arrow = create_clay_mat("m_conv_arrow", (0.98, 0.78, 0.15, 1.0), emission=(0.98, 0.78, 0.15, 1.0), emission_str=2.2)
    mat_roller = create_clay_mat("m_conv_roller", (0.50, 0.54, 0.60, 1.0), roughness=0.40)

    # 1. Main Rubber/Steel Tread Base
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.05))
    base = bpy.context.active_object
    base.scale = (tw, th, 0.20)
    base.data.materials.append(mat_track)
    apply_uniform_clay_bevel(base, width=0.04, segments=2)
    objs.append(base)

    # 2. Side Guide Guard Rails (Left & Right)
    for sx in [-tw * 0.46, tw * 0.46]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, 0, 0.08))
        rail = bpy.context.active_object
        rail.scale = (0.16, th, 0.16)
        rail.data.materials.append(mat_rail)
        apply_uniform_clay_bevel(rail, width=0.04, segments=2)
        objs.append(rail)

        # Rollers along the side
        for ry in [-0.65, 0.0, 0.65]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.18, vertices=12, location=(sx, ry, 0.12))
            roller = bpy.context.active_object
            roller.rotation_euler = (math.radians(90), 0, 0)
            roller.data.materials.append(mat_roller)
            apply_uniform_clay_bevel(roller, width=0.02, segments=2)
            objs.append(roller)

    # 3. Chevron Directional Arrows (Pointing UP)
    for ay in [-0.55, 0.0, 0.55]:
        # Left wing of chevron
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.24, ay - 0.08, 0.06))
        w1 = bpy.context.active_object
        w1.scale = (0.52, 0.14, 0.06)
        w1.rotation_euler = (0, 0, math.radians(35))
        w1.data.materials.append(mat_arrow)
        apply_uniform_clay_bevel(w1, width=0.02, segments=2)
        objs.append(w1)

        # Right wing of chevron
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.24, ay - 0.08, 0.06))
        w2 = bpy.context.active_object
        w2.scale = (0.52, 0.14, 0.06)
        w2.rotation_euler = (0, 0, math.radians(-35))
        w2.data.materials.append(mat_arrow)
        apply_uniform_clay_bevel(w2, width=0.02, segments=2)
        objs.append(w2)

    return objs

# ==================== 2. JUMP PAD / SUPER EJECTOR ====================
def build_jump_pad_tile():
    objs = []
    tw = TILE_FULL_BLEED
    th = TILE_FULL_BLEED

    mat_base = create_clay_mat("m_pad_base", (0.24, 0.26, 0.32, 1.0), roughness=0.60)
    mat_corner = create_clay_mat("m_pad_corner", (0.88, 0.35, 0.12, 1.0), roughness=0.50)
    mat_spring = create_clay_mat("m_pad_spring", (0.95, 0.55, 0.10, 1.0), roughness=0.35)
    mat_core = create_clay_mat("m_pad_core", (1.0, 0.50, 0.05, 1.0), emission=(1.0, 0.50, 0.05, 1.0), emission_str=3.5)
    mat_chevron = create_clay_mat("m_pad_chev", (1.0, 0.90, 0.20, 1.0), emission=(1.0, 0.90, 0.20, 1.0), emission_str=2.8)

    # 1. Heavy Outer Octagonal Steel Foundation
    bpy.ops.mesh.primitive_cylinder_add(radius=0.96, depth=0.22, vertices=8, location=(0, 0, -0.04))
    base = bpy.context.active_object
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.08, segments=3)
    objs.append(base)

    # 2. Four Corner Reinforced Shock Absorbers
    for (cx, cy) in [(-0.68, -0.68), (0.68, -0.68), (-0.68, 0.68), (0.68, 0.68)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.34, vertices=16, location=(cx, cy, 0.08))
        absorber = bpy.context.active_object
        absorber.data.materials.append(mat_corner)
        apply_uniform_clay_bevel(absorber, width=0.04, segments=2)
        objs.append(absorber)

        bpy.ops.mesh.primitive_torus_add(major_radius=0.14, minor_radius=0.035, location=(cx, cy, 0.20))
        coil = bpy.context.active_object
        coil.data.materials.append(mat_spring)
        bpy.ops.object.shade_smooth()
        objs.append(coil)

    # 3. Central Spring-Loaded Launch Plate
    bpy.ops.mesh.primitive_cylinder_add(radius=0.62, depth=0.26, vertices=24, location=(0, 0, 0.12))
    piston = bpy.context.active_object
    piston.data.materials.append(mat_spring)
    apply_uniform_clay_bevel(piston, width=0.06, segments=2)
    objs.append(piston)

    # Luminous Core Eye
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.26, location=(0, 0, 0.24))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(core)

    # Concentric Ejector Launch Target Cross
    for ang in [0, math.radians(90), math.radians(180), math.radians(270)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.26))
        chev = bpy.context.active_object
        chev.scale = (0.09, 0.22, 0.04)
        chev.location = (math.cos(ang) * 0.42, math.sin(ang) * 0.42, 0.26)
        chev.rotation_euler = (0, 0, ang)
        chev.data.materials.append(mat_chevron)
        apply_uniform_clay_bevel(chev, width=0.02, segments=2)
        objs.append(chev)

    return objs

def main():
    print("==================================================")
    print(" Rendering Conveyor Belt & Jump Pad Tile Sprites.. ")
    print("==================================================")

    # 1. Render Conveyor Belt
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting()
    conv_objs = build_conveyor_tile()
    conv_out = os.path.join(SPRITES_TILES, "tile_conveyor.png")
    render_and_clean(conv_objs, conv_out)
    print(f"[OK] Conveyor Belt rendered -> {conv_out}")

    # 2. Render Jump Pad
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting()
    jump_objs = build_jump_pad_tile()
    jump_out = os.path.join(SPRITES_TILES, "tile_jump_pad.png")
    render_and_clean(jump_objs, jump_out)
    print(f"[OK] Jump Pad rendered -> {jump_out}")

if __name__ == '__main__':
    main()
