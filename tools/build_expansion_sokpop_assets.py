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
    reset_jitter_seed,
    render_and_clean,
    ORTHO_SCALE_DEFAULT,
    ORTHO_SCALE_TANK,
    TILE_FULL_BLEED,
)

PROJECT_DIR = os.path.dirname(SCRIPT_DIR) if os.path.basename(SCRIPT_DIR) == 'tools' else SCRIPT_DIR
SPRITES_TANKS = os.path.join(PROJECT_DIR, "assets", "sprites", "tanks")
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")

os.makedirs(SPRITES_TANKS, exist_ok=True)
os.makedirs(SPRITES_UI, exist_ok=True)

# Import existing tank builder from unified script
from build_all_sokpop_assets_unified import build_sokpop_tank

# ==================== 1. SUMMIT COLOSSUS BOSS TANK ====================

def build_sokpop_boss_tank(frame=0):
    objs = []
    # Rich Obsidian, Imperial Gold and Glowing Ruby palette
    mat_hull = create_clay_mat(f"boss_h_{frame}", (0.16, 0.18, 0.24, 1.0), roughness=0.68)
    mat_armor = create_clay_mat(f"boss_arm_{frame}", (0.24, 0.27, 0.35, 1.0), roughness=0.60)
    mat_gold = create_clay_mat(f"boss_g_{frame}", (0.96, 0.78, 0.22, 1.0), roughness=0.45)
    mat_track = create_clay_mat(f"boss_tr_{frame}", (0.22, 0.20, 0.26, 1.0), roughness=0.88)
    mat_core = create_clay_mat(f"boss_core_{frame}", (0.98, 0.22, 0.32, 1.0), emission=(0.98, 0.22, 0.32, 1.0), emission_str=2.6)
    mat_bore = create_clay_mat(f"boss_bore_{frame}", (0.08, 0.08, 0.10, 1.0), roughness=0.92)

    w = 1.62
    l = 1.68
    tw = 0.42
    tx = w * 0.5 + tw * 0.5 - 0.05
    tl = l * 1.15

    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.015

    # 1. Colossal Lower & Upper Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.04, bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.62)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.18, segments=4)
    objs.append(hull)

    # Front Sloped Heavy Ram Plate
    bpy.ops.mesh.primitive_cylinder_add(radius=w*0.48, depth=0.52, vertices=16, location=(0, l*0.44, 0.06 + bob_z))
    ram = bpy.context.active_object
    ram.rotation_euler = (0, math.radians(90), 0)
    ram.data.materials.append(mat_armor)
    apply_uniform_clay_bevel(ram, width=0.12, segments=3)
    objs.append(ram)

    # Imperial Gold Eagle Crest Plate
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, l*0.48, 0.18 + bob_z))
    crest = bpy.context.active_object
    crest.scale = (0.64, 0.16, 0.22)
    crest.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(crest, width=0.06, segments=2)
    objs.append(crest)

    # 2. Quad Heavy Treads with 4 Roadwheels per side
    wheel_rot = (frame / 6.0) * (2.0 * math.pi)
    for x_pos in [-tx, tx]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, 0.02))
        tr = bpy.context.active_object
        tr.scale = (tw, tl, 0.68)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.18, segments=4)
        objs.append(tr)

        # 4 Heavy Roadwheels with rotating studs
        for wy in [-0.60, -0.20, 0.20, 0.60]:
            bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=tw*1.08, vertices=16, location=(x_pos, wy, 0))
            wh = bpy.context.active_object
            wh.rotation_euler = (0, math.radians(90), 0)
            wh.data.materials.append(mat_armor)
            apply_uniform_clay_bevel(wh, width=0.07, segments=3)
            objs.append(wh)

            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(x_pos + (0.09 if x_pos > 0 else -0.09), wy, 0))
            hub = bpy.context.active_object
            hub.data.materials.append(mat_gold)
            bpy.ops.object.shade_smooth()
            objs.append(hub)

            for b_i in range(3):
                b_ang = wheel_rot + b_i * (2.0 * math.pi / 3.0)
                b_y = wy + math.sin(b_ang) * 0.13
                b_z = math.cos(b_ang) * 0.13
                b_x = x_pos + (0.10 if x_pos > 0 else -0.10)
                bpy.ops.mesh.primitive_uv_sphere_add(radius=0.032, location=(b_x, b_y, b_z))
                w_bolt = bpy.context.active_object
                w_bolt.data.materials.append(mat_gold)
                bpy.ops.object.shade_smooth()
                objs.append(w_bolt)

        # Gold Side Armor Sponson Skirts
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos + (0.10 if x_pos > 0 else -0.10), 0, 0.24 + bob_z))
        skirt = bpy.context.active_object
        skirt.scale = (0.08, tl * 0.88, 0.22)
        skirt.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(skirt, width=0.04, segments=2)
        objs.append(skirt)

    # 3. Super Heavy Hexagonal Turret
    bpy.ops.mesh.primitive_cylinder_add(radius=0.68, depth=0.55, vertices=6, location=(0, 0.05, 0.44 + bob_z))
    turret = bpy.context.active_object
    turret.data.materials.append(mat_armor)
    apply_uniform_clay_bevel(turret, width=0.14, segments=3)
    objs.append(turret)

    # Commander Cupola Dome
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28, location=(0, -0.18, 0.68 + bob_z))
    cupola = bpy.context.active_object
    cupola.scale = (1.0, 1.0, 0.6)
    cupola.data.materials.append(mat_gold)
    bpy.ops.object.shade_smooth()
    objs.append(cupola)

    # Glowing Red Energy Reactor Core on Rear Deck
    core_pulse = 0.92 + math.sin(frame * (2.0 * math.pi / 6.0)) * 0.08
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.24 * core_pulse, location=(0, -0.58, 0.38 + bob_z))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(core)

    # 4. Dual Super-Heavy Siege Cannons
    for bx in [-0.30, 0.30]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.15, depth=1.20, vertices=16, location=(bx, 0.68, 0.45 + bob_z))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_hull)
        apply_uniform_clay_bevel(barrel, width=0.04, segments=2)
        objs.append(barrel)

        # Gold Reinforced Mantlet
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(bx, 0.32, 0.45 + bob_z))
        mant = bpy.context.active_object
        mant.scale = (0.24, 0.28, 0.24)
        mant.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(mant, width=0.05, segments=2)
        objs.append(mant)

        # Triple Muzzle Brake at tip
        bpy.ops.mesh.primitive_cylinder_add(radius=0.20, depth=0.22, vertices=16, location=(bx, 1.25, 0.45 + bob_z))
        muzzle = bpy.context.active_object
        muzzle.rotation_euler = (math.radians(90), 0, 0)
        muzzle.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(muzzle, width=0.05, segments=2)
        objs.append(muzzle)

        # Dark Gun Bore
        bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=0.06, vertices=16, location=(bx, 1.37, 0.45 + bob_z))
        bore = bpy.context.active_object
        bore.rotation_euler = (math.radians(90), 0, 0)
        bore.data.materials.append(mat_bore)
        objs.append(bore)

    return objs

