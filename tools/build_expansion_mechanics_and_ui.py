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
SPRITES_TILES = os.path.join(PROJECT_DIR, "assets", "sprites", "tiles")
SPRITES_EFFECTS = os.path.join(PROJECT_DIR, "assets", "sprites", "effects")
SPRITES_POWERUPS = os.path.join(PROJECT_DIR, "assets", "sprites", "powerups")
SPRITES_BUILDINGS = os.path.join(PROJECT_DIR, "assets", "sprites", "buildings")
SPRITES_UI = os.path.join(PROJECT_DIR, "assets", "sprites", "ui")

for folder in [SPRITES_TANKS, SPRITES_TILES, SPRITES_EFFECTS, SPRITES_POWERUPS, SPRITES_BUILDINGS, SPRITES_UI]:
    os.makedirs(folder, exist_ok=True)

# ==================== 1. MISSILE TANK (TRACKING MISSILES) ====================

def build_missile_tank(frame=0):
    objs = []
    mat_body = create_clay_mat(f"m_mis_b_{frame}", (0.24, 0.20, 0.38, 1.0))
    mat_pod = create_clay_mat(f"m_mis_p_{frame}", (0.38, 0.32, 0.52, 1.0))
    mat_trim = create_clay_mat(f"m_mis_t_{frame}", (0.85, 0.38, 0.95, 1.0))
    mat_rocket = create_clay_mat(f"m_mis_r_{frame}", (0.95, 0.28, 0.32, 1.0))
    mat_track = create_clay_mat(f"m_mis_tr_{frame}", (0.20, 0.18, 0.24, 1.0))

    w, l = 1.30, 1.35
    tw, tx, tl = 0.32, 0.68, 1.45
    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.015

    # Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.02, bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.44)
    hull.data.materials.append(mat_body)
    apply_uniform_clay_bevel(hull, width=0.14, segments=3)
    objs.append(hull)

    # Treads
    for x_pos in [-tx, tx]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, bob_z*0.5))
        tr = bpy.context.active_object
        tr.scale = (tw, tl, 0.48)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.12, segments=3)
        objs.append(tr)

    # Turret Base
    bpy.ops.mesh.primitive_cylinder_add(radius=0.48, depth=0.35, vertices=16, location=(0, -0.05, 0.30 + bob_z))
    tur = bpy.context.active_object
    tur.data.materials.append(mat_trim)
    apply_uniform_clay_bevel(tur, width=0.08, segments=3)
    objs.append(tur)

    # Dual Rocket Pod Launchers
    for px in [-0.34, 0.34]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, 0.15, 0.42 + bob_z))
        pod = bpy.context.active_object
        pod.scale = (0.26, 0.70, 0.32)
        pod.rotation_euler = (math.radians(-12), 0, 0)
        pod.data.materials.append(mat_pod)
        apply_uniform_clay_bevel(pod, width=0.04, segments=2)
        objs.append(pod)

        # 4 Rocket Tips inside each pod
        for ry in [-0.08, 0.08]:
            for rz in [-0.08, 0.08]:
                bpy.ops.mesh.primitive_cylinder_add(radius=0.045, depth=0.16, vertices=10, location=(px + ry, 0.48, 0.42 + rz + bob_z))
                rk = bpy.context.active_object
                rk.rotation_euler = (math.radians(78), 0, 0)
                rk.data.materials.append(mat_rocket)
                apply_uniform_clay_bevel(rk, width=0.02, segments=2)
                objs.append(rk)

    # Radar Dish
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(0, -0.26, 0.52 + bob_z))
    dish = bpy.context.active_object
    dish.scale = (1.0, 0.3, 1.0)
    dish.rotation_euler = (math.radians(25), 0, (frame / 6.0) * math.pi)
    dish.data.materials.append(mat_trim)
    bpy.ops.object.shade_smooth()
    objs.append(dish)

    return objs

# ==================== 2. LASER TANK (PIERCING BEAM) ====================

