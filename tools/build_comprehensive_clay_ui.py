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
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")
os.makedirs(SPRITES_UI, exist_ok=True)

# ==============================================================================
# 1. TITLE SCREEN & NAVIGATION ICONS
# ==============================================================================

def build_title_crest():
    """Golden crossed-cannons and shield crest for the main title."""
    objs = []
    mat_shield = create_clay_mat("m_tc_shd", (0.22, 0.20, 0.28, 1.0), roughness=0.45)
    mat_gold = create_clay_mat("m_tc_gld", (1.0, 0.82, 0.22, 1.0), roughness=0.35)
    mat_barrel = create_clay_mat("m_tc_brl", (0.55, 0.58, 0.65, 1.0), roughness=0.40)
    mat_ruby = create_clay_mat("m_tc_rby", (0.95, 0.20, 0.25, 1.0), emission=(0.95, 0.20, 0.25, 1.0), emission_str=3.0)

    # Crossed Cannon Barrels
    for angle in [-35.0, 35.0]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=2.8, vertices=16, location=(0, 0, -0.05))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (0, 0, math.radians(angle))
        barrel.data.materials.append(mat_barrel)
        apply_uniform_clay_bevel(barrel, width=0.03, segments=2)
        objs.append(barrel)

        # Muzzle Rings
        for dist in [-1.3, 1.3]:
            pos_x = dist * math.sin(math.radians(-angle))
            pos_y = dist * math.cos(math.radians(-angle))
            bpy.ops.mesh.primitive_cylinder_add(radius=0.19, depth=0.18, vertices=16, location=(pos_x, pos_y, -0.04))
            ring = bpy.context.active_object
            ring.rotation_euler = (0, 0, math.radians(angle))
            ring.data.materials.append(mat_gold)
            apply_uniform_clay_bevel(ring, width=0.02, segments=2)
            objs.append(ring)

    # Central Shield
    bpy.ops.mesh.primitive_cylinder_add(radius=1.1, depth=0.25, vertices=6, location=(0, 0, 0.1))
    shield = bpy.context.active_object
    shield.data.materials.append(mat_shield)
    apply_uniform_clay_bevel(shield, width=0.06, segments=2)
    objs.append(shield)

    # Golden Eagle / Star Emblem in Shield Center
    bpy.ops.mesh.primitive_cylinder_add(radius=0.85, depth=0.28, vertices=6, location=(0, 0, 0.15))
    inner = bpy.context.active_object
    inner.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(inner, width=0.05, segments=2)
    objs.append(inner)

    # Central Ruby Core
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.26, location=(0, 0, 0.28))
    ruby = bpy.context.active_object
    ruby.scale = (1.0, 1.0, 0.6)
    ruby.data.materials.append(mat_ruby)
    objs.append(ruby)

    # Flanking Stars
    for sx in [-0.5, 0.5]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.20, vertices=5, location=(sx, -0.4, 0.26))
        star = bpy.context.active_object
        star.rotation_euler = (0, 0, math.radians(18))
        star.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(star, width=0.02, segments=1)
        objs.append(star)

    return objs

