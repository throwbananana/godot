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
    reset_jitter_seed,
    ORTHO_SCALE_TANK,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
os.makedirs(SPRITES_TANKS, exist_ok=True)

# WARP PHANTOM TANK (enemy_warp_f0..f5.png) -- Act 3 signature enemy.
# Palette pulls from tile_wormhole.png's cyan-core/indigo-swirl look (sampled
# ~ (0.27, 0.62, 0.95) outer blue, (0.61, 1.0, 1.0) cyan core) so the tank
# visually reads as "the thing that made the map look like this," instead of
# reusing an existing archetype's palette. Ring cannon (torus) stands in for
# a barrel -- a wormhole shape up front rather than a gun, since its combat
# gimmick is a self-teleport blink (enemy.gd::_warp_blink), not a special
# projectile.
def build_warp_tank(frame=0):
    objs = []
    mat_hull = create_clay_mat("m_wrp_hull", (0.22, 0.16, 0.34, 1.0), roughness=0.50)
    mat_tread = create_clay_mat("m_wrp_trd", (0.14, 0.13, 0.18, 1.0), roughness=0.72)
    mat_core = create_clay_mat("m_wrp_core", (0.40, 0.85, 1.0, 1.0), emission=(0.40, 0.85, 1.0, 1.0), emission_str=4.2)
    mat_ring = create_clay_mat("m_wrp_ring", (0.62, 1.0, 1.0, 1.0), emission=(0.62, 1.0, 1.0, 1.0), emission_str=4.5)
    mat_trim = create_clay_mat("m_wrp_trim", (0.38, 0.30, 0.55, 1.0), roughness=0.40)

    # 1. Dual Track Chassis
    tread_phase = (frame / 6.0) * math.pi
    for tx in [-0.80, 0.80]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx, 0, -0.15))
        tread = bpy.context.active_object
        tread.scale = (0.42, 1.60, 0.45)
        tread.data.materials.append(mat_tread)
        apply_uniform_clay_bevel(tread, width=0.05, segments=2)
        objs.append(tread)

        for wy in [-0.48, 0.0, 0.48]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.44, vertices=16, location=(tx, wy, -0.15))
            wheel = bpy.context.active_object
            wheel.rotation_euler = (0, math.radians(90), tread_phase)
            wheel.data.materials.append(mat_tread)
            objs.append(wheel)

    # 2. Angular Void Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.08))
    hull = bpy.context.active_object
    hull.scale = (1.15, 1.30, 0.42)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.09, segments=2)
    objs.append(hull)

    # Trim edge along the hull's spine
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.32))
    spine = bpy.context.active_object
    spine.scale = (0.30, 1.10, 0.06)
    spine.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(spine, width=0.02, segments=1)
    objs.append(spine)

    # Floating energy shard clusters on the rear hull (glacial + warp motif)
    for sx, sy, sr in [(-0.55, -0.55, 0.16), (0.55, -0.55, 0.16), (0.0, -0.68, 0.13)]:
        bpy.ops.mesh.primitive_cone_add(radius1=sr, radius2=0.0, depth=0.42, vertices=6, location=(sx, sy, 0.30))
        shard = bpy.context.active_object
        shard.rotation_euler = (math.radians(20 * (1 if sx >= 0 else -1)), 0, 0)
        shard.data.materials.append(mat_core)
        objs.append(shard)

    # 3. Turret Ring Housing
    bpy.ops.mesh.primitive_cylinder_add(radius=0.46, depth=0.30, vertices=8, location=(0, -0.05, 0.38))
    turret = bpy.context.active_object
    turret.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(turret, width=0.04, segments=2)
    objs.append(turret)

    # 4. Wormhole Ring "Cannon" -- a torus facing forward instead of a barrel
    bpy.ops.mesh.primitive_torus_add(major_radius=0.26, minor_radius=0.08,
                                      major_segments=16, minor_segments=8,
                                      location=(0, 0.85, 0.38))
    ring = bpy.context.active_object
    ring.rotation_euler = (math.radians(90), 0, 0)
    ring.data.materials.append(mat_ring)
    objs.append(ring)

    # Inner core glow nested inside the ring
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(0, 0.85, 0.38))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    objs.append(core)

    # Support strut connecting ring to turret
    bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=0.55, vertices=10, location=(0, 0.55, 0.38))
    strut = bpy.context.active_object
    strut.rotation_euler = (math.radians(90), 0, 0)
    strut.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(strut, width=0.02, segments=1)
    objs.append(strut)

    return objs


def main():
    print("==================================================")
    print(" Executing Warp Phantom Tank Asset Pipeline...    ")
    print("==================================================")

    reset_jitter_seed(0)

    for f in range(6):
        clear_scene()
        setup_render_settings(256, 256, samples=28)
        create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
        objs = build_warp_tank(frame=f)
        out_p = os.path.join(SPRITES_TANKS, f"enemy_warp_f{f}.png")
        render_and_clean(objs, out_p)
        print(f"[OK] Warp Phantom Tank Frame {f} Rendered.")


if __name__ == '__main__':
    main()