def build_laser_tank(frame=0):
    objs = []
    mat_hull = create_clay_mat(f"m_las_h_{frame}", (0.85, 0.28, 0.30, 1.0))
    mat_armor = create_clay_mat(f"m_las_a_{frame}", (0.92, 0.94, 0.96, 1.0))
    mat_glow = create_clay_mat(f"m_las_g_{frame}", (0.20, 0.88, 1.0, 1.0), emission=(0.20, 0.88, 1.0, 1.0), emission_str=3.2)
    mat_track = create_clay_mat(f"m_las_tr_{frame}", (0.24, 0.22, 0.26, 1.0))

    w, l = 1.35, 1.40
    tw, tx, tl = 0.34, 0.70, 1.50
    bob_z = math.sin(frame * (2.0 * math.pi / 6.0)) * 0.015

    # Sleek Hull
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, -0.02, bob_z))
    hull = bpy.context.active_object
    hull.scale = (w, l, 0.46)
    hull.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(hull, width=0.15, segments=3)
    objs.append(hull)

    # Front Armor Wedge
    bpy.ops.mesh.primitive_cylinder_add(radius=w*0.42, depth=0.42, vertices=12, location=(0, l*0.40, 0.05 + bob_z))
    wedge = bpy.context.active_object
    wedge.rotation_euler = (0, math.radians(90), 0)
    wedge.data.materials.append(mat_armor)
    apply_uniform_clay_bevel(wedge, width=0.08, segments=3)
    objs.append(wedge)

    # Treads
    for x_pos in [-tx, tx]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_pos, 0, bob_z*0.5))
        tr = bpy.context.active_object
        tr.scale = (tw, tl, 0.50)
        tr.data.materials.append(mat_track)
        apply_uniform_clay_bevel(tr, width=0.12, segments=3)
        objs.append(tr)

    # Octagonal Energy Turret
    bpy.ops.mesh.primitive_cylinder_add(radius=0.52, depth=0.40, vertices=8, location=(0, -0.02, 0.32 + bob_z))
    tur = bpy.context.active_object
    tur.data.materials.append(mat_armor)
    apply_uniform_clay_bevel(tur, width=0.09, segments=3)
    objs.append(tur)

    # Long Rail / Laser Emitter Barrel
    bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=1.35, vertices=16, location=(0, 0.72, 0.35 + bob_z))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.radians(90), 0, 0)
    barrel.data.materials.append(mat_hull)
    apply_uniform_clay_bevel(barrel, width=0.03, segments=2)
    objs.append(barrel)

    # 3 Glowing Energy Focus Rings along barrel
    for fz in [0.35, 0.70, 1.05]:
        bpy.ops.mesh.primitive_torus_add(major_radius=0.18, minor_radius=0.045, location=(0, fz, 0.35 + bob_z))
        ring = bpy.context.active_object
        ring.rotation_euler = (math.radians(90), 0, 0)
        ring.data.materials.append(mat_glow)
        bpy.ops.object.shade_smooth()
        objs.append(ring)

    # Glowing Crystal Core in Turret Center
    core_pulse = 0.90 + math.sin(frame * (2.0 * math.pi / 6.0)) * 0.10
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.18 * core_pulse, location=(0, -0.15, 0.54 + bob_z))
    core = bpy.context.active_object
    core.data.materials.append(mat_glow)
    bpy.ops.object.shade_smooth()
    objs.append(core)

    return objs

# ==================== 3. PROJECTILES & TERRAIN PROPS ====================