def build_mode_icon_1p():
    """1P Single Player Tank Badge Icon."""
    objs = []
    mat_plate = create_clay_mat("m_m1_plt", (0.20, 0.18, 0.24, 1.0), roughness=0.50)
    mat_gold = create_clay_mat("m_m1_gld", (0.98, 0.82, 0.22, 1.0), roughness=0.35)
    mat_tank = create_clay_mat("m_m1_tnk", (0.95, 0.75, 0.18, 1.0), roughness=0.45)
    mat_track = create_clay_mat("m_m1_trk", (0.28, 0.26, 0.30, 1.0), roughness=0.60)

    # Octagonal backing plate
    bpy.ops.mesh.primitive_cylinder_add(radius=0.90, depth=0.20, vertices=8, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.76, depth=0.22, vertices=8, location=(0, 0, 0.03))
    trim = bpy.context.active_object
    trim.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(trim, width=0.04, segments=2)
    objs.append(trim)

    # Mini Yellow Tank
    # Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.05, 0.18))
    hull = bpy.context.active_object
    hull.scale = (0.55, 0.65, 0.22)
    hull.data.materials.append(mat_tank)
    apply_uniform_clay_bevel(hull, width=0.04, segments=2)
    objs.append(hull)

    # Treads
    for tx in [-0.34, 0.34]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx, -0.05, 0.16))
        tr = bpy.context.active_object
        tr.scale = (0.16, 0.72, 0.20)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.02, segments=1)
        objs.append(tr)

    # Turret & Gun
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.20, vertices=16, location=(0, -0.08, 0.30))
    turret = bpy.context.active_object
    turret.data.materials.append(mat_tank)
    apply_uniform_clay_bevel(turret, width=0.03, segments=2)
    objs.append(turret)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.45, vertices=12, location=(0, 0.22, 0.30))
    gun = bpy.context.active_object
    gun.rotation_euler = (math.radians(90), 0, 0)
    gun.data.materials.append(mat_tank)
    apply_uniform_clay_bevel(gun, width=0.015, segments=1)
    objs.append(gun)

    return objs

def build_mode_icon_2p():
    """2P Twin Tanks Co-op Badge Icon."""
    objs = []
    mat_plate = create_clay_mat("m_m2_plt", (0.18, 0.22, 0.26, 1.0), roughness=0.50)
    mat_trim = create_clay_mat("m_m2_trm", (0.45, 0.85, 0.60, 1.0), roughness=0.35)
    mat_tank1 = create_clay_mat("m_m2_tnk1", (0.98, 0.80, 0.20, 1.0), roughness=0.45)
    mat_tank2 = create_clay_mat("m_m2_tnk2", (0.35, 0.85, 0.45, 1.0), roughness=0.45)
    mat_track = create_clay_mat("m_m2_trk", (0.25, 0.25, 0.28, 1.0), roughness=0.60)

    # Hexagonal backing plate
    bpy.ops.mesh.primitive_cylinder_add(radius=0.90, depth=0.20, vertices=6, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.76, depth=0.22, vertices=6, location=(0, 0, 0.03))
    trim = bpy.context.active_object
    trim.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(trim, width=0.04, segments=2)
    objs.append(trim)

    # Two side-by-side miniature tanks
    tanks = [(-0.25, mat_tank1), (0.25, mat_tank2)]
    for x_off, mat in tanks:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_off, -0.05, 0.18))
        hull = bpy.context.active_object
        hull.scale = (0.36, 0.50, 0.18)
        hull.data.materials.append(mat)
        apply_uniform_clay_bevel(hull, width=0.03, segments=2)
        objs.append(hull)

        for tx in [-0.22, 0.22]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_off + tx, -0.05, 0.16))
            tr = bpy.context.active_object
            tr.scale = (0.10, 0.54, 0.16)
            tr.data.materials.append(mat_track)
            apply_uniform_clay_bevel(tr, width=0.015, segments=1)
            objs.append(tr)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=0.16, vertices=12, location=(x_off, -0.06, 0.27))
        turret = bpy.context.active_object
        turret.data.materials.append(mat)
        apply_uniform_clay_bevel(turret, width=0.02, segments=1)
        objs.append(turret)

        bpy.ops.mesh.primitive_cylinder_add(radius=0.045, depth=0.34, vertices=10, location=(x_off, 0.16, 0.27))
        gun = bpy.context.active_object
        gun.rotation_euler = (math.radians(90), 0, 0)
        gun.data.materials.append(mat)
        apply_uniform_clay_bevel(gun, width=0.01, segments=1)
        objs.append(gun)

    return objs

