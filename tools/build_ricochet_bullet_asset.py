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
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
os.makedirs(SPRITES_EFFECTS, exist_ok=True)

# Ricochet Rounds projectile (bullet.gd loads this whenever bounces_remaining
# > 0). Same oval-shell silhouette as the base bullet.png/bullet_plasma.png
# (build_all_sokpop_assets_unified.py::build_sokpop_bullet) so it still
# reads as "a bullet" at a glance, but in a jolting electric yellow-green
# instead of plasma's cyan or the base shell's orange, so players can tell
# at a glance which of their shots can bounce (and hit them back).
def build_ricochet_bullet():
    objs = []
    mat_shell = create_clay_mat("m_ricb_s", (0.80, 0.95, 0.20, 1.0), emission=(0.80, 0.95, 0.20, 1.0), emission_str=2.6)
    mat_tip = create_clay_mat("m_ricb_t", (0.95, 0.98, 0.85, 1.0), roughness=0.30)
    mat_base = create_clay_mat("m_ricb_b", (0.30, 0.32, 0.20, 1.0), roughness=0.55)
    mat_band = create_clay_mat("m_ricb_bd", (1.0, 0.55, 0.10, 1.0), emission=(1.0, 0.55, 0.10, 1.0), emission_str=2.2)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.48, location=(0, 0, 0))
    body = bpy.context.active_object
    body.scale = (1.0, 0.78, 1.0)
    body.data.materials.append(mat_shell)
    bpy.ops.object.shade_smooth()
    objs.append(body)

    bpy.ops.mesh.primitive_cone_add(radius1=0.32, depth=0.52, location=(0, 0.46, 0))
    tip = bpy.context.active_object
    tip.rotation_euler = (math.radians(90), 0, 0)
    tip.scale = (1.0, 1.0, 0.85)
    tip.data.materials.append(mat_tip)
    apply_uniform_clay_bevel(tip, width=0.04, segments=2)
    objs.append(tip)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.38, depth=0.16, vertices=14, location=(0, -0.45, 0))
    base_cap = bpy.context.active_object
    base_cap.rotation_euler = (math.radians(90), 0, 0)
    base_cap.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base_cap, width=0.04, segments=2)
    objs.append(base_cap)

    # Driving band ring at the equator, in a contrasting warning-orange
    bpy.ops.mesh.primitive_torus_add(major_radius=0.50, minor_radius=0.06, location=(0, 0, 0))
    band = bpy.context.active_object
    band.rotation_euler = (math.radians(90), 0, 0)
    band.data.materials.append(mat_band)
    objs.append(band)

    return objs


def main():
    print("==================================================")
    print(" Executing Ricochet Bullet Asset Pipeline...      ")
    print("==================================================")

    reset_jitter_seed(0)
    clear_scene()
    setup_render_settings(256, 256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_ricochet_bullet()
    render_and_clean(objs, os.path.join(SPRITES_EFFECTS, "bullet_ricochet.png"))
    print("[OK] Ricochet Bullet Rendered.")


if __name__ == '__main__':
    main()