def build_homing_missile():
    objs = []
    mat_body = create_clay_mat("mis_b", (0.92, 0.35, 0.25, 1.0))
    mat_cone = create_clay_mat("mis_c", (0.98, 0.85, 0.22, 1.0))
    mat_fin = create_clay_mat("mis_f", (0.24, 0.22, 0.28, 1.0))
    mat_flame = create_clay_mat("mis_fl", (1.0, 0.92, 0.45, 1.0), emission=(1.0, 0.85, 0.30, 1.0), emission_str=3.5)

    # Missile Body
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=1.0, vertices=16, location=(0, 0, 0))
    body = bpy.context.active_object
    body.data.materials.append(mat_body)
    apply_uniform_clay_bevel(body, width=0.04, segments=2)
    objs.append(body)

    # Nosecone
    bpy.ops.mesh.primitive_cone_add(radius1=0.22, radius2=0.02, depth=0.55, location=(0, 0, 0.72))
    cone = bpy.context.active_object
    cone.data.materials.append(mat_cone)
    apply_uniform_clay_bevel(cone, width=0.03, segments=2)
    objs.append(cone)

    # 4 Stabilizer Fins
    for ang in [0, math.pi/2, math.pi, 3*math.pi/2]:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.cos(ang)*0.26, math.sin(ang)*0.26, -0.32))
        fin = bpy.context.active_object
        fin.scale = (0.05, 0.20, 0.32) if (ang % math.pi == 0) else (0.20, 0.05, 0.32)
        fin.data.materials.append(mat_fin)
        apply_uniform_clay_bevel(fin, width=0.02, segments=2)
        objs.append(fin)

    # Rocket Flame
    bpy.ops.mesh.primitive_cone_add(radius1=0.18, radius2=0.01, depth=0.45, location=(0, 0, -0.68))
    flame = bpy.context.active_object
    flame.rotation_euler = (math.radians(180), 0, 0)
    flame.data.materials.append(mat_flame)
    bpy.ops.object.shade_smooth()
    objs.append(flame)

    return objs

def build_laser_beam_vfx():
    objs = []
    mat_core = create_clay_mat("las_c", (1.0, 1.0, 1.0, 1.0), emission=(0.4, 0.9, 1.0, 1.0), emission_str=4.5)
    mat_halo = create_clay_mat("las_h", (0.15, 0.70, 0.98, 1.0), emission=(0.15, 0.70, 0.98, 1.0), emission_str=2.5)

    # Core Beam
    bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=3.2, vertices=16, location=(0, 0, 0))
    core = bpy.context.active_object
    core.data.materials.append(mat_core)
    bpy.ops.object.shade_smooth()
    objs.append(core)

    # Glow Halo
    bpy.ops.mesh.primitive_cylinder_add(radius=0.32, depth=3.2, vertices=16, location=(0, 0, 0))
    halo = bpy.context.active_object
    halo.data.materials.append(mat_halo)
    bpy.ops.object.shade_smooth()
    objs.append(halo)

    return objs

def build_landmine_prop():
    objs = []
    mat_base = create_clay_mat("lm_b", (0.35, 0.38, 0.42, 1.0), roughness=0.75)
    mat_hazard = create_clay_mat("lm_h", (0.95, 0.82, 0.18, 1.0), roughness=0.60)
    mat_light = create_clay_mat("lm_l", (0.98, 0.22, 0.25, 1.0), emission=(0.98, 0.22, 0.25, 1.0), emission_str=3.5)

    # Circular Mine Base
    bpy.ops.mesh.primitive_cylinder_add(radius=1.10, depth=0.28, vertices=24, location=(0, 0, 0))
    base = bpy.context.active_object
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.08, segments=3)
    objs.append(base)

    # Inner Stepped Rim
    bpy.ops.mesh.primitive_cylinder_add(radius=0.82, depth=0.18, vertices=20, location=(0, 0, 0.14))
    rim = bpy.context.active_object
    rim.data.materials.append(mat_hazard)
    apply_uniform_clay_bevel(rim, width=0.06, segments=2)
    objs.append(rim)

    # 4 Pressure Pad Studs
    for ang in [0, math.pi/2, math.pi, 3*math.pi/2]:
        bx = math.cos(ang) * 0.58
        by = math.sin(ang) * 0.58
        bpy.ops.mesh.primitive_cylinder_add(radius=0.14, depth=0.12, vertices=12, location=(bx, by, 0.24))
        pad = bpy.context.active_object
        pad.data.materials.append(mat_base)
        apply_uniform_clay_bevel(pad, width=0.03, segments=2)
        objs.append(pad)

    # Center Red Blinking Detonator Dome
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.28, location=(0, 0, 0.25))
    det = bpy.context.active_object
    det.scale = (1.0, 1.0, 0.7)
    det.data.materials.append(mat_light)
    bpy.ops.object.shade_smooth()
    objs.append(det)

    return objs