# ==================== 2. EVENT DIORAMA SCENARIOS (480x240) ====================

def build_diorama_rest():
    objs = []
    mat_ground = create_clay_mat("d_rest_g", (0.16, 0.22, 0.28, 1.0), roughness=0.88)
    mat_log = create_clay_mat("d_rest_log", (0.38, 0.22, 0.14, 1.0), roughness=0.82)
    mat_fire_c = create_clay_mat("d_rest_fc", (1.0, 0.88, 0.25, 1.0), emission=(1.0, 0.88, 0.25, 1.0), emission_str=3.0)
    mat_fire_o = create_clay_mat("d_rest_fo", (0.98, 0.42, 0.16, 1.0), emission=(0.98, 0.42, 0.16, 1.0), emission_str=2.2)
    mat_pine = create_clay_mat("d_rest_pine", (0.18, 0.48, 0.32, 1.0))
    mat_tank = create_clay_mat("d_rest_tk", (0.98, 0.80, 0.22, 1.0))
    mat_star = create_clay_mat("d_rest_st", (1.0, 0.95, 0.65, 1.0), emission=(1.0, 0.95, 0.65, 1.0), emission_str=2.5)

    # 1. Base Ground Mound
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.4, -0.3))
    base = bpy.context.active_object
    base.scale = (5.2, 2.6, 0.5)
    base.data.materials.append(mat_ground)
    apply_uniform_clay_bevel(base, width=0.18, segments=4)
    objs.append(base)

    # 2. Central Campfire Logs
    for ang, (lx, ly) in [(0, (0, 0)), (math.pi/3, (0, 0)), (2*math.pi/3, (0, 0))]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.9, vertices=12, location=(lx, ly, 0.06))
        log = bpy.context.active_object
        log.rotation_euler = (math.radians(82), 0, ang)
        log.data.materials.append(mat_log)
        apply_uniform_clay_bevel(log, width=0.04, segments=2)
        objs.append(log)

    # Layered Campfire Flame Cones
    bpy.ops.mesh.primitive_cone_add(radius1=0.32, radius2=0.02, depth=0.75, location=(0, 0, 0.42))
    flame_out = bpy.context.active_object
    flame_out.data.materials.append(mat_fire_o)
    bpy.ops.object.shade_smooth()
    objs.append(flame_out)

    bpy.ops.mesh.primitive_cone_add(radius1=0.20, radius2=0.01, depth=0.55, location=(0, 0, 0.36))
    flame_in = bpy.context.active_object
    flame_in.data.materials.append(mat_fire_c)
    bpy.ops.object.shade_smooth()
    objs.append(flame_in)

    # Floating Sparkles
    for sx, sy, sz in [(-0.15, 0.12, 0.85), (0.18, -0.10, 0.95), (0.05, 0.18, 1.10)]:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, location=(sx, sy, sz))
        sp = bpy.context.active_object
        sp.data.materials.append(mat_star)
        bpy.ops.object.shade_smooth()
        objs.append(sp)

    # 3. Resting Miniature Clay Tank on left
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(-1.45, 0.05, 0.18))
    t_body = bpy.context.active_object
    t_body.scale = (0.9, 0.75, 0.36)
    t_body.data.materials.append(mat_tank)
    apply_uniform_clay_bevel(t_body, width=0.10, segments=3)
    objs.append(t_body)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=0.25, vertices=12, location=(-1.45, 0.05, 0.42))
    t_tur = bpy.context.active_object
    t_tur.data.materials.append(mat_tank)
    apply_uniform_clay_bevel(t_tur, width=0.06, segments=2)
    objs.append(t_tur)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.60, vertices=12, location=(-1.12, 0.05, 0.42))
    t_gun = bpy.context.active_object
    t_gun.rotation_euler = (0, math.radians(90), 0)
    t_gun.data.materials.append(mat_tank)
    objs.append(t_gun)

    # 4. Pine Trees on Right
    for px, py, scale_p in [(1.45, 0.15, 1.0), (1.95, -0.15, 0.75)]:
        for tz, r_top in [(0.25, 0.45), (0.55, 0.36), (0.85, 0.24)]:
            bpy.ops.mesh.primitive_cone_add(radius1=r_top * scale_p, radius2=0.04, depth=0.45 * scale_p, location=(px, py, tz * scale_p))
            cone = bpy.context.active_object
            cone.data.materials.append(mat_pine)
            bpy.ops.object.shade_smooth()
            objs.append(cone)

    return objs

