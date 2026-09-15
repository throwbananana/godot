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
)

ROOT_DIR = os.path.dirname(SCRIPT_DIR)
OUTPUT_DIR = os.path.join(ROOT_DIR, "assets", "sprites", "tiles")
os.makedirs(OUTPUT_DIR, exist_ok=True)

def build_ice_tile():
    objs = []
    # Glacial ice materials (Clay style with glossy reflection & frost fractures)
    mat_ice_base = create_clay_mat("m_ice_b", (0.42, 0.76, 0.90, 1.0), roughness=0.22)
    mat_ice_frost = create_clay_mat("m_ice_f", (0.86, 0.95, 0.99, 1.0), roughness=0.35)
    mat_ice_deep = create_clay_mat("m_ice_d", (0.24, 0.52, 0.70, 1.0), roughness=0.28)

    # 1. Full-Bleed Glacial Base Slab
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.08))
    base = bpy.context.active_object
    base.scale = (TILE_FULL_BLEED, TILE_FULL_BLEED, 0.24)
    base.data.materials.append(mat_ice_base)
    apply_uniform_clay_bevel(base, width=0.06, segments=3, jitter=0.0)
    objs.append(base)

    # 2. Layered Frost Sheets & Cracks
    # Center glossy frozen sheet
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.08))
    sheet = bpy.context.active_object
    sheet.scale = (2.90, 2.90, 0.12)
    sheet.data.materials.append(mat_ice_base)
    apply_uniform_clay_bevel(sheet, width=0.08, segments=3, jitter=0.01)
    objs.append(sheet)

    # Frost fracture ridges (Geometric clay crystal shards)
    fractures = [
        ((-0.75, 0.60, 0.15), (1.10, 0.12, 0.06), 0.42, mat_ice_frost),
        ((0.60, -0.70, 0.15), (0.95, 0.10, 0.06), -0.65, mat_ice_frost),
        ((0.10, 0.35, 0.15), (1.30, 0.09, 0.06), 1.15, mat_ice_deep),
        ((-0.50, -0.45, 0.15), (0.80, 0.12, 0.06), 0.85, mat_ice_frost),
        ((0.75, 0.55, 0.15), (0.70, 0.10, 0.06), -0.35, mat_ice_deep),
    ]
    for pos, sc, rot_z, mat in fractures:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=pos)
        f = bpy.context.active_object
        f.scale = sc
        f.rotation_euler = (0, 0, rot_z)
        f.data.materials.append(mat)
        apply_uniform_clay_bevel(f, width=0.03, segments=2, jitter=0.0)
        objs.append(f)

    # Corner frost highlights
    corner_coords = [(-1.25, -1.25), (1.25, -1.25), (-1.25, 1.25), (1.25, 1.25)]
    for cx, cy in corner_coords:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.14, location=(cx, cy, 0.12))
        c = bpy.context.active_object
        c.data.materials.append(mat_ice_frost)
        apply_uniform_clay_bevel(c, width=0.04, segments=2, jitter=0.0)
        objs.append(c)

    return objs

def build_moving_platform_tile():
    objs = []
    # Heavy industrial ferry / elevator platform materials
    mat_plate = create_clay_mat("m_mp_p", (0.40, 0.44, 0.50, 1.0), roughness=0.65)
    mat_tread = create_clay_mat("m_mp_t", (0.28, 0.30, 0.35, 1.0), roughness=0.80)
    mat_yellow_stripe = create_clay_mat("m_mp_y", (0.95, 0.78, 0.15, 1.0), roughness=0.55)
    mat_black_stripe = create_clay_mat("m_mp_b", (0.18, 0.16, 0.20, 1.0), roughness=0.70)
    mat_beacon = create_clay_mat("m_mp_l", (0.98, 0.55, 0.15, 1.0), emission=(1.0, 0.65, 0.2, 1.0), emission_str=2.5)

    # 1. Main Platform Chassis (Raised bevel plate)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.05))
    chassis = bpy.context.active_object
    chassis.scale = (3.12, 3.12, 0.28)
    chassis.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(chassis, width=0.10, segments=3, jitter=0.0)
    objs.append(chassis)

    # 2. Central Non-Slip Grate Area
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.12))
    grate = bpy.context.active_object
    grate.scale = (2.20, 2.20, 0.10)
    grate.data.materials.append(mat_tread)
    apply_uniform_clay_bevel(grate, width=0.06, segments=2, jitter=0.0)
    objs.append(grate)

    # 3. Industrial Hazard Safety Chevron Stripes (Top & Bottom borders)
    for y_pos in [-1.30, 1.30]:
        num_stripes = 7
        stripe_w = 2.80 / num_stripes
        for i in range(num_stripes):
            sx = -1.40 + (i + 0.5) * stripe_w
            use_mat = mat_yellow_stripe if i % 2 == 0 else mat_black_stripe
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, y_pos, 0.14))
            st = bpy.context.active_object
            st.scale = (stripe_w * 0.90, 0.32, 0.08)
            st.data.materials.append(use_mat)
            apply_uniform_clay_bevel(st, width=0.02, segments=2, jitter=0.0)
            objs.append(st)

    # 4. Corner Warning Beacons & Roller Nodes
    corners = [(-1.32, -1.32), (1.32, -1.32), (-1.32, 1.32), (1.32, 1.32)]
    for cx, cy in corners:
        # Base mount
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.20, location=(cx, cy, 0.14))
        mount = bpy.context.active_object
        mount.data.materials.append(mat_black_stripe)
        apply_uniform_clay_bevel(mount, width=0.03, segments=2, jitter=0.0)
        objs.append(mount)

        # Glowing amber light cap
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.12, location=(cx, cy, 0.26))
        lamp = bpy.context.active_object
        lamp.data.materials.append(mat_beacon)
        apply_uniform_clay_bevel(lamp, width=0.03, segments=2, jitter=0.0)
        objs.append(lamp)

    return objs

def main():
    print(">>> 1. Rendering 3D Sokpop Glacial Ice Tile (tile_ice.png)...")
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting()
    objs_ice = build_ice_tile()
    out_ice = os.path.join(OUTPUT_DIR, "tile_ice.png")
    render_and_clean(objs_ice, out_ice)

    print(">>> 2. Rendering 3D Sokpop Moving Ferry Platform (tile_platform.png)...")
    clear_scene()
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting()
    objs_plat = build_moving_platform_tile()
    out_plat = os.path.join(OUTPUT_DIR, "tile_platform.png")
    render_and_clean(objs_plat, out_plat)

    print(">>> ALL ICE & PLATFORM ASSETS RENDERED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
