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
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
os.makedirs(SPRITES_BUILDINGS, exist_ok=True)

# Cube-based "streak"/panel shapes are used for anything that needs to
# visibly point in a direction under this pipeline's top-down ortho camera --
# a cone's axis runs along local Z, so a Z-only rotation never reorients its
# silhouette from directly above (see the eagle-badge fix earlier in this
# project). A cube's rectangular footprint does reorient correctly.


# ============================================================
# 1. SIGNAL JAMMER TOWER -- base/mast body (buildings/signal_jammer_tower.png)
# ============================================================
def build_jammer_tower_base():
    objs = []
    mat_base = create_clay_mat("m_jam_base", (0.18, 0.16, 0.20, 1.0), roughness=0.55)
    mat_mast = create_clay_mat("m_jam_mast", (0.26, 0.22, 0.30, 1.0), roughness=0.45)
    mat_warn = create_clay_mat("m_jam_warn", (0.95, 0.15, 0.30, 1.0), emission=(0.95, 0.15, 0.30, 1.0), emission_str=3.8)
    mat_panel = create_clay_mat("m_jam_panel", (0.55, 0.20, 0.65, 1.0), emission=(0.55, 0.20, 0.65, 1.0), emission_str=1.8)

    # Hexagonal pedestal base
    bpy.ops.mesh.primitive_cylinder_add(radius=0.55, depth=0.22, vertices=8, location=(0, 0, -0.08))
    base = bpy.context.active_object
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.04, segments=2)
    objs.append(base)

    # Vertical mast
    bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=1.15, vertices=12, location=(0, 0, 0.55))
    mast = bpy.context.active_object
    mast.data.materials.append(mat_mast)
    apply_uniform_clay_bevel(mast, width=0.02, segments=2)
    objs.append(mast)

    # Warning light ring midway up the mast
    bpy.ops.mesh.primitive_torus_add(major_radius=0.20, minor_radius=0.035, major_segments=16, minor_segments=6, location=(0, 0, 0.62))
    ring = bpy.context.active_object
    ring.data.materials.append(mat_warn)
    objs.append(ring)

    # Four angled support struts (cube-based so they read correctly from above)
    for ang_deg in [45, 135, 225, 315]:
        ang = math.radians(ang_deg)
        cx, cy = math.cos(ang) * 0.30, math.sin(ang) * 0.30
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.20))
        strut = bpy.context.active_object
        strut.scale = (0.50, 0.08, 0.05)
        strut.rotation_euler = (0, 0, ang)
        strut.data.materials.append(mat_mast)
        apply_uniform_clay_bevel(strut, width=0.015, segments=1)
        objs.append(strut)

    # Purple interference panels around the pedestal
    for ang_deg in [0, 120, 240]:
        ang = math.radians(ang_deg)
        cx, cy = math.cos(ang) * 0.42, math.sin(ang) * 0.42
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.02))
        panel = bpy.context.active_object
        panel.scale = (0.14, 0.28, 0.20)
        panel.rotation_euler = (0, 0, ang)
        panel.data.materials.append(mat_panel)
        apply_uniform_clay_bevel(panel, width=0.02, segments=1)
        objs.append(panel)

    return objs


# ============================================================
# 2. SIGNAL JAMMER DISH -- separate top sprite, rotated at runtime
#    (buildings/signal_jammer_dish.png)
# ============================================================
def build_jammer_dish():
    objs = []
    mat_dish = create_clay_mat("m_jam_dish", (0.60, 0.58, 0.65, 1.0), roughness=0.35)
    mat_core = create_clay_mat("m_jam_core", (0.90, 0.25, 0.85, 1.0), emission=(0.90, 0.25, 0.85, 1.0), emission_str=4.5)
    mat_prong = create_clay_mat("m_jam_prong", (0.80, 0.20, 0.35, 1.0), emission=(0.80, 0.20, 0.35, 1.0), emission_str=2.5)

    # Parabolic dish, face-on so it reads clearly when rotated in 2D
    bpy.ops.mesh.primitive_cylinder_add(radius=0.55, depth=0.10, vertices=20, location=(0, 0, 0))
    dish = bpy.context.active_object
    dish.data.materials.append(mat_dish)
    apply_uniform_clay_bevel(dish, width=0.06, segments=2)
    objs.append(dish)

    # Glowing central emitter core
    bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.16, vertices=14, location=(0, 0, 0.10))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    apply_uniform_clay_bevel(core, width=0.02, segments=1)
    objs.append(core)

    # Three receiver prongs -- cube-based streaks so they carry a visible
    # asymmetric silhouette (needed for the rotation to actually read as
    # motion once spinning at runtime; a fully symmetric dish would look
    # static even while rotating)
    for ang_deg in [90, 210, 330]:
        ang = math.radians(ang_deg)
        cx, cy = math.cos(ang) * 0.42, math.sin(ang) * 0.42
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.06))
        prong = bpy.context.active_object
        prong.scale = (0.34, 0.07, 0.05)
        prong.rotation_euler = (0, 0, ang)
        prong.data.materials.append(mat_prong)
        apply_uniform_clay_bevel(prong, width=0.015, segments=1)
        objs.append(prong)

    return objs