def build_diorama_shop():
    objs = []
    mat_floor = create_clay_mat("d_shop_fl", (0.32, 0.28, 0.35, 1.0))
    mat_wood = create_clay_mat("d_shop_wd", (0.62, 0.38, 0.22, 1.0))
    mat_gold = create_clay_mat("d_shop_gd", (0.98, 0.82, 0.22, 1.0), roughness=0.35)
    mat_awning = create_clay_mat("d_shop_aw", (0.92, 0.32, 0.35, 1.0))
    mat_cream = create_clay_mat("d_shop_cr", (0.95, 0.92, 0.85, 1.0))
    mat_tool = create_clay_mat("d_shop_tl", (0.75, 0.82, 0.90, 1.0), roughness=0.40)
    mat_star = create_clay_mat("d_shop_st", (1.0, 0.90, 0.25, 1.0), emission=(1.0, 0.90, 0.25, 1.0), emission_str=2.6)

    # 1. Base Shop Counter & Floor
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.4, -0.3))
    base = bpy.context.active_object
    base.scale = (5.2, 2.6, 0.5)
    base.data.materials.append(mat_floor)
    apply_uniform_clay_bevel(base, width=0.18, segments=4)
    objs.append(base)

    # Wooden Shop Table
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.1, 0.15))
    table = bpy.context.active_object
    table.scale = (3.4, 0.95, 0.45)
    table.data.materials.append(mat_wood)
    apply_uniform_clay_bevel(table, width=0.08, segments=3)
    objs.append(table)

    # 2. Striped Shop Awning Canopy
    for i, col_mat in enumerate([mat_awning, mat_cream, mat_awning, mat_cream, mat_awning, mat_cream, mat_awning]):
        ax = -1.5 + i * 0.50
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(ax, 0.05, 1.15))
        awn = bpy.context.active_object
        awn.scale = (0.46, 1.10, 0.14)
        awn.rotation_euler = (math.radians(18), 0, 0)
        awn.data.materials.append(col_mat)
        apply_uniform_clay_bevel(awn, width=0.04, segments=2)
        objs.append(awn)

    # 3. Merchandise on Table
    # Stack of Brass Artillery Shells
    for sy, sx in [(0.42, -0.9), (0.42, -0.7), (0.62, -0.8)]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=0.35, vertices=12, location=(sx, -0.1, sy))
        shell = bpy.context.active_object
        shell.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(shell, width=0.03, segments=2)
        objs.append(shell)

    # Floating Golden Star Upgrade in Showcase
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28, location=(0.0, -0.1, 0.65))
    star = bpy.context.active_object
    star.data.materials.append(mat_star)
    bpy.ops.object.shade_smooth()
    objs.append(star)

    # Heavy Tool Chest & Wrench
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.85, -0.1, 0.50))
    chest = bpy.context.active_object
    chest.scale = (0.65, 0.45, 0.32)
    chest.data.materials.append(mat_awning)
    apply_uniform_clay_bevel(chest, width=0.06, segments=2)
    objs.append(chest)

    return objs