def build_mode_icon_arcade():
    """Arcade Lightning & Shield Badge Icon."""
    objs = []
    mat_plate = create_clay_mat("m_ma_plt", (0.28, 0.16, 0.26, 1.0), roughness=0.50)
    mat_gold = create_clay_mat("m_ma_gld", (1.0, 0.85, 0.25, 1.0), roughness=0.35)
    mat_bolt = create_clay_mat("m_ma_blt", (0.35, 0.88, 1.0, 1.0), emission=(0.35, 0.88, 1.0, 1.0), emission_str=4.0)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.90, depth=0.20, vertices=12, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.76, depth=0.22, vertices=12, location=(0, 0, 0.03))
    trim = bpy.context.active_object
    trim.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(trim, width=0.04, segments=2)
    objs.append(trim)

    # Lightning Bolt zig-zag
    for seg, rot, loc in [
        ((0.20, 0.65, 0.16), -25, (0.08, 0.25, 0.22)),
        ((0.20, 0.55, 0.16), 35, (-0.08, -0.05, 0.22)),
        ((0.16, 0.50, 0.16), -20, (0.02, -0.32, 0.22))
    ]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        b = bpy.context.active_object
        b.rotation_euler = (0, 0, math.radians(rot))
        b.scale = seg
        b.data.materials.append(mat_bolt)
        apply_uniform_clay_bevel(b, width=0.02, segments=1)
        objs.append(b)

    return objs

def build_mode_icon_continue():
    """Continue / Bookmark Play Badge Icon."""
    objs = []
    mat_plate = create_clay_mat("m_mc_plt", (0.16, 0.24, 0.22, 1.0), roughness=0.50)
    mat_gold = create_clay_mat("m_mc_gld", (0.95, 0.85, 0.30, 1.0), roughness=0.35)
    mat_play = create_clay_mat("m_mc_ply", (0.30, 0.95, 0.50, 1.0), emission=(0.30, 0.95, 0.50, 1.0), emission_str=2.5)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.90, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.76, depth=0.22, vertices=24, location=(0, 0, 0.03))
    trim = bpy.context.active_object
    trim.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(trim, width=0.04, segments=2)
    objs.append(trim)

    # Play Triangle
    bpy.ops.mesh.primitive_cylinder_add(radius=0.45, depth=0.18, vertices=3, location=(0.04, 0, 0.22))
    tri = bpy.context.active_object
    tri.rotation_euler = (0, 0, math.radians(-90))
    tri.data.materials.append(mat_play)
    apply_uniform_clay_bevel(tri, width=0.04, segments=2)
    objs.append(tri)

    return objs

def build_mode_icon_exit():
    """Exit / Quit Door Portal Badge Icon."""
    objs = []
    mat_plate = create_clay_mat("m_me_plt", (0.26, 0.16, 0.16, 1.0), roughness=0.50)
    mat_rim = create_clay_mat("m_me_rim", (0.90, 0.40, 0.35, 1.0), roughness=0.40)
    mat_door = create_clay_mat("m_me_dr", (0.98, 0.30, 0.30, 1.0), emission=(0.98, 0.30, 0.30, 1.0), emission_str=2.5)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.90, depth=0.20, vertices=8, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.76, depth=0.22, vertices=8, location=(0, 0, 0.03))
    trim = bpy.context.active_object
    trim.data.materials.append(mat_rim)
    apply_uniform_clay_bevel(trim, width=0.04, segments=2)
    objs.append(trim)

    # Exit Arrow & Portal
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-0.15, 0, 0.20))
    dr = bpy.context.active_object
    dr.scale = (0.16, 0.60, 0.15)
    dr.data.materials.append(mat_door)
    apply_uniform_clay_bevel(dr, width=0.02, segments=1)
    objs.append(dr)

    # Arrow Head
    bpy.ops.mesh.primitive_cylinder_add(radius=0.30, depth=0.16, vertices=3, location=(0.20, 0, 0.20))
    ah = bpy.context.active_object
    ah.rotation_euler = (0, 0, math.radians(-90))
    ah.data.materials.append(mat_door)
    apply_uniform_clay_bevel(ah, width=0.03, segments=1)
    objs.append(ah)

    return objs

# ==============================================================================
# 2. PERK / UPGRADE ICONS & SELECTION CARDS
# ==============================================================================