def build_laser_cannon_turret():
    objs = []
    mat_base = create_clay_mat("lc_b", (0.28, 0.30, 0.36, 1.0))
    mat_gold = create_clay_mat("lc_g", (0.95, 0.75, 0.22, 1.0))
    mat_lens = create_clay_mat("lc_l", (0.18, 0.88, 1.0, 1.0), emission=(0.18, 0.88, 1.0, 1.0), emission_str=3.8)

    # Hexagonal Armored Base
    bpy.ops.mesh.primitive_cylinder_add(radius=1.15, depth=0.35, vertices=6, location=(0, 0, 0))
    base = bpy.context.active_object
    base.data.materials.append(mat_base)
    apply_uniform_clay_bevel(base, width=0.12, segments=3)
    objs.append(base)

    # Rotating Prism Turret
    bpy.ops.mesh.primitive_cylinder_add(radius=0.68, depth=0.45, vertices=16, location=(0, 0, 0.32))
    tur = bpy.context.active_object
    tur.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(tur, width=0.08, segments=3)
    objs.append(tur)

    # Dual Heavy Laser Projectors
    for bx in [-0.28, 0.28]:
        bpy.ops.mesh.primitive_cylinder_add(radius=0.15, depth=1.10, vertices=16, location=(bx, 0.55, 0.35))
        barrel = bpy.context.active_object
        barrel.rotation_euler = (math.radians(90), 0, 0)
        barrel.data.materials.append(mat_base)
        apply_uniform_clay_bevel(barrel, width=0.03, segments=2)
        objs.append(barrel)

        # Lens at Muzzle
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.13, location=(bx, 1.08, 0.35))
        lens = bpy.context.active_object
        lens.data.materials.append(mat_lens)
        bpy.ops.object.shade_smooth()
        objs.append(lens)

    return objs

# ==================== 4. UI STAGE PREVIEW BADGE ICONS ====================

def build_icon_badge(symbol_type="mine"):
    objs = []
    mat_gold = create_clay_mat("ib_g", (0.95, 0.78, 0.24, 1.0))
    mat_plate = create_clay_mat("ib_p", (0.24, 0.22, 0.28, 1.0))
    mat_accent = create_clay_mat("ib_a", (0.92, 0.35, 0.35, 1.0))

    # Badge Hexagon Rim
    bpy.ops.mesh.primitive_cylinder_add(radius=1.35, depth=0.22, vertices=6, location=(0, 0, 0))
    rim = bpy.context.active_object
    rim.data.materials.append(mat_gold)
    apply_uniform_clay_bevel(rim, width=0.08, segments=3)
    objs.append(rim)

    # Inner Dark Plate
    bpy.ops.mesh.primitive_cylinder_add(radius=1.12, depth=0.26, vertices=6, location=(0, 0, 0.04))
    plate = bpy.context.active_object
    plate.data.materials.append(mat_plate)
    apply_uniform_clay_bevel(plate, width=0.06, segments=2)
    objs.append(plate)

    # Emblem in Center
    if symbol_type == "mine":
        mat_red = create_clay_mat("ib_red", (0.98, 0.25, 0.25, 1.0), emission=(0.98, 0.25, 0.25, 1.0), emission_str=2.5)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.65, depth=0.18, vertices=16, location=(0, 0, 0.18))
        em = bpy.context.active_object
        em.data.materials.append(mat_gold)
        objs.append(em)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.32, location=(0, 0, 0.28))
        bulb = bpy.context.active_object
        bulb.data.materials.append(mat_red)
        objs.append(bulb)
    elif symbol_type == "laser":
        mat_cyan = create_clay_mat("ib_cy", (0.2, 0.9, 1.0, 1.0), emission=(0.2, 0.9, 1.0, 1.0), emission_str=3.0)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=1.2, vertices=12, location=(0, 0, 0.22))
        beam = bpy.context.active_object
        beam.rotation_euler = (0, 0, math.radians(45))
        beam.data.materials.append(mat_cyan)
        objs.append(beam)
    elif symbol_type == "brick":
        mat_brick = create_clay_mat("ib_br", (0.92, 0.48, 0.28, 1.0))
        for ox, oy in [(-0.35, -0.22), (0.35, -0.22), (0.0, 0.22)]:
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(ox, oy, 0.20))
            b = bpy.context.active_object
            b.scale = (0.58, 0.32, 0.16)
            b.data.materials.append(mat_brick)
            apply_uniform_clay_bevel(b, width=0.03, segments=2)
            objs.append(b)
    elif symbol_type == "steel":
        mat_steel = create_clay_mat("ib_st", (0.78, 0.82, 0.88, 1.0))
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.20))
        s = bpy.context.active_object
        s.scale = (0.9, 0.9, 0.16)
        s.data.materials.append(mat_steel)
        apply_uniform_clay_bevel(s, width=0.05, segments=2)
        objs.append(s)

    return objs