def build_diorama_event():
    objs = []
    mat_stone = create_clay_mat("d_ev_st", (0.35, 0.38, 0.45, 1.0))
    mat_rune = create_clay_mat("d_ev_rn", (0.30, 0.88, 0.98, 1.0), emission=(0.30, 0.88, 0.98, 1.0), emission_str=2.8)
    mat_chest = create_clay_mat("d_ev_ch", (0.92, 0.68, 0.20, 1.0), roughness=0.42)
    mat_lock = create_clay_mat("d_ev_lk", (0.98, 0.25, 0.35, 1.0), emission=(0.98, 0.25, 0.35, 1.0), emission_str=2.0)
    mat_crystal = create_clay_mat("d_ev_cr", (0.50, 0.85, 1.0, 1.0), roughness=0.18, sss_weight=0.30)

    # 1. Base Ancient Ruins Platform
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.4, -0.3))
    base = bpy.context.active_object
    base.scale = (5.2, 2.6, 0.5)
    base.data.materials.append(mat_stone)
    apply_uniform_clay_bevel(base, width=0.18, segments=4)
    objs.append(base)

    # 2. Mystical Stone Monolith Pillars
    for px, pz_rot in [(-1.5, 8), (1.5, -8)]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, 0.1, 0.65))
        mon = bpy.context.active_object
        mon.scale = (0.55, 0.45, 1.35)
        mon.rotation_euler = (0, 0, math.radians(pz_rot))
        mon.data.materials.append(mat_stone)
        apply_uniform_clay_bevel(mon, width=0.08, segments=3)
        objs.append(mon)

        # Glowing Rune Strip on Monolith
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, -0.15, 0.65))
        rune = bpy.context.active_object
        rune.scale = (0.18, 0.08, 0.85)
        rune.data.materials.append(mat_rune)
        objs.append(rune)

    # 3. Ornate Golden Mystery Chest in Center
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.26))
    ch_body = bpy.context.active_object
    ch_body.scale = (0.95, 0.65, 0.48)
    ch_body.data.materials.append(mat_chest)
    apply_uniform_clay_bevel(ch_body, width=0.08, segments=3)
    objs.append(ch_body)

    # Chest Lid with Dome
    bpy.ops.mesh.primitive_cylinder_add(radius=0.45, depth=0.95, vertices=16, location=(0, 0, 0.52))
    lid = bpy.context.active_object
    lid.scale = (1.0, 0.65, 0.5)
    lid.rotation_euler = (0, math.radians(90), 0)
    lid.data.materials.append(mat_chest)
    apply_uniform_clay_bevel(lid, width=0.06, segments=2)
    objs.append(lid)

    # Ruby Keyhole Lock
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, -0.34, 0.36))
    lock = bpy.context.active_object
    lock.data.materials.append(mat_lock)
    bpy.ops.object.shade_smooth()
    objs.append(lock)

    # Surrounding Glowing Mana Crystals
    for cx, cy, cz in [(-0.65, -0.35, 0.15), (0.72, -0.30, 0.18), (0.85, 0.25, 0.22)]:
        bpy.ops.mesh.primitive_cone_add(radius1=0.14, radius2=0.02, depth=0.42, location=(cx, cy, cz))
        crys = bpy.context.active_object
        crys.data.materials.append(mat_crystal)
        apply_uniform_clay_bevel(crys, width=0.03, segments=2)
        objs.append(crys)

    return objs