def build_perk_icon(theme_type="atk"):
    """Vibrant 3D clay badge for RPG upgrade cards."""
    objs = []
    
    palettes = {
        "atk": ((0.95, 0.25, 0.20, 1.0), (0.28, 0.12, 0.12, 1.0)),
        "speed": ((0.30, 0.85, 0.98, 1.0), (0.12, 0.20, 0.28, 1.0)),
        "armor": ((0.95, 0.78, 0.20, 1.0), (0.22, 0.20, 0.14, 1.0)),
        "laser": ((0.35, 0.95, 0.75, 1.0), (0.10, 0.24, 0.18, 1.0)),
        "missile": ((0.98, 0.45, 0.15, 1.0), (0.28, 0.15, 0.10, 1.0)),
        "train": ((0.65, 0.45, 0.85, 1.0), (0.20, 0.14, 0.26, 1.0)),
        "shield": ((0.40, 0.70, 0.98, 1.0), (0.12, 0.18, 0.28, 1.0)),
        "regen": ((0.30, 0.95, 0.45, 1.0), (0.12, 0.26, 0.14, 1.0)),
        "ricochet": ((0.98, 0.85, 0.20, 1.0), (0.28, 0.22, 0.10, 1.0)),
        "bomb": ((0.95, 0.25, 0.35, 1.0), (0.26, 0.12, 0.14, 1.0)),
        "gold": ((1.0, 0.82, 0.18, 1.0), (0.28, 0.22, 0.10, 1.0)),
        "tactical": ((0.90, 0.65, 0.95, 1.0), (0.24, 0.16, 0.26, 1.0)),
    }
    
    fg_col, bg_col = palettes.get(theme_type, ((0.95, 0.85, 0.30, 1.0), (0.20, 0.18, 0.24, 1.0)))

    mat_bg = create_clay_mat(f"m_pk_{theme_type}_bg", bg_col, roughness=0.55)
    mat_rim = create_clay_mat(f"m_pk_{theme_type}_rim", fg_col, roughness=0.35)
    mat_core = create_clay_mat(f"m_pk_{theme_type}_cor", fg_col, emission=fg_col, emission_str=3.0)

    # Base Disc
    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=24, location=(0, 0, 0))
    base = bpy.context.active_object
    base.data.materials.append(mat_bg)
    apply_uniform_clay_bevel(base, width=0.05, segments=2)
    objs.append(base)

    # Beveled Rim
    bpy.ops.mesh.primitive_cylinder_add(radius=0.74, depth=0.24, vertices=24, location=(0, 0, 0.03))
    rim = bpy.context.active_object
    rim.data.materials.append(mat_rim)
    apply_uniform_clay_bevel(rim, width=0.04, segments=2)
    objs.append(rim)

    # Center Symbol per Type
    if theme_type in ["atk", "ricochet"]:
        for ang in [-30, 30]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.85, vertices=12, location=(0, 0, 0.20))
            blt = bpy.context.active_object
            blt.rotation_euler = (0, 0, math.radians(ang))
            blt.data.materials.append(mat_core)
            apply_uniform_clay_bevel(blt, width=0.02, segments=1)
            objs.append(blt)
    elif theme_type in ["speed", "laser"]:
        for i, y_pos in enumerate([0.15, -0.15]):
            bpy.ops.mesh.primitive_cylinder_add(radius=0.38 - i*0.06, depth=0.18, vertices=3, location=(0, y_pos, 0.20))
            arr = bpy.context.active_object
            arr.rotation_euler = (0, 0, 0)
            arr.data.materials.append(mat_core)
            apply_uniform_clay_bevel(arr, width=0.03, segments=1)
            objs.append(arr)
    elif theme_type in ["armor", "shield"]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.45, depth=0.20, vertices=6, location=(0, 0, 0.20))
        shd = bpy.context.active_object
        shd.data.materials.append(mat_core)
        apply_uniform_clay_bevel(shd, width=0.04, segments=2)
        objs.append(shd)
    elif theme_type in ["missile", "bomb"]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.32, location=(0, 0, 0.22))
        sph = bpy.context.active_object
        sph.data.materials.append(mat_core)
        objs.append(sph)
    elif theme_type == "regen":
        for scale in [(0.55, 0.18, 0.20), (0.18, 0.55, 0.20)]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.20))
            cross = bpy.context.active_object
            cross.scale = scale
            cross.data.materials.append(mat_core)
            apply_uniform_clay_bevel(cross, width=0.02, segments=1)
            objs.append(cross)
    elif theme_type in ["train", "gold", "tactical"]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.44, depth=0.20, vertices=5, location=(0, 0, 0.20))
        star = bpy.context.active_object
        star.rotation_euler = (0, 0, math.radians(18))
        star.data.materials.append(mat_core)
        apply_uniform_clay_bevel(star, width=0.03, segments=2)
        objs.append(star)

    return objs