# ============================================================
# 3. FACTORY -- protected escort-objective building (buildings/factory.png)
# ============================================================
def build_factory():
    # Front-facing wall windows don't read under a strict top-down ortho
    # camera -- the roof block sits at a higher Z and occludes anything
    # lower on the wall face from directly above (confirmed by rendering a
    # first pass: the window row was reduced to a barely-visible sliver
    # peeking past the roof edge). Skylights on the roof's TOP face instead,
    # since that's the surface this camera actually sees.
    objs = []
    mat_wall = create_clay_mat("m_fac_wall", (0.68, 0.42, 0.22, 1.0), roughness=0.65)
    mat_trim = create_clay_mat("m_fac_trim", (0.45, 0.28, 0.16, 1.0), roughness=0.55)
    mat_roof = create_clay_mat("m_fac_roof", (0.34, 0.36, 0.40, 1.0), roughness=0.50)
    mat_ridge = create_clay_mat("m_fac_ridge", (0.22, 0.23, 0.26, 1.0), roughness=0.55)
    mat_skylight = create_clay_mat("m_fac_sky", (1.0, 0.80, 0.32, 1.0), emission=(1.0, 0.80, 0.32, 1.0), emission_str=3.2)
    mat_chimney = create_clay_mat("m_fac_chim", (0.55, 0.30, 0.20, 1.0), roughness=0.70)
    mat_chim_glow = create_clay_mat("m_fac_chim_glow", (1.0, 0.45, 0.15, 1.0), emission=(1.0, 0.45, 0.15, 1.0), emission_str=3.5)

    # Main hall body
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.05))
    hall = bpy.context.active_object
    hall.scale = (1.55, 1.15, 0.55)
    hall.data.materials.append(mat_wall)
    apply_uniform_clay_bevel(hall, width=0.06, segments=2)
    objs.append(hall)

    # Corner trim posts (poke out past the roof edge, so they stay visible)
    for cx in [-0.72, 0.72]:
        for cy in [-0.52, 0.52]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, 0.05))
            post = bpy.context.active_object
            post.scale = (0.10, 0.10, 0.58)
            post.data.materials.append(mat_trim)
            objs.append(post)

    # Flat roof deck, full coverage of the hall
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.36))
    roof = bpy.context.active_object
    roof.scale = (1.50, 1.10, 0.10)
    roof.data.materials.append(mat_roof)
    apply_uniform_clay_bevel(roof, width=0.03, segments=2)
    objs.append(roof)

    # Ridge beams across the roof for texture/scale cues
    for ry in [-0.35, 0.35]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, ry, 0.42))
        ridge = bpy.context.active_object
        ridge.scale = (1.40, 0.06, 0.04)
        ridge.data.materials.append(mat_ridge)
        objs.append(ridge)

    # Grid of glowing skylights set INTO the roof top -- kept well inside the
    # roof's own XY footprint (half-extents 0.75 x 0.55) so they don't bleed
    # past its edges the way the first pass did.
    for sx in [0.0, 0.32]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sx, 0.0, 0.42))
        sky = bpy.context.active_object
        sky.scale = (0.16, 0.40, 0.02)
        sky.data.materials.append(mat_skylight)
        objs.append(sky)

    # Twin smokestacks sitting on the roof (within its footprint, not hanging
    # off the front edge) -- a narrower glowing cap sits proud of the wider
    # stack body so both stay visible from directly above instead of the cap
    # fully occluding the stack underneath it.
    for cx, cy in [(-0.58, -0.32), (-0.58, 0.32)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.55, vertices=12, location=(cx, cy, 0.58))
        stack = bpy.context.active_object
        stack.data.materials.append(mat_chimney)
        apply_uniform_clay_bevel(stack, width=0.02, segments=2)
        objs.append(stack)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.10, vertices=10, location=(cx, cy, 0.88))
        glow_cap = bpy.context.active_object
        glow_cap.data.materials.append(mat_chim_glow)
        objs.append(glow_cap)

    return objs


def main():
    print("==================================================")
    print(" Executing Jammer Tower & Factory Asset Pipeline... ")
    print("==================================================")

    reset_jitter_seed(0)

    clear_scene()
    setup_render_settings(256, 256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_jammer_tower_base()
    render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, "signal_jammer_tower.png"))
    print("[OK] Signal Jammer Tower base rendered.")

    clear_scene()
    setup_render_settings(256, 256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_jammer_dish()
    render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, "signal_jammer_dish.png"))
    print("[OK] Signal Jammer Dish rendered.")

    clear_scene()
    setup_render_settings(256, 256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    objs = build_factory()
    render_and_clean(objs, os.path.join(SPRITES_BUILDINGS, "factory.png"))
    print("[OK] Factory rendered.")


if __name__ == '__main__':
    main()