# ==================== 3. RPG HUD BADGES (128x128) ====================

def build_hud_icon(icon_type):
    objs = []
    mat_gold = create_clay_mat("hi_gd", (0.98, 0.82, 0.22, 1.0), roughness=0.35)
    mat_red = create_clay_mat("hi_rd", (0.95, 0.28, 0.35, 1.0))
    mat_green = create_clay_mat("hi_gn", (0.32, 0.88, 0.45, 1.0))
    mat_blue = create_clay_mat("hi_bl", (0.28, 0.65, 0.95, 1.0))
    mat_white = create_clay_mat("hi_wt", (0.96, 0.98, 1.0, 1.0))

    if icon_type == "atk":
        # Crossed Swords / Artillery Shell with Gold Starburst
        bpy.ops.mesh.primitive_cylinder_add(radius=0.35, depth=1.60, vertices=16, location=(0, 0, 0))
        shell = bpy.context.active_object
        shell.rotation_euler = (0, 0, math.radians(45))
        shell.data.materials.append(mat_red)
        apply_uniform_clay_bevel(shell, width=0.08, segments=3)
        objs.append(shell)

        bpy.ops.mesh.primitive_cone_add(radius1=0.35, radius2=0.04, depth=0.60, location=(0.60, 0.60, 0))
        tip = bpy.context.active_object
        tip.rotation_euler = (0, 0, math.radians(-45))
        tip.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(tip, width=0.05, segments=2)
        objs.append(tip)

    elif icon_type == "speed":
        # Winged Golden Lightning Bolt
        bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=1.60, vertices=6, location=(-0.15, 0, 0))
        bolt = bpy.context.active_object
        bolt.rotation_euler = (0, 0, math.radians(35))
        bolt.data.materials.append(mat_gold)
        apply_uniform_clay_bevel(bolt, width=0.06, segments=2)
        objs.append(bolt)

        # Emerald Wing Feather
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(0.35, 0.15, 0))
        wing = bpy.context.active_object
        wing.scale = (0.35, 1.2, 0.25)
        wing.rotation_euler = (0, 0, math.radians(-30))
        wing.data.materials.append(mat_green)
        apply_uniform_clay_bevel(wing, width=0.05, segments=2)
        objs.append(wing)

    elif icon_type == "armor":
        # Solid Clay Shield
        bpy.ops.mesh.primitive_cylinder_add(radius=0.85, depth=0.32, vertices=6, location=(0, 0, 0))
        shield = bpy.context.active_object
        shield.data.materials.append(mat_blue)
        apply_uniform_clay_bevel(shield, width=0.12, segments=3)
        objs.append(shield)

        # Gold Rim Boss
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.38, location=(0, 0, 0.18))
        boss = bpy.context.active_object
        boss.data.materials.append(mat_gold)
        bpy.ops.object.shade_smooth()
        objs.append(boss)

    elif icon_type == "regen":
        # Heart with Medic Cross
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.65, location=(-0.28, 0.22, 0))
        h1 = bpy.context.active_object
        h1.data.materials.append(mat_red)
        apply_uniform_clay_bevel(h1, width=0.08, segments=3)
        objs.append(h1)

        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.65, location=(0.28, 0.22, 0))
        h2 = bpy.context.active_object
        h2.data.materials.append(mat_red)
        apply_uniform_clay_bevel(h2, width=0.08, segments=3)
        objs.append(h2)

        bpy.ops.mesh.primitive_cone_add(radius1=0.82, radius2=0.05, depth=1.1, location=(0, -0.38, 0))
        h3 = bpy.context.active_object
        h3.rotation_euler = (0, 0, math.radians(180))
        h3.data.materials.append(mat_red)
        apply_uniform_clay_bevel(h3, width=0.08, segments=3)
        objs.append(h3)

        # White/Green Medic Cross
        for sx, sy in [(0.48, 0.14), (0.14, 0.48)]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.28))
            c = bpy.context.active_object
            c.scale = (sx, sy, 0.12)
            c.data.materials.append(mat_green)
            apply_uniform_clay_bevel(c, width=0.03, segments=2)
            objs.append(c)

    return objs

