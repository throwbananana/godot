import bpy
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sokpop_common import (
    TILE_FULL_BLEED,
    setup_render_settings,
    create_sokpop_lighting,
    create_clay_mat,
    apply_uniform_clay_bevel,
    render_and_clean,
    clear_scene,
    purge_orphans,
)

ROOT_DIR = os.path.dirname(SCRIPT_DIR)
OUTPUT_DIR = os.path.join(ROOT_DIR, "assets", "sprites", "tiles")
EFFECTS_DIR = os.path.join(ROOT_DIR, "assets", "sprites", "effects")
os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(EFFECTS_DIR, exist_ok=True)

def build_wormhole_tile():
    objs = []
    # Cosmic wormhole materials
    mat_void_base = create_clay_mat("m_wh_b", (0.12, 0.08, 0.20, 1.0), roughness=0.85)
    mat_outer_ring = create_clay_mat("m_wh_o", (0.55, 0.20, 0.75, 1.0), roughness=0.55)
    mat_mid_swirl = create_clay_mat("m_wh_m", (0.20, 0.65, 0.95, 1.0), roughness=0.40)
    mat_core_singularity = create_clay_mat("m_wh_c", (0.05, 0.02, 0.08, 1.0), roughness=0.95)
    mat_glow_core = create_clay_mat("m_wh_gl", (0.45, 0.95, 1.0, 1.0), emission=(0.45, 0.95, 1.0, 1.0), emission_str=4.0)
    mat_glow_mote = create_clay_mat("m_wh_gm", (0.95, 0.35, 0.85, 1.0), emission=(0.95, 0.35, 0.85, 1.0), emission_str=3.5)

    # 1. Dark Cosmic Substrate Base Plate
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.10))
    base = bpy.context.active_object
    base.scale = (TILE_FULL_BLEED, TILE_FULL_BLEED, 0.20)
    base.data.materials.append(mat_void_base)
    apply_uniform_clay_bevel(base, width=0.06, segments=3, jitter=0.0)
    objs.append(base)

    # 2. Outer Accretion Ring (Purple Clay Torus)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.35, minor_radius=0.28, major_segments=24, minor_segments=10, location=(0, 0, 0.08))
    ring1 = bpy.context.active_object
    ring1.data.materials.append(mat_outer_ring)
    apply_uniform_clay_bevel(ring1, width=0.04, segments=2, jitter=0.015)
    objs.append(ring1)

    # 3. Middle Swirling Vortex Arms (4 curved spiral lobes)
    for i in range(4):
        angle = i * (math.pi / 2.0)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=1.10, vertices=12, location=(math.cos(angle)*0.75, math.sin(angle)*0.75, 0.12))
        arm = bpy.context.active_object
        arm.rotation_euler = (math.radians(25), math.radians(20), angle + math.radians(45))
        arm.scale = (1.0, 1.0, 0.35)
        arm.data.materials.append(mat_mid_swirl)
        apply_uniform_clay_bevel(arm, width=0.04, segments=2, jitter=0.01)
        objs.append(arm)

    # 4. Singularity Abyss (Central funnel depression)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.62, depth=0.25, vertices=16, location=(0, 0, 0.02))
    hole = bpy.context.active_object
    hole.data.materials.append(mat_core_singularity)
    apply_uniform_clay_bevel(hole, width=0.04, segments=2, jitter=0.0)
    objs.append(hole)

    # 5. Glowing Singularity Core Eye
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.32, location=(0, 0, 0.06))
    core_eye = bpy.context.active_object
    core_eye.scale = (1.0, 1.0, 0.40)
    core_eye.data.materials.append(mat_glow_core)
    apply_uniform_clay_bevel(core_eye, width=0.02, segments=2, jitter=0.0)
    objs.append(core_eye)

    # 6. Orbiting Dimensional Energy Motes
    for m_idx in range(6):
        m_angle = m_idx * (2.0 * math.pi / 6.0) + 0.35
        m_r = 1.18 + 0.12 * math.sin(m_idx * 1.5)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(math.cos(m_angle)*m_r, math.sin(m_angle)*m_r, 0.22))
        mote = bpy.context.active_object
        mote.data.materials.append(mat_glow_mote)
        apply_uniform_clay_bevel(mote, width=0.02, segments=2, jitter=0.0)
        objs.append(mote)

    return objs

def main():
    print(">>> 1. Rendering 3D Sokpop Cosmic Wormhole Tile (tile_wormhole.png)...")
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting()
    objs = build_wormhole_tile()
    out_wh = os.path.join(OUTPUT_DIR, "tile_wormhole.png")
    render_and_clean(objs, out_wh)
    purge_orphans()

    print(">>> ALL WORMHOLE 3D ASSETS RENDERED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