def build_threat_star():
    """3D Golden Threat Star Rating Badge."""
    objs = []
    mat_gold = create_clay_mat("m_th_star", (1.0, 0.85, 0.22, 1.0), emission=(1.0, 0.85, 0.22, 1.0), emission_str=2.8)
    mat_rim = create_clay_mat("m_th_rim", (0.80, 0.60, 0.15, 1.0), roughness=0.35)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.90, depth=0.25, vertices=5, location=(0, 0, 0))
    star = bpy.context.active_object
    star.rotation_euler = (0, 0, math.radians(18))
    star.data.materials.append(mat_rim)
    apply_uniform_clay_bevel(star, width=0.04, segments=2)
    objs.append(star)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.72, depth=0.30, vertices=5, location=(0, 0, 0.04))
    inner = bpy.context.active_object
    inner.rotation_euler = (0, 0, math.radians(18))
    inner.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(inner, width=0.03, segments=2)
    objs.append(inner)

    return objs

def build_threat_skull():
    """Crimson Skull & Danger Marker for Elite/Boss."""
    objs = []
    mat_plate = create_clay_mat("m_sk_plt", (0.35, 0.12, 0.15, 1.0), roughness=0.45)
    mat_skull = create_clay_mat("m_sk_skl", (0.95, 0.92, 0.90, 1.0), roughness=0.55)
    mat_eyes = create_clay_mat("m_sk_eye", (0.95, 0.20, 0.25, 1.0), emission=(0.95, 0.20, 0.25, 1.0), emission_str=4.0)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=6, location=(0, 0, 0))
    base = bpy.context.active_object
    base.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(base, width=0.05, segments=2)
    objs.append(base)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.42, location=(0, 0.10, 0.16))
    cran = bpy.context.active_object
    cran.scale = (1.0, 0.9, 0.6)
    cran.data.materials.append(mat_skull)
    objs.append(cran)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.25, 0.16))
    jaw = bpy.context.active_object
    jaw.scale = (0.42, 0.28, 0.22)
    jaw.data.materials.append(mat_skull)
    apply_uniform_clay_bevel(jaw, width=0.03, segments=1)
    objs.append(jaw)

    for ex in [-0.18, 0.18]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.11, location=(ex, 0.08, 0.26))
        eye = bpy.context.active_object
        eye.data.materials.append(mat_eyes)
        objs.append(eye)

    return objs

# ==============================================================================
# 3. BATTLE HUD ICONS & VICTORY/DEFEAT BANNERS
# ==============================================================================