# ==================== MASTER BATCH RUNNER ====================

def main():
    clear_scene()
    reset_jitter_seed(2000)

    # 1. Summit Colossus Boss Tank (6 Frames)
    print(">>> 1. Rendering Summit Colossus Boss Tank (6 Frames)...")
    setup_render_settings(rx=256, ry=256)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    for frame in range(6):
        objs = build_sokpop_boss_tank(frame)
        render_and_clean(objs, os.path.join(SPRITES_TANKS, f"enemy_boss_f{frame}.png"))

    # 2. Player 2 Dedicated Emerald Clay Tiers (24 Frames)
    print(">>> 2. Rendering Player 2 Dedicated Clay Tiers (24 Frames)...")
    p2_palettes = {
        "player2_tier0": {"body": (0.24, 0.72, 0.42, 1.0), "turret": (0.40, 0.88, 0.58, 1.0), "trim": (0.96, 0.52, 0.24, 1.0), "b_cnt": 1, "blen": 0.95, "bthick": 0.19, "heavy": False, "plasma": False},
        "player2_tier1": {"body": (0.18, 0.60, 0.36, 1.0), "turret": (0.52, 0.85, 0.40, 1.0), "trim": (0.96, 0.82, 0.22, 1.0), "b_cnt": 1, "blen": 1.18, "bthick": 0.20, "heavy": False, "plasma": False},
        "player2_tier2": {"body": (0.16, 0.55, 0.52, 1.0), "turret": (0.32, 0.78, 0.72, 1.0), "trim": (0.92, 0.32, 0.38, 1.0), "b_cnt": 2, "blen": 1.08, "bthick": 0.16, "heavy": True, "plasma": False},
        "player2_tier3": {"body": (0.20, 0.78, 0.65, 1.0), "turret": (0.35, 0.88, 0.82, 1.0), "trim": (0.98, 0.65, 0.18, 1.0), "b_cnt": 1, "blen": 1.25, "bthick": 0.24, "heavy": True, "plasma": True},
    }
    for name, cfg in p2_palettes.items():
        for frame in range(6):
            objs = build_sokpop_tank(
                f"{name}_f{frame}", cfg["body"], cfg["turret"], cfg["trim"],
                barrel_count=cfg["b_cnt"], barrel_len=cfg["blen"], barrel_thick=cfg["bthick"],
                is_heavy=cfg["heavy"], is_plasma=cfg["plasma"], frame=frame
            )
            render_and_clean(objs, os.path.join(SPRITES_TANKS, f"{name}_f{frame}.png"))

    # 3. High-Detail Event Dioramas (480x240)
    print(">>> 3. Rendering Event Dioramas (480x240)...")
    setup_render_settings(rx=480, ry=240)
    create_sokpop_lighting(ortho_scale=5.2, sun_energy=2.6, ambient_strength=0.38)
    render_and_clean(build_diorama_rest(), os.path.join(SPRITES_UI, "diorama_rest.png"))
    render_and_clean(build_diorama_shop(), os.path.join(SPRITES_UI, "diorama_shop.png"))
    render_and_clean(build_diorama_event(), os.path.join(SPRITES_UI, "diorama_event.png"))

    # 4. RPG HUD Clay Badges (128x128)
    print(">>> 4. Rendering RPG HUD Clay Badges (128x128)...")
    setup_render_settings(rx=128, ry=128)
    create_sokpop_lighting(ortho_scale=2.6, sun_energy=2.8)
    for ic in ["atk", "speed", "armor", "regen"]:
        render_and_clean(build_hud_icon(ic), os.path.join(SPRITES_UI, f"icon_{ic}.png"))

    print(">>> ALL EXPANSION CLAY ASSETS RENDERED SUCCESSFULLY! <<<")

if __name__ == "__main__":
    main()
