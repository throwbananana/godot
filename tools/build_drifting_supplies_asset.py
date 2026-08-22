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
    ORTHO_SCALE_DEFAULT,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
os.makedirs(SPRITES_POWERUPS, exist_ok=True)

# Drifting Supplies (漂流物资): a wooden crate lashed to a life-ring buoy so
# it silhouettes as "floating on water" even sitting on this project's plain
# transparent render background -- the crate alone wouldn't read as
# waterborne without something buoy-shaped under/around it.
def build_drifting_supplies():
    objs = []
    mat_crate = create_clay_mat("m_drift_crate", (0.62, 0.42, 0.24, 1.0), roughness=0.68)
    mat_band = create_clay_mat("m_drift_band", (0.30, 0.20, 0.12, 1.0), roughness=0.55)
    mat_buoy = create_clay_mat("m_drift_buoy", (0.92, 0.30, 0.20, 1.0), roughness=0.40)
    mat_buoy_band = create_clay_mat("m_drift_buoy_band", (0.95, 0.95, 0.92, 1.0), roughness=0.35)
    mat_beacon = create_clay_mat("m_drift_beacon", (1.0, 0.75, 0.20, 1.0), emission=(1.0, 0.75, 0.20, 1.0), emission_str=3.5)

    # Life-ring buoy underneath, wide enough to peek out on all sides
    bpy.ops.mesh.primitive_torus_add(major_radius=0.62, minor_radius=0.16, major_segments=20, minor_segments=10, location=(0, 0, -0.12))
    buoy = bpy.context.active_object
    buoy.data.materials.append(mat_buoy)
    objs.append(buoy)

    # White cross-bands on the buoy (four short segments so the torus doesn't
    # need per-face material assignment)
    for ang_deg in [0, 90, 180, 270]:
        ang = math.radians(ang_deg)
        cx, cy = math.cos(ang) * 0.62, math.sin(ang) * 0.62
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, -0.12))
        band = bpy.context.active_object
        band.scale = (0.20, 0.20, 0.14)
        band.rotation_euler = (0, 0, ang)
        band.data.materials.append(mat_buoy_band)
        objs.append(band)

    # Main crate body
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
    crate = bpy.context.active_object
    crate.scale = (0.72, 0.72, 0.55)
    crate.data.materials.append(mat_crate)
    apply_uniform_clay_bevel(crate, width=0.05, segments=2)
    objs.append(crate)

    # Corner reinforcement bands (cube-based so they read correctly from
    # directly above -- this pipeline's top-down ortho camera can't tell a
    # cone/cylinder's rotation apart, but a rectangular strap silhouette
    # still reorients visibly)
    for ang_deg in [45, 135]:
        ang = math.radians(ang_deg)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
        strap = bpy.context.active_object
        strap.scale = (0.78, 0.10, 0.60)
        strap.rotation_euler = (0, 0, ang)
        strap.data.materials.append(mat_band)
        objs.append(strap)

    # Blinking recovery beacon on top so it reads at a glance on a busy water tile
    bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.14, vertices=10, location=(0, 0, 0.46))
    beacon = bpy.context.active_object
    beacon.data.materials.append(mat_beacon)
    apply_uniform_clay_bevel(beacon, width=0.015, segments=1)
    objs.append(beacon)

    return objs


def main():
    print("==================================================")
    print(" Executing Drifting Supplies Asset Pipeline...    ")
    print("==================================================")

    reset_jitter_seed(0)
    clear_scene()
    setup_render_settings(256, 256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_drifting_supplies()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "drifting_supplies.png"))
    print("[OK] Drifting Supplies rendered.")


if __name__ == '__main__':
    main()