def build_icon_trophy():
    """Golden Trophy / Medal for Score Display."""
    objs = []
    mat_gold = create_clay_mat("m_tr_gld", (1.0, 0.82, 0.20, 1.0), roughness=0.30)
    mat_cup = create_clay_mat("m_tr_cup", (1.0, 0.88, 0.30, 1.0), emission=(1.0, 0.88, 0.30, 1.0), emission_str=2.0)
    mat_ribbon = create_clay_mat("m_tr_rbn", (0.90, 0.25, 0.30, 1.0), roughness=0.40)

    for side in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 0.45, -0.20, -0.02))
        rbn = bpy.context.active_object
        rbn.rotation_euler = (0, 0, math.radians(30 * side))
        rbn.scale = (0.22, 0.65, 0.14)
        rbn.data.materials.append(mat_ribbon)
        apply_uniform_clay_bevel(rbn, width=0.02, segments=1)
        objs.append(rbn)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.72, depth=0.22, vertices=24, location=(0, 0.08, 0.05))
    med = bpy.context.active_object
    med.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(med, width=0.04, segments=2)
    objs.append(med)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.42, depth=0.26, vertices=5, location=(0, 0.08, 0.12))
    st = bpy.context.active_object
    st.rotation_euler = (0, 0, math.radians(18))
    st.data.materials.append(mat_cup)
    apply_uniform_clay_bevel(st, width=0.02, segments=1)
    objs.append(st)

    return objs

def build_icon_radar():
    """Enemy Radar / Skull Counter Badge."""
    objs = []
    mat_plate = create_clay_mat("m_rd_plt", (0.18, 0.14, 0.20, 1.0), roughness=0.55)
    mat_grid = create_clay_mat("m_rd_grd", (0.95, 0.25, 0.30, 1.0), roughness=0.40)
    mat_blip = create_clay_mat("m_rd_blp", (1.0, 0.20, 0.25, 1.0), emission=(1.0, 0.20, 0.25, 1.0), emission_str=4.0)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=24, location=(0, 0, 0))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.05, segments=2)
    objs.append(plate)

    for r in [0.65, 0.40]:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=0.22, vertices=24, location=(0, 0, 0.02))
        ring = bpy.context.active_object
        ring.data.materials.append(mat_grid)
        apply_uniform_clay_bevel(ring, width=0.02, segments=1)
        objs.append(ring)

    for bx, by in [(0.25, 0.20), (-0.18, -0.22), (0.10, -0.32)]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(bx, by, 0.16))
        blip = bpy.context.active_object
        blip.data.materials.append(mat_blip)
        objs.append(blip)

    return objs

def build_icon_tank_avatar(player_id=1):
    """Mini Tank Avatar Badge for P1 / P2 HUD."""
    objs = []
    tank_col = (0.98, 0.82, 0.22, 1.0) if player_id == 1 else (0.42, 0.88, 0.52, 1.0)
    border_col = (0.85, 0.65, 0.15, 1.0) if player_id == 1 else (0.28, 0.68, 0.38, 1.0)

    mat_border = create_clay_mat(f"m_tav_bdr_{player_id}", border_col, roughness=0.40)
    mat_hull = create_clay_mat(f"m_tav_hul_{player_id}", tank_col, roughness=0.45)
    mat_track = create_clay_mat("m_tav_trk", (0.22, 0.20, 0.24, 1.0), roughness=0.65)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.88, depth=0.20, vertices=16, location=(0, 0, 0))
    bdr = bpy.context.active_object
    bdr.data.materials.append(mat_border)
    apply_uniform_clay_bevel(bdr, width=0.05, segments=2)
    objs.append(bdr)

    # Tank Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.04, 0.18))
    hull = bpy.context.active_object
    hull.scale = (0.50, 0.60, 0.20)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.03, segments=2)
    objs.append(hull)

    for tx in [-0.30, 0.30]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx, -0.04, 0.16))
        tr = bpy.context.active_object
        tr.scale = (0.14, 0.66, 0.18)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.02, segments=1)
        objs.append(tr)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.18, vertices=12, location=(0, -0.06, 0.28))
    tur = bpy.context.active_object
    tur.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(tur, width=0.02, segments=1)
    objs.append(tur)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=0.40, vertices=10, location=(0, 0.20, 0.28))
    gn = bpy.context.active_object
    gn.rotation_euler = (math.radians(90), 0, 0)
    gn.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(gn, width=0.01, segments=1)
    objs.append(gn)

    return objs