# ==================== MAIN BATCH RENDER ENTRY ====================

def main():
    clear_scene()
    print(">>> 1. Rendering Missile Tank Frames (6 frames)...")
    setup_render_settings(rx=256, ry=256, samples=32)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    for frame in range(6):
        objs = build_missile_tank(frame)
        render_and_clean(objs, os.path.join(SPRITES_TANKS, f"enemy_missile_f{frame}.png"))

    print(">>> 2. Rendering Laser Tank Frames (6 frames)...")
    setup_render_settings(rx=256, ry=256, samples=32)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_TANK)
    for frame in range(6):
        objs = build_laser_tank(frame)
        render_and_clean(objs, os.path.join(SPRITES_TANKS, f"enemy_laser_f{frame}.png"))

    print(">>> 3. Rendering Homing Missile & Laser Beam VFX...")
    setup_render_settings(rx=256, ry=256, samples=32)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    render_and_clean(build_homing_missile(), os.path.join(SPRITES_EFFECTS, "bullet_missile.png"))
    render_and_clean(build_laser_beam_vfx(), os.path.join(SPRITES_EFFECTS, "laser_beam.png"))

    print(">>> 4. Rendering Terrain Landmine & Laser Cannon Turret...")
    setup_render_settings(rx=256, ry=256, samples=32)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    render_and_clean(build_landmine_prop(), os.path.join(SPRITES_TILES, "tile_landmine.png"))
    render_and_clean(build_landmine_prop(), os.path.join(SPRITES_POWERUPS, "landmine_prop.png"))
    render_and_clean(build_laser_cannon_turret(), os.path.join(SPRITES_BUILDINGS, "turret_laser.png"))
    render_and_clean(build_laser_cannon_turret(), os.path.join(SPRITES_POWERUPS, "laser_cannon_prop.png"))

    print(">>> 5. Rendering Stage Preview Badges...")
    setup_render_settings(rx=128, ry=128, samples=24)
    create_sokpop_lighting(ortho_scale=ORTHO_SCALE_DEFAULT)
    badges = {
        "badge_mine.png": "mine",
        "badge_laser.png": "laser",
        "badge_brick.png": "brick",
        "badge_steel.png": "steel",
    }
    for b_fname, b_type in badges.items():
        objs = build_icon_badge(b_type)
        render_and_clean(objs, os.path.join(SPRITES_UI, b_fname))

    print(">>> SUCCESS: All expansion 3D models and sprites rendered successfully!")

if __name__ == "__main__":
    main()
