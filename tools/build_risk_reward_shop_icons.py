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
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
os.makedirs(SPRITES_POWERUPS, exist_ok=True)
os.makedirs(SPRITES_EFFECTS, exist_ok=True)

# Three high-risk/high-reward shop item icons (shop_dialog.gd). Cube-based
# "streak"/wall shapes are used instead of cones for the direction-carrying
# elements -- a cone's axis runs along local Z, so under this pipeline's
# top-down ortho camera a Z-only rotation never changes its silhouette (see
# the eagle-badge fix earlier this project: rotating a cone about its own
# axis just spins its base circle in place). A cube's rectangular footprint
# actually reorients under a Z rotation, so it's the safe choice for anything
# that needs to visibly "point" in a particular direction from directly above.


# 1. RICOCHET ROUNDS (反射炮弹) -- ui/badge_ricochet_rounds.png
def build_icon_ricochet():
    objs = []
    mat_base = create_clay_mat("m_ric_base", (0.30, 0.10, 0.10, 1.0), roughness=0.55)
    mat_bullet = create_clay_mat("m_ric_bullet", (1.0, 0.85, 0.25, 1.0), emission=(1.0, 0.85, 0.25, 1.0), emission_str=3.5)
    mat_streak = create_clay_mat("m_ric_streak", (0.95, 0.30, 0.15, 1.0), emission=(0.95, 0.30, 0.15, 1.0), emission_str=2.2)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.85, depth=0.18, vertices=24, location=(0, 0, -0.05))
    base = bpy.context.active_object
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.05, segments=2)
    objs.append(base)

    # Central glowing bullet capsule
    bpy.ops.mesh.primitive_cylinder_add(radius=0.15, depth=0.42, vertices=12, location=(0, 0, 0.14))
    bulb = bpy.context.active_object
    bulb.data.materials.append(mat_bullet)
    apply_uniform_clay_bevel(bulb, width=0.05, segments=2)
    objs.append(bulb)

    # Deflection streaks radiating outward at three angles (not evenly
    # spaced, so it reads as "bounced off in random directions" rather than
    # a tidy symmetric icon)
    for ang_deg in [55, 190, 300]:
        ang = math.radians(ang_deg)
        cx, cy = math.cos(ang) * 0.52, math.sin(ang) * 0.52
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.10))
        streak = bpy.context.active_object
        streak.scale = (0.30, 0.09, 0.06)
        streak.rotation_euler = (0, 0, ang)
        streak.data.materials.append(mat_streak)
        apply_uniform_clay_bevel(streak, width=0.015, segments=1)
        objs.append(streak)

    return objs


# 2. AMPHIBIOUS HULL (两栖化改造) -- ui/badge_amphibious_hull.png
def build_icon_amphibious():
    objs = []
    mat_water = create_clay_mat("m_amp_water", (0.18, 0.52, 0.82, 1.0), roughness=0.35)
    mat_water_hi = create_clay_mat("m_amp_water_hi", (0.45, 0.88, 1.0, 1.0), emission=(0.45, 0.88, 1.0, 1.0), emission_str=1.6, roughness=0.30)
    mat_hull = create_clay_mat("m_amp_hull", (0.34, 0.44, 0.27, 1.0), roughness=0.55)
    mat_trim = create_clay_mat("m_amp_trim", (0.55, 0.64, 0.40, 1.0), roughness=0.45)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.85, depth=0.16, vertices=24, location=(0, 0, -0.10))
    base = bpy.context.active_object
    base.data.materials.append(mat_water)
    apply_uniform_clay_bevel(base, width=0.05, segments=2)
    objs.append(base)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.55, minor_radius=0.045, major_segments=20, minor_segments=6, location=(0, 0, -0.01))
    wave = bpy.context.active_object
    wave.data.materials.append(mat_water_hi)
    objs.append(wave)

    # Hull sits low/half-submerged
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.08))
    hull = bpy.context.active_object
    hull.scale = (0.85, 1.05, 0.32)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.06, segments=2)
    objs.append(hull)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.30, depth=0.20, vertices=10, location=(0, -0.05, 0.28))
    turret = bpy.context.active_object
    turret.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(turret, width=0.03, segments=2)
    objs.append(turret)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=0.45, vertices=8, location=(0, 0.28, 0.28))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.radians(90), 0, 0)
    barrel.data.materials.append(mat_trim)
    objs.append(barrel)

    return objs


# 3. ARMOR-PIERCING ROUNDS (穿甲弹) -- ui/badge_armor_piercing.png
def build_icon_armor_piercing():
    objs = []
    mat_wall = create_clay_mat("m_ap_wall", (0.42, 0.40, 0.44, 1.0), roughness=0.75)
    mat_hole = create_clay_mat("m_ap_hole", (0.16, 0.15, 0.17, 1.0), roughness=0.85)
    mat_dart = create_clay_mat("m_ap_dart", (0.95, 0.55, 0.15, 1.0), emission=(0.95, 0.55, 0.15, 1.0), emission_str=3.0)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.05, 0, 0.0))
    wall = bpy.context.active_object
    wall.scale = (1.35, 0.55, 0.45)
    wall.data.materials.append(mat_wall)
    apply_uniform_clay_bevel(wall, width=0.05, segments=2)
    objs.append(wall)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.50, vertices=12, location=(-0.05, 0, 0.05))
    hole = bpy.context.active_object
    hole.rotation_euler = (math.radians(90), 0, 0)
    hole.data.materials.append(mat_hole)
    objs.append(hole)

    # Long shaft passing all the way through the wall on both sides
    bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.95, vertices=10, location=(-0.05, 0, 0.05))
    shaft = bpy.context.active_object
    shaft.rotation_euler = (math.radians(90), 0, 0)
    shaft.data.materials.append(mat_dart)
    apply_uniform_clay_bevel(shaft, width=0.02, segments=1)
    objs.append(shaft)

    # Pointed tip poking out past the far edge
    bpy.ops.mesh.primitive_cone_add(radius1=0.11, radius2=0.0, depth=0.22, vertices=10, location=(-0.05, 0.55, 0.05))
    tip = bpy.context.active_object
    tip.rotation_euler = (math.radians(90), 0, 0)
    tip.data.materials.append(mat_dart)
    objs.append(tip)

    return objs


def main():
    print("==================================================")
    print(" Executing Risk/Reward Shop Icon Pipeline...      ")
    print("==================================================")

    reset_jitter_seed(0)

    clear_scene()
    setup_render_settings(128, 128, samples=24)
    create_sokpop_lighting(ortho_scale=2.00)
    objs = build_icon_ricochet()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "ricochet_rounds.png"))
    print("[OK] Ricochet Rounds icon rendered.")

    clear_scene()
    setup_render_settings(128, 128, samples=24)
    create_sokpop_lighting(ortho_scale=2.00)
    objs = build_icon_amphibious()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "amphibious_hull.png"))
    print("[OK] Amphibious Hull icon rendered.")

    clear_scene()
    setup_render_settings(128, 128, samples=24)
    create_sokpop_lighting(ortho_scale=2.00)
    objs = build_icon_armor_piercing()
    render_and_clean(objs, os.path.join(SPRITES_POWERUPS, "armor_piercing_rounds.png"))
    print("[OK] Armor-Piercing Rounds icon rendered.")


if __name__ == '__main__':
    main()