def build_banner_victory():
    """Grand Clay VICTORY Banner Ribbon with Laurel & Golden Stars."""
    objs = []
    mat_ribbon = create_clay_mat("m_bv_rbn", (0.98, 0.80, 0.22, 1.0), roughness=0.35)
    mat_trim = create_clay_mat("m_bv_trm", (0.90, 0.52, 0.18, 1.0), roughness=0.40)
    mat_star = create_clay_mat("m_bv_str", (1.0, 0.95, 0.40, 1.0), emission=(1.0, 0.95, 0.40, 1.0), emission_str=3.0)
    mat_gem = create_clay_mat("m_bv_gem", (0.30, 0.88, 0.98, 1.0), emission=(0.30, 0.88, 0.98, 1.0), emission_str=3.5)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    base = bpy.context.active_object
    base.scale = (4.60, 1.40, 0.30)
    base.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(base, width=0.16, segments=3)
    objs.append(base)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.10))
    inner = bpy.context.active_object
    inner.scale = (4.30, 1.10, 0.28)
    inner.data.materials.append(mat_ribbon)
    apply_uniform_clay_bevel(inner, width=0.12, segments=3)
    objs.append(inner)

    for side in [-1, 1]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * 2.35, -0.15, -0.05))
        wing = bpy.context.active_object
        wing.rotation_euler = (0, 0, math.radians(-15 * side))
        wing.scale = (0.75, 1.10, 0.25)
        wing.data.materials.append(mat_trim)
        apply_uniform_clay_bevel(wing, width=0.10, segments=2)
        objs.append(wing)

    star_locs = [(-0.85, 0.58), (0.0, 0.68), (0.85, 0.58)]
    for i, (sx, sy) in enumerate(star_locs):
        r = 0.28 if i == 1 else 0.22
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=0.25, vertices=5, location=(sx, sy, 0.28))
        star = bpy.context.active_object
        star.rotation_euler = (0, 0, math.radians(18))
        star.data.materials.append(mat_star)
        apply_uniform_clay_bevel(star, width=0.03, segments=2)
        objs.append(star)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.26, depth=0.30, vertices=8, location=(0, 0, 0.30))
    gem = bpy.context.active_object
    gem.rotation_euler = (0, 0, math.radians(22.5))
    gem.data.materials.append(mat_gem)
    apply_uniform_clay_bevel(gem, width=0.04, segments=2)
    objs.append(gem)

    return objs

def build_banner_gameover():
    """Dark Crimson DEFEAT Banner with Iron Rivets."""
    objs = []
    mat_plate = create_clay_mat("m_bg_plt", (0.24, 0.12, 0.14, 1.0), roughness=0.60)
    mat_crimson = create_clay_mat("m_bg_crm", (0.75, 0.20, 0.22, 1.0), roughness=0.50)
    mat_rivet = create_clay_mat("m_bg_rvt", (0.45, 0.40, 0.42, 1.0), roughness=0.40)
    mat_ruby = create_clay_mat("m_bg_rby", (0.95, 0.15, 0.20, 1.0), emission=(0.95, 0.15, 0.20, 1.0), emission_str=3.0)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    base = bpy.context.active_object
    base.scale = (4.60, 1.40, 0.30)
    base.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(base, width=0.16, segments=3)
    objs.append(base)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.10))
    inner = bpy.context.active_object
    inner.scale = (4.30, 1.10, 0.28)
    inner.data.materials.append(mat_crimson)
    apply_uniform_clay_bevel(inner, width=0.12, segments=3)
    objs.append(inner)

    for rx in [-1.90, 1.90]:
        for ry in [-0.40, 0.40]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.20, vertices=12, location=(rx, ry, 0.26))
            rvt = bpy.context.active_object
            rvt.data.materials.append(mat_rivet)
            apply_uniform_clay_bevel(rvt, width=0.015, segments=1)
            objs.append(rvt)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28, location=(0, 0, 0.28))
    skull = bpy.context.active_object
    skull.scale = (1.0, 0.9, 0.6)
    skull.data.materials.append(mat_ruby)
    objs.append(skull)

    return objs

# ==============================================================================
# MAIN RENDER PIPELINE ORCHESTRATOR
# ==============================================================================

def main():
    print("================================================================")
    print(" Executing Full Suite Sokpop Clay UI Asset Generation...        ")
    print("================================================================")

    reset_jitter_seed(42)

    # 1. Title Screen Assets
    clear_scene()
    setup_render_settings(256, 256, samples=28)
    create_sokpop_lighting(ortho_scale=3.20)
    render_and_clean(build_title_crest(), os.path.join(SPRITES_UI, "ui_title_crest.png"))
    print("[OK] UI Title Crest Rendered.")

    # Navigation / Mode Icons
    setup_render_settings(128, 128, samples=24)
    create_sokpop_lighting(ortho_scale=2.10)

    render_and_clean(build_mode_icon_1p(), os.path.join(SPRITES_UI, "ui_icon_mode_1p.png"))
    render_and_clean(build_mode_icon_2p(), os.path.join(SPRITES_UI, "ui_icon_mode_2p.png"))
    render_and_clean(build_mode_icon_arcade(), os.path.join(SPRITES_UI, "ui_icon_mode_arcade.png"))
    render_and_clean(build_mode_icon_continue(), os.path.join(SPRITES_UI, "ui_icon_mode_continue.png"))
    render_and_clean(build_mode_icon_exit(), os.path.join(SPRITES_UI, "ui_icon_mode_exit.png"))
    print("[OK] UI Title Mode Icons Rendered.")

    # 2. Perk & Upgrade Icons for Selection Dialog
    perk_types = ["atk", "speed", "armor", "laser", "missile", "train", "shield", "regen", "ricochet", "bomb", "gold", "tactical"]
    for p_type in perk_types:
        clear_scene()
        setup_render_settings(128, 128, samples=24)
        create_sokpop_lighting(ortho_scale=2.05)
        render_and_clean(build_perk_icon(p_type), os.path.join(SPRITES_UI, f"perk_{p_type}.png"))
    print("[OK] All 12 Perk Badges Rendered.")

    # Threat Rating Badges
    clear_scene()
    setup_render_settings(96, 96, samples=24)
    create_sokpop_lighting(ortho_scale=2.00)
    render_and_clean(build_threat_star(), os.path.join(SPRITES_UI, "ui_badge_threat_star.png"))
    render_and_clean(build_threat_skull(), os.path.join(SPRITES_UI, "ui_badge_threat_skull.png"))
    print("[OK] Threat Rating Badges Rendered.")

    # 3. Battle HUD & Status Icons
    clear_scene()
    setup_render_settings(128, 128, samples=24)
    create_sokpop_lighting(ortho_scale=2.10)
    render_and_clean(build_icon_trophy(), os.path.join(SPRITES_UI, "ui_icon_score_trophy.png"))
    render_and_clean(build_icon_radar(), os.path.join(SPRITES_UI, "ui_icon_enemy_radar.png"))
    render_and_clean(build_icon_tank_avatar(1), os.path.join(SPRITES_UI, "ui_icon_tank_p1.png"))
    render_and_clean(build_icon_tank_avatar(2), os.path.join(SPRITES_UI, "ui_icon_tank_p2.png"))
    print("[OK] HUD Status Icons Rendered.")

    # 4. Victory & Defeat Celebration Banners
    clear_scene()
    setup_render_settings(512, 160, samples=28)
    create_sokpop_lighting(ortho_scale=5.00)
    render_and_clean(build_banner_victory(), os.path.join(SPRITES_UI, "ui_banner_victory.png"))
    render_and_clean(build_banner_gameover(), os.path.join(SPRITES_UI, "ui_banner_gameover.png"))
    print("[OK] Victory & Defeat Banners Rendered.")

    print("\n================================================================")
    print(" Full Suite UI Asset Generation Complete!                       ")
    print("================================================================")

if __name__ == '__main__':
    main()
